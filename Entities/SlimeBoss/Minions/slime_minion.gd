class_name SlimeMinion3D extends CharacterBody3D
## A little slime the boss spits out. It lands, then hops after the nearest
## player. Touching it is safe; up close it lunges at them or swells up in a
## quick burst, both telegraphed by a crouch. Fragile and light: a few hits
## pop it, and every hit knocks it flying. It pops when its boss is beaten.
## A boss's minions share its element (SlimeElement): its color, and a
## milder dose of what its hits do to players.
## A Slime Tower (Tower3D) spits them out too, for a team: those wear the
## team's color and only go after the other team's players.
## Online the server runs it and streams where it is; everyone else just
## plays that back (like the boss).

enum State {
	LAUNCHED,  ## Flying out of the boss
	IDLE,      ## Resting between hops
	HOP_PREP,  ## Squashing down before a hop
	HOP,       ## In the air
	LUNGE_WINDUP,  ## Rearing back, about to lunge
	LUNGE,         ## Low, fast leap at a player
	SWELL_WINDUP,  ## Crouched and shivering, about to burst
	SWELL,         ## Puffed up: the burst
	DEAD,      ## Popping
}

const RADIUS := 1.0  # Matches the mesh
const HEIGHT := 1.0
const PLAYER_RADIUS := 0.5  # PlayerClass3D.BODY_RADIUS

@export var max_hp: float = 40.0  ## A sword hit, or four punches
@export var gravity_scale: float = 2.0
@export var hop_velocity: float = 5.0
@export var hop_speed: float = 5.5
@export var hop_rest_min: float = 0.3
@export var hop_rest_max: float = 0.7
## Stops chasing anyone farther than this; hops around aimlessly instead.
@export var chase_range: float = 25.0

@export_category("Lunge")
@export var lunge_trigger_range: float = 5.0  ## Lunge at a player this close
@export var lunge_cooldown: float = 2.5
@export var lunge_distance: float = 4.5
@export var lunge_damage: float = 8.0
@export var lunge_knockback: float = 9.0
@export var lunge_pop: float = 2.5
const LUNGE_WINDUP_TIME := 0.35
const LUNGE_AIR_TIME := 0.3
const LUNGE_AIM_LOCK := 0.12  # Stops tracking this long before it goes
const LUNGE_LEAN := 0.3

@export_category("Swell")
@export var swell_trigger_range: float = 2.0  ## Burst when a player is this close to its center
@export var swell_cooldown: float = 3.0
@export var swell_radius: float = 2.4
@export var swell_damage: float = 6.0
@export var swell_knockback: float = 10.0
@export var swell_pop: float = 4.0
const SWELL_WINDUP_TIME := 0.4
const SWELL_TIME := 0.25
const SWELL_SCALE := 1.8

const HOP_PREP_TIME := 0.12
## Hits launch it this fraction of their knockback (it's light).
const HIT_KNOCKBACK_RATIO := 0.8
const KNOCKBACK_FRICTION := 10.0
const HIT_FLASH_TIME := 0.12
const POP_TIME := 0.25
const SQUASH_STIFFNESS := 220.0
const SQUASH_DAMPING := 10.0

@onready var visual: Node3D = $Visual
@onready var body_mesh: MeshInstance3D = $Visual/MeshInstance3D
@onready var _body_material: StandardMaterial3D = body_mesh.get_surface_override_material(0)
@onready var _body_color: Color = _body_material.albedo_color if _body_material else Color.WHITE

## The team it fights for (a tower's), or -1 for the boss's. Set before
## it's added.
var team: int = -1
## Its boss's element, if it has one (RANDOM: none). Set before it's added.
var element: SlimeElement.Kind = SlimeElement.Kind.RANDOM
## Its hits afflict players this much as hard as its boss's do.
const STING_STRENGTH := 0.5
var hp: float = 0.0
var is_dead: bool = false
var state: State = State.LAUNCHED
var _state_time: float = 0.0
var _rest_time: float = 0.3
var _move_dir: Vector3 = Vector3.ZERO
## Sideways slide from being hit, on top of hopping.
var _knockback: Vector3 = Vector3.ZERO
var _lunge_cooldown: float = 0.0
var _swell_cooldown: float = 0.0
## Players the current lunge has already hit.
var _lunge_hits: Array[PlayerClass3D] = []
var _flash: float = 0.0
var _squash: float = 1.0
var _squash_vel: float = 0.0
var _wobble_time: float = 0.0

## Online: the server sends where it is; clients play it back.
var _motion := NetMotion.new()


func _ready() -> void:
	add_to_group("Minion")
	hp = max_hp
	if team >= 0:
		_body_color = Color(Players.TEAM_COLORS[team % Players.TEAM_COLORS.size()], _body_color.a)
	elif element != SlimeElement.Kind.RANDOM:
		_body_color = SlimeElement.BODY_COLORS[element]
	_wobble_time = randf() * TAU  # So a pair doesn't wobble in sync
	# Staggered so a fresh pair doesn't attack in sync either
	_lunge_cooldown = randf_range(0.5, 1.0) * lunge_cooldown
	_swell_cooldown = randf_range(0.3, 0.8) * swell_cooldown


## Fly out of the boss at `launch_velocity` (by whoever simulates it).
func launch(launch_velocity: Vector3) -> void:
	velocity = launch_velocity
	_set_state(State.LAUNCHED)


func _physics_process(delta: float) -> void:
	if not Net.decides() or is_dead or PerkDirector.halted():
		return
	_state_time += delta
	_lunge_cooldown = max(_lunge_cooldown - delta, 0.0)
	_swell_cooldown = max(_swell_cooldown - delta, 0.0)

	if not is_on_floor():
		velocity += get_gravity() * gravity_scale * delta
	match state:
		State.LAUNCHED, State.HOP:
			if is_on_floor() and _state_time > 0.1:
				_land()
		State.LUNGE:
			_lunge_strike()
			if is_on_floor() and _state_time > 0.05:
				_lunge_cooldown = lunge_cooldown * randf_range(0.8, 1.2)
				_land()
		State.LUNGE_WINDUP:
			velocity.x = 0.0
			velocity.z = 0.0
			_state_lunge_windup()
		State.SWELL_WINDUP:
			velocity.x = 0.0
			velocity.z = 0.0
			if _state_time >= SWELL_WINDUP_TIME:
				_swell_burst()
				_swell_cooldown = swell_cooldown * randf_range(0.8, 1.2)
				_set_state(State.SWELL)
		State.SWELL:
			velocity.x = 0.0
			velocity.z = 0.0
			if _state_time >= SWELL_TIME:
				_land()
		State.IDLE:
			velocity.x = 0.0
			velocity.z = 0.0
			if _state_time >= _rest_time:
				_choose_hop()
		State.HOP_PREP:
			velocity.x = 0.0
			velocity.z = 0.0
			if _state_time >= HOP_PREP_TIME:
				velocity = _move_dir * hop_speed + Vector3.UP * hop_velocity
				_set_state(State.HOP)
	var hop: Vector3 = velocity
	velocity += _knockback
	move_and_slide()
	velocity = Vector3(hop.x, velocity.y, hop.z)
	_knockback = _knockback.move_toward(Vector3.ZERO, KNOCKBACK_FRICTION * delta)

	_send_state()


func _process(delta: float) -> void:
	if not Net.decides():
		_motion.play(self, delta)
		_state_time += delta
	_update_squash(delta)
	_update_color(delta)


# ===== BEHAVIOR =====

func _set_state(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	if Net.in_session() and Net.is_server and Net.match_synced:
		_net_phase.rpc(new_state)
	_on_state_entered(new_state)


func _on_state_entered(new_state: State) -> void:
	match new_state:
		State.HOP, State.LAUNCHED, State.LUNGE:
			_squash_vel += 5.0
		State.IDLE:
			_squash_vel -= 6.0
		State.SWELL:
			_squash_vel += 4.0
			Sfx.play(&"hit_slime", global_position)


func _land() -> void:
	velocity = Vector3.ZERO
	_rest_time = randf_range(hop_rest_min, hop_rest_max)
	_set_state(State.IDLE)


## Burst if a player is right on it, lunge if one is near, otherwise hop
## toward the nearest living player in range, or somewhere at random.
func _choose_hop() -> void:
	var target: PlayerClass3D = _nearest_player()
	if target:
		var to_target: Vector3 = _flat(target.global_position - global_position)
		_move_dir = to_target.normalized()
		if _swell_cooldown <= 0.0 and to_target.length() < swell_trigger_range:
			_set_state(State.SWELL_WINDUP)
			return
		if _lunge_cooldown <= 0.0 and to_target.length() < lunge_trigger_range:
			_set_state(State.LUNGE_WINDUP)
			return
		_move_dir = _move_dir.rotated(Vector3.UP, randf_range(-0.3, 0.3))
	else:
		_move_dir = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	_set_state(State.HOP_PREP)


## Track the target while rearing back (until the aim locks), then leap.
func _state_lunge_windup() -> void:
	var target: PlayerClass3D = _nearest_player()
	if target and _state_time < LUNGE_WINDUP_TIME - LUNGE_AIM_LOCK:
		var to_target: Vector3 = _flat(target.global_position - global_position)
		if to_target.length() > 0.01:
			_move_dir = to_target.normalized()
	if _state_time >= LUNGE_WINDUP_TIME:
		var reach: float = lunge_distance
		if target:
			reach = min(reach, _flat(target.global_position - global_position).length() + 1.0)
		var gravity: float = get_gravity().length() * gravity_scale
		velocity = _move_dir * reach / LUNGE_AIR_TIME + Vector3.UP * gravity * LUNGE_AIR_TIME * 0.5
		_lunge_hits.clear()
		_set_state(State.LUNGE)


## Mid-lunge: knock over anyone it runs into (once each).
func _lunge_strike() -> void:
	for player: PlayerClass3D in _players():
		if player.is_dead() or _lunge_hits.has(player) or _is_ally(player):
			continue
		var offset: Vector3 = player.global_position - global_position
		if offset.y < -1.0 or offset.y > HEIGHT + 1.0:
			continue
		if _flat(offset).length() > RADIUS + PLAYER_RADIUS + 0.2:
			continue
		_lunge_hits.append(player)
		if Combat.strike(player, _move_dir, lunge_damage, lunge_knockback, lunge_pop):
			_sting(player)


## Burst outward: everyone close enough gets blasted away.
func _swell_burst() -> void:
	for player: PlayerClass3D in _players():
		if player.is_dead() or _is_ally(player):
			continue
		var offset: Vector3 = player.global_position - global_position
		if offset.y < -1.0 or offset.y > HEIGHT * SWELL_SCALE + 1.0:
			continue
		var flat: Vector3 = _flat(offset)
		if flat.length() > swell_radius:
			continue
		if Combat.strike(player, flat if flat.length() > 0.01 else _move_dir,
				swell_damage, swell_knockback, swell_pop):
			_sting(player)


## Its element's touch on a player it hit (if it has one).
func _sting(player: PlayerClass3D) -> void:
	if element != SlimeElement.Kind.RANDOM:
		SlimeElement.afflict(player, element, STING_STRENGTH)


# ===== DAMAGE =====

## Called by Combat.strike for every attack that lands on it. Online the
## server keeps the HP, so other machines pass their hits on to it.
func receive_hit(_dir: Vector3, damage: float, knockback_velocity: Vector3, attacker: Node3D = null) -> bool:
	if is_dead:
		return false
	if not Net.decides():
		if Net.match_synced:
			_request_hit.rpc_id(Net.SERVER_ID, damage, knockback_velocity)
		return true
	Sfx.play_everywhere(&"hit_slime", global_position)
	Vfx.play_everywhere(&"hit", global_position, knockback_velocity)  # Its dir is lost when passed to the server
	_knockback = _flat(knockback_velocity) * HIT_KNOCKBACK_RATIO
	velocity.y = max(velocity.y, knockback_velocity.y * HIT_KNOCKBACK_RATIO)
	Vfx.damage_number_everywhere(self, Vector3.UP * (HEIGHT + 0.5), minf(damage, hp), attacker)
	hp -= damage
	if hp <= 0.0:
		die()
	elif Net.in_session() and Net.match_synced:
		_net_flash.rpc()
	else:
		_flash = HIT_FLASH_TIME
	return true


## Loose physics pushes (see Combat.push) knock it around a little.
func receive_impulse(impulse: Vector3) -> void:
	if Net.decides():
		_knockback += _flat(impulse) * 0.5


## Pop, everywhere (server/offline decides).
func die() -> void:
	if not Net.decides():
		return
	if Net.in_session() and Net.match_synced:
		_net_die.rpc()
	else:
		_pop()


func _pop() -> void:
	if is_dead:
		return
	is_dead = true
	state = State.DEAD
	collision_layer = 0
	_flash = HIT_FLASH_TIME
	var tween: Tween = create_tween()
	tween.tween_property(visual, "scale", Vector3(1.6, 0.05, 1.6), POP_TIME)
	tween.tween_callback(queue_free)


# ===== HELPERS =====

func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _players() -> Array[PlayerClass3D]:
	if Global.Game3D:
		return Global.Game3D.players
	return []


## `player` is on its team (a tower's slime): it leaves them be.
func _is_ally(player: PlayerClass3D) -> bool:
	return team >= 0 and Combat.team_of(player) == team


func _nearest_player() -> PlayerClass3D:
	var best: PlayerClass3D = null
	var best_dist: float = chase_range
	for player: PlayerClass3D in _players():
		if not is_instance_valid(player) or player.is_dead() or _is_ally(player):
			continue
		var dist: float = _flat(player.global_position - global_position).length()
		if dist < best_dist:
			best_dist = dist
			best = player
	return best


# ===== VISUALS =====

func _update_squash(delta: float) -> void:
	if is_dead:
		return  # The pop tween owns the scale
	_wobble_time += delta
	var target: float = 1.0
	match state:
		State.IDLE:
			target = 1.0 + 0.06 * sin(_wobble_time * 7.0)
		State.HOP_PREP:
			target = 0.75
		State.HOP, State.LAUNCHED:
			target = 1.15
		State.LUNGE_WINDUP:
			target = 0.65 + 0.04 * sin(_wobble_time * 45.0)
		State.LUNGE:
			target = 0.8  # Stretched long and low
		State.SWELL_WINDUP:
			var t: float = clamp(_state_time / SWELL_WINDUP_TIME, 0.0, 1.0)
			target = lerp(0.9, 0.6, t) + 0.05 * sin(_wobble_time * lerp(30.0, 70.0, t))
	_squash_vel += (target - _squash) * SQUASH_STIFFNESS * delta
	_squash_vel *= max(1.0 - SQUASH_DAMPING * delta, 0.0)
	_squash = clamp(_squash + _squash_vel * delta, 0.4, 1.6)
	var side: float = 1.0 / sqrt(_squash)
	visual.scale = Vector3(side, _squash, side) * _puff()
	visual.position = _lean()


## Uniform swelling on top of the squash: a quick puff out and back for
## the burst.
func _puff() -> float:
	if state != State.SWELL:
		return 1.0
	var t: float = clamp(_state_time / SWELL_TIME, 0.0, 1.0)
	if t < 0.2:
		return lerp(1.0, SWELL_SCALE, t / 0.2)
	return lerp(SWELL_SCALE, 1.0, (t - 0.2) / 0.8)


## Rearing back away from a lunge's aim, then thrown forward into it.
func _lean() -> Vector3:
	match state:
		State.LUNGE_WINDUP:
			return -_move_dir * LUNGE_LEAN * ease(clamp(_state_time / LUNGE_WINDUP_TIME, 0.0, 1.0), 0.5)
		State.LUNGE:
			return _move_dir * LUNGE_LEAN
	return Vector3.ZERO


func _update_color(delta: float) -> void:
	if not _body_material:
		return
	_flash = max(_flash - delta, 0.0)
	var color: Color = _body_color.lerp(Color.WHITE, 0.7 * _flash / HIT_FLASH_TIME)
	color.a = _body_color.a
	_body_material.albedo_color = color


# ===== NETWORK =====

func _send_state() -> void:
	if Net.in_session() and Net.is_server and Net.match_synced and _motion.should_send(global_transform):
		_net_state.rpc(NetInterpolator.now(), global_transform, _move_dir)


@rpc("authority", "unreliable_ordered")
func _net_state(time: float, xform: Transform3D, aim: Vector3) -> void:
	_motion.push(time, xform)
	_move_dir = aim  # For the lunge's lean


@rpc("authority", "reliable")
func _net_phase(new_state: State) -> void:
	if is_dead:
		return
	state = new_state
	_state_time = 0.0
	_on_state_entered(new_state)


@rpc("authority", "reliable")
func _net_flash() -> void:
	_flash = HIT_FLASH_TIME


@rpc("authority", "call_local", "reliable")
func _net_die() -> void:
	_pop()


@rpc("any_peer", "reliable")
func _request_hit(damage: float, knockback_velocity: Vector3) -> void:
	if Net.is_server:
		var attacker: PlayerClass3D = Global.Game3D.rpc_sender() if Global.Game3D else null
		receive_hit(Vector3.ZERO, Combat.vetted_damage(damage, attacker), knockback_velocity, attacker)
