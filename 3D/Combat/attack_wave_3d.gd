class_name AttackWave3D extends Node3D
## A wave sent out by a swing (see AttackWaveSpec3D, WeaponMove3D): it
## travels away from whoever swung, hitting what it passes through, then
## fades. Light swings send a short one, so a slash reaches a little past the
## blade; heavies send big ones that go much further.
##
## Like an arrow (see Arrow3D), online the wave is real on the attacker's
## machine, which decides what it hits; everyone else's copy is just for show.

## Seconds it takes to fade in, and to fade out once it's done.
const FADE_IN := 0.05
const FADE_OUT := 0.12
## Seconds a bursting orb takes to swell out to its burst_radius and fade.
const BURST_TIME := 0.3
## A held orb (see hold_orb) throbs this much bigger, this often (s), once grown.
const HOLD_THROB := 1.1
const HOLD_THROB_TIME := 0.35
## A shockwave's hitbox and look sit this far below the wielder's middle,
## on the ground.
const GROUND_DROP := 0.9
## Segments in a crescent's or ring's curve.
const CURVE_SEGMENTS := 20
const RING_SEGMENTS := 48

var spec: AttackWaveSpec3D
## Who sent it: never hit, and credited with what it hits.
var attacker: Node3D = null
## The weapon it came from: plays the ball its own way, and wears from hits.
var weapon: Weapon3D = null
## False for online copies of someone else's wave, which only show it.
var deals_damage: bool = true
var damage: float = 0.0
var knockback: float = 0.0
## How far it goes (a ring: its final radius), after any charge scaling.
var reach: float = 0.0
## spec.color, leaned toward its weapon's rarity's (see Weapon3D.tint).
var color: Color

var _dir: Vector3 = Vector3.FORWARD
var _origin: Vector3
var _travelled: float = 0.0
var _delay: float = 0.0
var _age: float = 0.0
## Fading out, done hitting.
var _ending: bool = false
var _end_time: float = 0.0
## Bodies already hit, shared with the swing that sent it (and that
## swing's other waves) so nothing is hit twice by the same attack.
var _hits: Array[Node] = []
## With spec.rehit_time: when each body was last hit.
var _hit_times: Dictionary[Node, float] = {}
var _shape: Shape3D
var _visual: Node3D
var _material: StandardMaterial3D
var _light: OmniLight3D
## Its spec.look, while it's shown.
var _look: Node3D = null
## A held orb (see hold_orb) to fly off as its look, set before it's ready.
var _held: Node3D = null


## Send `spec`'s wave from `from` along `dir` (flattened), for `attacker`
## and its `weapon`. `hits` is the attack's shared list of bodies hit
## already; `power` scales its damage, knockback and reach (a charge).
## `held` is the orb held for it while charging (see hold_orb), to fly off
## as it.
static func emit(spec: AttackWaveSpec3D, from: Node3D, from_weapon: Weapon3D, dir: Vector3, real: bool,
		hits: Array[Node] = [], power: float = 1.0, held: Node3D = null) -> AttackWave3D:
	var wave := AttackWave3D.new()
	wave.spec = spec
	wave._held = held
	wave.color = from_weapon.tint(spec.color) if from_weapon else spec.color
	wave.attacker = from
	wave.weapon = from_weapon
	wave.deals_damage = real
	wave._hits = hits
	var behavior: WeaponBehavior3D = from_weapon.Behavior if from_weapon else null
	var weapon_power: float = from_weapon.power if from_weapon else 1.0
	wave.damage = (behavior.get_damage() if behavior else 20.0) * spec.damage_scale * weapon_power * power
	wave.knockback = (behavior.knockback_force if behavior else 8.0) * spec.knockback_scale * weapon_power * power
	wave.reach = spec.reach * power
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	wave._dir = dir.rotated(Vector3.UP, deg_to_rad(spec.angle_offset))
	wave._delay = spec.delay
	from.get_parent().add_child(wave)
	wave._origin = from.global_position
	wave._place_at_start()
	wave.visible = spec.delay <= 0.0
	return wave


## An orb that looks like `spec`'s, held where its wave would start in
## front of `holder` (along its +Z), growing from nothing over `grow_time`
## seconds then throbbing, until it flies off as its wave (see emit) or is
## freed. `tint` is its color (its weapon's, see Weapon3D.tint). Null if
## nothing's shown.
static func hold_orb(spec: AttackWaveSpec3D, holder: Node3D, grow_time: float, tint: Color) -> Node3D:
	if spec.look != &"":
		return Vfx.attach(spec.look, holder, Vector3(0.0, 0.0, spec.start_offset), grow_time, spec.width, tint)
	var orb := Node3D.new()
	var material: StandardMaterial3D = _new_material()
	material.albedo_color = tint
	var light: OmniLight3D = _build_orb(spec, orb, material, tint)
	light.light_energy = 0.0
	orb.position = Vector3(0.0, 0.0, spec.start_offset)
	orb.scale = Vector3.ONE * 0.01
	holder.add_child(orb)
	var grow: Tween = orb.create_tween().set_parallel()
	grow.tween_property(orb, ^"scale", Vector3.ONE, maxf(grow_time, 0.01)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	grow.tween_property(light, ^"light_energy", 1.2, maxf(grow_time, 0.01))
	grow.chain().tween_callback(func() -> void:
		var throb: Tween = orb.create_tween().set_loops()
		throb.tween_property(orb, ^"scale", Vector3.ONE * HOLD_THROB, HOLD_THROB_TIME).set_trans(Tween.TRANS_SINE)
		throb.tween_property(orb, ^"scale", Vector3.ONE, HOLD_THROB_TIME).set_trans(Tween.TRANS_SINE))
	return orb


func _ready() -> void:
	top_level = true
	_build_shape()
	_build_visual()
	_update_look()


func _physics_process(delta: float) -> void:
	if _delay > 0.0:
		_delay -= delta
		# Sets off from wherever its sender is by then
		if is_instance_valid(attacker):
			_origin = attacker.global_position
		_place_at_start()
		if _delay > 0.0:
			return
		visible = true
	_age += delta
	if _ending:
		_end_time += delta
		_update_look()
		if _end_time >= (BURST_TIME if _bursts() else FADE_OUT):
			queue_free()
		return
	_move(delta)
	_update_look()
	if _bursts():
		# Every machine's copy decides for itself when it touches something
		if not _ending and (_travelled >= reach or _touching_anyone()):
			_end()
		return
	if deals_damage and not _ending:
		_hit_overlapping()
	if _travelled >= reach:
		_end()


func _place_at_start() -> void:
	var start: Vector3 = _origin + _dir * spec.start_offset
	if spec.shape == AttackWaveSpec3D.Shape.SHOCKWAVE:
		start.y -= GROUND_DROP
	if spec.shape == AttackWaveSpec3D.Shape.RING:
		start = _origin + Vector3.DOWN * GROUND_DROP * 0.8
	global_transform = Transform3D(_facing_basis(), start)


## Forward (+Z) along its direction, upright.
func _facing_basis() -> Basis:
	return Basis(Vector3.UP.cross(_dir).normalized(), Vector3.UP, _dir)


func _move(delta: float) -> void:
	var step: float = spec.speed * delta
	_travelled += step
	if spec.follow:
		# Rides along with its sender
		if is_instance_valid(attacker):
			_origin = attacker.global_position
		_place_at_start()
		return
	if spec.shape == AttackWaveSpec3D.Shape.RING:
		return  # Spreads in place
	var from: Vector3 = global_position
	var to: Vector3 = from + _dir * step
	if not spec.through_walls and _wall_between(from, to):
		_end()
		return
	global_position = to


## A wall in the way, at the wave's middle height (a shockwave's, a little
## above the ground, so the floor doesn't count).
func _wall_between(from: Vector3, to: Vector3) -> bool:
	var lift: Vector3 = Vector3.UP * (0.4 if spec.shape == AttackWaveSpec3D.Shape.SHOCKWAVE else 0.0)
	var query := PhysicsRayQueryParameters3D.create(from + lift, to + lift + _dir * spec.length * 0.5, Combat.WORLD_MASK)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _end() -> void:
	if _ending:
		return
	_ending = true
	_end_time = 0.0
	if is_instance_valid(_look):
		Vfx.release(_look)
		_look = null
	if spec.end_look != &"":
		var size: float = spec.burst_radius * 2.0 if _bursts() else spec.width
		var ground: Vector3 = global_position
		if spec.shape != AttackWaveSpec3D.Shape.SHOCKWAVE:
			ground.y -= GROUND_DROP
		Vfx.play(spec.end_look, ground, _dir, false, size, color)
	if _bursts():
		_burst()


## An orb that bursts rather than hitting on its way (see
## AttackWaveSpec3D.burst_radius).
func _bursts() -> bool:
	return spec.shape == AttackWaveSpec3D.Shape.ORB and spec.burst_radius > 0.0


## 0 at the start of its flight, 1 at the end.
func _progress() -> float:
	return clampf(_travelled / maxf(reach, 0.01), 0.0, 1.0)


func _size_scale() -> float:
	return lerpf(1.0, spec.grow, _progress())


func _ring_radius() -> float:
	return lerpf(spec.width * 0.5, reach, _progress())


# ===== HITTING =====

func _build_shape() -> void:
	match spec.shape:
		AttackWaveSpec3D.Shape.ORB, AttackWaveSpec3D.Shape.RING:
			_shape = SphereShape3D.new()
		_:
			_shape = BoxShape3D.new()


## Where the hitbox is now, sized for how far it's got.
func _shape_transform() -> Transform3D:
	var s: float = _size_scale()
	match spec.shape:
		AttackWaveSpec3D.Shape.ORB:
			(_shape as SphereShape3D).radius = spec.width * 0.5 * s
			return global_transform
		AttackWaveSpec3D.Shape.RING:
			(_shape as SphereShape3D).radius = _ring_radius()
			return Transform3D(Basis(), global_position + Vector3.UP * GROUND_DROP * 0.8)
	(_shape as BoxShape3D).size = Vector3(spec.width * s, spec.height, spec.length * s)
	var center: Vector3 = global_position
	if spec.shape == AttackWaveSpec3D.Shape.SHOCKWAVE:
		center.y += spec.height * 0.5
	return Transform3D(global_basis.orthonormalized(), center)


func _exclude() -> Array[RID]:
	var exclude: Array[RID] = []
	if attacker is CollisionObject3D:
		exclude.append(attacker.get_rid())
	return exclude


func _hit_overlapping() -> void:
	for body: Node3D in Combat.overlaps(get_world_3d(), _shape, _shape_transform(), _exclude()):
		if body is Weapon3D or not _can_hit(body):
			continue
		_note_hit(body)
		var dir: Vector3 = _dir
		if spec.shape == AttackWaveSpec3D.Shape.RING or spec.shape == AttackWaveSpec3D.Shape.ORB:
			dir = body.global_position - global_position
			dir.y = 0.0
			if dir.length() < 0.1:
				dir = _dir
		if body is Ball3D:
			_hit_ball(body, dir)
			continue
		var landed: bool = Combat.strike(body, dir, damage, knockback, spec.pop, -1.0, attacker)
		if landed and is_instance_valid(weapon):
			weapon.wear_once()
		if landed and not spec.pierce:
			_end()
			return


## A bursting orb touching anyone it could hurt, or the ball.
func _touching_anyone() -> bool:
	for body: Node3D in Combat.overlaps(get_world_3d(), _shape, _shape_transform(), _exclude()):
		if not body is Weapon3D and not Combat.are_teammates(body, attacker):
			return true
	return false


## Burst: hit everything within burst_radius, shoved out from the middle.
func _burst() -> void:
	Sfx.play(&"spell_impact", global_position)
	CameraShake.add(CameraShake.LIGHT, global_position)
	if not deals_damage:
		return
	(_shape as SphereShape3D).radius = spec.burst_radius
	for body: Node3D in Combat.overlaps(get_world_3d(), _shape, global_transform, _exclude()):
		if body is Weapon3D or not _can_hit(body):
			continue
		_note_hit(body)
		var dir: Vector3 = body.global_position - global_position
		dir.y = 0.0
		if dir.length() < 0.1:
			dir = _dir
		if body is Ball3D:
			_hit_ball(body, dir)
			continue
		if Combat.strike(body, dir, damage, knockback, spec.pop, -1.0, attacker) and is_instance_valid(weapon):
			weapon.wear_once()


func _can_hit(body: Node3D) -> bool:
	if spec.rehit_time > 0.0:
		return not _hit_times.has(body) or _age - _hit_times[body] >= spec.rehit_time
	return not _hits.has(body)


func _note_hit(body: Node3D) -> void:
	if spec.rehit_time > 0.0:
		_hit_times[body] = _age
	else:
		_hits.append(body)


## The weapon plays the ball its own way (see WeaponBehavior3D.hit_ball).
func _hit_ball(ball: Ball3D, dir: Vector3) -> void:
	Sfx.play_everywhere(&"hit_ball", ball.global_position)
	var strength: float = knockback * spec.ball_scale
	if is_instance_valid(weapon) and weapon.Behavior:
		weapon.Behavior.hit_ball(ball, dir, Vector3.ZERO, strength, attacker)
	else:
		Combat.strike(ball, dir, 0.0, strength, spec.pop, -1.0, attacker)


# ===== LOOK =====

static func _new_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = false
	return material


## An orb's shell and core under `parent`, and its glow (returned).
static func _build_orb(orb_spec: AttackWaveSpec3D, parent: Node3D, material: StandardMaterial3D, tint: Color) -> OmniLight3D:
	var sphere := SphereMesh.new()
	sphere.radius = orb_spec.width * 0.5
	sphere.height = orb_spec.width
	_add_mesh_to(parent, sphere, material, Basis())
	var core := SphereMesh.new()
	core.radius = orb_spec.width * 0.28
	core.height = orb_spec.width * 0.56
	_add_mesh_to(parent, core, material, Basis())
	var light := OmniLight3D.new()
	light.light_color = Color(tint, 1.0)
	light.omni_range = orb_spec.width * 1.5
	light.light_energy = 1.2
	parent.add_child(light)
	return light


func _build_visual() -> void:
	_material = _new_material()
	_visual = Node3D.new()
	add_child(_visual)
	if spec.look != &"":
		if is_instance_valid(_held):
			# Already grown, facing along us
			_held.reparent(_visual, false)
			_held.position = Vector3.ZERO
			_look = _held
		else:
			_look = Vfx.attach(spec.look, _visual, Vector3.ZERO, 0.0, spec.width, color)
		return
	if is_instance_valid(_held):
		_held.queue_free()
	match spec.shape:
		AttackWaveSpec3D.Shape.ARC:
			_add_mesh(_crescent_mesh(spec.width, spec.length), Basis(Vector3.FORWARD, deg_to_rad(spec.tilt)))
		AttackWaveSpec3D.Shape.THRUST:
			var spike: ArrayMesh = _spike_mesh(spec.width, spec.length)
			_add_mesh(spike, Basis())
			_add_mesh(spike, Basis(Vector3.FORWARD, PI / 2.0))
		AttackWaveSpec3D.Shape.SHOCKWAVE:
			_add_mesh(_crescent_mesh(spec.width, spec.length), Basis(), Vector3.UP * 0.08)
			# A low wall of dust rising off its front edge
			var wall: ArrayMesh = _crescent_mesh(spec.width, spec.height * 0.6)
			_add_mesh(wall, Basis(Vector3.RIGHT, -deg_to_rad(70.0)), Vector3.UP * 0.05)
		AttackWaveSpec3D.Shape.ORB:
			_light = _build_orb(spec, _visual, _material, color)
		AttackWaveSpec3D.Shape.RING:
			_add_mesh(_ring_mesh(), Basis(), Vector3.UP * 0.08)
	if not _light and spec.width >= 3.0:
		_light = OmniLight3D.new()
		_light.light_color = Color(color, 1.0)
		_light.omni_range = spec.width * 1.5
		_light.light_energy = 1.2
		add_child(_light)


func _add_mesh(mesh: Mesh, basis: Basis, offset: Vector3 = Vector3.ZERO) -> void:
	_add_mesh_to(_visual, mesh, _material, basis, offset)


static func _add_mesh_to(parent: Node3D, mesh: Mesh, material: Material, basis: Basis, offset: Vector3 = Vector3.ZERO) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.transform = Transform3D(basis, offset)
	parent.add_child(instance)


## Fades in, then out over the last part of its flight (and once it's done).
func _update_look() -> void:
	if spec.look != &"":
		_visual.scale = Vector3.ONE * _size_scale()
		return
	var alpha: float = clampf(_age / FADE_IN, 0.0, 1.0)
	if not _bursts():
		alpha *= 1.0 - pow(_progress(), 3.0) * 0.7
	if _ending and _bursts():
		_update_burst_look()
		return
	if _ending:
		alpha *= 1.0 - clampf(_end_time / FADE_OUT, 0.0, 1.0)
	_material.albedo_color = Color(color, color.a * alpha)
	if _light:
		_light.light_energy = 1.2 * alpha
	if spec.shape == AttackWaveSpec3D.Shape.RING:
		var r: float = _ring_radius()
		_visual.scale = Vector3(r, 1.0, r)
	else:
		var s: float = _size_scale()
		_visual.scale = Vector3.ONE * s
	if spec.shape == AttackWaveSpec3D.Shape.ORB:
		_visual.rotation.y += 0.2


## Swells out to its burst_radius, flaring, and fades.
func _update_burst_look() -> void:
	var t: float = clampf(_end_time / BURST_TIME, 0.0, 1.0)
	var full: float = spec.burst_radius / maxf(spec.width * 0.5, 0.01)
	_visual.scale = Vector3.ONE * lerpf(_size_scale(), full, ease(t, 0.3))
	_material.albedo_color = Color(color, color.a * (1.0 - t * t))
	if _light:
		_light.light_energy = 4.0 * (1.0 - t)
		_light.omni_range = spec.burst_radius * 2.0


## A crescent `width` across, `depth` thick in the middle, bowed forward
## (+Z) in the XZ plane. Solid along its front edge, fading out behind.
static func _crescent_mesh(width: float, depth: float) -> ArrayMesh:
	var radius: float = maxf(width * 0.75, 0.1)
	var half_angle: float = asin(minf(width * 0.5 / radius, 1.0))
	var center := Vector3(0, 0, -radius + depth * 0.5)
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	for i in CURVE_SEGMENTS + 1:
		var u: float = float(i) / CURVE_SEGMENTS
		var a: float = lerpf(-half_angle, half_angle, u)
		var thickness: float = depth * sin(u * PI)  # Tapers to points at the tips
		var out := Vector3(sin(a), 0, cos(a))
		verts.append(center + out * radius)
		colors.append(Color(1, 1, 1, 1))
		verts.append(center + out * (radius - thickness))
		colors.append(Color(1, 1, 1, 0))
	return _strip_mesh(verts, colors)


## A flat diamond spike `width` across and `length` long, point forward (+Z).
static func _spike_mesh(width: float, length: float) -> ArrayMesh:
	var verts := PackedVector3Array([
		Vector3(0, 0, length * 0.6), Vector3(-width * 0.5, 0, 0),
		Vector3(width * 0.5, 0, 0), Vector3(0, 0, -length * 0.6)])
	var colors := PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	return _strip_mesh(verts, colors)


## A flat band round a circle of radius 1, solid on its outer edge.
func _ring_mesh() -> ArrayMesh:
	var band: float = clampf(spec.length / maxf(reach, 0.1), 0.05, 0.5)
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	for i in RING_SEGMENTS + 1:
		var a: float = TAU * i / RING_SEGMENTS
		var out := Vector3(cos(a), 0, sin(a))
		verts.append(out)
		colors.append(Color(1, 1, 1, 1))
		verts.append(out * (1.0 - band))
		colors.append(Color(1, 1, 1, 0))
	return _strip_mesh(verts, colors)


static func _strip_mesh(verts: PackedVector3Array, colors: PackedColorArray) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
	return mesh
