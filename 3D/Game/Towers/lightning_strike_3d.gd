class_name LightningStrike3D extends Node3D
## A telegraphed lightning strike (a Storm Tower's, see Tower3D): a disc on
## the ground pulses where it'll land (like the boss's stomp telegraph)
## while a brighter one grows out from its middle to fill it, then a bolt
## of lightning (Vfx "lightning") comes down on it and hits everything
## inside but `team`. With no warning (warn_time 0) and no radius it's just
## the bolt, for show (a Striker Tower's zap).
##
## Made on every machine; only the deciding one's (`real`) hurts.

## Seconds the marker takes to fade once the bolt's down.
const FADE_TIME := 0.25
## How wide (m) a bolt with no radius lands.
const ZAP_SIZE := 2.0
## Hits reach this high over the ground.
const REACH_HEIGHT := 3.0
const MARKER_ALPHA := 0.3
const FILL_ALPHA := 0.45

## Where it lands: its own position, on the ground.
var radius: float = 3.0
var warn_time: float = 1.0
var color: Color = Color(1.0, 0.95, 0.5)
var damage: float = 25.0
var knockback: float = 10.0
var pop: float = 5.0
## Above 0, knocks players down too (see Combat.strike).
var knock_down: float = 0.0
## Who it spares (and who's credited): its tower's team, and the tower.
var team: int = -1
var attacker: Node3D = null
var real: bool = false

var _age: float = 0.0
var _struck: bool = false
var _disc: MeshInstance3D
var _disc_material: StandardMaterial3D
var _fill: MeshInstance3D


## A strike landing at `at` after `warn` seconds. Add it to the tree
## yourself.
static func make(at: Vector3, reach: float, warn: float, tint: Color) -> LightningStrike3D:
	var strike := LightningStrike3D.new()
	strike.position = at
	strike.radius = reach
	strike.warn_time = warn
	strike.color = tint
	return strike


func _ready() -> void:
	top_level = true
	if radius > 0.0:
		_disc_material = _unshaded(Color(color, MARKER_ALPHA))
		_disc = _flat_cylinder(radius, _disc_material)
		_fill = _flat_cylinder(radius, _unshaded(Color(color, FILL_ALPHA)))
		_fill.position.y += 0.01  # Over the disc
		_fill.scale = Vector3(0.01, 1.0, 0.01)
	if warn_time <= 0.0:
		_strike()


func _process(delta: float) -> void:
	_age += delta
	if not _struck:
		var left: float = clampf(1.0 - _age / warn_time, 0.0, 1.0)
		# Pulse faster as it comes, filling in from the middle
		var speed: float = lerpf(25.0, 8.0, left)
		_disc_material.albedo_color.a = MARKER_ALPHA + 0.15 * sin(_age * speed)
		var grown: float = maxf(1.0 - left, 0.01)
		_fill.scale = Vector3(grown, 1.0, grown)
		if _age >= warn_time:
			_strike()
		return
	var fade: float = 1.0 - (_age - warn_time) / FADE_TIME
	if fade <= 0.0:
		queue_free()
		return
	if _disc_material:
		_disc_material.albedo_color.a = MARKER_ALPHA * fade


## The bolt comes down; a real one hits everything in reach.
func _strike() -> void:
	_struck = true
	_age = maxf(_age, warn_time)
	if _fill:
		_fill.visible = false
	Vfx.play(&"lightning", global_position, Vector3.FORWARD, false, radius * 2.0 if radius > 0.0 else ZAP_SIZE, color)
	Sfx.play(&"spell_impact", global_position)
	if radius > 0.0:
		CameraShake.add(CameraShake.MEDIUM, global_position)
		ElementReactions.strike(Element.Kind.LIGHTNING, global_position, radius, attacker)
	if real and radius > 0.0:
		_hit_all()


func _hit_all() -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = REACH_HEIGHT
	var at := Transform3D(Basis(), global_position + Vector3.UP * REACH_HEIGHT * 0.5)
	var credit: Node3D = attacker if is_instance_valid(attacker) else null
	var exclude: Array[RID] = []
	if credit is CollisionObject3D:
		exclude.append(credit.get_rid())
	for body: Node3D in Combat.overlaps(get_world_3d(), shape, at, exclude):
		if team >= 0 and Combat.team_of(body) == team:
			continue
		if body is Tower3D or (body is Weapon3D and body.wielder):
			continue  # Towers don't fight each other; a held weapon goes with its wielder
		var out: Vector3 = body.global_position - global_position
		Combat.strike(body, out, damage, knockback, pop, -1.0, credit, knock_down)


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
	add_child(instance)
	return instance


func _unshaded(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = tint
	return material
