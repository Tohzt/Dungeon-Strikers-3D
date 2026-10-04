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
@export var group_padding: float = 5.0  # World units kept visible around each player
@export var group_max_fov: float = 70.0  # Furthest the camera zooms out to fit everyone
@export var group_zoom_speed: float = 3.0
@export var frame_ball: bool = true  # Also keep the ball on screen
@export var goal_frame_distance: float = 15.0  # Pull a goal into view once a player or the ball is this close
@export var goal_half_width: float = 3.5  # Goal centre to each post

@export_group("Arena Framing")
## Inside an arena (a node in the "ArenaZone" group, e.g. the dungeon's
## boss room), the view widens past the player to also show the boss, the
## ball and enemy players that are in there too, if they're this close.
## Outside it the camera sticks to the player. A level without any
## ArenaZone counts as arena everywhere.
@export var context_range: float = 30.0
@export var frame_bosses: bool = true
@export var frame_enemies: bool = true
## Extra ground kept in view below (nearer the camera than) the players while
## framing several things, so the boss health bar doesn't cover them.
@export var hud_margin: float = 5.0

@export_group("Bottom Wall")
## The near (bottom-of-screen) wall hides whatever is right up against it,
## so the camera tilts toward top-down as a player or the ball approaches it.
## Distances are measured from this wall, so resizing the arena keeps working.
@export var bottom_wall: Node3D
@export var top_down_start_distance: float = 10.0  # Start tilting once something is this close to the wall (its center)
@export var top_down_full_distance: float = 2.0  # Fully tilted from here to the wall
@export_range(0.0, 30.0) var top_down_extra_pitch: float = 25.0  # Degrees added to the usual downward tilt
@export var top_down_ease: float = 3.0  # How quickly the tilt follows

var initial_transform: Transform3D
## The camera's current rotation: its starting one, tilted by top_down_blend.
var view_basis: Basis
var top_down_blend: float = 0.0  # 0 = usual angle, 1 = fully tilted
var aim_offset: Vector3 = Vector3.ZERO  # Eased controller look-ahead
## The player's chosen zoom (scroll wheel); the camera never frames tighter.
var zoom_fov: float
## Jumped to the players yet (so the match doesn't open on an empty room).
var _placed: bool = false

func _ready() -> void:
	# The headless server has no screen, and none of its players read local input.
	if Net.is_server:
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	initial_transform = global_transform
	zoom_fov = initial_fov
	view_basis = initial_transform.basis
	#initial_fov = fov
	
	var Game: Game3D_Class = Global.Game3D
	if Game.has_signal("set_camera_active"):
		Game.set_camera_active.connect(_set_camera_active)

func _set_camera_active(TorF: bool) -> void: is_active = TorF
 

## Scrolling sets the base zoom the automatic camera works from, rather than
## the FOV itself (which the camera eases every frame). Wheel up zooms in.
func _input(event: InputEvent) -> void:
	if not can_zoom or not event is InputEventMouseButton or not event.pressed:
		return
	var zoom_dir: int = 0
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP: zoom_dir = -1
		MOUSE_BUTTON_WHEEL_DOWN: zoom_dir = 1
	if zoom_dir:
		zoom_fov = clamp(zoom_fov + zoom_dir * fov_sensitivity, min_fov, max_fov)


## Who to keep in view: the exported target if one is set; online, just our
## own player (the others are on their own screens); else every local person
## playing (bots only show up as enemies nearby, see _context_points), or
## every bot when nobody is.
func _get_targets() -> Array[Node3D]:
	var targets: Array[Node3D] = []
	if target:
		targets.append(target)
		return targets
	if not Global.Game3D:
		return targets
	var bots: Array[Node3D] = []
	for player: PlayerClass3D in Global.Game3D.players:
		if not is_instance_valid(player):
			continue
		if Net.in_session() and not player.is_multiplayer_authority():
			continue
		if player.slot and player.slot.is_bot:
			bots.append(player)
		else:
			targets.append(player)
	return targets if not targets.is_empty() else bots


## Everything the group view should fit: the players, what's around them
## in the arena (see _context_points), and any goal one of those is close to
## (both posts, so the whole mouth shows).
func _get_group_points(targets: Array[Node3D]) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for t: Node3D in targets:
		points.append(t.global_position)
		points.append(_below_on_screen(t.global_position))
	points.append_array(_context_points(targets))
	points.append_array(_goal_points_near(points))
	return points


## The boss, balls and enemy players worth showing alongside `targets`:
## only for targets in an arena, and only within context_range of one.
func _context_points(targets: Array[Node3D]) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var game: Game3D_Class = Global.Game3D
	if not game:
		return points
	var zones: Array[Node] = get_tree().get_nodes_in_group("ArenaZone")
	var anchors: Array[Node3D] = []
	for t: Node3D in targets:
		if zones.is_empty() or _in_arena(t, zones):
			anchors.append(t)
	if anchors.is_empty():
		return points
	var candidates: Array[Node3D] = []
	if frame_ball:
		for ball: Ball3D in game.balls:
			if is_instance_valid(ball) and ball.is_inside_tree():
				candidates.append(ball)
	if frame_bosses:
		for boss: Boss3D in game.bosses:
			if is_instance_valid(boss) and boss.is_awake and not boss.is_defeated:
				candidates.append(boss)
	if frame_enemies:
		for player: PlayerClass3D in game.players:
			if is_instance_valid(player) and not targets.has(player) and not player.is_dead() \
					and (zones.is_empty() or _in_arena(player, zones)):
				candidates.append(player)
	for candidate: Node3D in candidates:
		for anchor: Node3D in anchors:
			if candidate is PlayerClass3D and _same_team(candidate, anchor):
				continue
			var gap: Vector3 = candidate.global_position - anchor.global_position
			if Vector2(gap.x, gap.z).length() <= context_range:
				points.append(candidate.global_position)
				break
	return points


func _in_arena(node: Node3D, zones: Array[Node]) -> bool:
	for zone: Node in zones:
		if zone is Area3D and (zone as Area3D).overlaps_body(node):
			return true
	return false


func _same_team(a: Node3D, b: Node3D) -> bool:
	var slot_a: PlayerSlot = a.get("slot")
	var slot_b: PlayerSlot = b.get("slot")
	return slot_a != null and slot_b != null and slot_a.team == slot_b.team


## Every ball in play (none between rounds).
func _ball_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	if not Global.Game3D:
		return points
	for ball: Ball3D in Global.Game3D.balls:
		if is_instance_valid(ball) and ball.is_inside_tree():
			points.append(ball.global_position)
	return points


## Both posts of every goal within goal_frame_distance of any of `sources`.
func _goal_points_near(sources: Array[Vector3]) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for goal: Node3D in get_tree().get_nodes_in_group("Goal"):
		var goal_flat := Vector2(goal.global_position.x, goal.global_position.z)
		for p: Vector3 in sources:
			if Vector2(p.x, p.z).distance_to(goal_flat) <= goal_frame_distance:
				points.append(goal.to_global(Vector3(0, 0, goal_half_width)))
				points.append(goal.to_global(Vector3(0, 0, -goal_half_width)))
				break
	return points


func _process(delta: float) -> void:
	if not _placed:
		_place_on_targets()
	if !is_active:
		if fov > zoom_fov:
			fov = lerp(fov, zoom_fov, delta)
		return

	var targets := _get_targets()
	_update_tilt(targets, delta)
	global_transform.basis = view_basis

	if targets.size() > 1:
		_frame_group(_get_group_points(targets), delta)
		return

	# Single player: fixed zoom, camera pulled toward where they're aiming,
	# widening only while the ball is near a goal.
	if targets.is_empty():
		fov = lerp(fov, zoom_fov, clamp(delta * group_zoom_speed, 0.0, 1.0))
		return
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

	# In the arena: widen to also show the boss, ball and enemies nearby (and
	# a goal the ball is closing in on), keeping the player and where they're
	# aiming in view.
	var context: Array[Vector3] = _context_points(targets)
	if not context.is_empty():
		var points: Array[Vector3] = [target_pos, look_target, _below_on_screen(target_pos)]
		points.append_array(context)
		points.append_array(_goal_points_near(context))
		_frame_group(points, delta)
		return

	# Eases back in rather than snapping after the ball leaves a goal, or the
	# group shrinks to one.
	fov = lerp(fov, zoom_fov, clamp(delta * group_zoom_speed, 0.0, 1.0))
	# Smoothly move camera position (panning only, no rotation)
	global_position = global_position.lerp(_ideal_position(look_target), delta * follow_speed)


## `point` moved hud_margin toward the bottom of the screen (along the ground).
func _below_on_screen(point: Vector3) -> Vector3:
	var toward_camera: Vector3 = Vector3(view_basis.z.x, 0.0, view_basis.z.z).normalized()
	return point + toward_camera * hud_margin


## Start over the players rather than wherever the camera sits in the scene.
func _place_on_targets() -> void:
	var targets: Array[Node3D] = _get_targets()
	if targets.is_empty():
		return
	var center: Vector3 = Vector3.ZERO
	for t: Node3D in targets:
		center += t.global_position
	center /= targets.size()
	global_position = _ideal_position(center)
	_placed = true


## Ease the tilt toward top-down by how close the lowest player (or the
## ball) is to the bottom wall. Tilts about the camera's own right axis, so
## it only ever pitches, never turns.
func _update_tilt(targets: Array[Node3D], delta: float) -> void:
	var lowest_z: float = -INF
	for t: Node3D in targets:
		lowest_z = max(lowest_z, t.global_position.z)
	for p: Vector3 in _ball_points():
		lowest_z = max(lowest_z, p.z)
	var goal_blend: float = 0.0
	if lowest_z > -INF and bottom_wall:
		var wall_z: float = bottom_wall.global_position.z
		goal_blend = smoothstep(wall_z - top_down_start_distance, wall_z - top_down_full_distance, lowest_z)
	top_down_blend = lerp(top_down_blend, goal_blend, clamp(delta * top_down_ease, 0.0, 1.0))
	var tilt: float = -deg_to_rad(top_down_extra_pitch) * top_down_blend
	view_basis = Basis(initial_transform.basis.x.normalized(), tilt) * initial_transform.basis


## Several players: center on the group and widen the FOV just enough to keep
## every point (plus padding) on screen, never tighter than the player's chosen zoom.
func _frame_group(points: Array[Vector3], delta: float) -> void:
	var min_pos: Vector3 = points[0]
	var max_pos: Vector3 = min_pos
	for p: Vector3 in points:
		min_pos = min_pos.min(p)
		max_pos = max_pos.max(p)
	var ideal_pos: Vector3 = _ideal_position((min_pos + max_pos) * 0.5)

	# Measure each point from where the camera is heading, in camera space,
	# and find the half-angle (as a tangent) needed to fit them. FOV is
	# vertical, so horizontal extents are divided by the aspect ratio.
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = viewport_size.x / viewport_size.y
	var to_camera_space: Basis = view_basis.inverse()
	var needed_tan: float = tan(deg_to_rad(zoom_fov) * 0.5)
	for p: Vector3 in points:
		var local: Vector3 = to_camera_space * (p - ideal_pos)
		var depth: float = -local.z
		if depth <= 0.01: continue
		needed_tan = max(needed_tan,
			(abs(local.y) + group_padding) / depth,
			(abs(local.x) + group_padding) / depth / aspect)
	var target_fov: float = clamp(rad_to_deg(2.0 * atan(needed_tan)), zoom_fov, max(group_max_fov, zoom_fov))

	fov = lerp(fov, target_fov, clamp(delta * group_zoom_speed, 0.0, 1.0))
	global_position = global_position.lerp(ideal_pos, delta * follow_speed)


## Where the camera sits (fixed height and angle) so look_target is centered.
func _ideal_position(look_target: Vector3) -> Vector3:
	var fixed_y: float = initial_transform.origin.y
	# The camera looks in direction -view_basis.z (forward)
	var forward_dir: Vector3 = -view_basis.z
	var height_diff: float = fixed_y - look_target.y
	
	# Calculate distance needed along forward direction to position camera correctly
	# We want: look_target = camera_pos + forward_dir * distance (projected)
	# Since forward_dir has a Y component, we need to solve for distance
	var distance: float = height_diff / -forward_dir.y if forward_dir.y < 0 else 30.0
	
	# Position camera so that when looking in fixed direction, look_target is centered
	var ideal_pos: Vector3 = look_target - forward_dir * distance
	ideal_pos.y = fixed_y
	return ideal_pos
