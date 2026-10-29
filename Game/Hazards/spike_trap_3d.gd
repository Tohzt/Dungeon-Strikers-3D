class_name SpikeTrap3D extends Area3D
## A floor plate whose spikes cycle: down (safe), a warning peek, then up,
## when they skewer whoever is on it: damage and a big pop into the air.
## Anything standing on it as the spikes come up gets hit, and so does
## anything that walks (or is knocked) onto it while they're up, once per
## cycle each. The ball gets popped too. Its origin is the middle of the
## plate, on the floor; the plate is built when it loads.
##
## The cycle runs off the wall clock, so every machine shows the spikes at
## (nearly) the same moment; only the deciding machine (see Net.decides)
## lands the hits, which go through Combat like any other attack.

enum Stage { DOWN, WARN, UP }

## Plate size: X by Z, in meters.
@export var size: Vector2 = Vector2(4, 4)
## Seconds for a whole down-warn-up cycle.
@export var period: float = 3.5
@export var warn_time: float = 0.7
@export var up_time: float = 1.0
## Shifts this trap's cycle (seconds), so neighbours don't all fire at once.
@export var offset: float = 0.0
@export var damage: float = 30.0
@export var knockback: float = 4.0
@export var pop: float = 9.0
@export var ball_pop: float = 7.0

const SPIKE_HEIGHT := 0.8
const SPIKE_RADIUS := 0.12
const SPIKE_SPACING := 0.7
## How far the tips show during the warning.
const WARN_PEEK := 0.25
const SPIKE_SPEED := 14.0  # m/s the spikes move between stages
## The plate stands a little proud of the floor, over any lines painted on it.
const PLATE_TOP := 0.15
const PLATE_COLOR := Color(0.25, 0.24, 0.26)
const WARN_COLOR := Color(1.0, 0.2, 0.1)
## Hits only count up to this high over the plate.
const REACH_HEIGHT := 1.5

var stage: Stage = Stage.DOWN
var _spikes: Node3D
var _plate_material: StandardMaterial3D
## Bodies already hit during this UP stage.
var _hit: Array[Node3D] = []


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
	_spikes.position.y = -SPIKE_HEIGHT - 0.05


func _physics_process(delta: float) -> void:
	var new_stage: Stage = _stage_now()
	if new_stage != stage:
		stage = new_stage
		_hit.clear()
		if stage == Stage.UP:
			Sfx.play(&"hit_wall", global_position)
	var target_y: float = -SPIKE_HEIGHT - 0.05
	if stage == Stage.WARN:
		target_y = -SPIKE_HEIGHT + WARN_PEEK
	elif stage == Stage.UP:
		target_y = 0.0
	_spikes.position.y = move_toward(_spikes.position.y, target_y, SPIKE_SPEED * delta)
	var warn: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 20.0) if stage == Stage.WARN else 0.0
	_plate_material.emission_energy_multiplier = warn * 2.0
	if stage == Stage.UP and Net.decides():
		_skewer()


func _stage_now() -> Stage:
	var t: float = fposmod(Time.get_unix_time_from_system() + offset, period)
	if t >= period - up_time:
		return Stage.UP
	if t >= period - up_time - warn_time:
		return Stage.WARN
	return Stage.DOWN


## Server/offline: hit everything on the plate that hasn't been yet.
func _skewer() -> void:
	for body: Node3D in get_overlapping_bodies():
		if _hit.has(body):
			continue
		_hit.append(body)
		var away: Vector3 = body.global_position - global_position
		if body is Ball3D:
			Combat.push(body, Vector3.UP * ball_pop + away.normalized() * 1.5)
		elif body is PlayerClass3D or Combat.is_monster(body):
			Combat.strike(body, away, damage, knockback, pop, -1.0, null, 0.0, DamageType.Kind.PIERCE)


func _build() -> void:
	_plate_material = StandardMaterial3D.new()
	_plate_material.albedo_color = PLATE_COLOR
	_plate_material.metallic = 0.6
	_plate_material.roughness = 0.5
	_plate_material.emission_enabled = true
	_plate_material.emission = WARN_COLOR
	_plate_material.emission_energy_multiplier = 0.0
	var plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(size.x, PLATE_TOP, size.y)
	plate_mesh.material = _plate_material
	plate.mesh = plate_mesh
	plate.position.y = PLATE_TOP * 0.5
	add_child(plate)

	var spike_material := StandardMaterial3D.new()
	spike_material.albedo_color = Color(0.75, 0.75, 0.8)
	spike_material.metallic = 0.9
	spike_material.roughness = 0.3
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = SPIKE_RADIUS
	cone.height = SPIKE_HEIGHT
	cone.radial_segments = 6
	cone.rings = 1
	cone.material = spike_material
	var columns: int = maxi(int(size.x / SPIKE_SPACING), 1)
	var rows: int = maxi(int(size.y / SPIKE_SPACING), 1)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = cone
	multimesh.instance_count = columns * rows
	for i in columns:
		for j in rows:
			var x: float = (i - (columns - 1) * 0.5) * SPIKE_SPACING
			var z: float = (j - (rows - 1) * 0.5) * SPIKE_SPACING
			multimesh.set_instance_transform(i * rows + j, Transform3D(Basis(), Vector3(x, SPIKE_HEIGHT * 0.5, z)))
	var instances := MultiMeshInstance3D.new()
	instances.multimesh = multimesh
	_spikes = Node3D.new()
	_spikes.add_child(instances)
	add_child(_spikes)
