extends Camera3D
@export var target: Node3D
var is_active: bool = false
var can_zoom: bool = true

@export var fov_sensitivity: float = 5.0
@export var min_fov: float = 10.0
@export var max_fov: float = 120.0
@export var initial_fov: float = 30.0

@export var max_camera_offset: float = 10.0  # Maximum distance camera can move from player
@export var follow_speed: float = 8.0  # Camera follow responsiveness
@export var mouse_pull_strength: float = 0.3  # How much the camera pulls toward mouse (0-1)
@export var controller_pull_strength: float = 0.3  # How much the camera pulls toward controller stick (0-1)
@export var controller_pull_distance: float = 30.0  # Max distance to offset from player when using controller

var initial_transform: Transform3D
var test_offset: float = 0.0

func _ready() -> void:
	initial_transform = global_transform
	#initial_fov = fov
	
	if !target:
		# Target Player
		var player: Node = get_tree().get_first_node_in_group("Player")
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
	if !is_active:
		if fov > initial_fov:
			fov = lerp(fov, initial_fov, delta)
	else:
		if fov != initial_fov:
			fov = initial_fov
	if !target or !is_active: return
	
	# Keep rotation fixed - never change it
	global_transform.basis = initial_transform.basis
	
	var target_pos: Vector3 = target.global_position
	var fixed_y: float = initial_transform.origin.y
	var plane_y: float = target_pos.y
	var look_target: Vector3 = target_pos  # Default to player position
	
	# Detect input type and calculate offset accordingly
	if Global.input_type == "Controller":
		# Controller mode: use right stick for camera offset
		var stick_input: Vector2 = Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
		
		if stick_input.length() > 0.1:  # Deadzone to prevent drift
			# Get camera's forward and right vectors projected onto ground plane
			var forward_3d: Vector3 = -initial_transform.basis.z  # Camera forward
			var right_3d: Vector3 = initial_transform.basis.x      # Camera right
			
			# Project onto ground plane (remove Y component, normalize)
			var forward_ground: Vector3 = Vector3(forward_3d.x, 0, forward_3d.z).normalized()
			var right_ground: Vector3 = Vector3(right_3d.x, 0, right_3d.z).normalized()
			
			# Calculate offset from player position based on stick input
			# Negate stick_input.y to fix up/down inversion
			var offset: Vector3 = (right_ground * stick_input.x + forward_ground * -stick_input.y) * controller_pull_distance
			var controller_target: Vector3 = target_pos + offset
			controller_target.y = target_pos.y  # Keep at player's height
			
			# Blend between player and controller target
			look_target = target_pos.lerp(controller_target, controller_pull_strength)
		else:
			# No stick input, camera centers on player
			look_target = target_pos
	else:
		# Keyboard/mouse mode: use mouse cursor position
		# Get mouse position in world space (projected onto ground plane)
		# Clamp mouse position to viewport bounds to ensure it's within the game window
		var viewport: Viewport = get_viewport()
		var mouse_pos_2d: Vector2 = viewport.get_mouse_position()
		var viewport_size: Vector2 = viewport.get_visible_rect().size
		mouse_pos_2d.x = clamp(mouse_pos_2d.x, 0, viewport_size.x)
		mouse_pos_2d.y = clamp(mouse_pos_2d.y, 0, viewport_size.y)
		
		var mouse_ray_origin: Vector3 = project_ray_origin(mouse_pos_2d)
		var mouse_ray_dir: Vector3 = project_ray_normal(mouse_pos_2d)
		
		# Project mouse position onto the ground plane (at player's Y level)
		var cursor_world_pos: Vector3 = target_pos  # Default to player position
		
		# Calculate intersection of mouse ray with ground plane
		if mouse_ray_dir.y < -0.001:  # Ray is pointing down
			var t: float = (plane_y - mouse_ray_origin.y) / mouse_ray_dir.y
			cursor_world_pos = mouse_ray_origin + mouse_ray_dir * t
		
		# Calculate look target: blend between player and mouse cursor
		look_target = target_pos.lerp(cursor_world_pos, mouse_pull_strength)
		look_target.y = target_pos.y  # Keep at player's height
	
	# Ensure look_target is at player's height
	look_target.y = target_pos.y
	
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
