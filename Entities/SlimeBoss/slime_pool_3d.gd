class_name SlimePool3D extends Node3D
## A puddle a slime boss leaves behind (poison, fire: see
## SlimeElement.POOLS): while it lasts, anyone standing in it is afflicted
## (SlimeElement.afflict) a little at a time. It's harmless to jump over.
##
## Made on every machine; each looks after its own players, so nothing
## goes over the network.

## How often it stings whoever's in it, and how strong each sting is.
const TICK := 0.4
const STRENGTH := 0.4
## Players this far over the ground are clear (their origin sits ~1m up).
const REACH_HEIGHT := 1.6
const FADE_TIME := 0.5
const ALPHA := 0.35

var element: SlimeElement.Kind = SlimeElement.Kind.POISON
var radius: float = 2.5
var lifetime: float = 6.0

var _age: float = 0.0
var _tick: float = 0.0
var _disc: MeshInstance3D
var _material: StandardMaterial3D
var _fx: Node3D


## A puddle of `kind` at `at` (on the ground). Add it to the tree yourself.
static func make(at: Vector3, kind: SlimeElement.Kind, reach: float, seconds: float) -> SlimePool3D:
	var pool := SlimePool3D.new()
	pool.position = at
	pool.element = kind
	pool.radius = reach
	pool.lifetime = seconds
	return pool


func _ready() -> void:
	top_level = true
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = Color(SlimeElement.COLORS[element], ALPHA)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.02
	mesh.radial_segments = 32
	mesh.rings = 1
	mesh.material = _material
	_disc = MeshInstance3D.new()
	_disc.mesh = mesh
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_disc.position.y = 0.04
	add_child(_disc)
	var look: Array = SlimeElement.POOLS.get(element, [])
	if not look.is_empty():
		_fx = Vfx.attach(look[0], self, Vector3.ZERO, 0.0, radius * look[1])
	# Splat in
	scale = Vector3(0.3, 1.0, 0.3)
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if PerkDirector.halted():
		return
	_age += delta
	if _age >= lifetime:
		_dry_up()
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK
		_sting()


## Afflict our machine's players standing in it.
func _sting() -> void:
	if not Global.Game3D:
		return
	for player: PlayerClass3D in Global.Game3D.players:
		if not is_instance_valid(player) or not player._is_local() or player.is_dead():
			continue
		var offset: Vector3 = player.global_position - global_position
		if offset.y > REACH_HEIGHT or offset.y < -1.0:
			continue
		if Vector2(offset.x, offset.z).length() > radius:
			continue
		SlimeElement.afflict(player, element, STRENGTH)


func _dry_up() -> void:
	set_process(false)
	if _fx:
		Vfx.release(_fx)
		_fx = null
	var tween: Tween = create_tween()
	tween.tween_property(_material, "albedo_color:a", 0.0, FADE_TIME)
	tween.tween_callback(queue_free)
