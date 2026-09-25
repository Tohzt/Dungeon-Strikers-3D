class_name PlayerInputHandler3D extends Node
@onready var Master: CharacterBody3D = get_parent()

enum STATUS { NONE, PRESSED, HELD, RELEASED }

var move_jump: bool = false
var move_dir: Vector3
var look_dir: Vector3 = Vector3.ZERO
var action_left: bool = false
var action_right: bool = false
var action_heavy_left: bool = false
var action_heavy_right: bool = false
var interact: bool = false
var interact_held: bool = false
var target_toggle: bool = false
var target_scroll: bool = false
var move_dodge: bool = false
var dodge_dur: float = 0.0
var dodge_status: STATUS = STATUS.NONE

# After the right stick is released, keep the last aim this long so a flick
# (or a stick briefly passing through the deadzone) doesn't snap the facing.
var aim_release_timer: float = 0.0
const AIM_RELEASE_COOLDOWN: float = 0.5

# Camera reference for 3D mouse look
var camera: Camera3D = null

## Which local player/device this handler listens to; set by the owning
## player. Null = legacy mode that reads the shared actions from any device.
var slot: PlayerSlot = null


## The input action this handler should read for a project action name.
func action(base: StringName) -> StringName:
	return slot.action(base) if slot else base


func uses_mouse() -> bool:
	if slot:
		return slot.uses_keyboard_mouse()
	return Global.input_type == "Keyboard"


func get_aim_stick() -> Vector2:
	return Input.get_vector(action("aim_left"), action("aim_right"), action("aim_up"), action("aim_down"))


func _ready() -> void:
	# Find camera in scene
	camera = get_viewport().get_camera_3d()
	if not camera:
		# Try to find camera as sibling or in tree
		var parent := get_parent()
		if parent:
			camera = parent.get_node_or_null("Camera3D")
			if not camera:
				camera = get_tree().get_first_node_in_group("camera")


func _process(delta: float) -> void:
	# Get 2D input and convert to 3D (X/Z plane)
	var input_2d: Vector2 = Input.get_vector(action("move_left"), action("move_right"), action("move_up"), action("move_down"))
	move_dir = Vector3(input_2d.x, 0, input_2d.y).normalized()
	
	# Update action_left to track current held state (for ball throwing and other actions)
	action_left = Input.is_action_pressed(action("attack_left"))
	move_jump = Input.is_action_just_pressed(action("move_jump"))
	_handle_input_dodge(delta)
	_handle_input_look(delta)

func _handle_input_dodge(delta: float) -> void:
	move_dodge = Input.is_action_pressed(action("move_dodge"))
	if move_dodge:
		if dodge_status == STATUS.NONE:
			dodge_status = STATUS.PRESSED
		else:
			dodge_status = STATUS.HELD
		dodge_dur+=delta
	else:
		if dodge_status == STATUS.HELD:
			pass
		dodge_status = STATUS.RELEASED
		dodge_dur = 0.0

## look_dir is where the player wants to face; zero means "face the walking
## direction". Mouse players always aim at the cursor, except while holding
## face_movement (Ctrl); controller players aim with the right stick.
func _handle_input_look(delta: float) -> void:
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
	if event.is_action(action("attack_left")):
		action_left = event.is_action_pressed(action("attack_left"))
	
	if event.is_action(action("attack_right")):
		action_right = event.is_action_pressed(action("attack_right"))

	if event.is_action(action("attack_heavy_left")):
		action_heavy_left = event.is_action_pressed(action("attack_heavy_left"))

	if event.is_action(action("attack_heavy_right")):
		action_heavy_right = event.is_action_pressed(action("attack_heavy_right"))

	if event.is_action(action("move_dodge")):
		move_dodge = event.is_action_pressed(action("move_dodge"))
	
	if event.is_action(action("interact")):
		interact = event.is_action_pressed(action("interact"))
	
	if event.is_action(action("target")):
		target_toggle = event.is_action_pressed(action("target"))
	
	if event.is_action(action("target_scroll")):
		if event.is_action_pressed(action("target_scroll")):
			target_scroll = true
