class_name LockOnMarker3D extends Node3D
## Shows what a player is locked on to (PlayerInputHandler3D.lock_target):
## a ring of bracket arcs turning on the floor under the target and a
## spinning arrow over its head, in the player's color. Both are real 3D
## shapes, so they read from any camera angle (from the top-down one, a
## spinning diamond inside a ring). Locked on to a teammate (a pass, see
## PlayerCarry3D.shoot) it's green, turns the other way, and the arrow
## is round instead.
##
## Built in code; top_level, so it can live under whatever owns the lock.

@export var color: Color = Color(1.0, 0.82, 0.25)
## Used instead of `color` on a teammate.
@export var pass_color: Color = Color(0.3, 1.0, 0.55)
## Space between the target's body and the floor ring.
@export var ring_margin: float = 0.35
@export var ring_width: float = 0.09
@export var ring_spin: float = 0.8  # Radians per second
@export var arrow_gap: float = 0.6  # Above the head (clear of a leader's crown)
@export var arrow_spin: float = 3.0
@export var bob_height: float = 0.12
@export var bob_speed: float = 4.0
## How far the floor is looked for under a target in the air.
@export var floor_search: float = 8.0

## Set before adding to the tree: whose lock this shows.
var handler: PlayerInputHandler3D

const ARC_COUNT := 4
const ARC_FILL := 0.6  # Share of each quarter the bracket covers
const ARC_STEPS := 10
const FLOOR_LIFT := 0.04  # Over the player's own team ring (0.03)
## Where a player's floor and head are relative to its origin (player_3d.tscn).
const PLAYER_FEET := -1.0
const PLAYER_HEAD := 1.4
## The ring pops in from this much bigger when a new target is picked.
const POP_SCALE := 1.6
const POP_TIME := 0.18

var _ring: MeshInstance3D
var _arrow: MeshInstance3D
var _diamond: CylinderMesh
var _round: CylinderMesh
## The target's a teammate (see _restyle).
var _friendly: bool = false
var _target: Node3D = null
var _time: float = 0.0
var _pop: float = 1.0  # 0 just picked, 1 settled


func _init() -> void:
	top_level = true
	visible = false
	_ring = MeshInstance3D.new()
	_ring.mesh = _build_ring_mesh()
	_ring.material_override = _make_material(false)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_arrow = MeshInstance3D.new()
	# Point down; four sides make it a diamond seen from above
	_diamond = _make_cone(4)
	_round = _make_cone(16)
	_arrow.mesh = _diamond
	# Drawn over walls and the target itself so it's never lost
	_arrow.material_override = _make_material(true)
	_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arrow)


func _process(delta: float) -> void:
	var target: Node3D = null
	if is_instance_valid(handler) and is_instance_valid(handler.lock_target):
		target = handler.lock_target
	if target != _target:
		_target = target
		_pop = 0.0
		_restyle(target is PlayerClass3D and Combat.are_teammates(target, handler.Master))
	visible = target != null
	if not target:
		return

	_time += delta
	_pop = min(_pop + delta / POP_TIME, 1.0)
	var is_boss: bool = target is Boss3D
	var radius: float = (Boss3D.RADIUS if is_boss else PlayerClass3D.BODY_RADIUS) + ring_margin
	var floor_y: float = _floor_under(target, target.global_position.y + (0.0 if is_boss else PLAYER_FEET))
	var head_y: float = target.global_position.y + (Boss3D.HEIGHT if is_boss else PLAYER_HEAD)

	var eased: float = ease(_pop, 0.4)  # Fast out, soft landing
	var pop_scale: float = lerp(POP_SCALE, 1.0, eased)
	var pulse: float = 1.0 + 0.04 * sin(_time * bob_speed * 1.5)
	_ring.global_transform = Transform3D(
		Basis(Vector3.UP, _time * ring_spin * (-1.0 if _friendly else 1.0)).scaled(Vector3.ONE * radius * pop_scale * pulse),
		Vector3(target.global_position.x, floor_y + FLOOR_LIFT, target.global_position.z))
	_arrow.global_transform = Transform3D(
		Basis(Vector3.UP, _time * arrow_spin).scaled(Vector3.ONE * lerp(0.0, 1.0, eased)),
		Vector3(target.global_position.x, head_y + arrow_gap + bob_height * sin(_time * bob_speed), target.global_position.z))
	var alpha: float = lerp(0.0, 1.0, eased)
	(_ring.material_override as StandardMaterial3D).albedo_color.a = alpha * 0.9
	(_arrow.material_override as StandardMaterial3D).albedo_color.a = alpha


## Teammate (green, round arrow, turning back) or not.
func _restyle(friendly: bool) -> void:
	_friendly = friendly
	_arrow.mesh = _round if friendly else _diamond
	for mesh: MeshInstance3D in [_ring, _arrow]:
		(mesh.material_override as StandardMaterial3D).albedo_color = pass_color if friendly else color


func _make_cone(sides: int) -> CylinderMesh:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.26
	cone.bottom_radius = 0.0
	cone.height = 0.45
	cone.radial_segments = sides
	cone.rings = 1
	return cone


## The world floor's height under `target`, or `fallback` if there's none
## close below (in which case it's probably standing on it).
func _floor_under(target: Node3D, fallback: float) -> float:
	var from: Vector3 = target.global_position + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * floor_search, 1)  # World only
	if target is CollisionObject3D:
		query.exclude = [target.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if hit else fallback


func _make_material(on_top: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	mat.no_depth_test = on_top
	mat.render_priority = 1
	return mat


## Flat bracket arcs around a unit circle on the floor, scaled to the target
## in _process.
func _build_ring_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner: float = 1.0 - ring_width
	var quarter: float = TAU / ARC_COUNT
	for arc in ARC_COUNT:
		var start: float = arc * quarter + quarter * (1.0 - ARC_FILL) * 0.5
		var span: float = quarter * ARC_FILL
		for step in ARC_STEPS:
			var a0: float = start + span * step / ARC_STEPS
			var a1: float = start + span * (step + 1) / ARC_STEPS
			var d0 := Vector3(cos(a0), 0.0, sin(a0))
			var d1 := Vector3(cos(a1), 0.0, sin(a1))
			st.add_vertex(d0 * inner)
			st.add_vertex(d0)
			st.add_vertex(d1)
			st.add_vertex(d0 * inner)
			st.add_vertex(d1)
			st.add_vertex(d1 * inner)
	return st.commit()
