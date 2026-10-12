class_name WeaponPhantom3D extends Node3D
## A held weapon sent flying by a heavy attack (see WeaponMove3D): out along
## the aim and back like a boomerang, or round and round its wielder. It's a
## copy of the weapon's model; the weapon itself stays in the hand, hidden
## and unable to swing (Weapon3D.away), until the copy comes back.
##
## Like a wave (see AttackWave3D), online it's real on the wielder's machine
## and just for show everywhere else.

enum Mode { BOOMERANG, ORBIT }

## How close it has to get on the way back to be caught.
const CATCH_DISTANCE := 1.2
## The boomerang turns for home after this share of its flight out...
const BOOMERANG_OUT_SHARE := 0.5
## ...and gives up and comes straight back after this long, whatever happens.
const MAX_FLIGHT_TIME := 3.0
## The boomerang's spin, turns per second.
const SPIN_SPEED := 3.0
## The hitbox round it.
const HIT_RADIUS := 0.9
## Hits a body again after this long (an orbit cuts the same people up more
## than once; a boomerang gets them on the way out and back).
const REHIT_TIME := 0.3

var mode: Mode = Mode.BOOMERANG
var weapon: Weapon3D
var wielder: Node3D
var move: WeaponMove3D
var deals_damage: bool = true
var damage: float = 0.0
var knockback: float = 0.0
## Orbits clockwise (1) or the other way (-1), and from which angle.
var orbit_sign: float = 1.0
var _start_angle: float = 0.0
var _dir: Vector3 = Vector3.FORWARD
var _age: float = 0.0
var _out: Vector3  # Boomerang: where it turns back
var _start: Vector3
var _returning: bool = false
var _model: Node3D
var _hit_times: Dictionary[Node, float] = {}
var _shape := SphereShape3D.new()


## Send `from_weapon` out on `with_move`'s action, along `dir`.
static func launch(with_move: WeaponMove3D, from_weapon: Weapon3D, by: Node3D, dir: Vector3, real: bool,
		sign: float = 1.0) -> WeaponPhantom3D:
	var phantom := WeaponPhantom3D.new()
	phantom.mode = Mode.ORBIT if with_move.action == WeaponMove3D.Action.ORBIT else Mode.BOOMERANG
	phantom.move = with_move
	phantom.weapon = from_weapon
	phantom.wielder = by
	phantom.deals_damage = real
	phantom.orbit_sign = sign
	dir.y = 0.0
	phantom._dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	var behavior: WeaponBehavior3D = from_weapon.Behavior
	phantom.damage = (behavior.get_damage() if behavior else 20.0) * with_move.action_damage_scale * from_weapon.power
	phantom.knockback = (behavior.knockback_force if behavior else 8.0) * with_move.action_knockback_scale * from_weapon.power
	by.get_parent().add_child(phantom)
	phantom._begin()
	return phantom


func _begin() -> void:
	top_level = true
	_shape.radius = HIT_RADIUS
	_start = wielder.global_position
	global_position = weapon.global_position
	_out = _start + _dir * move.throw_reach
	# Each dagger starts on its own side, and they go round opposite ways
	_start_angle = atan2(_dir.z, _dir.x) + (0.0 if orbit_sign > 0.0 else PI)
	var source: Node3D = weapon.get_node_or_null(^"Model") as Node3D
	if source:
		_model = source.duplicate() as Node3D
		add_child(_model)
		_model.transform = Transform3D(Basis(), Vector3.ZERO)
		# Lie flat to spin like a blade
		_model.rotation = Vector3(PI / 2.0, 0.0, 0.0)
		_model.position = Vector3(0, 0, -0.4)
	weapon.set_away(true)
	Sfx.play(&"throw", global_position)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(wielder) or not is_instance_valid(weapon) or weapon.wielder != wielder:
		_finish()
		return
	_age += delta
	match mode:
		Mode.BOOMERANG:
			_fly_boomerang(delta)
		Mode.ORBIT:
			_fly_orbit()
	rotation.y += SPIN_SPEED * TAU * delta * orbit_sign
	if deals_damage:
		_hit_overlapping()


## Out along the aim, slowing to a stop, then back to wherever the wielder
## has got to, faster and faster.
func _fly_boomerang(delta: float) -> void:
	var out_time: float = move.throw_reach / maxf(move.throw_speed, 0.1) / BOOMERANG_OUT_SHARE
	if not _returning:
		var t: float = minf(_age / out_time, 1.0)
		var next: Vector3 = _start.lerp(_out, 1.0 - (1.0 - t) * (1.0 - t))
		next.y = _start.y
		if _wall_between(global_position, next) or t >= 1.0:
			_returning = true
			_hit_times.clear()
		else:
			global_position = next
		return
	var home: Vector3 = wielder.global_position
	var to_home: Vector3 = home - global_position
	var speed: float = move.throw_speed * (1.0 + (_age - out_time) * 1.5)
	if to_home.length() <= maxf(CATCH_DISTANCE, speed * delta) or _age > MAX_FLIGHT_TIME:
		_finish()
		return
	global_position += to_home.normalized() * speed * delta


## Round the wielder: out to orbit_radius and back in as it goes round.
func _fly_orbit() -> void:
	var t: float = _age / maxf(move.orbit_time, 0.01)
	if t >= 1.0:
		_finish()
		return
	var angle: float = _start_angle + orbit_sign * move.orbit_turns * TAU * t
	var radius: float = move.orbit_radius * sqrt(sin(t * PI))
	global_position = wielder.global_position + Vector3(cos(angle), 0.0, sin(angle)) * maxf(radius, 0.6)


func _wall_between(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, Combat.WORLD_MASK)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _hit_overlapping() -> void:
	var exclude: Array[RID] = []
	if wielder is CollisionObject3D:
		exclude.append(wielder.get_rid())
	for body: Node3D in Combat.overlaps(get_world_3d(), _shape, global_transform, exclude):
		if body is Weapon3D:
			continue
		if _hit_times.has(body) and _age - _hit_times[body] < REHIT_TIME:
			continue
		_hit_times[body] = _age
		var dir: Vector3 = body.global_position - global_position
		if mode == Mode.BOOMERANG:
			dir = (wielder.global_position - global_position) if _returning else _dir
		if body is Ball3D:
			Sfx.play_everywhere(&"hit_ball", body.global_position)
			if weapon.Behavior:
				weapon.Behavior.hit_ball(body, dir, Vector3.ZERO, knockback, wielder)
			continue
		if Combat.strike(body, dir, damage, knockback, Weapon3D.HIT_POP, -1.0, wielder):
			weapon.wear_once()


## Back in the hand.
func _finish() -> void:
	if is_instance_valid(weapon):
		weapon.set_away(false)
		if weapon.wielder:
			Sfx.play(&"equip_small", weapon.global_position)
	queue_free()
