class_name WeaponShatter3D extends Node3D
## The look of a weapon breaking: shards flung out, a flash, and a shockwave
## ring as wide as its burst. Looks only (the burst's hits are decided by
## Weapon3D); frees itself when done.

const LIFETIME := 0.6
const SHARD_COUNT := 10
const SHARD_SIZE := 0.14
const SHARD_SPEED_MIN := 4.0
const SHARD_SPEED_MAX := 8.0
const SHARD_GRAVITY := 14.0
const FLASH_ENERGY := 6.0
const FLASH_COLOR := Color(1.0, 0.85, 0.6)

var _radius: float = 2.5
var _age: float = 0.0
var _shards: Array[MeshInstance3D] = []
var _shard_velocities: Array[Vector3] = []
var _ring: MeshInstance3D
var _ring_material: StandardMaterial3D
var _flash: OmniLight3D


## A burst `radius` wide at `pos`, its shards tinted `color`.
static func spawn(parent: Node, pos: Vector3, color: Color, radius: float) -> void:
	if not parent or not parent.is_inside_tree():
		return
	var shatter := WeaponShatter3D.new()
	shatter._radius = radius
	parent.add_child(shatter)
	shatter.global_position = pos
	shatter._build(color)


func _build(color: Color) -> void:
	var shard_material := StandardMaterial3D.new()
	shard_material.albedo_color = color
	shard_material.emission_enabled = true
	shard_material.emission = color.lerp(FLASH_COLOR, 0.5)
	shard_material.emission_energy_multiplier = 2.0
	var shard_mesh := BoxMesh.new()
	shard_mesh.size = Vector3.ONE * SHARD_SIZE
	shard_mesh.material = shard_material
	for i in SHARD_COUNT:
		var shard := MeshInstance3D.new()
		shard.mesh = shard_mesh
		shard.rotation = Vector3(randf(), randf(), randf()) * TAU
		add_child(shard)
		_shards.append(shard)
		var out := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		_shard_velocities.append((out + Vector3.UP * randf_range(0.3, 1.0)).normalized() * randf_range(SHARD_SPEED_MIN, SHARD_SPEED_MAX))

	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.albedo_color = Color(FLASH_COLOR, 0.8)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.85
	ring_mesh.outer_radius = 1.0
	ring_mesh.material = _ring_material
	_ring = MeshInstance3D.new()
	_ring.mesh = ring_mesh
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	_flash = OmniLight3D.new()
	_flash.light_color = FLASH_COLOR
	_flash.light_energy = FLASH_ENERGY
	_flash.omni_range = _radius * 2.0
	add_child(_flash)
	_update_look(0.0)


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	for i in _shards.size():
		_shard_velocities[i].y -= SHARD_GRAVITY * delta
		_shards[i].position += _shard_velocities[i] * delta
		_shards[i].rotate_x(10.0 * delta)
	_update_look(_age / LIFETIME)


func _update_look(t: float) -> void:
	var ease_out: float = 1.0 - (1.0 - t) * (1.0 - t)
	_ring.scale = Vector3.ONE * lerpf(0.2, _radius, ease_out)
	_ring_material.albedo_color.a = 0.8 * (1.0 - t)
	_flash.light_energy = FLASH_ENERGY * (1.0 - t) * (1.0 - t)
	for shard: MeshInstance3D in _shards:
		shard.scale = Vector3.ONE * (1.0 - t)
