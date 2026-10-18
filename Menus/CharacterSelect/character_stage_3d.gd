class_name CharacterStage3D extends Node3D
## The character select lineup: every character one side can play stands in
## a row, holding its kit, idling. The focused one steps forward into the
## light, plays its flourish (Roster.flourish_of) and then holds its ready
## pose, and the camera glides over to it. Lives in its own world inside a
## SubViewport (see CharacterSelectPanel), so it never touches a match.

## Clip libraries the players use, plus the ones only the lineup needs
## (cheering, the skeletons' own idles and taunts).
const EXTRA_LIBRARIES: Dictionary[StringName, String] = {
	&"Simulation": "res://Assets/Characters/Animations/Rig_Medium/Rig_Medium_Simulation.glb",
	&"Special": "res://Assets/Characters/Animations/Rig_Medium/Rig_Medium_Special.glb",
}
const HUMAN_IDLE := &"General/Idle_A"
const SKELETON_IDLE := &"Special/Skeletons_Idle"
## Played once after the flourish by a human (skeletons go straight to ready).
const CHEER := &"Simulation/Cheering"
const BLEND := 0.2
## Now and then each figure breaks off from its idle (or ready pose) for one
## of these, or its own flourish, then goes back to it. Seconds between.
const HUMAN_FIDGETS: Array[StringName] = [
	&"Simulation/Cheering", &"Simulation/Waving", &"General/Interact", &"General/Use_Item",
	&"General/PickUp", &"Simulation/Push_Ups",
]
const SKELETON_FIDGETS: Array[StringName] = [
	&"Special/Skeletons_Taunt", &"Special/Skeletons_Taunt_Longer", &"Simulation/Waving",
	&"General/Interact",
]
const FIDGET_GAP := Vector2(4.0, 10.0)

## The bodies are shrunk in a match too (see player_3d.tscn), but weapons
## aren't, so the weapons are scaled back up to match.
const BODY_SCALE := 0.85
const SPACING := 1.5
## The row bends back towards its ends.
const ROW_CURVE := 0.12
const FOCUS_FORWARD := 1.1
const FOCUS_SCALE := 1.12
const FOCUS_TIME := 0.35
## Each figure turns a little towards the middle of the row.
const TURN_IN := deg_to_rad(10.0)

const CAMERA_HEIGHT := 1.9
const CAMERA_DISTANCE := 5.2
const CAMERA_LOOK_HEIGHT := 0.9
const CAMERA_FOV := 40.0
## How quickly the camera follows the focus (per second).
const CAMERA_FOLLOW := 6.0

const BACKGROUND := Color(0.075, 0.05, 0.045)
const FLOOR_COLOR := Color(0.16, 0.11, 0.09)

class Figure:
	var character: int
	var root: Node3D
	var anim: AnimationPlayer
	var home: Vector3
	## How it stands when it isn't picked out.
	var home_turn: float
	var idle: StringName
	## Seconds until it next breaks off for a fidget.
	var fidget_in: float
	var last_fidget: StringName


var team: int = -1
var focused: int = -1
var _figures: Array[Figure] = []
var _camera: Camera3D
var _spot: SpotLight3D
var _ring: MeshInstance3D
var _ring_material: StandardMaterial3D
var _camera_x: float = 0.0
static var _libraries: Dictionary[StringName, AnimationLibrary] = {}


func _ready() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.45, 0.4)
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(30), 0)
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	add_child(sun)

	_spot = SpotLight3D.new()
	_spot.light_color = Color(1.0, 0.85, 0.6)
	_spot.light_energy = 6.0
	_spot.spot_range = 8.0
	_spot.spot_angle = 22.0
	_spot.shadow_enabled = true
	_spot.rotation = Vector3(deg_to_rad(-90), 0, 0)
	add_child(_spot)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(40, 20)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = FLOOR_COLOR
	floor_material.roughness = 0.9
	floor_mesh.material = floor_material
	var floor_instance := MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	add_child(floor_instance)

	# A glowing ring in the team's color under whoever is focused
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.55
	ring_mesh.outer_radius = 0.7
	ring_mesh.rings = 32
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.emission_enabled = true
	ring_mesh.material = _ring_material
	_ring = MeshInstance3D.new()
	_ring.mesh = ring_mesh
	_ring.scale = Vector3(1, 0.05, 1)
	add_child(_ring)

	_camera = Camera3D.new()
	_camera.fov = CAMERA_FOV
	add_child(_camera)
	_place_camera()


func _process(delta: float) -> void:
	for figure: Figure in _figures:
		figure.fidget_in -= delta
		if figure.fidget_in <= 0.0 and figure.anim.current_animation == _rest_clip(figure):
			_fidget(figure)
	var target_x: float = _focused_figure().home.x if _focused_figure() else 0.0
	_camera_x = lerpf(_camera_x, target_x, clampf(delta * CAMERA_FOLLOW, 0.0, 1.0))
	_place_camera()


func _place_camera() -> void:
	_camera.position = Vector3(_camera_x, CAMERA_HEIGHT, CAMERA_DISTANCE)
	_camera.look_at(Vector3(_camera_x, CAMERA_LOOK_HEIGHT, 0.0))


## Show `new_team`'s lineup with `character` stepped forward.
func show_choice(new_team: int, character: int) -> void:
	if new_team != team:
		team = new_team
		focused = -1
		_build_lineup()
	_focus(character)


## The character whose figure is nearest `screen_position` (in the
## viewport's pixels), or -1 if nobody is near it.
func character_at(screen_position: Vector2) -> int:
	var best: int = -1
	var best_dist: float = 90.0
	for figure: Figure in _figures:
		var on_screen: Vector2 = _camera.unproject_position(figure.root.global_position + Vector3.UP)
		var dist: float = absf(on_screen.x - screen_position.x)
		if dist < best_dist:
			best = figure.character
			best_dist = dist
	return best


func _build_lineup() -> void:
	for figure: Figure in _figures:
		figure.root.queue_free()
	_figures.clear()
	var color: Color = Players.team_color(team)
	_ring_material.albedo_color = color
	_ring_material.emission = color
	var characters: Array[int] = Roster.characters_of_team(team)
	var middle: float = (characters.size() - 1) / 2.0
	for i in characters.size():
		var offset: float = i - middle
		var figure := _make_figure(characters[i])
		figure.home = Vector3(offset * SPACING, 0.0, -absf(offset) * absf(offset) * ROW_CURVE)
		figure.root.position = figure.home
		figure.home_turn = -signf(offset) * TURN_IN
		figure.root.rotation.y = figure.home_turn
		_figures.append(figure)
	_camera_x = 0.0


func _make_figure(character: int) -> Figure:
	var figure := Figure.new()
	figure.character = character
	figure.idle = SKELETON_IDLE if Roster.side_of(character) == Roster.SKELETONS else HUMAN_IDLE
	figure.root = Node3D.new()
	add_child(figure.root)
	var body: Node3D = Roster.model_of(character).instantiate()
	body.scale = Vector3.ONE * BODY_SCALE
	figure.root.add_child(body)
	_hide_armor_extras(body)
	_hold_kit(body, character)

	figure.anim = AnimationPlayer.new()
	body.add_child(figure.anim)
	figure.anim.root_node = figure.anim.get_path_to(body)
	for library_name: StringName in _all_libraries():
		figure.anim.add_animation_library(library_name, _all_libraries()[library_name])
	figure.anim.animation_finished.connect(_on_clip_finished.bind(figure))
	_play(figure, figure.idle)
	_wait_to_fidget(figure)
	# Out of step with each other, so the row doesn't bob as one
	figure.anim.seek(randf() * figure.anim.current_animation_length, true)
	return figure


## In a match, headgear only shows with armor on (see PlayerVisual3D); the
## lineup shows everyone as they start.
func _hide_armor_extras(body: Node3D) -> void:
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if String(mesh.name).rsplit("_", true, 1)[-1] in PlayerVisual3D.ARMOR_MESHES:
			mesh.visible = false


## Put the character's kit in its hands: just each weapon's model, on the
## hand bone, sitting the way it does in a match (see Weapon3D.follow_hand).
func _hold_kit(body: Node3D, character: int) -> void:
	var skeleton: Skeleton3D = body.get_node_or_null(PlayerVisual3D.SKELETON_PATH) as Skeleton3D
	if not skeleton:
		return
	var scenes: Array[PackedScene] = Roster.kit_of(character)
	for i in scenes.size():
		if not scenes[i]:
			continue
		var weapon: Weapon3D = scenes[i].instantiate() as Weapon3D
		var model: Node3D = weapon.get_node_or_null(^"Model") as Node3D
		if not model:
			weapon.free()
			continue
		var is_left: bool = weapon.grip == Weapon3D.Grip.OFF_HAND \
			or (i == 1 and weapon.grip != Weapon3D.Grip.TWO_HANDED) or weapon.rides_left_hand
		var mirrored: bool = is_left and weapon.grip != Weapon3D.Grip.OFF_HAND and not weapon.rides_left_hand
		var grip := Node3D.new()
		grip.transform = (Weapon3D.LEFT_HAND_TURN if mirrored else Transform3D.IDENTITY) * weapon.hold_offset
		grip.scale /= BODY_SCALE
		weapon.remove_child(model)
		model.owner = null
		grip.add_child(model)
		weapon.free()
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = "handslot.l" if is_left else "handslot.r"
		skeleton.add_child(attachment)
		attachment.add_child(grip)


func _focus(character: int) -> void:
	if character == focused:
		return
	var old: Figure = _focused_figure()
	focused = character
	if old:
		_step(old, old.home, 1.0, old.home_turn)
		_play(old, old.idle)
		_wait_to_fidget(old)
	var figure: Figure = _focused_figure()
	if not figure:
		return
	_step(figure, figure.home + Vector3(0, 0, FOCUS_FORWARD), FOCUS_SCALE, 0.0)
	figure.last_fidget = &""
	_play(figure, Roster.flourish_of(character))
	_wait_to_fidget(figure)
	var spot_at := figure.home + Vector3(0, 0, FOCUS_FORWARD)
	var tween: Tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_spot, "position", spot_at + Vector3.UP * 5.0, FOCUS_TIME)
	tween.tween_property(_ring, "position", spot_at + Vector3.UP * 0.02, FOCUS_TIME)


## Move `figure` to `to` at `size`, turned `turn` radians (facing the
## camera when it's picked out, a little towards the middle otherwise).
func _step(figure: Figure, to: Vector3, size: float, turn: float) -> void:
	var tween: Tween = figure.root.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(figure.root, "position", to, FOCUS_TIME)
	tween.tween_property(figure.root, "scale", Vector3.ONE * size, FOCUS_TIME)
	tween.tween_property(figure.root, "rotation:y", turn, FOCUS_TIME)


func _focused_figure() -> Figure:
	for figure: Figure in _figures:
		if figure.character == focused:
			return figure
	return null


func _play(figure: Figure, clip: StringName) -> void:
	if figure.anim.has_animation(clip):
		figure.anim.play(clip, BLEND)
	elif clip != figure.idle:
		_play(figure, figure.idle)


## Clips don't loop on their own: idles start over, and the focused figure
## goes flourish -> (cheer, for a human) -> its ready pose. A fidget goes
## back to whichever of those it broke off from.
func _on_clip_finished(clip: StringName, figure: Figure) -> void:
	if figure.character == focused and clip == Roster.flourish_of(figure.character) \
			and figure.last_fidget != clip and Roster.side_of(figure.character) == Roster.HUMANS:
		_play(figure, CHEER)
		return
	_play(figure, _rest_clip(figure))


## What it stands in between fidgets: its ready pose once picked out, else
## its idle.
func _rest_clip(figure: Figure) -> StringName:
	return Roster.ready_clip_of(figure.character) if figure.character == focused else figure.idle


func _wait_to_fidget(figure: Figure) -> void:
	figure.fidget_in = randf_range(FIDGET_GAP.x, FIDGET_GAP.y)


## Break off for a random fidget (never the same one twice running).
func _fidget(figure: Figure) -> void:
	var pool: Array[StringName] = []
	pool.assign(SKELETON_FIDGETS if Roster.side_of(figure.character) == Roster.SKELETONS else HUMAN_FIDGETS)
	pool.append(Roster.flourish_of(figure.character))
	pool = pool.filter(func(clip: StringName) -> bool:
		return clip != figure.last_fidget and figure.anim.has_animation(clip))
	_wait_to_fidget(figure)
	if pool.is_empty():
		return
	figure.last_fidget = pool.pick_random()
	_play(figure, figure.last_fidget)


static func _all_libraries() -> Dictionary[StringName, AnimationLibrary]:
	if _libraries.is_empty():
		_libraries.merge(PlayerVisual3D.LIBRARIES)
		for library_name: StringName in EXTRA_LIBRARIES:
			_libraries[library_name] = load(EXTRA_LIBRARIES[library_name])
	return _libraries
