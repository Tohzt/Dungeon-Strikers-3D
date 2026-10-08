class_name SlimeMinion3D extends CharacterBody3D
## A little slime the boss spits out. It lands, then hops after the nearest
## player and bumps them for light damage. Fragile and light: a few hits
## pop it, and every hit knocks it flying. It pops when its boss is beaten.
## Online the server runs it and streams where it is; everyone else just
## plays that back (like the boss).

enum State {
	LAUNCHED,  ## Flying out of the boss
	IDLE,      ## Resting between hops
	HOP_PREP,  ## Squashing down before a hop
	HOP,       ## In the air
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

@export_category("Bump")
@export var bump_damage: float = 5.0
@export var bump_knockback: float = 7.0
@export var bump_pop: float = 2.0
const BUMP_COOLDOWN := 0.8  # Per player

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

var hp: float = 0.0
var is_dead: bool = false
var state: State = State.LAUNCHED
var _state_time: float = 0.0
var _rest_time: float = 0.3
var _move_dir: Vector3 = Vector3.ZERO
## Sideways slide from being hit, on top of hopping.
var _knockback: Vector3 = Vector3.ZERO
var _bump_cooldowns: Dictionary[Node, float] = {}
var _flash: float = 0.0
var _squash: float = 1.0
var _squash_vel: float = 0.0
var _wobble_time: float = 0.0

## Online: the server sends where it is; clients play it back.
var _motion := NetMotion.new()


func _ready() -> void:
	add_to_group("Minion")
	hp = max_hp
	_wobble_time = randf() * TAU  # So a pair doesn't wobble in sync


## Fly out of the boss at `launch_velocity` (by whoever simulates it).
func launch(launch_velocity: Vector3) -> void:
	velocity = launch_velocity
	_set_state(State.LAUNCHED)


func _physics_process(delta: float) -> void:
	if not Net.decides() or is_dead:
		return
	_state_time += delta
	for key: Node in _bump_cooldowns.keys():
		_bump_cooldowns[key] -= delta
		if _bump_cooldowns[key] <= 0.0 or not is_instance_valid(key):
			_bump_cooldowns.erase(key)

	if not is_on_floor():
		velocity += get_gravity() * gravity_scale * delta
	match state:
		State.LAUNCHED, State.HOP:
			if is_on_floor() and _state_time > 0.1:
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

	_bump_players()
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
		State.HOP, State.LAUNCHED:
			_squash_vel += 5.0
		State.IDLE:
			_squash_vel -= 6.0


func _land() -> void:
	velocity = Vector3.ZERO
	_rest_time = randf_range(hop_rest_min, hop_rest_max)
	_set_state(State.IDLE)


## Hop toward the nearest living player in range, or somewhere at random.
func _choose_hop() -> void:
	var target: PlayerClass3D = _nearest_player()
	if target:
		_move_dir = _flat(target.global_position - global_position).normalized()
		_move_dir = _move_dir.rotated(Vector3.UP, randf_range(-0.3, 0.3))
	else:
		_move_dir = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	_set_state(State.HOP_PREP)


func _bump_players() -> void:
	for player: PlayerClass3D in _players():
		if player.is_dead() or _bump_cooldowns.has(player):
			continue
		var offset: Vector3 = player.global_position - global_position
		if offset.y < -1.0 or offset.y > HEIGHT + 1.0:
			continue
		var flat: Vector3 = _flat(offset)
		if flat.length() > RADIUS + PLAYER_RADIUS + 0.1:
			continue
		_bump_cooldowns[player] = BUMP_COOLDOWN
		var dir: Vector3 = flat if flat.length() > 0.01 else _move_dir
		Combat.strike(player, dir, bump_damage, bump_knockback, bump_pop)


# ===== DAMAGE =====

## Called by Combat.strike for every attack that lands on it. Online the
## server keeps the HP, so other machines pass their hits on to it.
func receive_hit(_dir: Vector3, damage: float, knockback_velocity: Vector3, _attacker: Node3D = null) -> bool:
	if is_dead:
		return false
	if not Net.decides():
		if Net.match_synced:
			_request_hit.rpc_id(Net.SERVER_ID, damage, knockback_velocity)
		return true
	Sfx.play_everywhere(&"hit_slime", global_position)
	_knockback = _flat(knockback_velocity) * HIT_KNOCKBACK_RATIO
	velocity.y = max(velocity.y, knockback_velocity.y * HIT_KNOCKBACK_RATIO)
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


func _nearest_player() -> PlayerClass3D:
	var best: PlayerClass3D = null
	var best_dist: float = chase_range
	for player: PlayerClass3D in _players():
		if not is_instance_valid(player) or player.is_dead():
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
	_squash_vel += (target - _squash) * SQUASH_STIFFNESS * delta
	_squash_vel *= max(1.0 - SQUASH_DAMPING * delta, 0.0)
	_squash = clamp(_squash + _squash_vel * delta, 0.4, 1.6)
	var side: float = 1.0 / sqrt(_squash)
	visual.scale = Vector3(side, _squash, side)


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
		_net_state.rpc(NetInterpolator.now(), global_transform)


@rpc("authority", "unreliable_ordered")
func _net_state(time: float, xform: Transform3D) -> void:
	_motion.push(time, xform)


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
		receive_hit(Vector3.ZERO, damage, knockback_velocity)
