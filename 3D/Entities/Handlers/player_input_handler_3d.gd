class_name PlayerInputHandler3D extends Node
@onready var Master: CharacterBody3D = get_parent()

var move_jump: bool = false
var move_dir: Vector3
var look_dir: Vector3 = Vector3.ZERO
var action_left: bool = false
var action_right: bool = false
var action_heavy_left: bool = false
var action_heavy_right: bool = false
## Simple controls' Throw button, routed to one hand like Attack.
var throw_left: bool = false
var throw_right: bool = false
var interact: bool = false
var interact_held: bool = false
var target_toggle: bool = false
var target_scroll: bool = false
# The dodge button: a quick tap rolls (on release), holding it sprints.
## Held past DODGE_TAP_TIME: sprinting.
var move_dodge: bool = false
var dodge_dur: float = 0.0
const DODGE_TAP_TIME: float = 0.2
## When a tap last asked for a roll (Time.get_ticks_msec(); -1 = none). The
## player clears it once it rolls, or ignores it once it's too old.
var dodge_request_msec: int = -1

# After the right stick is released, keep the last aim this long so a flick
# (or a stick briefly passing through the deadzone) doesn't snap the facing.
var aim_release_timer: float = 0.0
const AIM_RELEASE_COOLDOWN: float = 0.5

# Camera reference for 3D mouse look
var camera: Camera3D = null

## Which local player/device this handler listens to; set by the owning
## player. Null = legacy mode that reads the shared actions from any device.
var slot: PlayerSlot = null

## Simple controls: which hand the current Attack press went to, and which
## went last (dual-wielding alternates, for combos).
var _attack_was_pressed: bool = false
var _attack_hand_left: bool = false
var _last_attack_left: bool = true
var _throw_was_pressed: bool = false
var _throw_hand_left: bool = false

## Set while this player uses the souls-like controls: movement turns with
## this camera, and the player faces where they walk or their lock-on target.
var souls_camera: SoulsCamera3D = null


## The input action this handler should read for a project action name.
func action(base: StringName) -> StringName:
	return slot.action(base) if slot else base


## Simple controls (the default): Attack, Guard and Throw buttons, which this
## turns into the per-hand presses the player reads; Attack swings on press.
## Advanced: every hand has its own attack and heavy buttons, and a hold
## throws. See PlayerSlot.advanced_controls.
func uses_simple_controls() -> bool:
	return slot == null or not slot.advanced_controls


func uses_mouse() -> bool:
	if slot:
		return slot.uses_keyboard_mouse()
	return Global.input_type == "Keyboard"


func get_aim_stick() -> Vector2:
	return Input.get_vector(action("aim_left"), action("aim_right"), action("aim_up"), action("aim_down"))


func _ready() -> void:
	Players.slot_changed.connect(_on_slot_changed)
	# Find camera in scene
	camera = get_viewport().get_camera_3d()
	if not camera:
		# Try to find camera as sibling or in tree
		var parent := get_parent()
		if parent:
			camera = parent.get_node_or_null("Camera3D")
			if not camera:
				camera = get_tree().get_first_node_in_group("camera")


## Our slot moved to another device: the old device's release events will
## never arrive, so let go of anything it was holding.
func _on_slot_changed(changed: PlayerSlot) -> void:
	if changed != slot:
		return
	release_all()


## Let go of every held button, e.g. after input was ignored for a while
## (a perk pick paused the game) and its release events were missed.
func release_all() -> void:
	action_left = false
	action_right = false
	action_heavy_left = false
	action_heavy_right = false
	throw_left = false
	throw_right = false
	move_dodge = false
	dodge_dur = 0.0
	dodge_request_msec = -1
	look_dir = Vector3.ZERO
	aim_release_timer = 0.0
	interact = false
	move_jump = false


func _process(delta: float) -> void:
	# Get 2D input and convert to 3D (X/Z plane)
	var input_2d: Vector2 = Input.get_vector(action("move_left"), action("move_right"), action("move_up"), action("move_down"))
	if souls_camera:
		move_dir = souls_camera.camera_relative(input_2d).normalized()
	else:
		move_dir = Vector3(input_2d.x, 0, input_2d.y).normalized()
	
	if uses_simple_controls():
		_handle_simple_controls()
	else:
		# Update action_left to track current held state (for ball throwing and other actions)
		action_left = Input.is_action_pressed(action("attack_left"))
	move_jump = Input.is_action_just_pressed(action("move_jump"))
	# Stays set until the player acts on it
	if Input.is_action_just_pressed(action("interact")):
		interact = true
	_handle_input_dodge(delta)
	_handle_input_look(delta)

## Attack and Throw each go to one hand for the whole press, chosen when it
## goes down (Throw takes what Attack would swing next); Guard raises any
## shield held.
func _handle_simple_controls() -> void:
	var attack: bool = Input.is_action_pressed(action("attack"))
	if attack and not _attack_was_pressed:
		_attack_hand_left = _pick_attack_hand()
		_last_attack_left = _attack_hand_left
	_attack_was_pressed = attack
	action_left = attack and _attack_hand_left
	action_right = attack and not _attack_hand_left
	var throw: bool = Input.is_action_pressed(action("throw"))
	if throw and not _throw_was_pressed:
		_throw_hand_left = _pick_attack_hand()
	_throw_was_pressed = throw
	throw_left = throw and _throw_hand_left
	throw_right = throw and not _throw_hand_left
	var guard: bool = Input.is_action_pressed(action("guard"))
	var player := Master as PlayerClass3D
	action_heavy_left = guard and player != null and player.held_weapon_left is ShieldClass3D
	action_heavy_right = guard and player != null and player.held_weapon_right is ShieldClass3D


## Which hand an Attack press uses (true = left). Weapons beat shields (a
## shield only bashes when it's all you hold); two weapons, or two fists,
## take turns, skipping an arm that's still mid-swing.
func _pick_attack_hand() -> bool:
	var player := Master as PlayerClass3D
	if not player or player.held_ball:
		return false  # Either hand bonks or throws the ball
	var left: Weapon3D = player.held_weapon_left
	var right: Weapon3D = player.held_weapon_right
	var left_attacks: bool = left != null and not left is ShieldClass3D
	var right_attacks: bool = right != null and not right is ShieldClass3D
	if left_attacks != right_attacks:
		return left_attacks
	if not left_attacks and (left != null) != (right != null):
		return left != null  # Just a shield: bash with it
	# Both hands alike: take turns, unless the next one is still busy
	var next_left: bool = not _last_attack_left
	if player.is_arm_swinging(next_left) and not player.is_arm_swinging(not next_left):
		next_left = not next_left
	return next_left


## Tap = roll, hold = sprint. The roll goes off on release (like the souls
## games), since until then a tap can't be told apart from a hold.
func _handle_input_dodge(delta: float) -> void:
	if Input.is_action_pressed(action("move_dodge")):
		dodge_dur += delta
		move_dodge = dodge_dur >= DODGE_TAP_TIME
	elif dodge_dur > 0.0:
		if dodge_dur < DODGE_TAP_TIME:
			dodge_request_msec = Time.get_ticks_msec()
		dodge_dur = 0.0
		move_dodge = false

## look_dir is where the player wants to face; zero means "face the walking
## direction". Mouse players always aim at the cursor, except while holding
## face_movement (Ctrl); controller players aim with the right stick.
## Souls-like controls face the lock-on target, if any.
func _handle_input_look(delta: float) -> void:
	if souls_camera:
		# The mouse and right stick turn the camera instead
		look_dir = souls_camera.lock_direction(Master.global_position)
		return
	if uses_mouse():
		look_dir = Vector3.ZERO if Input.is_action_pressed(action("face_movement")) else _get_mouse_aim()
	else:
		var controller_input: Vector2 = get_aim_stick()
		if controller_input.length() > 0.1:
			look_dir = Vector3(controller_input.x, 0, controller_input.y).normalized()
			aim_release_timer = AIM_RELEASE_COOLDOWN
		else:
			aim_release_timer -= delta
			if aim_release_timer <= 0:
				look_dir = Vector3.ZERO


## Direction from the player to the mouse cursor on the player's ground plane.
func _get_mouse_aim() -> Vector3:
	if not camera: return Vector3.ZERO
	# Get mouse position relative to viewport (game window)
	var viewport: Viewport = get_viewport()
	var mouse_pos: Vector2 = viewport.get_mouse_position()
	
	# Clamp mouse position to viewport bounds to ensure it's within the game window
	var viewport_size: Vector2 = viewport.get_visible_rect().size
	mouse_pos.x = clamp(mouse_pos.x, 0, viewport_size.x)
	mouse_pos.y = clamp(mouse_pos.y, 0, viewport_size.y)
	
	# Project mouse ray from camera
	var mouse_ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var mouse_ray_dir: Vector3 = camera.project_ray_normal(mouse_pos)
	
	# Intersect the ray with the ground plane at the player's height
	if mouse_ray_dir.y >= -0.001: return Vector3.ZERO  # Ray isn't pointing down
	var plane_y: float = Master.global_position.y
	var t: float = (plane_y - mouse_ray_origin.y) / mouse_ray_dir.y
	var cursor_world_pos: Vector3 = mouse_ray_origin + mouse_ray_dir * t
	
	var direction: Vector3 = cursor_world_pos - Master.global_position
	direction.y = 0
	# Cursor right on top of the player: no meaningful direction
	if direction.length() < 0.1: return Vector3.ZERO
	return direction.normalized()


func _input(event: InputEvent) -> void:
	if not uses_simple_controls():
		_input_advanced_hands(event)

	if event.is_action(action("move_dodge")):
		move_dodge = event.is_action_pressed(action("move_dodge"))
	
	if event.is_action(action("target")):
		target_toggle = event.is_action_pressed(action("target"))
	
	if event.is_action(action("target_scroll")):
		if event.is_action_pressed(action("target_scroll")):
			target_scroll = true


## Advanced controls: each hand's own attack and heavy buttons.
func _input_advanced_hands(event: InputEvent) -> void:
	if event.is_action(action("attack_left")):
		action_left = event.is_action_pressed(action("attack_left"))
	
	if event.is_action(action("attack_right")):
		action_right = event.is_action_pressed(action("attack_right"))

	if event.is_action(action("attack_heavy_left")):
		action_heavy_left = event.is_action_pressed(action("attack_heavy_left"))

	if event.is_action(action("attack_heavy_right")):
		action_heavy_right = event.is_action_pressed(action("attack_heavy_right"))
