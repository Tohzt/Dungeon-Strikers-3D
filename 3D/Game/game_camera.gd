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
@export var controller_aim_offset: float = 3.5  # How far the right stick shifts the view (world units)
@export var controller_sprint_aim_offset: float = 7.0  # ...while sprinting, to see further ahead
@export var controller_aim_ease: float = 2.5  # How quickly the view eases toward the stick offset

@export_group("Multiple Players")
@export var group_padding: float = 3.0  # World units kept visible around each player
@export var group_max_fov: float = 70.0  # Furthest the camera zooms out to fit everyone
@export var group_zoom_speed: float = 3.0

var initial_transform: Transform3D
var aim_offset: Vector3 = Vector3.ZERO  # Eased controller look-ahead
var test_offset: float = 0.0

func _ready() -> void:
	initial_transform = global_transform
	#initial_fov = fov
	
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


## Who to keep in view: the exported target if one is set, else every player.
func _get_targets() -> Array[Node3D]:
	var targets: Array[Node3D] = []
	if target:
		targets.append(target)
	elif Global.Game3D:
		for player: Node3D in Global.Game3D.players:
			if is_instance_valid(player):
				targets.append(player)
	return targets


func _process(delta: float) -> void:
	if !is_active:
		if fov > initial_fov:
			fov = lerp(fov, initial_fov, delta)
		return

	# Keep rotation fixed - never change it
	global_transform.basis = initial_transform.basis

	var targets := _get_targets()
	if targets.size() > 1:
		_frame_group(targets, delta)
		return

	# Single player: fixed zoom, camera pulled toward where they're aiming.
	# Eases back in rather than snapping if the group just shrank to one.
	fov = lerp(fov, initial_fov, clamp(delta * group_zoom_speed, 0.0, 1.0))
	if targets.is_empty(): return
	var focus: Node3D = targets[0]
	var handler: PlayerInputHandler3D = focus.get("Input_Handler")
	var uses_mouse: bool = handler.uses_mouse() if handler else Global.input_type != "Controller"

	var target_pos: Vector3 = focus.global_position
	var plane_y: float = target_pos.y
	var look_target: Vector3 = target_pos  # Default to player position
	
	# Detect input type and calculate offset accordingly
	if !uses_mouse:
		# Controller mode: the right stick shifts the view ahead of the player.
		# The offset eases in/out on its own (rather than jumping to the stick)
		# and responds gently to small tilts, so aiming doesn't jerk the camera.
		var stick_input: Vector2 = handler.get_aim_stick() if handler else Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
		var desired_offset: Vector3 = Vector3.ZERO
		if stick_input.length() > 0.1:  # Deadzone to prevent drift
			# Get camera's forward and right vectors projected onto ground plane
			var forward_3d: Vector3 = -initial_transform.basis.z  # Camera forward
			var right_3d: Vector3 = initial_transform.basis.x      # Camera right
			var forward_ground: Vector3 = Vector3(forward_3d.x, 0, forward_3d.z).normalized()
			var right_ground: Vector3 = Vector3(right_3d.x, 0, right_3d.z).normalized()
			
			# Negate stick_input.y to fix up/down inversion
			var dir: Vector3 = (right_ground * stick_input.x + forward_ground * -stick_input.y).normalized()
			var strength: float = min(stick_input.length(), 1.0)
			var sprinting: bool = focus.get("is_sprinting") == true
			var reach: float = controller_sprint_aim_offset if sprinting else controller_aim_offset
			desired_offset = dir * strength * strength * reach
		aim_offset = aim_offset.lerp(desired_offset, clamp(delta * controller_aim_ease, 0.0, 1.0))
		look_target = target_pos + aim_offset
	elif not Input.is_action_pressed(handler.action("face_movement") if handler else &"face_movement"):
		# Keyboard/mouse mode: pull toward the cursor while aiming at it (i.e.
		# not holding Ctrl to face the walking direction);
		# otherwise look_target stays on the player
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
	
	# Smoothly move camera position (panning only, no rotation)
	global_position = global_position.lerp(_ideal_position(look_target), delta * follow_speed)


## Several players: center on the group and widen the FOV just enough to keep
## everyone (plus padding) on screen, never tighter than the single-player view.
func _frame_group(targets: Array[Node3D], delta: float) -> void:
	var min_pos: Vector3 = targets[0].global_position
	var max_pos: Vector3 = min_pos
	for t: Node3D in targets:
		min_pos = min_pos.min(t.global_position)
		max_pos = max_pos.max(t.global_position)
	var ideal_pos: Vector3 = _ideal_position((min_pos + max_pos) * 0.5)

	# Measure each player from where the camera is heading, in camera space,
	# and find the half-angle (as a tangent) needed to fit them. FOV is
	# vertical, so horizontal extents are divided by the aspect ratio.
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = viewport_size.x / viewport_size.y
	var to_camera_space: Basis = initial_transform.basis.inverse()
	var needed_tan: float = tan(deg_to_rad(initial_fov) * 0.5)
	for t: Node3D in targets:
		var local: Vector3 = to_camera_space * (t.global_position - ideal_pos)
		var depth: float = -local.z
		if depth <= 0.01: continue
		needed_tan = max(needed_tan,
			(abs(local.y) + group_padding) / depth,
			(abs(local.x) + group_padding) / depth / aspect)
	var target_fov: float = clamp(rad_to_deg(2.0 * atan(needed_tan)), initial_fov, group_max_fov)

	fov = lerp(fov, target_fov, clamp(delta * group_zoom_speed, 0.0, 1.0))
	global_position = global_position.lerp(ideal_pos, delta * follow_speed)


## Where the camera sits (fixed height and angle) so look_target is centered.
func _ideal_position(look_target: Vector3) -> Vector3:
	var fixed_y: float = initial_transform.origin.y
	# The camera looks in direction -initial_transform.basis.z (forward)
	var forward_dir: Vector3 = -initial_transform.basis.z
	var height_diff: float = fixed_y - look_target.y
	
	# Calculate distance needed along forward direction to position camera correctly
	# We want: look_target = camera_pos + forward_dir * distance (projected)
	# Since forward_dir has a Y component, we need to solve for distance
	var distance: float = height_diff / -forward_dir.y if forward_dir.y < 0 else 30.0
	
	# Position camera so that when looking in fixed direction, look_target is centered
	var ideal_pos: Vector3 = look_target - forward_dir * distance
	ideal_pos.y = fixed_y
	return ideal_pos
