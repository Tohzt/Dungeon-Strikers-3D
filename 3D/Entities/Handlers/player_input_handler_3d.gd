class_name PlayerInputHandler3D extends Node
@onready var Master: CharacterBody3D = get_parent()

var move_dir: Vector3
var look_dir: Vector3 = Vector3.ZERO
var action_left: bool = false
var action_right: bool = false
var dodge: bool = false
var interact: bool = false
var interact_held: bool = false
var target_toggle: bool = false
var target_scroll: bool = false

# Mouse movement tracking for 3D
var last_mouse_pos: Vector2
var mouse_movement_timer: float = 0.0
const MOUSE_MOVEMENT_COOLDOWN: float = 0.5
const MOUSE_LOOK_STRENGTH: float = 15.0

# Camera reference for 3D mouse look
var camera: Camera3D = null


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
	var input_2d: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	move_dir = Vector3(input_2d.x, 0, input_2d.y).normalized()
	_handle_look_input(delta)


func _handle_look_input(delta: float) -> void:
	if Global.input_type == "Keyboard":
		print("Keyboard")
		# For 3D, we can use mouse position to determine look direction
		# This is a simplified version - can be enhanced with raycasting
		if camera:
			var mouse_pos: Vector2 = get_viewport().get_mouse_position()
			var from: Vector3 = camera.project_ray_origin(mouse_pos)
			var to: Vector3 = from + camera.project_ray_normal(mouse_pos) * 1000.0
			
			# Calculate direction from player to mouse ray intersection point
			# For now, project onto X/Z plane
			var _player_pos: Vector3 = Master.global_position
			var ray_dir: Vector3 = (to - from).normalized()
			var horizontal_dir: Vector3 = Vector3(ray_dir.x, 0, ray_dir.z).normalized()
			
			if horizontal_dir.length() > 0.1:
				look_dir = horizontal_dir
				mouse_movement_timer = MOUSE_MOVEMENT_COOLDOWN
			else:
				mouse_movement_timer -= delta
				if mouse_movement_timer <= 0:
					look_dir = Vector3.ZERO
		else:
			# Fallback: no camera, zero look dir
			mouse_movement_timer -= delta
			if mouse_movement_timer <= 0:
				look_dir = Vector3.ZERO
	
	elif Global.input_type == "Controller":
		print("Controller")
		var controller_input: Vector2 = Input.get_vector("aim_left","aim_right","aim_up","aim_down")
		if controller_input.length() > 0.1:
			look_dir = Vector3(controller_input.x, 0, controller_input.y).normalized()
			mouse_movement_timer = MOUSE_MOVEMENT_COOLDOWN
		else:
			mouse_movement_timer -= delta
			if mouse_movement_timer <= 0:
				look_dir = Vector3.ZERO
	printt("Looking Dir: ", look_dir)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_movement_timer = MOUSE_MOVEMENT_COOLDOWN
		# Look direction will be updated in _process via _handle_look_input
	
	if event.is_action("attack_left"):
		action_left = event.is_action_pressed("attack_left")
	
	if event.is_action("attack_right"):
		action_right = event.is_action_pressed("attack_right")
	
	if event.is_action("dodge"):
		dodge = event.is_action_pressed("dodge")
	
	if event.is_action("interact"):
		interact = event.is_action_pressed("interact")
	
	if event.is_action("target"):
		target_toggle = event.is_action_pressed("target")
	
	if event.is_action("target_scroll"):
		if event.is_action_pressed("target_scroll"):
			target_scroll = true
