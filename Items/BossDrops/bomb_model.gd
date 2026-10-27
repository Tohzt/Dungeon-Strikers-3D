class_name BombModel3D extends Node3D
## How a bomb looks (see Bomb3D): a round iron shell banded in its type's
## color, with a lit fuse on top. Also floats in a boss that swallowed one.
## The band glows brighter, and the spark flickers faster, as the fuse
## burns down (see set_urgency).

const SHELL_RADIUS := 0.42
const SHELL_COLOR := Color(0.13, 0.13, 0.16)
const SPARK_COLOR := Color(1.0, 0.75, 0.3)

var _band_material := StandardMaterial3D.new()
var _spark: MeshInstance3D
var _light: OmniLight3D
var _color: Color = Color.WHITE
## 0 = plenty of fuse left, 1 = about to go off.
var _urgency: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	var shell_material := StandardMaterial3D.new()
	shell_material.albedo_color = SHELL_COLOR
	shell_material.metallic = 0.6
	shell_material.roughness = 0.45
	var shell := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = SHELL_RADIUS
	sphere.height = SHELL_RADIUS * 2.0
	sphere.material = shell_material
	shell.mesh = sphere
	add_child(shell)
	# The band round its middle, in its type's color
	_band_material.emission_enabled = true
	var band := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = SHELL_RADIUS - 0.04
	ring.outer_radius = SHELL_RADIUS + 0.05
	ring.material = _band_material
	band.mesh = ring
	add_child(band)
	# The neck the fuse comes out of
	var neck := MeshInstance3D.new()
	var cap := CylinderMesh.new()
	cap.top_radius = 0.12
	cap.bottom_radius = 0.14
	cap.height = 0.14
	cap.material = shell_material
	neck.mesh = cap
	neck.position = Vector3.UP * (SHELL_RADIUS + 0.03)
	add_child(neck)
	var fuse_material := StandardMaterial3D.new()
	fuse_material.albedo_color = Color(0.55, 0.45, 0.3)
	var fuse := MeshInstance3D.new()
	var cord := CylinderMesh.new()
	cord.top_radius = 0.025
	cord.bottom_radius = 0.025
	cord.height = 0.2
	cord.material = fuse_material
	fuse.mesh = cord
	fuse.position = Vector3(0.03, SHELL_RADIUS + 0.17, 0.0)
	fuse.rotation.z = -0.3
	add_child(fuse)
	var spark_material := StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.albedo_color = SPARK_COLOR
	_spark = MeshInstance3D.new()
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.06
	spark_mesh.height = 0.12
	spark_mesh.material = spark_material
	_spark.mesh = spark_mesh
	_spark.position = Vector3(0.07, SHELL_RADIUS + 0.28, 0.0)
	add_child(_spark)
	_light = OmniLight3D.new()
	_light.omni_range = 3.0
	_light.position = _spark.position
	add_child(_light)
	_apply_color()


## Band and glow in `color` (the bomb's type, see Bomb3D.COLORS).
func set_color(color: Color) -> void:
	_color = color
	if is_node_ready():
		_apply_color()


## How close to going off it is, 0 to 1.
func set_urgency(value: float) -> void:
	_urgency = clampf(value, 0.0, 1.0)


func _apply_color() -> void:
	_band_material.albedo_color = _color
	_band_material.emission = _color
	_light.light_color = _color.lerp(SPARK_COLOR, 0.5)


func _process(delta: float) -> void:
	# Flickers faster and glows harder the less fuse is left
	_time += delta * lerpf(6.0, 30.0, _urgency * _urgency)
	var flicker: float = 0.5 + 0.5 * sin(_time)
	_spark.scale = Vector3.ONE * (0.8 + 0.5 * flicker)
	_band_material.emission_energy_multiplier = lerpf(0.6, 3.0, _urgency) * (0.6 + 0.4 * flicker)
	_light.light_energy = lerpf(0.6, 2.5, _urgency) * (0.5 + 0.5 * flicker)
