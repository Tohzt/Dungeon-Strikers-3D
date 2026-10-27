class_name SlimeGlob3D extends Node3D
## A blob a slime boss lobs (its poison and fire spells, see Boss3D._cast):
## it arcs from the boss's mouth to where it was aimed, a marker on the
## ground showing where it'll land (filling in as it comes, like
## LightningStrike3D's), then splashes there, hitting everyone close, and
## leaves a puddle (SlimePool3D) if its element has one.
##
## Made on every machine; only the deciding one's (`real`) hurts.

## Hits reach this high over the ground.
const REACH_HEIGHT := 3.0
## How high the arc goes, for every meter it travels (and at least).
const ARC_PER_METER := 0.35
const ARC_MIN := 4.0
const MARKER_ALPHA := 0.3
const FILL_ALPHA := 0.45
const BLOB_RADIUS := 0.6

var element: SlimeElement.Kind = SlimeElement.Kind.POISON
var from: Vector3 = Vector3.ZERO
## Where it lands, on the ground.
var to: Vector3 = Vector3.ZERO
var flight_time: float = 1.2
var radius: float = 2.5
var damage: float = 15.0
var knockback: float = 8.0
var pop: float = 4.0
## How long the puddle it leaves lasts.
var pool_time: float = 6.0
## The boss that threw it (spared, and its minions with it).
var attacker: Node3D = null
var real: bool = false

var _age: float = 0.0
var _arc: float = 0.0
var _blob: MeshInstance3D
var _marker: Node3D
var _marker_material: StandardMaterial3D
var _fill: MeshInstance3D


## A glob of `kind` thrown from `start` to land at `at` after `seconds`.
## Add it to the tree yourself.
static func make(start: Vector3, at: Vector3, kind: SlimeElement.Kind, seconds: float) -> SlimeGlob3D:
	var glob := SlimeGlob3D.new()
	glob.from = start
	glob.to = at
	glob.element = kind
	glob.flight_time = seconds
	glob.position = start
	return glob


func _ready() -> void:
	top_level = true
	_arc = maxf(ARC_MIN, Vector2(to.x - from.x, to.z - from.z).length() * ARC_PER_METER)
	var color: Color = SlimeElement.COLORS[element]

	var blob_material := StandardMaterial3D.new()
	blob_material.albedo_color = SlimeElement.BODY_COLORS[element]
	blob_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blob_material.emission_enabled = true
	blob_material.emission = color
	blob_material.emission_energy_multiplier = 1.5
	var sphere := SphereMesh.new()
	sphere.radius = BLOB_RADIUS
	sphere.height = BLOB_RADIUS * 2.0
	sphere.material = blob_material
	_blob = MeshInstance3D.new()
	_blob.mesh = sphere
	add_child(_blob)
	if element == SlimeElement.Kind.FIRE:
		Vfx.attach(&"burning", _blob, Vector3.ZERO, 0.0, 0.8)

	# The marker stays put on the ground while the glob flies
	_marker = Node3D.new()
	_marker.top_level = true
	add_child(_marker)
	_marker.global_position = to
	_marker_material = _unshaded(Color(color, MARKER_ALPHA))
	_flat_cylinder(radius, _marker_material)
	_fill = _flat_cylinder(radius, _unshaded(Color(color, FILL_ALPHA)))
	_fill.position.y += 0.01
	_fill.scale = Vector3(0.01, 1.0, 0.01)


func _process(delta: float) -> void:
	_age += delta
	var t: float = clampf(_age / flight_time, 0.0, 1.0)
	global_position = from.lerp(to, t) + Vector3.UP * (4.0 * _arc * t * (1.0 - t))
	_blob.rotation += Vector3(3.0, 5.0, 0.0) * delta
	_marker_material.albedo_color.a = MARKER_ALPHA + 0.15 * sin(_age * lerpf(8.0, 25.0, t))
	_fill.scale = Vector3(maxf(t, 0.01), 1.0, maxf(t, 0.01))
	if t >= 1.0:
		_splash()


func _splash() -> void:
	set_process(false)
	SlimeElement.show_burst(element, to, radius)
	Sfx.play(&"fireball" if element == SlimeElement.Kind.FIRE else &"hit_slime", to)
	CameraShake.add(CameraShake.MEDIUM, to)
	ElementReactions.strike(Element.of_slime(element), to, radius)
	if real:
		_hit_all()
	if SlimeElement.POOLS.has(element) and is_inside_tree():
		get_parent().add_child(SlimePool3D.make(to, element, radius, pool_time))
	queue_free()


func _hit_all() -> void:
	if not Global.Game3D:
		return
	var credit: Node3D = attacker if is_instance_valid(attacker) else null
	for player: PlayerClass3D in Global.Game3D.players:
		if not is_instance_valid(player) or player.is_dead():
			continue
		var offset: Vector3 = player.global_position - to
		if offset.y > REACH_HEIGHT or offset.y < -1.0:
			continue
		var flat := Vector3(offset.x, 0.0, offset.z)
		if flat.length() > radius:
			continue
		if Combat.strike(player, flat, damage, knockback, pop, -1.0, credit, SlimeElement.knock_down(element)):
			SlimeElement.afflict(player, element)


func _flat_cylinder(reach: float, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = reach
	mesh.bottom_radius = reach
	mesh.height = 0.02
	mesh.radial_segments = 48
	mesh.rings = 1
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position.y = 0.05
	_marker.add_child(instance)
	return instance


func _unshaded(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = tint
	return material
