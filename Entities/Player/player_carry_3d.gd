class_name PlayerCarry3D extends RefCounted
## A player carrying the ball (PlayerClass3D.ball_carry). Rolling or sliding
## into a ball picks it up (so does Interact, for a ball in reach). Carrying
## it drains the carry meter (shown on the HUD) and puts the weapons in our
## hands out of sight. Light (or Throw) charges and throws it the way we
## face, Heavy passes it straight to the nearest teammate, Shoot (E / LT)
## charges and shoots it at the goal we attack (a skull: at our altar), and
## an empty meter tosses it forward on its own. Locked on (teammates can be
## locked on to while carrying), Shoot passes to a teammate or attacks an
## enemy with the ball instead. The meter refills while we don't carry.
##
## The ball itself decides who holds it (see Ball3D.request_grab and
## request_throw); this keeps the player's side of it.

signal changed(new_meter: float, max_meter: float)

const MAX := 100.0
## A full meter lasts this many seconds of carrying.
const DRAIN_PER_SEC := 100.0 / 3.0
## Refills from empty in this many seconds.
const REGEN_PER_SEC := 100.0 / 4.0
## Need this much to pick the ball up.
const MIN_TO_GRAB := 25.0
const REACH := 2.0
## A roll or slide picks up a ball this close, flat (closer than REACH, so
## it has to actually go into it). Checked where the roll is about to take
## us, so we get it before our body knocks it away.
const ROLL_REACH := 1.4
## Walking speed while carrying, times normal (no sprinting either).
const WALK_SPEED := 0.85
## Throw speed (scaled by the throw charge), and how much it rises.
const THROW_SPEED := 14.0
const THROW_LIFT := 0.15
## Shot speed (scaled by the charge like a throw: half to 1.5x), and how
## much it rises.
const SHOT_SPEED := 16.0
const SHOT_LIFT := 0.12
## A pass flies at least this fast, keeping low so it reaches them.
const PASS_MIN_SPEED := 10.0
## Heavy's pass to the nearest teammate: this fast per metre to them, up to
## PASS_MAX_SPEED.
const PASS_SPEED_PER_M := 1.2
const PASS_MAX_SPEED := 22.0
const PASS_LIFT := 0.05
## A ball attack's damage, from no charge to full.
const ATTACK_DAMAGE_MIN := 8.0
const ATTACK_DAMAGE_MAX := 20.0
## Meter ran dry: tossed forward this fast.
const TOSS_SPEED := 6.0
## Hit while carrying: the ball pops loose along the hit this fast.
const FUMBLE_SPEED := 5.0

var meter: float = MAX:
	set(value):
		meter = clampf(value, 0.0, MAX)
		changed.emit(meter, MAX)
## The ball we carry (every machine), if any.
var ball: Ball3D = null

var _player: PlayerClass3D
## Asked to throw (online, until the server lets go).
var _thrown: bool = false
## Asked for a ball during this roll or slide already (online, the answer
## takes a moment; this keeps it to one ask).
var _roll_asked: bool = false


func _init(player: PlayerClass3D) -> void:
	_player = player


## Whether we have the ball in hand (and haven't let it go yet).
func is_carrying() -> bool:
	return is_instance_valid(ball) and ball.holder == _player and not _thrown


## Whether we could pick `target` up now. Mid-roll is fine (see
## ball_ahead); knocked about isn't.
func can_grab(target: Ball3D, reach: float = REACH) -> bool:
	return not target.holder and not _player.is_dead() and not _player.knocked_about() \
		and not is_instance_valid(ball) and not _player.holds_throwable() and meter >= MIN_TO_GRAB \
		and _player.global_position.distance_to(target.global_position) <= reach


## Interact: pick up the nearest ball within reach. Returns whether we are
## (or, online, have asked to).
func grab_nearest() -> bool:
	if not Global.Game3D:
		return false
	var from: Vector3 = _player.global_position
	var nearest: Ball3D = null
	for each: Ball3D in Global.Game3D.balls:
		if is_instance_valid(each) and each.is_inside_tree() and can_grab(each) and (not nearest \
				or from.distance_to(each.global_position) < from.distance_to(nearest.global_position)):
			nearest = each
	if nearest:
		nearest.request_grab(_player)
	return nearest != null


## A new roll or slide: it may ask for a ball again.
func start_roll() -> void:
	_roll_asked = false


## Whether this roll or slide may still scoop up `target` (see scoop).
func can_scoop(target: Ball3D) -> bool:
	return not _roll_asked and not is_carrying() and can_grab(target, INF)


## Mid-roll or slide, before this step's move: a ball we're about to run
## into, moving `step` this frame, that we can scoop up (or null).
func ball_ahead(step: Vector3) -> Ball3D:
	if _roll_asked or is_carrying() or not Global.Game3D:
		return null
	var ahead: Vector3 = _player.global_position + step
	for each: Ball3D in Global.Game3D.balls:
		if not is_instance_valid(each) or not each.is_inside_tree() or not can_grab(each, INF):
			continue
		var to: Vector3 = each.global_position - ahead
		if Vector2(to.x, to.z).length() <= ROLL_REACH and absf(to.y) < 1.5:
			return each
	return null


## Ask for `target` mid-roll (once per roll).
func scoop(target: Ball3D) -> void:
	_roll_asked = true
	target.request_grab(_player)


## Every machine (see Ball3D.grab).
func on_grabbed(target: Ball3D) -> void:
	ball = target
	_thrown = false


## Every machine (see Ball3D.release).
func on_released(target: Ball3D) -> void:
	if ball == target:
		ball = null
	_thrown = false


## Throw the ball along our aim, harder with more `charge` (0-1).
func throw(charge: float) -> void:
	if not is_carrying():
		return
	var dir: Vector3 = _flat_or_forward(_player.get_aim_direction())
	var speed: float = THROW_SPEED * _player.throw_force_ratio(charge) * _player.perk_stat(&"throw_power")
	_launch((dir + Vector3.UP * THROW_LIFT).normalized() * speed)
	_player.right_arm.play_throw_release()


## Shoot the ball, further with more `charge` (0-1): at what we're locked
## on to (a pass to a teammate, an attack on anyone else), or else at the
## goal we attack (a skull: at our altar), or else along our aim.
func shoot(charge: float) -> void:
	if not is_carrying():
		return
	var speed: float = SHOT_SPEED * _player.throw_force_ratio(charge) * _player.perk_stat(&"throw_power")
	var lift: float = SHOT_LIFT
	var shot: Ball3D.Shot = Ball3D.Shot.NONE
	var damage: float = 0.0
	var lock: Node3D = _player.Input_Handler.lock_target
	var target: Node3D = null
	if is_instance_valid(lock):
		target = lock
		if Combat.are_teammates(lock, _player):
			shot = Ball3D.Shot.PASS
			speed = maxf(speed, PASS_MIN_SPEED)
			lift = PASS_LIFT
		else:
			shot = Ball3D.Shot.ATTACK
			damage = lerpf(ATTACK_DAMAGE_MIN, ATTACK_DAMAGE_MAX, charge)
	elif Global.Game3D:
		target = Global.Game3D.shot_target(_player, ball)
	_launch_at(target, speed, lift, shot, damage)


## Heavy while carrying: pass straight to the nearest teammate, hard enough
## to reach them. With nobody to pass to, it's a plain throw.
func pass_to_teammate() -> void:
	if not is_carrying():
		return
	var mate: PlayerClass3D = _player.nearest_teammate()
	if not mate:
		throw(0.5)
		return
	var speed: float = clampf(_player.global_position.distance_to(mate.global_position) * PASS_SPEED_PER_M,
		PASS_MIN_SPEED, PASS_MAX_SPEED)
	_launch_at(mate, speed, PASS_LIFT, Ball3D.Shot.PASS)


## Owner: a hit knocks the ball loose, along `dir`.
func fumble(dir: Vector3) -> void:
	if is_carrying():
		_launch(_flat_or_forward(dir) * FUMBLE_SPEED + Vector3.UP * 3.0)


## Back to a full meter (respawning).
func refill() -> void:
	meter = MAX


## Owner: drain the meter while carrying (tossing the ball forward once it's
## empty, or when we're knocked about), refill it otherwise.
func update(delta: float) -> void:
	if not is_instance_valid(ball):
		ball = null
	if is_carrying():
		meter -= DRAIN_PER_SEC * delta
		if meter <= 0.0 or _player.knocked_about():
			_launch(_player.global_basis.z * TOSS_SPEED + Vector3.UP * 2.0)
	elif not ball:
		meter += REGEN_PER_SEC * delta


## Let the ball go at `target` (leading a moving one on a pass or attack),
## or along our aim without one.
func _launch_at(target: Node3D, speed: float, lift: float, shot: Ball3D.Shot = Ball3D.Shot.NONE, damage: float = 0.0) -> void:
	var dir: Vector3 = _player.get_aim_direction()
	if target:
		dir = target.global_position - _player.global_position
		if shot != Ball3D.Shot.NONE and target is CharacterBody3D:
			dir += (target as CharacterBody3D).velocity * dir.length() / speed  # Lead them
	_launch((_flat_or_forward(dir) + Vector3.UP * lift).normalized() * speed, shot, damage)
	_player.right_arm.play_throw_release()


func _launch(launch: Vector3, shot: Ball3D.Shot = Ball3D.Shot.NONE, damage: float = 0.0) -> void:
	ball.touched_by(_player)
	ball.request_throw(_player, launch, shot, damage)
	_thrown = true


## `dir` flattened and normalized, or the way we face if it's too short.
func _flat_or_forward(dir: Vector3) -> Vector3:
	dir.y = 0.0
	return dir.normalized() if dir.length() > 0.01 else _player.global_basis.z
