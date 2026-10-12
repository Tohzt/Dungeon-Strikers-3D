class_name PlayerVisual3D extends Node3D
## The player's skinned KayKit body. It plays locomotion, dodge, slide,
## stagger, knockdown, hit and spawn clips from the player's state, and each arm's attack, throw
## or hold clip on top; wears the team ring, flashes red during iframes and
## sees stars while knocked down. Held
## weapons ride its hand bones. It reads only state that's synced online
## (velocity, anim_pose, arm_anim, iframes, what's in each hand),
## so remote copies animate the same as the owner without any extra sync.

## Rig_Medium clips, by library name (clips are referred to as "Library/Clip").
const LIBRARIES: Dictionary[StringName, AnimationLibrary] = {
	&"General": preload("res://Assets/Characters/Animations/Rig_Medium/Rig_Medium_General.glb"),
	&"MovementBasic": preload("res://Assets/Characters/Animations/Rig_Medium/Rig_Medium_MovementBasic.glb"),
	&"MovementAdvanced": preload("res://Assets/Characters/Animations/Rig_Medium/Rig_Medium_MovementAdvanced.glb"),
	&"CombatMelee": preload("res://Assets/Characters/Animations/Rig_Medium/Rig_Medium_CombatMelee.glb"),
	&"CombatRanged": preload("res://Assets/Characters/Animations/Rig_Medium/Rig_Medium_CombatRanged.glb"),
	&"Tools": preload("res://Assets/Characters/Animations/Rig_Medium/Rig_Medium_Tools.glb"),
	&"Simulation": preload("res://Assets/Characters/Animations/Rig_Medium/Rig_Medium_Simulation.glb"),
}
const SKELETON_PATH := "Rig_Medium/Skeleton3D"
## Each character's headgear and cape, by the last part of the mesh name
## (e.g. Knight_Helmet, Skeleton_Warrior_Helmet). Hidden until the player picks up armor (see
## PlayerClass3D.armored). The Ranger's quiver isn't armor, so it stays.
const ARMOR_MESHES: Array[String] = ["Helmet", "HelmetVisor", "Hat", "BearHat", "Mask", "Cape"]

const IDLE_CLIP := &"General/Idle_A"
const WALK_CLIP := &"MovementBasic/Walking_A"
const RUN_CLIP := &"MovementBasic/Running_A"
## A dodge roll dives (this lunge, pitched forward until nearly flat), then
## tucks (crouched) and rolls over: the body flips through a full turn on
## top of the clips (see _roll_flip), as the rig has no roll of its own.
const DIVE_CLIP := &"MovementAdvanced/Dodge_Forward"
const TUCK_CLIP := &"MovementAdvanced/Crouching"
## Share of the roll spent diving; the rest is the tucked roll.
const DIVE_SHARE := 0.35
const DIVE_PITCH := deg_to_rad(80)
## Top of the dive's arc, above the floor.
const DIVE_HEIGHT := 0.45
## How high up the body (from the feet) it turns around while flipping.
const ROLL_PIVOT_HEIGHT := 0.55
const BACKSTEP_CLIP := &"MovementAdvanced/Dodge_Backward"
## A slide tackle: sat on the floor, legs out front, leaning back a little.
const SLIDE_CLIP := &"Simulation/Sit_Floor_Idle"
const SLIDE_LEAN := deg_to_rad(-12)
## Slide-tackled: thrown on our back, then back up by playing the fall in
## reverse.
const KNOCKDOWN_CLIP := &"General/Death_A"
## Seeing stars while knocked down: a ring of them circling over the head.
const STAR_COUNT := 5
const STAR_RING_RADIUS := 0.4
const STAR_SIZE := 0.13
## Above the head bone (which sits at the bottom of the head).
const STAR_HEIGHT := 0.75
const STAR_ORBIT_SPEED := 4.0  # Radians per second
const STAR_BOB := 0.06
const STAR_COLOR := Color(1.0, 0.88, 0.2)
const STAGGER_CLIP := &"General/Hit_B"
const HIT_CLIP := &"General/Hit_A"
const SPAWN_CLIP := &"General/Spawn_Ground"
## Killed or knocked out: fall down and lie there.
const DOWN_CLIP := &"General/Death_A"

## Ground speeds (m/s) the locomotion blend puts each clip at. Above
## RUN_SPEED (sprinting, sliding) the run cycle speeds up instead.
const WALK_SPEED := 2.0
const RUN_SPEED := 6.5
const MAX_RUN_TIME_SCALE := 2.0
## A flinch only moves the upper body, so the legs keep walking.
const HIT_DURATION := 0.4
const UPPER_BODY_BONES: Array[String] = [
	"spine", "chest", "head",
	"upperarm.l", "lowerarm.l", "wrist.l", "hand.l", "handslot.l",
	"upperarm.r", "lowerarm.r", "wrist.r", "hand.r", "handslot.r",
]
## Each arm plays its own clip over the rest of the body, so both hands can
## act at once (see PlayerClass3D.arm_anim).
const ARM_BONES: Array[String] = ["upperarm", "lowerarm", "wrist", "hand", "handslot"]
## Whatever an arm does (a swing, a throw, a raised shield, a drawn bow),
## the body turns into it too: the torso plays that arm's clip as well.
const TORSO_BONES: Array[String] = ["hips", "spine", "chest", "head"]
## On top of the clip, the whole body sweeps through each attack, so it reads
## from the top-down camera: (yaw when swung right-handed, yaw left-handed,
## forward pitch), in degrees. The yaw is the way the strike sweeps (positive
## = to the character's left); it winds back the other way first. Clips not
## listed don't sweep.
const CLIP_SWEEP: Dictionary[StringName, Vector3] = {
	&"CombatMelee/Melee_1H_Attack_Slice_Horizontal": Vector3(-55, -55, 0),
	&"CombatMelee/Melee_1H_Attack_Slice_Diagonal": Vector3(-45, -45, 10),
	&"CombatMelee/Melee_1H_Attack_Chop": Vector3(0, 0, 18),
	&"CombatMelee/Melee_1H_Attack_Stab": Vector3(0, 0, 10),
	&"CombatMelee/Melee_2H_Attack_Slice": Vector3(-60, -60, 0),
	&"CombatMelee/Melee_2H_Attack_Chop": Vector3(-25, -25, 20),
	&"CombatMelee/Melee_2H_Attack_Stab": Vector3(0, 0, 12),
	&"CombatMelee/Melee_Dualwield_Attack_Slice": Vector3(10, 10, 14),
	&"CombatMelee/Melee_Dualwield_Attack_Stab": Vector3(-10, -10, 8),
	&"CombatMelee/Melee_Dualwield_Attack_Chop": Vector3(-5, -5, 14),
	&"CombatMelee/Melee_Unarmed_Attack_Punch_A": Vector3(15, -15, 8),
	&"General/Throw": Vector3(5, 5, 15),
}
## How quickly the sweep settles back once the arm is done (per second).
const SWEEP_RETURN_SPEED := 6.0
## Seconds for an arm to blend into its clip, and back out once it's done.
const ARM_BLEND_IN := 0.05
const ARM_BLEND_OUT := 0.15
const PUNCH_CLIP := &"CombatMelee/Melee_Unarmed_Attack_Punch_A"
const THROW_CLIP := &"General/Throw"
## The Throw clip only moves the right arm: the left throws overarm with
## the left half of the dual-wield chop.
const OFFHAND_THROW_CLIP := &"CombatMelee/Melee_Dualwield_Attack_Chop"
## Where an arm's action phase (see PlayerClass3D.arm_anim) falls in each
## clip, in seconds: (start, strike begins, strike ends, end). Phase 0-1 is
## the wind-up, 1-2 the strike, 2-3 the recovery. Found by measuring how
## fast the hand moves through each clip; a held pose has all four the same.
## The right-hand clips are timed for the right arm, the dual-wield ones for
## the left.
const CLIP_KEYS: Dictionary[StringName, Vector4] = {
	&"CombatMelee/Melee_1H_Attack_Chop": Vector4(0.0, 0.5, 0.67, 1.07),
	&"CombatMelee/Melee_1H_Attack_Slice_Diagonal": Vector4(0.0, 0.33, 0.5, 1.0),
	&"CombatMelee/Melee_1H_Attack_Slice_Horizontal": Vector4(0.0, 0.2, 0.37, 1.1),
	&"CombatMelee/Melee_1H_Attack_Stab": Vector4(0.0, 0.33, 0.47, 1.4),
	&"CombatMelee/Melee_2H_Attack_Chop": Vector4(0.0, 0.6, 0.9, 1.63),
	&"CombatMelee/Melee_2H_Attack_Slice": Vector4(0.0, 0.33, 0.47, 1.1),
	&"CombatMelee/Melee_2H_Attack_Stab": Vector4(0.0, 0.33, 0.47, 1.4),
	&"CombatMelee/Melee_Dualwield_Attack_Chop": Vector4(0.4, 0.8, 0.93, 1.27),
	&"CombatMelee/Melee_Dualwield_Attack_Slice": Vector4(0.2, 0.5, 0.67, 1.17),
	&"CombatMelee/Melee_Dualwield_Attack_Stab": Vector4(0.0, 0.33, 0.47, 1.4),
	&"CombatMelee/Melee_Unarmed_Attack_Punch_A": Vector4(0.1, 0.33, 0.5, 1.17),
	&"CombatMelee/Melee_Blocking": Vector4(0.3, 0.3, 0.3, 0.3),
	&"General/Throw": Vector4(0.0, 0.57, 0.8, 1.37),
	&"CombatRanged/Ranged_Magic_Shoot": Vector4(0.0, 0.0, 0.33, 0.93),
	# A bow: held drawn and aimed; a shot lets go at the start of the release
	&"CombatRanged/Ranged_Bow_Aiming_Idle": Vector4(0.5, 0.5, 0.5, 0.5),
	&"CombatRanged/Ranged_Bow_Release": Vector4(0.0, 0.0, 0.1, 0.8),
}
## The dual-wield clips where the right arm doesn't strike when the left
## does (CLIP_KEYS has the left's timing): the right arm's own.
const RIGHT_ARM_CLIP_KEYS: Dictionary[StringName, Vector4] = {
	&"CombatMelee/Melee_Dualwield_Attack_Chop": Vector4(0.0, 0.4, 0.6, 1.0),
}
const STATE_XFADE := 0.1
const RETURN_XFADE := 0.15
## The red tint pulsing over the character during iframes: its strongest
## alpha, and pulses per second.
const IFRAME_FLASH_ALPHA := 0.35
const IFRAME_FLASH_RATE := 6.0

## Overrides the player's chosen character (e.g. for testing in a scene).
@export var character: PackedScene

@onready var body: Node3D = $Character
@onready var team_ring: MeshInstance3D = $TeamRing
## Someone playing on this machine: a copy of their ring keeps spreading
## out from it and fading (a sonar ping), and the ring swells as each one
## leaves, so they can spot themselves in a crowd.
const RING_PULSE := 0.12
const PING_PERIOD := 1.4
const PING_DURATION := 0.9
const PING_SCALE := 2.2
const PING_ALPHA := 0.7
var _ping_ring: MeshInstance3D = null
var _ping_time: float = 0.0

var player: PlayerClass3D = null
var tree: AnimationTree = null
var skeleton: Skeleton3D = null
var _playback: AnimationNodeStateMachinePlayback = null
var _last_pose: int = PlayerClass3D.Pose.NONE
var _iframe_flash: bool = false
var _iframe_time: float = 0.0
var _flash_material: StandardMaterial3D = null
## Laid over the body while a status lasts (see set_status_overlay), under
## the iframe flash.
var _status_overlay: Material = null
var _armored: bool = false
## Where the body sits when nothing moves it (a dodge roll lifts and pivots it).
var _body_rest_position := Vector3.ZERO
## Seconds into the current dodge roll, for the flip.
var _roll_elapsed: float = 0.0
## The ring of stars (see STAR_COUNT) and the bone it follows.
var _stars: Node3D = null
var _head_bone: int = -1
var _stars_time: float = 0.0

## Follow the handslot bones, which is where weapons are held (see hand()).
var _hand_left := Node3D.new()
var _hand_right := Node3D.new()
var _hand_bone_left: int = -1
var _hand_bone_right: int = -1
## Per arm: the clip it's playing (kept while it blends back out) and how
## far blended in it is.
var _arm_clip_left: StringName = &""
var _arm_clip_right: StringName = &""
var _arm_weight_left: float = 0.0
var _arm_weight_right: float = 0.0
## The body's sweep (see CLIP_SWEEP) right now, in radians.
var _sweep_yaw: float = 0.0
var _sweep_pitch: float = 0.0
## What each arm's action wants the sweep to be this frame: [yaw, pitch], or empty.
var _sweep_want_left: Array = []
var _sweep_want_right: Array = []
## The torso's clip (kept while it blends back out) and how far blended in.
var _torso_clip: StringName = &""
var _torso_weight: float = 0.0
## What each arm wants the torso to play this frame: [clip, time], or empty.
var _torso_want_left: Array = []
var _torso_want_right: Array = []
## Clips already warned about (missing from CLIP_KEYS), so it's once each.
var _warned_clips: Dictionary[StringName, bool] = {}
## Each arm's swing phase last frame (0 when not swinging), to hear it
## strike (see _update_swing_sound).
var _swing_phase_left: float = 0.0
var _swing_phase_right: float = 0.0
## A swing whooshes as its phase passes this, into the strike.
const SWING_SOUND_PHASE := 1.05
## Seconds between footsteps: half the walk or run clip's cycle (two steps
## each), blended by speed like the clips are, and quicker as a sprint
## speeds the run up.
static var _walk_step_time: float = _half_cycle(WALK_CLIP)
static var _run_step_time: float = _half_cycle(RUN_CLIP)
## Slower than this is standing still.
const STEP_MIN_SPEED := 0.5
## Falling at least this fast (m/s) lands with a thud.
const LAND_FALL_SPEED := 4.0
## Seconds left until the next footstep.
var _step_left: float = 0.0
## How fast the body was falling, while it's in the air.
var _fall_speed: float = 0.0


## Called by the player once its Properties are set up.
func setup(owner_player: PlayerClass3D) -> void:
	player = owner_player
	_hand_left.name = "HandLeft"
	_hand_right.name = "HandRight"
	add_child(_hand_left)
	add_child(_hand_right)
	# Each player tints its own ring
	team_ring.material_override = team_ring.material_override.duplicate()
	_make_ping_ring()
	_make_stars()
	var scene: PackedScene = character
	if not scene:
		scene = Roster.model_of(player.slot.character if player.slot else 0)
	_set_character(scene)


func _set_character(scene: PackedScene) -> void:
	var new_body: Node3D = scene.instantiate()
	new_body.transform = body.transform
	remove_child(body)
	body.queue_free()
	new_body.name = "Character"
	add_child(new_body)
	body = new_body
	_body_rest_position = body.position
	skeleton = body.get_node(SKELETON_PATH) as Skeleton3D
	_head_bone = skeleton.find_bone("head")
	_hand_bone_left = skeleton.find_bone("handslot.l")
	_hand_bone_right = skeleton.find_bone("handslot.r")
	skeleton.skeleton_updated.connect(_on_skeleton_updated)
	set_armored(_armored)
	if tree:
		tree.queue_free()
	_build_tree()


func _build_tree() -> void:
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	for library_name: StringName in LIBRARIES:
		tree.add_animation_library(library_name, LIBRARIES[library_name])

	var states := AnimationNodeStateMachine.new()
	var roll: float = PlayerClass3D.ROLL_DURATION
	states.add_node(&"Move", _locomotion())
	states.add_node(&"Dive", _clip(DIVE_CLIP, roll * DIVE_SHARE))
	states.add_node(&"Tuck", _clip(TUCK_CLIP, roll * (1.0 - DIVE_SHARE)))
	states.add_node(&"Backstep", _clip(BACKSTEP_CLIP, PlayerClass3D.BACKSTEP_DURATION))
	states.add_node(&"Slide", _clip(SLIDE_CLIP, PlayerClass3D.SLIDE_DURATION))
	states.add_node(&"Stagger", _clip(STAGGER_CLIP, PlayerClass3D.STAGGER_DURATION))
	states.add_node(&"Knockdown", _clip(KNOCKDOWN_CLIP))  # Holds its last frame, lying down
	states.add_node(&"GetUp", _clip(KNOCKDOWN_CLIP, PlayerClass3D.GETUP_DURATION, true))
	states.add_node(&"Spawn", _clip(SPAWN_CLIP))
	states.add_node(&"Down", _clip(DOWN_CLIP))  # Holds its last frame, lying down
	states.add_transition(&"Start", &"Move", _transition(0.0, true))
	# Where each one goes on its own once it's finished (the dive tucks into
	# the roll); Knockdown waits for GetUp.
	var then: Dictionary[StringName, StringName] = {
		&"Dive": &"Tuck", &"Tuck": &"Move", &"Backstep": &"Move", &"Slide": &"Move",
		&"Stagger": &"Move", &"GetUp": &"Move", &"Spawn": &"Move",
	}
	var one_shots: Array[StringName] = [&"Dive", &"Tuck", &"Backstep", &"Slide",
			&"Stagger", &"Knockdown", &"GetUp", &"Spawn"]
	for from: StringName in one_shots:
		states.add_transition(&"Move", from, _transition(STATE_XFADE))
		if then.has(from):
			var next := _transition(RETURN_XFADE if then[from] == &"Move" else 0.05, true)
			next.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
			states.add_transition(from, then[from], next)
		for to: StringName in one_shots:
			if to != from and then.get(from) != to:
				states.add_transition(from, to, _transition(STATE_XFADE))
	# Down from anything; only getting back up (Spawn) leaves it
	for from: StringName in [&"Move", &"Dive", &"Tuck", &"Backstep", &"Slide", &"Stagger", &"Knockdown", &"GetUp"]:
		states.add_transition(from, &"Down", _transition(STATE_XFADE))
	states.add_transition(&"Down", &"Spawn", _transition(STATE_XFADE))

	var hit := AnimationNodeOneShot.new()
	hit.fadein_time = 0.05
	hit.fadeout_time = 0.15
	hit.filter_enabled = true
	for bone: String in UPPER_BODY_BONES:
		hit.set_filter_path(NodePath("%s:%s" % [SKELETON_PATH, bone]), true)

	var root := AnimationNodeBlendTree.new()
	root.add_node(&"base", states)
	root.add_node(&"hit", hit)
	root.add_node(&"hit_clip", _clip(HIT_CLIP, HIT_DURATION))
	root.connect_node(&"hit", 0, &"base")
	root.connect_node(&"hit", 1, &"hit_clip")
	_add_layer(root, &"torso", TORSO_BONES, &"hit")
	_add_layer(root, &"arm_l", _arm_bones("l"), &"torso")
	_add_layer(root, &"arm_r", _arm_bones("r"), &"arm_l")
	root.connect_node(&"output", 0, &"arm_r")

	tree.tree_root = root
	add_child(tree)
	tree.root_node = tree.get_path_to(body)
	tree.active = true
	tree.set(&"parameters/arm_l_scale/scale", 0.0)
	tree.set(&"parameters/arm_r_scale/scale", 0.0)
	tree.set(&"parameters/torso_scale/scale", 0.0)
	_playback = tree.get(&"parameters/base/playback")
	_last_pose = PlayerClass3D.Pose.NONE


func _arm_bones(side: String) -> Array[String]:
	var bones: Array[String] = []
	for bone: String in ARM_BONES:
		bones.append("%s.%s" % [bone, side])
	return bones


## A clip over `below`, filtered to `bones` (an arm, or the torso). The clip
## doesn't play on its own: it's frozen and moved to the time the arm's
## action is at each frame (see _update_arm), so hitstop, rebound and online
## playback all come out of the player's own timers.
func _add_layer(root: AnimationNodeBlendTree, layer: StringName, bones: Array[String], below: StringName) -> void:
	var blend := AnimationNodeBlend2.new()
	blend.filter_enabled = true
	for bone: String in bones:
		blend.set_filter_path(NodePath("%s:%s" % [SKELETON_PATH, bone]), true)
	var clip := AnimationNodeAnimation.new()
	clip.animation = PUNCH_CLIP
	root.add_node(layer, blend)
	root.add_node(StringName(layer + "_clip"), clip)
	root.add_node(StringName(layer + "_scale"), AnimationNodeTimeScale.new())
	root.add_node(StringName(layer + "_seek"), AnimationNodeTimeSeek.new())
	root.connect_node(StringName(layer + "_scale"), 0, StringName(layer + "_clip"))
	root.connect_node(StringName(layer + "_seek"), 0, StringName(layer + "_scale"))
	root.connect_node(layer, 0, below)
	root.connect_node(layer, 1, StringName(layer + "_seek"))


## Idle, walk and run blended by ground speed, sped up past a run.
func _locomotion() -> AnimationNodeBlendTree:
	var space := AnimationNodeBlendSpace1D.new()
	space.min_space = 0.0
	space.max_space = RUN_SPEED
	space.add_blend_point(_clip(IDLE_CLIP), 0.0, -1, &"idle")
	space.add_blend_point(_clip(WALK_CLIP), WALK_SPEED, -1, &"walk")
	space.add_blend_point(_clip(RUN_CLIP), RUN_SPEED, -1, &"run")
	var blend := AnimationNodeBlendTree.new()
	blend.add_node(&"locomotion", space)
	blend.add_node(&"speed", AnimationNodeTimeScale.new())
	blend.connect_node(&"speed", 0, &"locomotion")
	blend.connect_node(&"output", 0, &"speed")
	return blend


## A clip, stretched to last `duration` seconds if given (so e.g. a dodge
## lasts exactly as long as the roll it shows), and played in reverse if
## `backward`.
func _clip(clip: StringName, duration: float = 0.0, backward: bool = false) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	if backward:
		node.play_mode = AnimationNodeAnimation.PLAY_MODE_BACKWARD
	if duration > 0.0:
		node.use_custom_timeline = true
		node.timeline_length = duration
		node.stretch_time_scale = true
	return node


func _transition(xfade: float, auto: bool = false) -> AnimationNodeStateMachineTransition:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = xfade
	transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO if auto \
		else AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	return transition


func _process(delta: float) -> void:
	if not player or not tree:
		return
	_update_ping(delta)
	var speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	tree.set(&"parameters/base/Move/locomotion/blend_position", speed)
	tree.set(&"parameters/base/Move/speed/scale", clampf(speed / RUN_SPEED, 1.0, MAX_RUN_TIME_SCALE))

	var pose: int = player.anim_pose
	if pose != _last_pose and not player.is_dead():  # Knocked out bodies stay down
		# Frozen solid: the body holds whatever pose it was in
		tree.active = pose != PlayerClass3D.Pose.FROZEN
		match pose:
			PlayerClass3D.Pose.ROLL:
				_go(&"Dive")
				_roll_elapsed = 0.0
				Sfx.play(&"roll", player.global_position)
			PlayerClass3D.Pose.BACKSTEP:
				_go(&"Backstep")
				Sfx.play(&"roll", player.global_position)
			PlayerClass3D.Pose.SLIDE:
				_go(&"Slide")
				Sfx.play(&"roll", player.global_position)
			PlayerClass3D.Pose.KNOCKDOWN:
				_go(&"Knockdown")
				Sfx.play(&"land", player.global_position)
			PlayerClass3D.Pose.GETUP: _go(&"GetUp")
			PlayerClass3D.Pose.ASLEEP: _go(&"Knockdown")  # Lies there until woken
			PlayerClass3D.Pose.STAGGER: _go(&"Stagger")
		_last_pose = pose

	_update_arm(true, delta)
	_update_arm(false, delta)
	_update_swing_sound(true)
	_update_swing_sound(false)
	_update_footsteps(speed, delta)
	_update_torso(delta)
	_update_sweep(delta)
	_update_iframe_flash(delta)
	_update_stars(delta)
	# Leaning back into a slide, pivoting at the feet, sweeping into attacks and
	# spinning through a spin combo; or flipping through a dodge roll, turning
	# round the middle of the body instead
	var flip: Vector2 = _roll_flip(delta)
	var lean: float = SLIDE_LEAN if player.anim_pose == PlayerClass3D.Pose.SLIDE else 0.0
	body.rotation.x = _sweep_pitch + lean + flip.x
	body.rotation.y = _sweep_yaw + player.arm_anim[6]
	var body_position: Vector3 = _body_rest_position
	if flip != Vector2.ZERO:
		var pivot := Vector3(0.0, ROLL_PIVOT_HEIGHT, 0.0)
		body_position += pivot - Basis.from_euler(body.rotation) * pivot + Vector3.UP * flip.y
	body.position = body_position


## The dodge roll's flip right now: (forward pitch, lift), both 0 when not
## rolling. Diving, the body tips forward to nearly flat and arcs up off
## the floor and back down onto its hands; then it rolls the rest of the
## way over, ending upright just as the roll does.
func _roll_flip(delta: float) -> Vector2:
	if player.anim_pose != PlayerClass3D.Pose.ROLL or player.is_dead():
		return Vector2.ZERO
	_roll_elapsed += delta
	var t: float = clampf(_roll_elapsed / PlayerClass3D.ROLL_DURATION, 0.0, 1.0)
	if t < DIVE_SHARE:
		var dive: float = t / DIVE_SHARE
		return Vector2(DIVE_PITCH * sin(dive * PI * 0.5), DIVE_HEIGHT * sin(dive * PI))
	var over: float = (t - DIVE_SHARE) / (1.0 - DIVE_SHARE)
	return Vector2(lerpf(DIVE_PITCH, TAU, smoothstep(0.0, 1.0, over)), 0.0)


## Whoosh as an arm's swing passes into its strike: its weapon's swing
## sound, or a punch's. Read off arm_anim, so every machine hears it. A
## ranged weapon's shot has its own sound (see CrossbowClass3D.fire_sound),
## unless a combo beat swings it like a club.
func _update_swing_sound(is_left: bool) -> void:
	var arm: PackedFloat32Array = player.arm_anim
	var swinging: bool = roundi(arm[0 if is_left else 2]) == PlayerClass3D.ArmAction.SWING
	var phase: float = arm[1 if is_left else 3] if swinging else 0.0
	var last: float = _swing_phase_left if is_left else _swing_phase_right
	if is_left:
		_swing_phase_left = phase
	else:
		_swing_phase_right = phase
	if last >= SWING_SOUND_PHASE or phase < SWING_SOUND_PHASE:
		return
	var weapon: Weapon3D = player.held_weapon_left if is_left else player.held_weapon_right
	var sound: StringName = &"swing_fist"
	if weapon:
		var combo_beat: bool = arm[4 if is_left else 5] >= 0.0
		if not weapon.plays_swipe_animation and not combo_beat:
			return
		sound = weapon.swing_sound
	Sfx.play(sound, player.global_position)


## A footstep every stride while walking or running on the ground (in
## chain mail while armored), and a thud on landing from a fall. Read off
## the synced velocity, so every machine hears everyone.
func _update_footsteps(speed: float, delta: float) -> void:
	var falling: float = -player.velocity.y
	if falling > 1.0:
		_fall_speed = maxf(_fall_speed, falling)
		return  # In the air
	if _fall_speed >= LAND_FALL_SPEED:
		Sfx.play(&"land", player.global_position)
		_step_left = _run_step_time * 0.5
	_fall_speed = 0.0
	if speed < STEP_MIN_SPEED or player.anim_pose != PlayerClass3D.Pose.NONE or player.is_dead():
		_step_left = 0.0  # The first step comes as soon as it moves off
		return
	_step_left -= delta * clampf(speed / RUN_SPEED, 1.0, MAX_RUN_TIME_SCALE)
	if _step_left > 0.0:
		return
	var run: float = clampf(remap(speed, WALK_SPEED, RUN_SPEED, 0.0, 1.0), 0.0, 1.0)
	_step_left = maxf(_step_left + lerpf(_walk_step_time, _run_step_time, run), 0.0)
	Sfx.play(&"footstep_armored" if player.armored else &"footstep", player.global_position)


## Half of `clip`'s length: one step of a two-step cycle.
static func _half_cycle(clip: StringName) -> float:
	var parts: PackedStringArray = String(clip).split("/")
	return LIBRARIES[StringName(parts[0])].get_animation(StringName(parts[1])).length * 0.5


## Blend the arm into (or out of) its action's clip, at the action's phase.
## A two-handed weapon brings the free left arm along with the right.
func _update_arm(is_left: bool, delta: float) -> void:
	var arm: PackedFloat32Array = player.arm_anim
	var action: int = roundi(arm[0 if is_left else 2])
	var phase: float = arm[1 if is_left else 3]
	var clip_is_left: bool = is_left
	if is_left and action == PlayerClass3D.ArmAction.REST and _holds_two_handed():
		action = roundi(arm[2])
		phase = arm[3]
		clip_is_left = false
	var layer: String = "arm_l" if is_left else "arm_r"
	var clip: StringName = &""
	if action != PlayerClass3D.ArmAction.REST:
		clip = _arm_clip(action, clip_is_left, clip_at(arm[4 if clip_is_left else 5]))
	var torso_want: Array = []
	var sweep_want: Array = []
	if clip != &"":
		torso_want = [clip, _clip_time(clip, phase, clip_is_left)]
		if action != PlayerClass3D.ArmAction.HOLD and CLIP_SWEEP.has(clip):
			sweep_want = _sweep_at(CLIP_SWEEP[clip], clip_is_left, phase)
	if is_left:
		_torso_want_left = torso_want
		_sweep_want_left = sweep_want
	else:
		_torso_want_right = torso_want
		_sweep_want_right = sweep_want
	var weight: float = _arm_weight_left if is_left else _arm_weight_right
	var target: float = 1.0 if clip != &"" else 0.0
	weight = move_toward(weight, target, delta / (ARM_BLEND_IN if target > weight else ARM_BLEND_OUT))
	if clip != &"":
		if clip != (_arm_clip_left if is_left else _arm_clip_right):
			var node := (tree.tree_root as AnimationNodeBlendTree).get_node(StringName(layer + "_clip")) as AnimationNodeAnimation
			node.animation = clip
		if is_left:
			_arm_clip_left = clip
		else:
			_arm_clip_right = clip
		tree.set("parameters/%s_seek/seek_request" % layer, _clip_time(clip, phase, clip_is_left))
	if is_left:
		_arm_weight_left = weight
	else:
		_arm_weight_right = weight
	tree.set("parameters/%s/blend_amount" % layer, weight)


## [yaw, pitch] (radians) of a `sweep` (see CLIP_SWEEP) at action `phase`:
## wound back the other way over the wind-up, whipped through the strike
## (fast, then easing off), and settling back over the recovery.
func _sweep_at(sweep: Vector3, is_left: bool, phase: float) -> Array:
	var yaw: float = deg_to_rad(sweep.y if is_left else sweep.x)
	var pitch: float = deg_to_rad(sweep.z)
	var wound := Vector2(-0.5 * yaw, -0.3 * pitch)
	var full := Vector2(yaw, pitch)
	var at: Vector2
	if phase <= 1.0:
		at = wound * smoothstep(0.0, 1.0, maxf(phase, 0.0))
	elif phase <= 2.0:
		var u: float = phase - 1.0
		at = wound.lerp(full, 1.0 - (1.0 - u) * (1.0 - u))
	else:
		at = full.lerp(Vector2.ZERO, smoothstep(0.0, 1.0, minf(phase - 2.0, 1.0)))
	return [at.x, at.y]


## The body follows whichever arm's attack sweeps (the right first), and
## eases back to straight once neither does.
func _update_sweep(delta: float) -> void:
	var want: Array = _sweep_want_right if not _sweep_want_right.is_empty() else _sweep_want_left
	if want.is_empty():
		var _ease: float = minf(SWEEP_RETURN_SPEED * delta, 1.0)
		_sweep_yaw = lerpf(_sweep_yaw, 0.0, _ease)
		_sweep_pitch = lerpf(_sweep_pitch, 0.0, _ease)
	else:
		_sweep_yaw = want[0]
		_sweep_pitch = want[1]


## The torso follows whichever arm wants it (the right first), blending back
## to the body's own clip once neither does.
func _update_torso(delta: float) -> void:
	var want: Array = _torso_want_right if not _torso_want_right.is_empty() else _torso_want_left
	var target: float = 0.0 if want.is_empty() else 1.0
	_torso_weight = move_toward(_torso_weight, target, delta / (ARM_BLEND_IN if target > _torso_weight else ARM_BLEND_OUT))
	if not want.is_empty():
		if want[0] != _torso_clip:
			_torso_clip = want[0]
			var node := (tree.tree_root as AnimationNodeBlendTree).get_node(&"torso_clip") as AnimationNodeAnimation
			node.animation = _torso_clip
		tree.set(&"parameters/torso_seek/seek_request", want[1])
	tree.set(&"parameters/torso/blend_amount", _torso_weight)


func _holds_two_handed() -> bool:
	var weapon: Weapon3D = player.held_weapon_right
	return weapon != null and weapon.grip == Weapon3D.Grip.TWO_HANDED


## The clip an arm plays for `action`, given what's in that hand. A combo
## beat's own swing clip (`combo_clip`) wins over the weapon's.
func _arm_clip(action: int, is_left: bool, combo_clip: StringName = &"") -> StringName:
	var weapon: Weapon3D = player.held_weapon_left if is_left else player.held_weapon_right
	match action:
		PlayerClass3D.ArmAction.SWING:
			if not weapon:
				return PUNCH_CLIP
			if combo_clip != &"":
				return combo_clip
			return weapon.offhand_swing_clip if is_left else weapon.swing_clip
		PlayerClass3D.ArmAction.THROW:
			return OFFHAND_THROW_CLIP if is_left else THROW_CLIP
		PlayerClass3D.ArmAction.HOLD:
			return weapon.hold_clip if weapon else &""
	return &""


## `clip` as a number for PlayerClass3D.arm_anim: its place in CLIP_KEYS,
## or -1 for none.
static func clip_index(clip: StringName) -> int:
	if clip == &"":
		return -1
	var index: int = CLIP_KEYS.keys().find(clip)
	if index < 0:
		push_warning("Combo clip %s isn't in PlayerVisual3D.CLIP_KEYS" % clip)
	return index


## The clip clip_index() numbered, or none.
static func clip_at(index: float) -> StringName:
	var i: int = roundi(index)
	return CLIP_KEYS.keys()[i] if i >= 0 and i < CLIP_KEYS.size() else &""


## Seconds into `clip` for an action `phase` (see CLIP_KEYS) of that arm.
func _clip_time(clip: StringName, phase: float, is_left: bool) -> float:
	var keys: Vector4 = CLIP_KEYS.get(clip, Vector4(-1.0, 0.0, 0.0, 0.0))
	if not is_left:
		keys = RIGHT_ARM_CLIP_KEYS.get(clip, keys)
	if keys.x < 0.0:
		if not _warned_clips.has(clip):
			_warned_clips[clip] = true
			push_warning("No CLIP_KEYS timing for %s; add it to PlayerVisual3D" % clip)
		keys = Vector4(0.0, 0.3, 0.5, 1.0)
	if phase <= 1.0:
		return lerpf(keys.x, keys.y, maxf(phase, 0.0))
	if phase <= 2.0:
		return lerpf(keys.y, keys.z, phase - 1.0)
	return lerpf(keys.z, keys.w, minf(phase - 2.0, 1.0))


## Where `is_left`'s hand holds things: its handslot bone, posed this frame.
func hand(is_left: bool) -> Node3D:
	return _hand_left if is_left else _hand_right


## The skeleton has just been posed: move the hands, and what they hold, to
## the new pose at once, so nothing trails a frame behind the arm.
func _on_skeleton_updated() -> void:
	if not is_inside_tree():
		return  # The scene is being torn down (e.g. a match restarting)
	_hand_left.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(_hand_bone_left)
	_hand_right.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(_hand_bone_right)
	if not player:
		return
	for weapon: Weapon3D in [player.held_weapon_left, player.held_weapon_right]:
		if weapon:
			weapon.on_hand_posed()


func _go(state: StringName) -> void:
	if _playback.get_current_node() == state:
		_playback.start(state, true)
	else:
		_playback.travel(state)


## Back from the dead: rise out of the ground.
func play_spawn() -> void:
	if _playback:
		_go(&"Spawn")


## Killed or knocked out: collapse and stay down until play_spawn().
func play_down() -> void:
	if _playback:
		tree.active = true  # Even if frozen
		_go(&"Down")


## Flinch from a hit. Rolling, sliding, staggered, knocked down or spawning
## bodies already have their own clip going, so they don't.
func play_hit() -> void:
	if not tree or player.anim_pose != PlayerClass3D.Pose.NONE \
			or _playback.get_current_node() == &"Spawn":
		return
	tree.set(&"parameters/hit/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func set_team_color(color: Color) -> void:
	var material := team_ring.material_override as StandardMaterial3D
	if material:
		material.albedo_color = color
	if _ping_ring:
		(_ping_ring.material_override as StandardMaterial3D).albedo_color = color


# ===== SPOTTING YOURSELF =====

func _make_ping_ring() -> void:
	_ping_ring = MeshInstance3D.new()
	_ping_ring.name = "PingRing"
	_ping_ring.mesh = team_ring.mesh
	_ping_ring.transform = team_ring.transform
	_ping_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = (team_ring.material_override as StandardMaterial3D).albedo_color
	_ping_ring.material_override = material
	_ping_ring.visible = false
	add_child(_ping_ring)


## Pulse our ring and send out pings, if we're someone playing here.
func _update_ping(delta: float) -> void:
	var mine: bool = player.is_local_person() and not player.is_dead()
	_ping_ring.visible = mine
	if not mine:
		team_ring.scale = Vector3.ONE
		return
	_ping_time = fmod(_ping_time + delta, PING_PERIOD)
	var t: float = _ping_time / PING_DURATION
	var swell: float = clampf(1.0 - t, 0.0, 1.0)
	team_ring.scale = Vector3.ONE * (1.0 + RING_PULSE * swell * swell)
	_ping_ring.visible = t < 1.0
	var spread: float = lerp(1.0, PING_SCALE, ease(t, 0.5))  # Fast out, slowing
	_ping_ring.scale = Vector3(spread, 1.0, spread)
	(_ping_ring.material_override as StandardMaterial3D).albedo_color.a = PING_ALPHA * (1.0 - t)


## Show or hide the character's headgear and cape (see ARMOR_MESHES).
func set_armored(on: bool) -> void:
	_armored = on
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if String(mesh.name).rsplit("_", true, 1)[-1] in ARMOR_MESHES:
			mesh.visible = on


## A light red pulse while in iframes, laid over each mesh (material_overlay)
## so the textures are kept and nothing shows through the armor.
func set_iframe_fade(on: bool) -> void:
	_iframe_flash = on
	_iframe_time = 0.0
	if on and _flash_material == null:
		_flash_material = StandardMaterial3D.new()
		_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_material.albedo_color = Color(1.0, 0.1, 0.1, IFRAME_FLASH_ALPHA)
	_apply_overlay()


## Lay `material` over the body (a status: frozen, burning), or null for
## none. The iframe flash still shows over it while it lasts.
func set_status_overlay(material: Material) -> void:
	_status_overlay = material
	_apply_overlay()


func _apply_overlay() -> void:
	var material: Material = _flash_material if _iframe_flash else _status_overlay
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		mesh.material_overlay = material


## The stars: small flat five-pointed ones, always facing the camera,
## spaced round a ring that's hidden until we're knocked down.
func _make_stars() -> void:
	var points := PackedVector3Array()
	for i in 10:
		var angle: float = PI * 0.5 + TAU * i / 10.0
		var radius: float = STAR_SIZE if i % 2 == 0 else STAR_SIZE * 0.45
		points.append(Vector3(cos(angle), sin(angle), 0.0) * radius)
	var vertices := PackedVector3Array()
	for i in 10:
		vertices.append_array([Vector3.ZERO, points[i], points[(i + 1) % 10]])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = STAR_COLOR
	mesh.surface_set_material(0, material)
	_stars = Node3D.new()
	_stars.name = "Stars"
	_stars.visible = false
	add_child(_stars)
	for i in STAR_COUNT:
		var star := MeshInstance3D.new()
		star.mesh = mesh
		star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_stars.add_child(star)


## Knocked down (and getting up): the stars circle over the head, wherever
## the fall has put it, each bobbing as it goes.
func _update_stars(delta: float) -> void:
	var pose: int = player.anim_pose
	var on: bool = (pose == PlayerClass3D.Pose.KNOCKDOWN or pose == PlayerClass3D.Pose.GETUP) \
			and not player.is_dead() and _head_bone >= 0
	if on and not _stars.visible:
		_stars_time = 0.0
	_stars.visible = on
	if not on:
		return
	_stars_time += delta
	var head: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(_head_bone)).origin
	_stars.global_position = head + Vector3.UP * STAR_HEIGHT
	# Pop in rather than appear all at once
	var grow: float = minf(_stars_time / 0.2, 1.0)
	var count: int = _stars.get_child_count()
	for i in count:
		var star := _stars.get_child(i) as MeshInstance3D
		var angle: float = _stars_time * STAR_ORBIT_SPEED + TAU * i / count
		star.position = Vector3(cos(angle) * STAR_RING_RADIUS,
				sin(_stars_time * 5.0 + i * 1.7) * STAR_BOB, sin(angle) * STAR_RING_RADIUS)
		star.scale = Vector3.ONE * grow


func _update_iframe_flash(delta: float) -> void:
	if not _iframe_flash:
		return
	_iframe_time += delta
	var pulse: float = 0.5 + 0.5 * cos(_iframe_time * TAU * IFRAME_FLASH_RATE)
	_flash_material.albedo_color.a = IFRAME_FLASH_ALPHA * pulse
