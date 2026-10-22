extends Node
## Visual effects (Binbun's packs, see Assets/VFX): flashes for heavy
## swings, hits and blocks, the swirl of a heavy charging up, spells (orbs,
## bolts, fireballs and where they land) and weapons shattering.
##
## Like Sfx: play() is just this machine, for things every machine already
## does (a heavy's strike); play_everywhere() is for the ones only one
## machine sees happen (a hit, a block), and sends them on to the rest.
##
## Every effect lies along the ground (the camera looks down on them), its
## front pointing along the `dir` it's given.

const DIR := "res://Assets/VFX/"

enum Kind {
	ONE_SHOT,  ## Plays its "main" animation once (swing, claw, charge, cast)
	FLASH,  ## Opens quickly, then fades out (slash, shield)
	BURST,  ## Opens, then closes, as made (a blast, a fire patch, shards)
	HELD,  ## Opens and stays until let go (see release): an orb, a bolt
}

## id: [scene under DIR, kind, size, how far ahead along its dir it goes
## (m), primary color, secondary color, and optionally false to leave its
## secondary color alone when tinting]. Spells' sizes make them 1m across,
## to be scaled to what they're on.
const EFFECTS: Dictionary[StringName, Array] = {
	# Heavy attacks (see WeaponMove3D.vfx)
	&"swing": ["BattleFX/effects/swing/vfx_blank_swing.tscn", Kind.ONE_SHOT, 1.1, 0.0, Color(1.0, 1.0, 1.0), Color(0.55, 0.65, 0.8)],
	&"claw": ["BattleFX/effects/claw/vfx_blank_claw.tscn", Kind.ONE_SHOT, 0.8, 0.6, Color(1.0, 0.95, 0.85), Color(0.9, 0.5, 0.2)],
	&"thrust": ["BattleFX/effects/slash/vfx_blank_slash.tscn", Kind.FLASH, 0.9, 1.2, Color(1.0, 1.0, 1.0), Color(0.55, 0.65, 0.8)],
	&"fire_cast": ["ElementalMagicFX/effects/cast/vfx_fire_cast_01.tscn", Kind.ONE_SHOT, 0.3, 0.2, Color(1.0, 0.8, 0.2), Color(1.0, 0.4, 0.1)],
	# Something taking a hit (a hard one: see HARD_HIT_DAMAGE), or blocking one
	&"hit": ["HitFX/effects/hit/vfx_hit_01.tscn", Kind.ONE_SHOT, 0.6, 0.0, Color(1.0, 1.0, 1.0), Color(1.0, 0.8, 0.4)],
	&"hit_hard": ["HitFX/effects/impact/vfx_impact_01.tscn", Kind.ONE_SHOT, 0.8, 0.0, Color(1.0, 1.0, 1.0), Color(1.0, 0.8, 0.4)],
	&"block": ["BattleFX/effects/shield/vfx_blank_shield_01.tscn", Kind.FLASH, 0.28, 0.0, Color(0.8, 0.92, 1.0), Color(0.3, 0.55, 1.0)],
	# A big blast on the ground (Thunderclap, a legendary heavy)
	&"impact": ["HitFX/effects/big_impact/vfx_big_impact_01.tscn", Kind.ONE_SHOT, 1.0, 0.0, Color(1.0, 1.0, 1.0), Color(1.0, 0.8, 0.4)],
	# Sparks gathering on a heavy's weapon as it charges (see PlayerClass3D._show_charging)
	&"charging": ["StatusFX/effects/status/vfx_status_shatter.tscn", Kind.HELD, 1.0, 0.0, Color(1.0, 0.95, 0.8), Color(1.0, 0.7, 0.3)],
	# Spells in flight (see AttackWaveSpec3D.look, Arrow3D.look)
	&"dark_ball": ["DarkMagicFX/effects/ball/vfx_ball_evil_01.tscn", Kind.HELD, 0.9, 0.0, Color(1.0, 0.37, 0.0), Color(1.0, 0.0, 0.0)],
	&"dark_bolt": ["DarkMagicFX/effects/projectile/vfx_evil_projectile_01.tscn", Kind.HELD, 1.25, 0.0, Color(1.0, 0.37, 0.0), Color(1.0, 0.0, 0.0)],
	&"fire_bolt": ["ElementalMagicFX/effects/projectile/vfx_fire_projectile_01.tscn", Kind.HELD, 1.4, 0.0, Color(1.0, 0.71, 0.31), Color(1.0, 0.4, 0.1)],
	# Where spells land (see AttackWaveSpec3D.end_look)
	&"dark_blast": ["DarkMagicFX/effects/area/vfx_evil_area_01.tscn", Kind.BURST, 0.45, 0.0, Color(1.0, 0.37, 0.0), Color(1.0, 0.0, 0.0)],
	&"fire_patch": ["ElementalMagicFX/effects/area/vfx_fire_area_01.tscn", Kind.BURST, 0.36, 0.0, Color(1.0, 0.8, 0.2), Color(1.0, 0.4, 0.1)],
	# A weapon breaking (see Weapon3D._break), someone thawing out
	&"shatter": ["StatusFX/effects/status/vfx_status_shatter.tscn", Kind.BURST, 0.5, 0.0, Color(1.0, 1.0, 1.0), Color(0.84, 0.84, 0.84)],
	# On someone, while it lasts (see PlayerStatus3D)
	&"frozen": ["StatusFX/effects/status/vfx_status_frozen.tscn", Kind.HELD, 1.0, 0.0, Color(0.85, 0.97, 1.0), Color(0.45, 0.8, 1.0)],
	&"healing": ["StatusFX/effects/status/vfx_status_heal.tscn", Kind.HELD, 1.0, 0.0, Color(0.75, 1.0, 0.6), Color(0.3, 0.9, 0.35)],
	&"asleep": ["StatusFX/effects/status/vfx_status_sleep.tscn", Kind.HELD, 1.0, 0.0, Color(0.9, 0.85, 1.0), Color(0.6, 0.5, 1.0)],
	&"burning": ["FlameFX/effects/fire/vfx_basic_fire_01.tscn", Kind.HELD, 0.8, 0.0, Color(1.0, 0.72, 0.29), Color(0.69, 0.0, 0.18)],
	# A warp's way in and out (stands upright)
	&"portal": ["PortalVFX/effects/simple/simple_portal_vfx.tscn", Kind.HELD, 1.0, 0.0, Color(0.8, 0.8, 0.8), Color(0.2, 0.2, 0.2), false],
}

## Laid over a body's meshes while it lasts (see PlayerVisual3D.set_status_overlay):
## id: [material, primary color, secondary color].
const OVERLAYS: Dictionary[StringName, Array] = {
	&"frozen": ["StatusFX/effects/overlay/shatter_overlay.tres", Color(0.8, 0.95, 1.0), Color(0.35, 0.65, 1.0)],
	&"burning": ["FlameFX/effects/overlay/basic_fire_overlay_material.tres", Color(1.0, 0.72, 0.29), Color(0.69, 0.0, 0.18)],
}

## A FLASH takes this long to open, and this long to fade.
const FLASH_IN := 0.08
const FLASH_OUT := 0.35

var _scenes: Dictionary[StringName, PackedScene] = {}
var _overlays: Dictionary[StringName, Material] = {}
## A dedicated server has nobody to show them to.
var _silent: bool = DisplayServer.get_name() == "headless"


## Show `id` at `at` (or ahead of it, see EFFECTS) on this machine only,
## pointing along `dir` (flat).
## `mirror` flips which way it sweeps (a left-hand swing). `size` scales it
## (a spell's: meters across); a `tint` with any alpha recolors it.
func play(id: StringName, at: Vector3, dir: Vector3 = Vector3.FORWARD, mirror: bool = false,
		size: float = 1.0, tint: Color = Color.TRANSPARENT) -> void:
	var fx: Node3D = _spawn(id, _world(), tint)
	if not fx:
		return
	var facing: Basis = _facing(dir, mirror)
	fx.global_transform = Transform3D(facing.scaled(Vector3.ONE * EFFECTS[id][2] * size), at + facing.x * EFFECTS[id][3] * size)
	_start(fx, id, 1.0)


## Show `id` here and, online, on every other machine too.
func play_everywhere(id: StringName, at: Vector3, dir: Vector3 = Vector3.FORWARD, mirror: bool = false) -> void:
	play(id, at, dir, mirror)
	if Net.match_synced:
		_net_play.rpc(id, at, dir, mirror)


@rpc("any_peer", "unreliable")
func _net_play(id: StringName, at: Vector3, dir: Vector3, mirror: bool) -> void:
	play(id, at, dir, mirror)


## Show `id` on `parent`, following it around (its front along the
## parent's +Z), played over `duration` seconds (its "main" animation, or a
## HELD one's opening, sped up or slowed to fit; 0 = as made). `size` and
## `tint` as in play().
## Frees itself once done (a HELD one once let go, see release); free it
## sooner to cut it short. Null if nothing is shown.
func attach(id: StringName, parent: Node3D, offset: Vector3 = Vector3.ZERO, duration: float = 0.0,
		size: float = 1.0, tint: Color = Color.TRANSPARENT) -> Node3D:
	var fx: Node3D = _spawn(id, parent, tint)
	if not fx:
		return null
	fx.transform = Transform3D(_ALONG_Z.scaled(Vector3.ONE * EFFECTS[id][2] * size), offset)
	var anim: AnimationPlayer = fx.get_node("AnimationPlayer")
	var opening: StringName = &"open" if EFFECTS[id][1] == Kind.HELD else &"main"
	var length: float = anim.get_animation(opening).length if anim.has_animation(opening) else 0.0
	_start(fx, id, length / duration if duration > 0.0 and length > 0.0 else 1.0)
	return fx


## A HELD effect's front (+X) turned to +Z, the way things here face.
const _ALONG_Z := Basis(Vector3(0, 0, 1), Vector3.UP, Vector3(-1, 0, 0))


## Every effect shown is in this group (see is_part_of_effect).
const GROUP := &"vfx"


## Whether `node` belongs to an effect (looking no higher than `top`).
func is_part_of_effect(node: Node, top: Node) -> bool:
	while node and node != top:
		if node.is_in_group(GROUP):
			return true
		node = node.get_parent()
	return false


## Let go of a HELD effect (see attach): it stays where it is, closes, and
## goes.
func release(fx: Node3D) -> void:
	if not is_instance_valid(fx):
		return
	if fx.get_parent() != _world() and is_instance_valid(_world()):
		fx.reparent(_world())
	var anim: AnimationPlayer = fx.get_node("AnimationPlayer")
	if not anim.has_animation(&"close"):
		fx.queue_free()
		return
	anim.play(&"close")
	await anim.animation_finished
	if is_instance_valid(fx):
		fx.queue_free()


## The effect's scene, made into a node under `parent` with its own
## materials (so it can be tinted, and animate without touching any other
## copy) in its colors.
func _spawn(id: StringName, parent: Node, tint: Color = Color.TRANSPARENT) -> Node3D:
	if _silent or not is_instance_valid(parent):
		return null
	var scene: PackedScene = _scene(id)
	if not scene:
		return null
	var fx: Node3D = scene.instantiate()
	for child: Node in fx.get_children():
		if child is GeometryInstance3D and child.material_override:
			child.material_override = child.material_override.duplicate()
	fx.add_to_group(GROUP)
	if fx.get(&"particle_local_coords") != null:
		fx.set(&"particle_local_coords", true)  # Move with whatever they're on
	parent.add_child(fx)
	# Colored once in the tree: some only find their parts there (a portal)
	var secondary: bool = EFFECTS[id].size() < 7 or EFFECTS[id][6]
	if tint.a > 0.0:
		_tint(fx, Color(tint, 1.0), secondary)
	else:
		fx.set(&"primary_color", EFFECTS[id][4])
		if secondary:
			fx.set(&"secondary_color", EFFECTS[id][5])
	return fx


## All its colors from `color`: lighter at its heart, darker at its edges.
## Without `secondary`, only its heart (and light).
func _tint(fx: Node3D, color: Color, secondary: bool = true) -> void:
	fx.set(&"primary_color", color.lightened(0.15))
	if not secondary:
		return
	fx.set(&"secondary_color", color)
	if fx.get(&"tertiary_color") != null:
		fx.set(&"tertiary_color", color.darkened(0.6))
	if fx.get(&"light_color") != null:
		fx.set(&"light_color", color)


func _start(fx: Node3D, id: StringName, speed: float) -> void:
	match EFFECTS[id][1]:
		Kind.ONE_SHOT:
			# It frees itself when "main" finishes, which a looping one
			# never does (the claw's is made to loop): it would stay for good
			var main: Animation = fx.get_node("AnimationPlayer").get_animation(&"main")
			if main:
				main.loop_mode = Animation.LOOP_NONE
			fx.set(&"one_shot", true)
			fx.set(&"speed_scale", speed)
			fx.finished.connect(fx.queue_free)
			fx.play()
		Kind.FLASH:
			_flash(fx)
		Kind.BURST:
			_burst(fx)
		Kind.HELD:
			fx.get_node("AnimationPlayer").play(&"open", -1, speed)


## Open, then close as made, and go.
func _burst(fx: Node3D) -> void:
	var anim: AnimationPlayer = fx.get_node("AnimationPlayer")
	anim.play(&"open")
	await anim.animation_finished
	if not is_instance_valid(fx):
		return
	if anim.has_animation(&"close"):
		anim.play(&"close")
		await anim.animation_finished
	if is_instance_valid(fx):
		fx.queue_free()


## Open, then fade out and go.
func _flash(fx: Node3D) -> void:
	var anim: AnimationPlayer = fx.get_node("AnimationPlayer")
	anim.play(&"open", -1, anim.get_animation(&"open").length / FLASH_IN)
	await anim.animation_finished
	if not is_instance_valid(fx):
		return
	anim.play(&"close", -1, anim.get_animation(&"close").length / FLASH_OUT)
	await anim.animation_finished
	if is_instance_valid(fx):
		fx.queue_free()


## Lying flat, its +X along `dir`; `mirror` flips it front to back.
func _facing(dir: Vector3, mirror: bool) -> Basis:
	dir.y = 0.0
	var x: Vector3 = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	var z: Vector3 = x.cross(Vector3.UP)
	return Basis(x, Vector3.UP, -z if mirror else z)


## OVERLAYS' `id` material in its colors (made once, shared), or null.
func overlay(id: StringName) -> Material:
	if _silent or not OVERLAYS.has(id):
		return null
	if not _overlays.has(id):
		var material := (load(DIR + OVERLAYS[id][0]) as ShaderMaterial).duplicate() as ShaderMaterial
		material.set_shader_parameter(&"primary_color", OVERLAYS[id][1])
		material.set_shader_parameter(&"secondary_color", OVERLAYS[id][2])
		_overlays[id] = material
	return _overlays[id]


## Where one-off effects go: the level, so they're cleared with it.
func _world() -> Node:
	if is_instance_valid(Global.Game3D):
		return Global.Game3D
	return get_tree().current_scene


## Loaded the first time it's shown.
func _scene(id: StringName) -> PackedScene:
	if _scenes.has(id):
		return _scenes[id]
	if not EFFECTS.has(id):
		push_error("Unknown effect: %s" % id)
		_scenes[id] = null
		return null
	_scenes[id] = load(DIR + EFFECTS[id][0]) as PackedScene
	return _scenes[id]
