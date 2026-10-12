class_name BossPen3D extends Node3D
## A walled pen that holds a boss until a countdown runs out, then opens its
## gate and lets the boss loose. The gate stays open until the next boss is
## shut in, so anything inside (e.g. an altar) can be reached meanwhile. Its
## origin is the middle of the pen floor; the gate is on the +Z side. The
## walls, gate and (optionally) floor are built when it loads, sized by
## `inner_size`. Set into a level's wall, it makes a boss lair behind a door.
##
## The mode puts a boss in with shut() (on every machine, e.g. from an
## Net.everywhere RPC); the deciding machine (see Net.decides) opens it
## once the countdown ends, on every machine together.

## The pen let its boss out. On every machine.
signal released(boss: Boss3D)

## Room inside: width (X) by depth (Z), in meters.
@export var inner_size: Vector2 = Vector2(16, 12)
@export var wall_height: float = 5.0
@export var wall_thickness: float = 1.0
enum GateStyle {
	BARS,   ## Iron bars that sink into the floor
	DOORS,  ## A giant pair of doors that swing inward
}

@export var gate_style: GateStyle = GateStyle.BARS
## Build a floor under the pen, for one set outside the level's own floor.
@export var build_floor: bool = false
## Seconds a boss stays shut in before the gate drops.
@export var release_time: float = 20.0
## Floats over the gate while it counts down. %d = seconds left.
@export var countdown_text: String = "BOSS IN %d"
## Shown on the scoreboard as the gate drops. %s = the boss's name.
@export var release_message: String = "%s breaks loose!"

const WALL_COLOR := Color(0.32, 0.3, 0.36)
const BAR_COLOR := Color(0.18, 0.18, 0.2)
const FLOOR_COLOR := Color(0.2, 0.19, 0.22)
const WOOD_COLOR := Color(0.34, 0.21, 0.12)
const DOOR_THICKNESS := 0.5
const DOOR_SWING := 95.0  # Degrees each door turns, into the pen
const BAR_SPACING := 0.8
const BAR_RADIUS := 0.08
const GATE_DEPTH := 0.4
const GATE_MOVE_TIME := 0.8
## Seconds the boss takes to get going once let out (Boss3D.start_delay).
const WAKE_DELAY := 0.6
## How far past the gate anyone caught inside is put when the pen shuts.
const CLEAR_DISTANCE := 2.5

var boss: Boss3D = null
## Seconds until the gate drops; below zero when nothing's counting down.
var release_left: float = -1.0

var _gate: StaticBody3D
var _gate_shape: CollisionShape3D
var _gate_tween: Tween
## DOORS: the left and right doors, each turning about its outer edge.
var _leaves: Array[Node3D] = []
var _label: Label3D
## Server/offline: the release has been sent, don't send it again.
var _releasing: bool = false


func _ready() -> void:
	add_to_group("BossPen")
	var half := Vector2(inner_size.x, inner_size.y) * 0.5
	var outer_x: float = inner_size.x + wall_thickness * 2.0
	_add_wall(Vector3(0, 0, -half.y - wall_thickness * 0.5), Vector3(outer_x, wall_height, wall_thickness))
	_add_wall(Vector3(-half.x - wall_thickness * 0.5, 0, 0), Vector3(wall_thickness, wall_height, inner_size.y))
	_add_wall(Vector3(half.x + wall_thickness * 0.5, 0, 0), Vector3(wall_thickness, wall_height, inner_size.y))
	if build_floor:
		_add_wall(Vector3(0, -0.5, 0), Vector3(outer_x, 0.5, inner_size.y), FLOOR_COLOR)
	_build_gate(half.y)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	# Big enough to read from the zoomed-out match camera
	_label.pixel_size = 0.01
	_label.font_size = 96
	_label.outline_size = 24
	_label.modulate = Color(1.0, 0.45, 0.35)
	_label.position = Vector3(0, wall_height + 1.5, half.y)
	_label.visible = false
	add_child(_label)


func _process(delta: float) -> void:
	if release_left < 0.0:
		return
	if Global.Game3D and Global.Game3D.perks.in_draft:
		return  # Not before the match gets going
	release_left = max(release_left - delta, 0.0)
	_label.text = countdown_text % ceili(release_left)
	if release_left <= 0.0 and Net.decides() and not _releasing:
		_releasing = true
		Net.everywhere(_release)


## On every machine: shut `new_boss` (already in the level) in the pen,
## asleep, raise the gate and start counting down. Anyone caught inside
## is put out past the gate first.
func shut(new_boss: Boss3D) -> void:
	boss = new_boss
	boss.global_position = global_position
	boss.wait_for_players = true
	boss.start_delay = WAKE_DELAY
	boss.penned = true
	_clear_out()
	_move_gate(true)
	release_left = release_time
	_releasing = false
	_label.visible = true


@rpc("authority", "call_local", "reliable")
func _release() -> void:
	release_left = -1.0
	_label.visible = false
	_move_gate(false)
	Sfx.play(&"boss_stomp", global_position)
	if gate_style == GateStyle.DOORS:
		Sfx.play(&"chest_open", _gate.global_position)
	if is_instance_valid(boss):
		boss.penned = false
		boss.wake()
		if Global.Game3D and release_message != "":
			Global.Game3D.scoreboard.announce(release_message % boss.display_name, Color(1.0, 0.45, 0.35))
	released.emit(boss)


## Whether `point` is inside the pen's walls.
func contains(point: Vector3) -> bool:
	var local: Vector3 = to_local(point)
	return absf(local.x) < inner_size.x * 0.5 and absf(local.z) < inner_size.y * 0.5


## Put players (each by its owner) and loose balls (by whoever simulates
## them) out past the gate, so nobody gets shut in with the boss.
func _clear_out() -> void:
	var outside: Vector3 = to_global(Vector3(0, 1, inner_size.y * 0.5 + CLEAR_DISTANCE))
	for node: Node in get_tree().get_nodes_in_group("Player"):
		var player := node as PlayerClass3D
		if player and contains(player.global_position) and (not Net.in_session() or player.is_multiplayer_authority()):
			player.global_position = outside
	if Global.Game3D and Net.decides():
		for ball: Ball3D in Global.Game3D.balls:
			if is_instance_valid(ball) and contains(ball.global_position):
				ball.global_position = outside + Vector3.UP
				ball.linear_velocity = Vector3.ZERO


# ===== BUILDING =====

func _add_wall(center: Vector3, size: Vector3, color: Color = WALL_COLOR) -> void:
	var body := StaticBody3D.new()
	body.position = center + Vector3.UP * size.y * 0.5
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = _material(color)
	mesh.mesh = box_mesh
	body.add_child(mesh)
	add_child(body)


## The gate across the open side (see GateStyle).
func _build_gate(front_z: float) -> void:
	var depth: float = GATE_DEPTH if gate_style == GateStyle.BARS else DOOR_THICKNESS
	_gate = StaticBody3D.new()
	_gate.position = Vector3(0, 0, front_z + depth * 0.5)
	_gate.collision_mask = 0
	_gate_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(inner_size.x, wall_height, depth)
	_gate_shape.shape = box
	_gate_shape.position = Vector3.UP * wall_height * 0.5
	_gate.add_child(_gate_shape)
	if gate_style == GateStyle.DOORS:
		_build_doors()
	else:
		_build_bars()
	add_child(_gate)


## Iron bars, which sink into the floor to open.
func _build_bars() -> void:
	var bar_material: StandardMaterial3D = _material(BAR_COLOR)
	bar_material.metallic = 0.8
	var bar_mesh := CylinderMesh.new()
	bar_mesh.top_radius = BAR_RADIUS
	bar_mesh.bottom_radius = BAR_RADIUS
	bar_mesh.height = wall_height
	bar_mesh.material = bar_material
	var count: int = int(inner_size.x / BAR_SPACING)
	for i in range(1, count):
		var bar := MeshInstance3D.new()
		bar.mesh = bar_mesh
		bar.position = Vector3(-inner_size.x * 0.5 + i * BAR_SPACING, wall_height * 0.5, 0)
		_gate.add_child(bar)
	for y: float in [0.6, wall_height - 0.2]:
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(inner_size.x, 0.25, GATE_DEPTH * 0.6)
		rail_mesh.material = bar_material
		rail.mesh = rail_mesh
		rail.position = Vector3(0, y, 0)
		_gate.add_child(rail)


## Two wooden doors banded with iron, each hinged at its outer edge.
func _build_doors() -> void:
	var width: float = inner_size.x * 0.5
	var wood: StandardMaterial3D = _material(WOOD_COLOR)
	var seam: StandardMaterial3D = _material(WOOD_COLOR.darkened(0.35))
	var iron: StandardMaterial3D = _material(BAR_COLOR)
	iron.metallic = 0.8
	for side: float in [-1.0, 1.0]:
		var leaf := Node3D.new()
		leaf.position = Vector3(side * inner_size.x * 0.5, 0, 0)
		_gate.add_child(leaf)
		_leaves.append(leaf)
		var inward: float = -side  # From the hinge toward the middle
		_add_box(leaf, Vector3(inward * width * 0.5, wall_height * 0.5, 0), Vector3(width - 0.05, wall_height, DOOR_THICKNESS), wood)
		# Planks, so it reads as wood from far off
		for i in range(1, 4):
			_add_box(leaf, Vector3(inward * width * i / 4.0, wall_height * 0.5, 0), Vector3(0.08, wall_height, DOOR_THICKNESS + 0.04), seam)
		for y: float in [wall_height * 0.15, wall_height * 0.5, wall_height * 0.85]:
			_add_box(leaf, Vector3(inward * width * 0.5, y, 0), Vector3(width - 0.05, 0.35, DOOR_THICKNESS + 0.1), iron)
		# A big ring handle by the middle, on the field side
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.35
		torus.outer_radius = 0.5
		torus.material = iron
		ring.mesh = torus
		ring.rotation = Vector3(PI / 2.0, 0, 0)
		ring.position = Vector3(inward * (width - 0.8), wall_height * 0.4, DOOR_THICKNESS * 0.5 + 0.12)
		leaf.add_child(ring)


func _add_box(parent: Node3D, center: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = material
	mesh.mesh = box_mesh
	mesh.position = center
	parent.add_child(mesh)


## Close (`shut`) or open the gate: bars rise or sink, doors swing.
func _move_gate(shut: bool) -> void:
	if _gate_tween:
		_gate_tween.kill()
	_gate_shape.set_deferred(&"disabled", not shut)
	_gate_tween = create_tween()
	if gate_style == GateStyle.DOORS:
		_gate_tween.set_parallel()
		_gate_tween.set_trans(Tween.TRANS_BACK if not shut else Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		for i in _leaves.size():
			var side: float = -1.0 if i == 0 else 1.0
			var angle: float = 0.0 if shut else -side * DOOR_SWING
			_gate_tween.tween_property(_leaves[i], ^"rotation_degrees:y", angle, GATE_MOVE_TIME * 1.5)
		return
	_gate_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_gate_tween.tween_property(_gate, ^"position:y", 0.0 if shut else -wall_height - 0.1, GATE_MOVE_TIME)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material
