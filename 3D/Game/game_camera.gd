extends Camera3D
@export var target: Node3D
var is_active: bool = false
var can_zoom: bool = true

@export var fov_sensitivity: float = 5.0
@export var min_fov: float = 10.0
@export var max_fov: float = 120.0

@export var max_camera_offset: float = 10.0  # Maximum distance camera can move from player
@export var follow_speed: float = 8.0  # Camera follow responsiveness
@export var mouse_pull_strength: float = 0.3  # How much the camera pulls toward mouse (0-1)

var initial_transform: Transform3D
var initial_fov: float = 0.0
var test_offset: float = 0.0

func _ready() -> void:
	initial_transform = global_transform
	initial_fov = fov
	
	if !target:
		# Target Player
		var player: Node = get_tree().get_first_node_in_group("Player")
		print("Camera target Player: ", player)
		if player: target = player as Node3D
	
	var Game: Game3D_Class = Global.Game3D
	if Game.has_signal("set_camera_active"):
		Game.set_camera_active.connect(_set_camera_active)

func _set_camera_active(TorF: bool) -> void: is_active = TorF
 

# Zoom functionality commented out for now
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var zoom_out: bool = event.button_index == MOUSE_BUTTON_WHEEL_UP
		var zoom_in: bool = event.button_index == MOUSE_BUTTON_WHEEL_DOWN
		var zoom_dir := -1 if zoom_out else 1 if zoom_in else 0
		if can_zoom: 
			fov = clamp(fov + zoom_dir*fov_sensitivity, min_fov, max_fov)
		else:
			if zoom_in:
				test_offset-=1 
			if zoom_out:
				test_offset+=1


func _process(delta: float) -> void:
	if !target: return
	
	# Keep rotation fixed - never change it
	global_transform.basis = initial_transform.basis
	
	var target_pos: Vector3 = target.global_position
	var fixed_y: float = initial_transform.origin.y
	
	# Get mouse position in world space (projected onto ground plane)
	var mouse_pos_2d: Vector2 = get_viewport().get_mouse_position()
	var mouse_ray_origin: Vector3 = project_ray_origin(mouse_pos_2d)
	var mouse_ray_dir: Vector3 = project_ray_normal(mouse_pos_2d)
	
	# Project mouse position onto the ground plane (at player's Y level)
	var plane_y: float = target_pos.y
	var cursor_world_pos: Vector3 = target_pos  # Default to player position
	
	# Calculate intersection of mouse ray with ground plane
	if mouse_ray_dir.y < -0.001:  # Ray is pointing down
		var t: float = (plane_y - mouse_ray_origin.y) / mouse_ray_dir.y
		cursor_world_pos = mouse_ray_origin + mouse_ray_dir * t
	
	# Calculate look target: blend between player and mouse cursor
	var look_target: Vector3 = target_pos.lerp(cursor_world_pos, mouse_pull_strength)
	look_target.y = target_pos.y  # Keep at player's height
	
	# Calculate where camera should be positioned to center on look_target
	# The camera looks in direction -initial_transform.basis.z (forward)
	var forward_dir: Vector3 = -initial_transform.basis.z
	var height_diff: float = fixed_y - plane_y
	
	# Calculate distance needed along forward direction to position camera correctly
	# We want: look_target = camera_pos + forward_dir * distance (projected)
	# Since forward_dir has a Y component, we need to solve for distance
	var distance: float = height_diff / -forward_dir.y if forward_dir.y < 0 else 30.0
	
	# Position camera so that when looking in fixed direction, look_target is centered
	var ideal_pos: Vector3 = look_target - forward_dir * distance
	ideal_pos.y = fixed_y
	
	# Smoothly move camera position (panning only, no rotation)
	global_position = global_position.lerp(ideal_pos, delta * follow_speed)
