class_name FireStrip3D extends Area3D
## A strip of burning floor. Anyone in it gets scorched every `tick`
## seconds (a little damage and a hop, so they tend to bounce out), and a
## ball rolling through catches fire (see Ball3D: a burning ball hurts
## whoever it hits). Its origin is the middle of the strip, on the floor;
## the strip is built when it loads. Only the deciding machine (see
## Net.decides) lands the burns, which go through Combat like any attack.

## Strip size: X by Z, in meters.
@export var size: Vector2 = Vector2(12, 3)
@export var tick: float = 0.5
@export var damage: float = 8.0
@export var knockback: float = 3.0
@export var pop: float = 4.0
## Seconds a ball keeps burning after rolling through.
@export var ball_burn: float = 4.0

const LAVA_COLOR := Color(1.0, 0.35, 0.05)
const REACH_HEIGHT := 1.2
## The lava stands a little proud of the floor, over any lines painted on it.
const LAVA_TOP := 0.15

var _tick_left: float = 0.0
var _lava_material: StandardMaterial3D
var _light: OmniLight3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = Combat.HIT_MASK
	monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, REACH_HEIGHT, size.y)
	shape.shape = box
	shape.position = Vector3.UP * REACH_HEIGHT * 0.5
	add_child(shape)
	_build()
	Sfx.play_loop(&"fire_loop", self)


func _process(_delta: float) -> void:
	var t: float = Time.get_ticks_msec() / 1000.0
	var flicker: float = 0.8 + 0.2 * sin(t * 7.0) * sin(t * 13.0)
	_lava_material.emission_energy_multiplier = 2.5 * flicker
	_light.light_energy = 2.0 * flicker


func _physics_process(delta: float) -> void:
	if not Net.decides():
		return
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = tick
	for body: Node3D in get_overlapping_bodies():
		if body is Ball3D:
			body._ignite(ball_burn, "")
		elif body is PlayerClass3D or Combat.is_monster(body):
			Combat.strike(body, _out_of_strip(body), damage, knockback, pop, -1.0, null, 0.0, DamageType.Kind.FIRE)


## The quickest way out: across the strip's short side, away from its middle.
func _out_of_strip(body: Node3D) -> Vector3:
	var local: Vector3 = to_local(body.global_position)
	var out := Vector3(signf(local.x), 0, 0) if size.x < size.y else Vector3(0, 0, signf(local.z))
	if out.is_zero_approx():
		out = Vector3.BACK
	return global_basis * out


func _build() -> void:
	_lava_material = StandardMaterial3D.new()
	_lava_material.albedo_color = LAVA_COLOR.darkened(0.3)
	_lava_material.emission_enabled = true
	_lava_material.emission = LAVA_COLOR
	var lava := MeshInstance3D.new()
	var lava_mesh := BoxMesh.new()
	lava_mesh.size = Vector3(size.x, LAVA_TOP, size.y)
	lava_mesh.material = _lava_material
	lava.mesh = lava_mesh
	lava.position.y = LAVA_TOP * 0.5
	add_child(lava)

	var flames := CPUParticles3D.new()
	flames.amount = int(size.x * size.y * 3.0)
	flames.lifetime = 0.8
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flames.emission_box_extents = Vector3(size.x * 0.5, 0.05, size.y * 0.5)
	flames.direction = Vector3.UP
	flames.spread = 10.0
	flames.gravity = Vector3.UP * 2.0
	flames.initial_velocity_min = 0.5
	flames.initial_velocity_max = 1.5
	flames.scale_amount_min = 0.25
	flames.scale_amount_max = 0.5
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.8, 0.2, 1.0))
	fade.set_color(1, Color(1.0, 0.2, 0.0, 0.0))
	flames.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 0.6)
	var flame_material := StandardMaterial3D.new()
	flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	flame_material.vertex_color_use_as_albedo = true
	quad.material = flame_material
	flames.mesh = quad
	add_child(flames)

	_light = OmniLight3D.new()
	_light.light_color = LAVA_COLOR
	_light.omni_range = maxf(size.x, size.y) * 0.6
	_light.position.y = 1.0
	add_child(_light)
