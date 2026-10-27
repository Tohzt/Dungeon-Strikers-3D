class_name GroundPatch3D extends Node3D
## A puddle on the floor for a while: the ice or fire a trail buff leaves
## behind its player (the ice_trail and fire_trail perk stats), or what a
## thrown flask leaves where it shatters (see Potion.LARGE).
## It only bothers the enemies of whoever made it:
## - ICE is slippery (see PlayerClass3D's ICE_TRACTION),
## - FIRE sets them burning,
## - POISON poisons them.
##
## Every machine makes its own (trails from where it sees each player go,
## puddles where a flask burst), and checks only its own players against
## them (see effects_on), so nothing about them is sent online.

enum Kind { ICE, FIRE, POISON }

const COLORS: Dictionary[Kind, Color] = {
	Kind.ICE: Color(0.7, 0.92, 1.0, 0.75),
	Kind.FIRE: Color(1.0, 0.45, 0.1, 0.8),
	Kind.POISON: Color(0.45, 0.9, 0.15, 0.75),
}
## A trail drops a patch every this far its player goes (m), this wide,
## lasting this long (s).
const TRAIL_SPACING := 0.9
const TRAIL_RADIUS := 0.9
const TRAIL_TIME := 5.0
## The last this share of its life it fades out (and stops working at the end).
const FADE_SHARE := 0.25
## Poison tops up to this long while standing in it.
const POISON_TOP_UP := 1.5

## Every patch on the floor now.
static var all: Array[GroundPatch3D] = []
## One look per kind, shared (each patch fades through its own transparency).
static var _materials: Dictionary[Kind, StandardMaterial3D] = {}
static var _mesh: CylinderMesh = null

var kind: Kind = Kind.ICE
var radius: float = TRAIL_RADIUS
## Its maker's team (-1 = nobody's: only the maker is spared) and name.
var team: int = -1
var maker_name: String = ""
## Used up by a reaction (see consume): no longer on the floor.
var consumed: bool = false
var _life: float = TRAIL_TIME
var _left: float = TRAIL_TIME
var _disc: MeshInstance3D
var _fx: Node3D = null


## Lay a patch of `kind` on the floor under `at`, made by `made_by`, on this
## machine. `with_fx` adds flames or fumes (puddles; too many for trails).
static func lay(parent: Node, kind_: Kind, at: Vector3, made_by: Node3D, radius_: float = TRAIL_RADIUS,
		seconds: float = TRAIL_TIME, with_fx: bool = false) -> GroundPatch3D:
	var patch := GroundPatch3D.new()
	patch.kind = kind_
	patch.radius = radius_
	patch._life = seconds
	patch._left = seconds
	if is_instance_valid(made_by):
		patch.team = Combat.team_of(made_by)
		patch.maker_name = String(made_by.name)
	parent.add_child(patch)
	patch.global_position = _floor_under(patch, at)
	if with_fx:
		patch._add_fx()
	ElementReactions.on_laid(patch)
	return patch


static func _floor_under(node: Node3D, at: Vector3) -> Vector3:
	var from: Vector3 = at + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0, Combat.WORLD_MASK)
	var hit: Dictionary = node.get_world_3d().direct_space_state.intersect_ray(query)
	return (hit.position as Vector3) + Vector3.UP * 0.03 if not hit.is_empty() else at


func _ready() -> void:
	all.append(self)
	_disc = MeshInstance3D.new()
	_disc.mesh = _shared_mesh()
	_disc.material_override = _material_of(kind)
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_disc.scale = Vector3(radius, 1.0, radius) * 0.2
	_disc.rotation.y = randf() * TAU
	add_child(_disc)
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
		.tween_property(_disc, ^"scale", Vector3(radius, 1.0, radius), 0.2)


func _exit_tree() -> void:
	all.erase(self)


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		Vfx.release(_fx)
		queue_free()
		return
	var fade: float = _life * FADE_SHARE
	_disc.transparency = 1.0 - clampf(_left / fade, 0.0, 1.0) if _left < fade else 0.0


## Used up by a reaction (see ElementReactions): it stops working at once
## and shrinks away.
func consume() -> void:
	if consumed:
		return
	consumed = true
	all.erase(self)
	set_process(false)
	Vfx.release(_fx)
	_fx = null
	var tween := create_tween()
	tween.tween_property(_disc, ^"scale", Vector3(radius, 1.0, radius) * 0.1, 0.25)
	tween.tween_callback(queue_free)


func _add_fx() -> void:
	match kind:
		Kind.FIRE:
			_fx = Vfx.attach(&"burning", self, Vector3.ZERO, 0.0, radius * 0.8)
		Kind.POISON:
			_fx = Vfx.attach(&"poisoned", self, Vector3.UP * 0.4, 0.0, radius * 0.8)
		Kind.ICE:
			Vfx.play(&"shatter", global_position, Vector3.FORWARD, false, radius, COLORS[kind])


## Whether it's still there and `player` stands in it as one of its maker's
## enemies.
func catches(player: PlayerClass3D) -> bool:
	if _left <= 0.0 or String(player.name) == maker_name:
		return false
	if team >= 0 and Combat.team_of(player) == team:
		return false
	var away: Vector3 = player.global_position - global_position
	return Vector2(away.x, away.z).length() <= radius and absf(away.y) < 1.5


## Whoever made it, if they're still here.
func maker() -> PlayerClass3D:
	return Global.Game3D.player_named(maker_name) if Global.Game3D else null


## Owner: what the patches `player` is standing in do to them. Returns
## whether they're on ice (slippery, see PlayerClass3D).
static func effects_on(player: PlayerClass3D) -> bool:
	var on_ice: bool = false
	for patch: GroundPatch3D in all:
		if not patch.catches(player):
			continue
		match patch.kind:
			Kind.ICE:
				on_ice = true
			Kind.FIRE:
				if player.status.time_left(PlayerStatus3D.Kind.BURNING) <= 0.0:
					player.status.apply(PlayerStatus3D.Kind.BURNING, PlayerStatus3D.BURN_TIME,
						patch.maker())
			Kind.POISON:
				if player.status.time_left(PlayerStatus3D.Kind.POISONED) < 0.3:
					player.status.apply(PlayerStatus3D.Kind.POISONED, POISON_TOP_UP,
						patch.maker())
	return on_ice


static func _shared_mesh() -> CylinderMesh:
	if not _mesh:
		_mesh = CylinderMesh.new()
		_mesh.top_radius = 1.0
		_mesh.bottom_radius = 1.0
		_mesh.height = 0.04
		_mesh.radial_segments = 20
		_mesh.rings = 1
	return _mesh


static func _material_of(kind_: Kind) -> StandardMaterial3D:
	if not _materials.has(kind_):
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = COLORS[kind_]
		material.emission_enabled = true
		material.emission = COLORS[kind_]
		material.emission_energy_multiplier = 0.6 if kind_ == Kind.ICE else 1.2
		material.roughness = 0.05 if kind_ == Kind.ICE else 0.6
		material.metallic_specular = 1.0 if kind_ == Kind.ICE else 0.5
		_materials[kind_] = material
	return _materials[kind_]
