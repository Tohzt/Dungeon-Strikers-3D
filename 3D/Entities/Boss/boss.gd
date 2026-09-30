class_name Boss3D extends CharacterBody3D
## A big slime that roams the pitch in short hops. It bodies anyone it
## lands on or bumps into, leaps up for a big stomp when a player is close,
## and when it finds itself near the ball it dribbles it into whichever goal
## it's nearest, so it's a threat to both teams.
## A ball floats in its core; beating it drops a fresh ball into play.
## Online the server runs it and streams where it is (like the ball);
## everyone else just plays that back.

enum State {
	IDLE,           ## Resting on the ground between hops
	HOP_PREP,       ## Squashing down before a hop
	HOP,            ## In the air on a small hop
	STOMP_WINDUP,   ## Crouched and quivering, telegraphing a stomp
	STOMP_RISE,     ## Leaping up toward the stomp target
	STOMP_HANG,     ## Hovering at the top, drifting over the target
	STOMP_FALL,     ## Slamming down
	RECOVER,        ## Flattened after a stomp, catching its breath
	STAGGERED,      ## Poise broken: dazed and defenseless for a while
	DEAD,           ## Beaten: deflating, ball released
}

## HP changed (on every machine). For the boss health bar.
signal hp_changed(hp: float, max_hp: float)
## The fight has started (the start delay ran out). On every machine.
signal awakened
## Beaten, by `killer` (the player who landed the last hit; null if
## unknown). On every machine.
signal defeated(killer: PlayerClass3D)

# ===== SIZE =====
const RADIUS := 3.0
const HEIGHT := 4.0
const PLAYER_RADIUS := 0.5  # PlayerClass3D.BODY_RADIUS
const BALL_RADIUS := 0.5

# ===== MOVEMENT =====
@export_category("Hopping")
@export var gravity_scale: float = 2.0
@export var hop_velocity: float = 7.0  ## Upward speed of a small hop
@export var hop_speed: float = 6.0  ## Sideways speed during a small hop
@export var hop_rest_min: float = 0.35  ## Pause on the ground between hops
@export var hop_rest_max: float = 0.8
const HOP_PREP_TIME := 0.15
## Pokes from players slide the slime a little; this is how fast that stops.
const SHOVE_FRICTION := 12.0
const SHOVE_MAX := 4.0
const SHOVE_RESISTANCE := 0.15  # Share of an impulse that actually moves it

# ===== STOMP =====
@export_category("Stomp")
@export var stomp_trigger_range: float = 9.0  ## Stomp when a player is this close
@export var stomp_cooldown: float = 5.0
@export var stomp_radius: float = 6.0  ## Shockwave reach from the slime's center
@export var stomp_damage: float = 80.0  ## At the center, falling to half at the edge
@export var stomp_knockback: float = 14.0
@export var stomp_pop: float = 5.0
@export var stomp_ball_impulse: float = 8.0
const STOMP_WINDUP_TIME := 0.7
const STOMP_JUMP_VELOCITY := 16.0
const STOMP_MAX_DISTANCE := 10.0  # How far it can travel in one stomp leap
const STOMP_HANG_TIME := 0.3
const STOMP_HANG_TRACKING := 4.0  # m/s it drifts toward its target while hanging
const STOMP_FALL_SPEED := 35.0
const STOMP_RECOVER_TIME := 1.1
## Players this far above the ground when it lands jumped the shockwave.
const STOMP_DODGE_HEIGHT := 1.2

# ===== BUMPING =====
@export_category("Bump")
@export var bump_damage: float = 25.0
@export var bump_knockback: float = 10.0
@export var bump_pop: float = 3.0
const BUMP_COOLDOWN := 0.8  # Per player

# ===== BALL =====
@export_category("Ball")
## Goes after the ball instead of players when it's within this range.
@export var ball_interest_range: float = 10.0
@export var kick_impulse: float = 7.0
@export var kick_lift: float = 1.5
const KICK_COOLDOWN := 0.5
## How far behind the ball (away from the goal) it lines up before pushing.
const DRIBBLE_SETUP_OFFSET := RADIUS + BALL_RADIUS + 0.5

# ===== HEALTH =====
@export_category("Health")
@export var display_name: String = "Gelatinous Colossus"
@export var max_hp: float = 1200.0
## Drop a ball into play when beaten (shown floating in the core until then).
@export var drops_ball: bool = true
## How hard the dropped ball pops out.
@export var release_impulse: float = 1.5
## Hits tint the slime this bright for a moment.
const HIT_FLASH_TIME := 0.15
## Hits move it this fraction as far as they'd shove a loose object.
const HIT_SHOVE_RATIO := 0.3
const DEATH_TIME := 1.2
## How much the core bobs around inside the slime.
const CORE_BOB := 0.2

# ===== POISE =====
# Hits wear down its poise; enough damage in quick succession (a few players
# ganging up on it) staggers it: it stops, can't hurt anyone, and takes extra
# damage for a while. A stagger earned in mid-air waits until it's grounded.
@export_category("Poise")
@export var poise_max: float = 180.0
## Poise fully recovers after this long without being hit.
@export var poise_reset_delay: float = 2.5
@export var stagger_duration: float = 2.5
@export var staggered_damage_multiplier: float = 1.5
var _poise_damage: float = 0.0
var _poise_reset_wait: float = 0.0
var _poise_broken: bool = false

## Don't start acting until the match has had a moment to settle.
@export var start_delay: float = 3.0

@onready var visual: Node3D = $Visual
@onready var body_mesh: MeshInstance3D = $Visual/MeshInstance3D
@onready var core: MeshInstance3D = $Visual/Core
@onready var telegraph: MeshInstance3D = $StompTelegraph
@onready var _core_rest: Vector3 = core.position
@onready var _body_material: StandardMaterial3D = body_mesh.get_surface_override_material(0)
@onready var _body_color: Color = _body_material.albedo_color if _body_material else Color.WHITE

var hp: float:
	set(value):
		hp = value
		hp_changed.emit(hp, max_hp)
var is_awake: bool = false
var is_defeated: bool = false
var _flash: float = 0.0

var state: State = State.IDLE
var _state_time: float = 0.0
var _rest_time: float = 0.5
var _stomp_cooldown: float = 0.0
var _kick_cooldown: float = 0.0
var _bump_cooldowns: Dictionary[Node, float] = {}
var _shove: Vector3 = Vector3.ZERO
var _move_dir: Vector3 = Vector3.ZERO
var _stomp_target: Vector3 = Vector3.ZERO
var _ground_y: float = 0.0

# Squash and stretch: a spring on the vertical scale (sideways scale keeps
# the volume roughly constant).
const SQUASH_STIFFNESS := 180.0
const SQUASH_DAMPING := 10.0
var _squash: float = 1.0
var _squash_vel: float = 0.0
var _wobble_time: float = 0.0

## Clients: the server's recent updates, played back smoothly.
var _net_motion: NetInterpolator = null
var _last_sent_transform: Transform3D
var _last_sent_msec: int = 0


func _ready() -> void:
	add_to_group("Boss")
	_ground_y = global_position.y
	telegraph.top_level = true
	telegraph.visible = false
	var ring: CylinderMesh = telegraph.mesh as CylinderMesh
	if ring:
		ring.top_radius = stomp_radius
		ring.bottom_radius = stomp_radius
	_stomp_cooldown = stomp_cooldown * 0.5
	hp = max_hp
	core.visible = drops_ball
	if Net.in_session() and not Net.is_server:
		_net_motion = NetInterpolator.new()


func _physics_process(delta: float) -> void:
	if not _simulates():
		return
	if not is_awake or is_defeated:
		_apply_gravity(delta)
		move_and_slide()
		_send_state()
		return

	_state_time += delta
	_stomp_cooldown = max(_stomp_cooldown - delta, 0.0)
	_kick_cooldown = max(_kick_cooldown - delta, 0.0)
	_update_poise(delta)
	for key: Node in _bump_cooldowns.keys():
		_bump_cooldowns[key] -= delta
		if _bump_cooldowns[key] <= 0.0 or not is_instance_valid(key):
			_bump_cooldowns.erase(key)

	match state:
		State.IDLE: _state_idle()
		State.HOP_PREP: _state_hop_prep()
		State.HOP: _state_hop(delta)
		State.STOMP_WINDUP: _state_stomp_windup()
		State.STOMP_RISE: _state_stomp_rise(delta)
		State.STOMP_HANG: _state_stomp_hang(delta)
		State.STOMP_FALL: _state_stomp_fall()
		State.RECOVER: _state_recover()
		State.STAGGERED: _state_staggered()

	_bump_players()
	_touch_ball()
	_send_state()


func _process(delta: float) -> void:
	# Every machine counts down itself, so everyone's health bar appears together
	if not is_awake:
		start_delay -= delta
		if start_delay <= 0.0:
			is_awake = true
			awakened.emit()
	if _net_motion:
		var sample: Array = _net_motion.sample(delta)
		if not sample.is_empty():
			global_transform = sample[0]
		_state_time += delta  # Clients don't run the states, but the visuals time them
	elif state == State.DEAD:
		_state_time += delta  # Physics has stopped, but the fade-out times itself
	_update_squash(delta)
	_update_core()
	_update_color(delta)
	_update_telegraph()


# ===== STATES =====

func _set_state(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	if Net.in_session() and Net.is_server and Net.match_synced:
		_net_phase.rpc(new_state)
	_on_state_entered(new_state)


## Visual kicks for a state, run on every machine.
func _on_state_entered(new_state: State) -> void:
	match new_state:
		State.HOP:
			_squash_vel += 4.0  # Stretch up on takeoff
		State.STOMP_RISE:
			_squash_vel += 8.0
		State.IDLE:
			_squash_vel -= 5.0  # Splat on landing
		State.RECOVER:
			_squash_vel -= 12.0
		State.STAGGERED:
			_squash_vel -= 10.0
		State.DEAD:
			_squash_vel -= 6.0


func _state_idle() -> void:
	_slide_shove()
	if _state_time < _rest_time:
		return
	_choose_action()


func _state_hop_prep() -> void:
	_slide_shove()
	if _state_time >= HOP_PREP_TIME:
		velocity = _move_dir * hop_speed + Vector3.UP * hop_velocity
		_set_state(State.HOP)


func _state_hop(delta: float) -> void:
	_apply_gravity(delta)
	move_and_slide()
	if is_on_floor() and _state_time > 0.05:
		_land()


func _state_stomp_windup() -> void:
	_slide_shove()
	# Keep following the target while crouched, so the leap is aimed late
	var target: Node3D = _nearest_player()
	if target:
		_stomp_target = _clamp_stomp_target(target.global_position)
	if _state_time >= STOMP_WINDUP_TIME:
		_ground_y = global_position.y
		var rise_time: float = STOMP_JUMP_VELOCITY / _gravity()
		var travel: Vector3 = _flat(_stomp_target - global_position)
		velocity = travel / rise_time + Vector3.UP * STOMP_JUMP_VELOCITY
		_set_state(State.STOMP_RISE)


func _state_stomp_rise(delta: float) -> void:
	_apply_gravity(delta)
	move_and_slide()
	if velocity.y <= 0.0:
		velocity = Vector3.ZERO
		_set_state(State.STOMP_HANG)


func _state_stomp_hang(_delta: float) -> void:
	# Drift over the target, slowly enough that a quick player can get out
	var target: Node3D = _nearest_player()
	if target:
		var to_target: Vector3 = _flat(target.global_position - global_position)
		velocity = to_target.limit_length(STOMP_HANG_TRACKING)
	else:
		velocity = Vector3.ZERO
	move_and_slide()
	if _state_time >= STOMP_HANG_TIME:
		velocity = Vector3.DOWN * STOMP_FALL_SPEED
		_set_state(State.STOMP_FALL)


func _state_stomp_fall() -> void:
	velocity = Vector3.DOWN * STOMP_FALL_SPEED
	move_and_slide()
	if is_on_floor():
		velocity = Vector3.ZERO
		_stomp_shockwave()
		_stomp_cooldown = stomp_cooldown
		_set_state(State.RECOVER)


func _state_recover() -> void:
	_slide_shove()
	if _state_time >= STOMP_RECOVER_TIME:
		_rest_time = hop_rest_min
		_set_state(State.IDLE)


func _state_staggered() -> void:
	_slide_shove()
	if _state_time >= stagger_duration:
		_rest_time = hop_rest_min
		_set_state(State.IDLE)


## Count down to poise recovering, and stagger once it's broken and grounded.
func _update_poise(delta: float) -> void:
	if _poise_reset_wait > 0.0:
		_poise_reset_wait -= delta
		if _poise_reset_wait <= 0.0:
			_poise_damage = 0.0
	if _poise_broken and state in [State.IDLE, State.HOP_PREP, State.STOMP_WINDUP, State.RECOVER]:
		_poise_broken = false
		_poise_damage = 0.0
		velocity = Vector3.ZERO
		_set_state(State.STAGGERED)


func _land() -> void:
	velocity = Vector3.ZERO
	_ground_y = global_position.y
	_rest_time = randf_range(hop_rest_min, hop_rest_max)
	_set_state(State.IDLE)


# ===== DECISIONS =====

## On the ground and rested: dribble the ball if it's close, otherwise go
## after the nearest player (stomping them if they're in range).
func _choose_action() -> void:
	var ball: Ball3D = _free_ball()
	if ball and _flat(ball.global_position - global_position).length() < ball_interest_range:
		_move_dir = _dribble_direction(ball)
		_set_state(State.HOP_PREP)
		return

	var target: Node3D = _nearest_player()
	if not target:
		_rest_time = hop_rest_max
		_state_time = 0.0
		return
	var to_target: Vector3 = _flat(target.global_position - global_position)
	if _stomp_cooldown <= 0.0 and to_target.length() < stomp_trigger_range:
		_stomp_target = _clamp_stomp_target(target.global_position)
		_set_state(State.STOMP_WINDUP)
		return
	_move_dir = to_target.normalized()
	# A little randomness so it doesn't beeline like a robot
	_move_dir = _move_dir.rotated(Vector3.UP, randf_range(-0.35, 0.35))
	_set_state(State.HOP_PREP)


## Which way to hop to push the ball toward the nearest goal: get behind it
## first, then hop through it.
func _dribble_direction(ball: Ball3D) -> Vector3:
	var goal_dir: Vector3 = _flat(_goal_aim(ball) - ball.global_position).normalized()
	var setup_point: Vector3 = ball.global_position - goal_dir * DRIBBLE_SETUP_OFFSET
	var to_ball: Vector3 = _flat(ball.global_position - global_position)
	var to_setup: Vector3 = _flat(setup_point - global_position)
	# Already lined up behind it: push straight through toward the goal
	if to_ball.normalized().dot(goal_dir) > 0.6 or to_setup.length() < 1.0:
		return goal_dir
	# Otherwise swing around to the setup point, going around the ball rather
	# than through it (which would knock it the wrong way)
	var dir: Vector3 = to_setup.normalized()
	var side: Vector3 = goal_dir.cross(Vector3.UP)
	if to_ball.length() < DRIBBLE_SETUP_OFFSET + 1.0 and dir.dot(to_ball.normalized()) > 0.3:
		dir = (dir + side * sign(side.dot(-to_ball)) * 1.5).normalized()
	return dir


# ===== ATTACKS =====

## Anyone overlapping the slime gets bowled over.
func _bump_players() -> void:
	if state == State.STOMP_FALL:
		return  # The landing shockwave deals with whoever's underneath
	if state == State.STAGGERED:
		return  # Dazed: safe to crowd around
	for player: PlayerClass3D in _players():
		if _bump_cooldowns.has(player):
			continue
		var offset: Vector3 = player.global_position - global_position
		if offset.y < -1.0 or offset.y > HEIGHT:
			continue
		var flat: Vector3 = _flat(offset)
		if flat.length() > RADIUS + PLAYER_RADIUS + 0.1:
			continue
		_bump_cooldowns[player] = BUMP_COOLDOWN
		var dir: Vector3 = flat if flat.length() > 0.01 else _move_dir
		# Falling on someone hurts more than walking into them
		var dmg: float = bump_damage * (1.5 if velocity.y < -1.0 else 1.0)
		Combat.strike(player, dir, dmg, bump_knockback, bump_pop)


func _stomp_shockwave() -> void:
	for player: PlayerClass3D in _players():
		var offset: Vector3 = player.global_position - global_position
		if offset.y > STOMP_DODGE_HEIGHT + 1.0:  # Player origin sits ~1m up
			continue
		var dist: float = _flat(offset).length()
		if dist > stomp_radius:
			continue
		var falloff: float = 1.0 - 0.5 * dist / stomp_radius
		_bump_cooldowns[player] = BUMP_COOLDOWN
		Combat.strike(player, _flat(offset), stomp_damage * falloff,
				stomp_knockback * falloff, stomp_pop)
	var ball: Ball3D = _free_ball()
	if ball:
		var offset: Vector3 = _flat(ball.global_position - global_position)
		if offset.length() < stomp_radius:
			var falloff: float = 1.0 - 0.5 * offset.length() / stomp_radius
			var dir: Vector3 = offset.normalized() if offset.length() > 0.01 else Vector3.FORWARD
			Combat.push(ball, (dir + Vector3.UP * 0.8) * stomp_ball_impulse * falloff)
	_kick_cooldown = KICK_COOLDOWN


## Touching the ball knocks it toward the nearest goal, as long as the slime
## is behind it (otherwise it just bounces off).
func _touch_ball() -> void:
	if _kick_cooldown > 0.0:
		return
	var ball: Ball3D = _free_ball()
	if not ball:
		return
	var offset: Vector3 = ball.global_position - global_position
	if offset.y > HEIGHT + BALL_RADIUS:
		return
	var flat: Vector3 = _flat(offset)
	if flat.length() > RADIUS + BALL_RADIUS + 0.3:
		return
	var goal_dir: Vector3 = _flat(_goal_aim(ball) - ball.global_position).normalized()
	if flat.normalized().dot(goal_dir) < 0.0:
		return
	_kick_cooldown = KICK_COOLDOWN
	Combat.push(ball, goal_dir * kick_impulse + Vector3.UP * kick_lift)


## Called by Combat.strike for every attack that lands on the boss.
## `attacker` gets the kill if this hit finishes it. Online the server keeps
## the HP, so other machines pass their hits on to it.
func receive_hit(_dir: Vector3, damage: float, knockback_velocity: Vector3, attacker: Node3D = null) -> bool:
	if is_defeated:
		return false
	if not _simulates():
		if Net.match_synced:
			_request_hit.rpc_id(Net.SERVER_ID, damage, knockback_velocity)
		return true
	receive_impulse(knockback_velocity * HIT_SHOVE_RATIO)
	if state == State.STAGGERED:
		damage *= staggered_damage_multiplier
	elif not _poise_broken:
		_poise_damage += damage
		_poise_reset_wait = poise_reset_delay
		_poise_broken = _poise_damage >= poise_max
	_set_hp(hp - damage)
	if hp <= 0.0:
		var killer: String = String(attacker.name) if attacker is PlayerClass3D else ""
		if Net.in_session():
			_net_defeated.rpc(killer)
		else:
			_defeat(killer)
	return true


func _set_hp(value: float) -> void:
	value = max(value, 0.0)
	if value < hp:
		_flash = HIT_FLASH_TIME
	hp = value
	if Net.in_session() and Net.is_server and Net.match_synced:
		_net_hp.rpc(hp)


## Beaten, on every machine: stop, deflate, and drop the ball.
func _defeat(killer_name: String) -> void:
	if is_defeated:
		return
	is_defeated = true
	_set_state(State.DEAD)
	velocity = Vector3(0.0, min(velocity.y, 0.0), 0.0)
	collision_layer = 0  # Players and the ball pass through; it still lands on the floor
	telegraph.visible = false
	if drops_ball and Global.Game3D:
		core.visible = false
		var dir: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		Global.Game3D.spawn_ball(core.global_position, (Vector3.UP * 2.0 + dir) * release_impulse)
	var killer: PlayerClass3D = null
	if Global.Game3D and killer_name != "":
		killer = Global.Game3D.get_node_or_null(killer_name) as PlayerClass3D
	defeated.emit(killer)
	await get_tree().create_timer(DEATH_TIME).timeout
	queue_free()


## Hit by a punch, sword or thrown weapon (see Combat.push). It's heavy, so
## it only slides a little.
func receive_impulse(impulse: Vector3) -> void:
	if not _simulates():
		_request_push.rpc_id(Net.SERVER_ID, impulse)
		return
	_shove = (_shove + _flat(impulse) * SHOVE_RESISTANCE).limit_length(SHOVE_MAX)
	_squash_vel -= 2.0


func _slide_shove() -> void:
	var delta: float = get_physics_process_delta_time()
	_apply_gravity(delta)
	velocity.x = _shove.x
	velocity.z = _shove.z
	move_and_slide()
	_shove = _shove.move_toward(Vector3.ZERO, SHOVE_FRICTION * delta)


# ===== HELPERS =====

func _simulates() -> bool:
	return not Net.in_session() or Net.is_server


func _gravity() -> float:
	return get_gravity().length() * gravity_scale


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * gravity_scale * delta


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _clamp_stomp_target(pos: Vector3) -> Vector3:
	var travel: Vector3 = _flat(pos - global_position).limit_length(STOMP_MAX_DISTANCE)
	return global_position + travel


func _players() -> Array[PlayerClass3D]:
	if Global.Game3D:
		return Global.Game3D.players
	var found: Array[PlayerClass3D] = []
	for node: Node in get_tree().get_nodes_in_group("Player"):
		if node is PlayerClass3D:
			found.append(node)
	return found


func _nearest_player() -> PlayerClass3D:
	var best: PlayerClass3D = null
	var best_dist: float = INF
	for player: PlayerClass3D in _players():
		var dist: float = _flat(player.global_position - global_position).length()
		if dist < best_dist:
			best_dist = dist
			best = player
	return best


## The nearest ball that's loose on the pitch (not in someone's hands).
func _free_ball() -> Ball3D:
	if not Global.Game3D:
		return null
	var best: Ball3D = null
	var best_dist: float = INF
	for ball: Ball3D in Global.Game3D.balls:
		if not is_instance_valid(ball) or not ball.is_inside_tree() or ball.holder:
			continue
		var dist: float = global_position.distance_to(ball.global_position)
		if dist < best_dist:
			best_dist = dist
			best = ball
	return best


## Where to send the ball: the net of whichever goal the slime is nearest.
func _goal_aim(ball: Ball3D) -> Vector3:
	var best: Goal3D = null
	var best_dist: float = INF
	for goal: Goal3D in get_tree().get_nodes_in_group("Goal"):
		var dist: float = global_position.distance_to(goal.global_position)
		if dist < best_dist:
			best_dist = dist
			best = goal
	return best.net.global_position if best else ball.global_position + Vector3.FORWARD


# ===== VISUALS =====

func _update_squash(delta: float) -> void:
	_wobble_time += delta
	var target: float = 1.0
	match state:
		State.IDLE:
			target = 1.0 + 0.04 * sin(_wobble_time * 5.0)
		State.HOP_PREP:
			target = 0.8
		State.HOP:
			target = 1.12 if velocity.y > 0.0 else 1.04
		State.STOMP_WINDUP:
			# Crouch lower and lower, shivering faster as it goes
			var t: float = clamp(_state_time / STOMP_WINDUP_TIME, 0.0, 1.0)
			target = lerp(0.9, 0.6, t) + 0.03 * sin(_wobble_time * lerp(20.0, 60.0, t))
		State.STOMP_RISE:
			target = 1.25
		State.STOMP_HANG:
			target = 1.0
		State.STOMP_FALL:
			target = 1.35
		State.RECOVER:
			target = 0.85
		State.STAGGERED:
			# Slumped and swaying
			target = 0.7 + 0.05 * sin(_wobble_time * 8.0)
		State.DEAD:
			target = 0.15
	_squash_vel += (target - _squash) * SQUASH_STIFFNESS * delta
	_squash_vel *= max(1.0 - SQUASH_DAMPING * delta, 0.0)
	_squash = clamp(_squash + _squash_vel * delta, 0.4, 1.6)
	var side: float = 1.0 / sqrt(_squash)
	visual.scale = Vector3(side, _squash, side)


## The ball floating inside: stays round however the slime squashes, and
## drifts lazily around the middle.
func _update_core() -> void:
	if not core.visible:
		return
	var inv: Vector3 = Vector3.ONE / visual.scale
	core.scale = inv
	var bob := Vector3(sin(_wobble_time * 1.3) * 0.5, sin(_wobble_time * 2.1), cos(_wobble_time * 1.7) * 0.5) * CORE_BOB
	# Squashing pushes the core down with the body, but never out of it
	core.position = _core_rest + bob * inv
	core.rotation.y = _wobble_time * 0.6


## Hit flash, and fading out once beaten.
func _update_color(delta: float) -> void:
	if not _body_material:
		return
	_flash = max(_flash - delta, 0.0)
	var brighten: float = 0.7 * _flash / HIT_FLASH_TIME
	if state == State.STAGGERED:
		brighten = max(brighten, 0.15 + 0.15 * sin(_wobble_time * 10.0))  # Dazed shimmer
	var color: Color = _body_color.lerp(Color.WHITE, brighten)
	color.a = _body_color.a
	if state == State.DEAD:
		color.a *= clamp(1.0 - _state_time / DEATH_TIME, 0.0, 1.0)
	_body_material.albedo_color = color


## The danger zone on the ground while a stomp is coming.
func _update_telegraph() -> void:
	var showing: bool = state in [State.STOMP_WINDUP, State.STOMP_RISE, State.STOMP_HANG, State.STOMP_FALL]
	telegraph.visible = showing
	if not showing:
		return
	var center: Vector3 = _stomp_target if state == State.STOMP_WINDUP else global_position
	telegraph.global_position = Vector3(center.x, _ground_y + 0.05, center.z)
	var mat: StandardMaterial3D = telegraph.get_surface_override_material(0) as StandardMaterial3D
	if mat:
		# Pulse faster the closer it is to landing
		var speed: float = 25.0 if state == State.STOMP_FALL else 10.0
		mat.albedo_color.a = 0.25 + 0.2 * sin(_wobble_time * speed)


# ===== NETWORK =====

func _send_state() -> void:
	if not Net.in_session() or not Net.is_server or not Net.match_synced:
		return
	var now_msec: int = Time.get_ticks_msec()
	if global_transform.is_equal_approx(_last_sent_transform) \
			and now_msec - _last_sent_msec < NetInterpolator.RESEND_IDLE_MSEC:
		return
	_last_sent_transform = global_transform
	_last_sent_msec = now_msec
	_net_state.rpc(NetInterpolator.now(), global_transform, _stomp_target, _ground_y)


@rpc("authority", "unreliable_ordered")
func _net_state(time: float, xform: Transform3D, stomp_target: Vector3, ground_y: float) -> void:
	_net_motion.push(time, xform)
	_stomp_target = stomp_target
	_ground_y = ground_y


@rpc("authority", "reliable")
func _net_phase(new_state: State) -> void:
	if is_defeated:
		return
	state = new_state
	_state_time = 0.0
	_on_state_entered(new_state)


@rpc("authority", "reliable")
func _net_hp(value: float) -> void:
	_set_hp(value)


@rpc("authority", "call_local", "reliable")
func _net_defeated(killer_name: String) -> void:
	_defeat(killer_name)


## A client's player hit the boss; the sender's player gets the credit.
@rpc("any_peer", "reliable")
func _request_hit(damage: float, knockback_velocity: Vector3) -> void:
	if Net.is_server:
		var attacker: PlayerClass3D = Global.Game3D.player_of_peer(multiplayer.get_remote_sender_id())
		receive_hit(Vector3.ZERO, damage, knockback_velocity, attacker)


@rpc("any_peer", "reliable")
func _request_push(impulse: Vector3) -> void:
	if Net.is_server:
		receive_impulse(impulse)
