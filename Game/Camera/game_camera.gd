class_name GameCamera3D extends Camera3D
## The match camera: follows the local players from above, frames them all
## (and the ball), and widens to show a goal when play gets near one.

@export var target: Node3D
var is_active: bool = false
var can_zoom: bool = true

@export var fov_sensitivity: float = 5.0
@export var min_fov: float = 10.0
@export var max_fov: float = 120.0
@export var initial_fov: float = 25.0

@export var max_camera_offset: float = 10.0  # Maximum distance camera can move from player
@export var follow_speed: float = 8.0  # Camera follow responsiveness
@export var mouse_pull_strength: float = 0.3  # How much the camera pulls toward mouse (0-1)
@export var controller_aim_offset: float = 3.5  # How far the right stick shifts the view (world units)
@export var controller_sprint_aim_offset: float = 7.0  # ...while sprinting, to see further ahead
@export var controller_aim_ease: float = 2.5  # How quickly the view eases toward the stick offset

@export_group("Multiple Players")
@export var group_padding: float = 5.0  # World units kept visible around each player
@export var group_max_fov: float = 55.0  # Furthest the camera zooms out to fit everyone
@export var group_zoom_speed: float = 3.0
@export var frame_ball: bool = true  # Also keep the ball on screen
@export var goal_frame_distance: float = 15.0  # Frame a goal and the ball once both a player and the ball are this close to it
@export var goal_half_width: float = 3.5  # Goal centre to each post

@export_group("Focus")
## The view stays on the players. It only widens to also show a goal and
## the ball while one of them and the ball are both near it.

## Extra ground kept in view below (nearer the camera than) the players while
## framing several things, so the boss health bar doesn't cover them.
@export var hud_margin: float = 5.0
## The view stays centred on the players, sliding at most this far toward
## what they're focused on; the FOV widens to show the rest.
@export var context_max_shift: float = 5.0
## How quickly that slide follows (slower than follow_speed, so framing a
## goal doesn't yank the view).
@export var context_ease: float = 1.5

@export_group("Wall Tilt")
## A wall between a player (or the ball) and the camera hides them, so the
## camera tilts toward top-down just enough to see them over it, and once
## fully tilted, slides out over the field (away from the wall) and widens
## the FOV to keep them on screen. Found by line of sight from each of them
## to where the camera would be, so this works on any map and any wall
## height without being told about either.
@export_flags_3d_physics var wall_mask: int = 1
@export var wall_ray_height: float = 0.5  # Sight line starts this far above their origin (about knee height)
## ...and this far toward the bottom of the screen (but only halfway to a
## wall there), so the camera gets out of the way before they reach the
## wall, by as much as that wall's height actually calls for.
@export var wall_lead: float = 2.0
## A wall toward the bottom of the screen within this distance starts the
## tilt early: by how much standing right at it would need, ramping in...
@export var tilt_start_distance: float = 16.0
## ...to all of that from this distance in, so the camera is already as far
## over as that wall will ever need before they reach it.
@export var full_tilt_distance: float = 6.0
## Moving toward that wall counts as already being this many seconds of
## that movement closer, so running at it tilts sooner than walking.
@export var tilt_velocity_lead: float = 0.4
@export_range(0.0, 60.0) var top_down_extra_pitch: float = 40.0  # Most degrees added to the usual downward tilt (never past straight down)
@export var top_down_ease: float = 4.0  # How quickly the tilt (and slide) eases back
@export var top_down_in_ease: float = 6.0  # How quickly it tilts further over (quicker, so it keeps up with a sprint)
## A ball within this distance of a player also tilts the view to be seen
## over a wall (tilt only: it never moves or widens the view).
@export var ball_tilt_range: float = 12.0
## Furthest the view slides out over the field, past full tilt, to see a
## player over a wall.
@export var wall_max_shift: float = 10.0
@export var wall_fov_padding: float = 2.5  # World units kept visible around a player while slid out
## How much more of the field fits on screen at full tilt (1.35 = 35% more),
## eased in with the tilt, so being zoomed in doesn't feel cramped against
## the bottom wall.
@export var tilt_zoom_out: float = 1.35

@export_group("Audio")
## Sounds are heard from this far back from the middle of the view (along
## the camera's line of sight) rather than from the camera itself, which is
## far off and would make everything quiet.
@export var listener_distance: float = 6.0

var initial_transform: Transform3D
## The camera's current rotation: its starting one, tilted by top_down_blend.
var view_basis: Basis
var top_down_blend: float = 0.0  # 0 = usual angle, 1 = fully tilted
var wall_shift: float = 0.0  # How far the view has slid out over the field (see wall_max_shift)
var aim_offset: Vector3 = Vector3.ZERO  # Eased controller look-ahead
var context_shift: Vector3 = Vector3.ZERO  # Eased slide toward what's focused on (see context_max_shift)
## Where the view was last centred (before any wall slide), so the wall
## checks see the players from where the camera really is, not as if it
## were centred on each of them (the mouse pull alone moves it a long way
## when zoomed out).
var _view_center: Vector3
var _has_view_center: bool = false
## The player's chosen zoom (scroll wheel); the camera never frames tighter.
var zoom_fov: float
## Jumped to the players yet (so the match doesn't open on an empty room).
var _placed: bool = false
## Hears for this camera while it's the one in use (see _update_listener).
var _listener: AudioListener3D

func _ready() -> void:
	# The headless server has no screen, and none of its players read local input.
	if Net.is_server:
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	initial_transform = global_transform
	zoom_fov = initial_fov
	view_basis = initial_transform.basis
	#initial_fov = fov
	_listener = AudioListener3D.new()
	_listener.top_level = true
	add_child(_listener)
	
	var Game: Game3D_Class = Global.Game3D
	if Game.has_signal("set_camera_active"):
		Game.set_camera_active.connect(_set_camera_active)

func _set_camera_active(TorF: bool) -> void: is_active = TorF
 

## Scrolling sets the base zoom the automatic camera works from, rather than
## the FOV itself (which the camera eases every frame). Wheel up zooms in.
## Not during the opening move (until is_active), which would snap at the end.
func _input(event: InputEvent) -> void:
	if not is_active or not can_zoom or not event is InputEventMouseButton or not event.pressed:
		return
	var zoom_dir: int = 0
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP: zoom_dir = -1
		MOUSE_BUTTON_WHEEL_DOWN: zoom_dir = 1
	if zoom_dir:
		zoom_fov = clamp(zoom_fov + zoom_dir * fov_sensitivity, min_fov, max_fov)


## Who to keep in view: the exported target if one is set; online, just our
## own player (the others are on their own screens); else every local person
## playing, or every bot when nobody is.
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


## Everything the group view should fit: the players and what they're
## focused on (see _focus_points).
func _get_group_points(targets: Array[Node3D]) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for t: Node3D in targets:
		points.append(t.global_position)
		points.append(_below_on_screen(t.global_position))
	points.append_array(_focus_points(targets))
	return points


## What the view should widen to show besides `targets` themselves: for
## any ball near a goal that one of them is also near, that ball and both
## posts (so the whole mouth shows). Nothing else pulls the view.
func _focus_points(targets: Array[Node3D]) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for goal: Node3D in get_tree().get_nodes_in_group("Goal"):
		var balls: Array[Ball3D] = _balls_at_goal(goal, targets)
		for ball: Ball3D in balls:
			points.append(ball.global_position)
		if not balls.is_empty():
			points.append(goal.to_global(Vector3(0, 0, goal_half_width)))
			points.append(goal.to_global(Vector3(0, 0, -goal_half_width)))
	return points


## The balls within goal_frame_distance of `goal`, if one of `targets` is
## too (else none).
func _balls_at_goal(goal: Node3D, targets: Array[Node3D]) -> Array[Ball3D]:
	var balls: Array[Ball3D] = []
	if not frame_ball or not Global.Game3D:
		return balls
	var goal_flat: Vector2 = _flat(goal.global_position)
	var player_near: bool = false
	for t: Node3D in targets:
		if _flat(t.global_position).distance_to(goal_flat) <= goal_frame_distance:
			player_near = true
			break
	if not player_near:
		return balls
	for ball: Ball3D in Global.Game3D.balls:
		if is_instance_valid(ball) and ball.is_inside_tree() \
				and _flat(ball.global_position).distance_to(goal_flat) <= goal_frame_distance:
			balls.append(ball)
	return balls


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _process(delta: float) -> void:
	_update_listener()
	_update_shake(delta)
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
		var own: Array[Vector3] = []
		for t: Node3D in targets:
			own.append(t.global_position)
			own.append(_below_on_screen(t.global_position))
		_frame_group(_get_group_points(targets), _bounds_center(own), delta)
		return

	# Single player: fixed zoom, camera pulled a little toward where they're
	# aiming, widening only to show a goal they and the ball are near (see
	# _focus_points).
	if targets.is_empty():
		fov = lerp(fov, _base_fov(), clamp(delta * group_zoom_speed, 0.0, 1.0))
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
	elif not (focus is PlayerClass3D and (focus as PlayerClass3D).is_perk_locked()) \
			and not Input.is_action_pressed(handler.action("face_movement") if handler else &"face_movement"):
		# Keyboard/mouse mode: pull toward the cursor while aiming at it (i.e.
		# not holding Ctrl to face the walking direction, and not pointing
		# at a shop or perk cards); otherwise look_target stays on the player
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

	# Widen to also show the goal they and the ball are near, keeping the
	# player and where they're aiming in view.
	var focus_points: Array[Vector3] = _focus_points(targets)
	if not focus_points.is_empty():
		var points: Array[Vector3] = [target_pos, look_target, _below_on_screen(target_pos)]
		points.append_array(focus_points)
		_frame_group(points, look_target, delta)
		return

	# Eases back in rather than snapping once the focus ends, or the group
	# shrinks to one.
	context_shift = context_shift.lerp(Vector3.ZERO, clamp(delta * context_ease, 0.0, 1.0))
	_set_view_center(look_target + context_shift)
	var ideal_pos: Vector3 = _ideal_position(look_target + context_shift + _wall_offset())
	# Slid out from a wall: widen to keep the player on screen.
	var target_fov: float = _base_fov()
	if wall_shift > 0.01:
		target_fov = _fov_to_fit([target_pos], ideal_pos, wall_fov_padding)
	fov = lerp(fov, target_fov, clamp(delta * group_zoom_speed, 0.0, 1.0))
	# Smoothly move camera position (panning only, no rotation)
	global_position = global_position.lerp(ideal_pos, delta * follow_speed)


## While this camera is in use, hear from listener_distance short of where
## its line of sight meets the floor, facing the same way (so left/right
## still match the screen).
func _update_listener() -> void:
	if not is_current():
		if _listener.is_current():
			_listener.clear_current()
		return
	var forward: Vector3 = -global_transform.basis.z
	var to_floor: float = 0.0  # Looking level or up: hear from the camera
	if forward.y < -0.001:
		to_floor = -global_position.y / forward.y
	var reach: float = max(to_floor - listener_distance, 0.0)
	_listener.global_transform = Transform3D(global_transform.basis, global_position + forward * reach)
	if not _listener.is_current():
		_listener.make_current()


## Shake (see CameraShake) about where the line of sight meets the floor.
func _update_shake(delta: float) -> void:
	var forward: Vector3 = -global_transform.basis.z
	var to_floor: float = 20.0  # Looking level or up: just somewhere ahead
	if forward.y < -0.001:
		to_floor = -global_position.y / forward.y
	CameraShake.apply(self, delta, to_floor, global_position + forward * to_floor)


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


## Ease the tilt toward top-down, just enough to see every player (and a
## ball near one, or framed at a goal) over any wall in the way, and slide out over the field if even
## full tilt isn't enough to see a player. Tilts about the camera's own
## right axis, so it only ever pitches, never turns.
func _update_tilt(targets: Array[Node3D], delta: float) -> void:
	var goal_blend: float = 0.0
	var goal_shift: float = 0.0
	for t: Node3D in targets:
		var need: Vector2 = _wall_need(t, true)
		goal_blend = max(goal_blend, need.x)
		goal_shift = max(goal_shift, need.y)
	# A ball near a player, or framed at a goal (see _focus_points). It only
	# ever tilts the view, never slides it.
	var tilt_balls: Array[Ball3D] = _balls_near(targets)
	for goal: Node3D in get_tree().get_nodes_in_group("Goal"):
		for ball: Ball3D in _balls_at_goal(goal, targets):
			if not ball in tilt_balls:
				tilt_balls.append(ball)
	for ball: Ball3D in tilt_balls:
		goal_blend = max(goal_blend, _wall_need(ball, false).x)
	var in_weight: float = clamp(delta * top_down_in_ease, 0.0, 1.0)
	var out_weight: float = clamp(delta * top_down_ease, 0.0, 1.0)
	top_down_blend = lerp(top_down_blend, goal_blend, in_weight if goal_blend > top_down_blend else out_weight)
	wall_shift = lerp(wall_shift, goal_shift, in_weight if goal_shift > wall_shift else out_weight)
	view_basis = _tilted_basis(top_down_blend)


## The balls within ball_tilt_range of any of `targets`.
func _balls_near(targets: Array[Node3D]) -> Array[Ball3D]:
	var balls: Array[Ball3D] = []
	if not Global.Game3D:
		return balls
	for ball: Ball3D in Global.Game3D.balls:
		if not is_instance_valid(ball) or not ball.is_inside_tree():
			continue
		var ball_flat: Vector2 = _flat(ball.global_position)
		for t: Node3D in targets:
			if _flat(t.global_position).distance_to(ball_flat) <= ball_tilt_range:
				balls.append(ball)
				break
	return balls


## The starting rotation pitched `blend` (0-1) of the way to its furthest
## tilt: top_down_extra_pitch more, but never past straight down.
func _tilted_basis(blend: float) -> Basis:
	var start_pitch: float = rad_to_deg(asin(clamp(initial_transform.basis.z.y, -1.0, 1.0)))
	var extra: float = clamp(top_down_extra_pitch, 0.0, max(88.0 - start_pitch, 0.0))
	return Basis(initial_transform.basis.x.normalized(), -deg_to_rad(extra) * blend) * initial_transform.basis


## Along the ground toward the bottom of the screen.
func _toward_camera() -> Vector3:
	return Vector3(initial_transform.basis.z.x, 0.0, initial_transform.basis.z.z).normalized()


## Where the view is slid to, out over the field, away from the wall.
func _wall_offset() -> Vector3:
	return -_toward_camera() * wall_shift


func _set_view_center(center: Vector3) -> void:
	_view_center = center
	_has_view_center = true


## What it takes to see `who` over the walls: x is the least tilt (0-1),
## y (only if `may_shift`, and only at full tilt) the least slide out over
## the field. The tilt also leads a wall ahead toward the bottom of the
## screen (see tilt_start_distance), so it's done before they get there.
func _wall_need(who: Node3D, may_shift: bool) -> Vector2:
	var exclude: Array[RID] = []
	if who is CollisionObject3D:
		exclude.append((who as CollisionObject3D).get_rid())
	# Goal posts are solid but too thin to hide anyone: never tilt for them
	for goal: Node in get_tree().get_nodes_in_group("Goal"):
		if goal is CollisionObject3D:
			exclude.append((goal as CollisionObject3D).get_rid())
	var at: Vector3 = who.global_position
	var view_offset: Vector3 = _view_center - at if _has_view_center else Vector3.ZERO
	view_offset.y = 0.0
	var from: Vector3 = _sight_point(at, exclude)
	var blend: float = max(_tilt_need(from, at, view_offset, exclude), _wall_ahead_need(who, view_offset, exclude))
	if blend < 1.0 or not may_shift or not _hidden_by_wall(from, at, view_offset, exclude, 1.0, 0.0):
		return Vector2(blend, 0.0)
	if _hidden_by_wall(from, at, view_offset, exclude, 1.0, wall_max_shift):
		return Vector2(1.0, wall_max_shift)
	var low_shift: float = 0.0
	var high_shift: float = wall_max_shift
	for i: int in 5:
		var mid_shift: float = (low_shift + high_shift) * 0.5
		if _hidden_by_wall(from, at, view_offset, exclude, 1.0, mid_shift):
			low_shift = mid_shift
		else:
			high_shift = mid_shift
	return Vector2(1.0, high_shift)


## The least tilt (0-1) that sees `from` over the walls with the view
## centred `view_offset` from `at`: 1 if even full tilt doesn't. Found by
## halving its range a few times.
func _tilt_need(from: Vector3, at: Vector3, view_offset: Vector3, exclude: Array[RID]) -> float:
	if not _hidden_by_wall(from, at, view_offset, exclude, 0.0, 0.0):
		return 0.0
	if _hidden_by_wall(from, at, view_offset, exclude, 1.0, 0.0):
		return 1.0
	var low: float = 0.0
	var high: float = 1.0
	for i: int in 6:
		var mid: float = (low + high) * 0.5
		if _hidden_by_wall(from, at, view_offset, exclude, mid, 0.0):
			low = mid
		else:
			high = mid
	return high


## For the nearest wall toward the bottom of the screen within
## tilt_start_distance: the tilt standing right against it would need,
## ramped in from tilt_start_distance to full at full_tilt_distance (nearer
## the faster `who` is heading for it, see tilt_velocity_lead). A wall low
## enough to see over needs none, however close.
func _wall_ahead_need(who: Node3D, view_offset: Vector3, exclude: Array[RID]) -> float:
	var at: Vector3 = who.global_position
	var lead: float = max(_ground_velocity(who).dot(_toward_camera()), 0.0) * tilt_velocity_lead
	var origin: Vector3 = at + Vector3.UP * wall_ray_height
	var query := PhysicsRayQueryParameters3D.create(origin, origin + _toward_camera() * (tilt_start_distance + lead), wall_mask, exclude)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 0.0
	var hit_pos: Vector3 = hit.position
	var distance: float = origin.distance_to(hit_pos) - lead
	# Standing just short of the wall, seen from where the view would be.
	var at_wall: Vector3 = Vector3(hit_pos.x, at.y, hit_pos.z) - _toward_camera() * 0.3
	var from: Vector3 = at_wall + Vector3.UP * wall_ray_height
	var need: float = _tilt_need(from, at_wall, view_offset, exclude)
	var ramp: float = 1.0 - smoothstep(full_tilt_distance, max(tilt_start_distance, full_tilt_distance + 0.01), distance)
	return need * ramp


## How fast `who` is moving along the ground.
func _ground_velocity(who: Node3D) -> Vector3:
	var v: Vector3 = Vector3.ZERO
	if who is CharacterBody3D:
		v = (who as CharacterBody3D).velocity
	elif who is RigidBody3D:
		v = (who as RigidBody3D).linear_velocity
	v.y = 0.0
	return v


## Where to check `at` can be seen from: wall_ray_height up and wall_lead
## toward the bottom of the screen, or halfway to a wall that's closer than
## twice that.
func _sight_point(at: Vector3, exclude: Array[RID]) -> Vector3:
	var origin: Vector3 = at + Vector3.UP * wall_ray_height
	var query := PhysicsRayQueryParameters3D.create(origin, origin + _toward_camera() * wall_lead * 2.0, wall_mask, exclude)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return origin + _toward_camera() * wall_lead
	return origin.lerp(hit.position, 0.5)


## Whether a wall cuts the line of sight from `from` to where the camera
## would be at tilt `blend`, centred `view_offset` from `at` and slid
## `shift` out over the field. Counts a sight line starting inside a wall.
func _hidden_by_wall(from: Vector3, at: Vector3, view_offset: Vector3, exclude: Array[RID], blend: float, shift: float) -> bool:
	var eye: Vector3 = _ideal_position_for(at + view_offset - _toward_camera() * shift, _tilted_basis(blend))
	var query := PhysicsRayQueryParameters3D.create(from, eye, wall_mask, exclude)
	query.hit_from_inside = true
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _bounds_center(points: Array[Vector3]) -> Vector3:
	var min_pos: Vector3 = points[0]
	var max_pos: Vector3 = min_pos
	for p: Vector3 in points:
		min_pos = min_pos.min(p)
		max_pos = max_pos.max(p)
	return (min_pos + max_pos) * 0.5


## Center on `anchor` (the players), eased at most context_max_shift toward
## the middle of `points` (and slid out from any wall, see wall_shift), and
## widen the FOV just enough to keep every point
## (plus padding) on screen, never tighter than the player's chosen zoom.
func _frame_group(points: Array[Vector3], anchor: Vector3, delta: float) -> void:
	var desired_shift: Vector3 = _bounds_center(points) - anchor
	desired_shift.y = 0.0
	context_shift = context_shift.lerp(desired_shift.limit_length(context_max_shift), clamp(delta * context_ease, 0.0, 1.0))
	_set_view_center(anchor + context_shift)
	var ideal_pos: Vector3 = _ideal_position(anchor + context_shift + _wall_offset())
	fov = lerp(fov, _fov_to_fit(points, ideal_pos, group_padding), clamp(delta * group_zoom_speed, 0.0, 1.0))
	global_position = global_position.lerp(ideal_pos, delta * follow_speed)


## The FOV that keeps every point (plus `padding`) on screen from
## `camera_pos`, never tighter than the player's chosen zoom. Measures each
## point in camera space and finds the half-angle (as a tangent) needed to
## fit them. FOV is vertical, so horizontal extents are divided by the
## aspect ratio.
func _fov_to_fit(points: Array[Vector3], camera_pos: Vector3, padding: float) -> float:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = viewport_size.x / viewport_size.y
	var to_camera_space: Basis = view_basis.inverse()
	var base_fov: float = _base_fov()
	var needed_tan: float = tan(deg_to_rad(base_fov) * 0.5)
	for p: Vector3 in points:
		var local: Vector3 = to_camera_space * (p - camera_pos)
		var depth: float = -local.z
		if depth <= 0.01: continue
		needed_tan = max(needed_tan,
			(abs(local.y) + padding) / depth,
			(abs(local.x) + padding) / depth / aspect)
	return clamp(rad_to_deg(2.0 * atan(needed_tan)), base_fov, max(group_max_fov, base_fov))


## The player's chosen zoom, widened by tilt_zoom_out as the view tilts
## over a wall (see top_down_blend).
func _base_fov() -> float:
	var widen: float = lerp(1.0, tilt_zoom_out, top_down_blend)
	return min(rad_to_deg(2.0 * atan(tan(deg_to_rad(zoom_fov) * 0.5) * widen)), max_fov)


## Where the camera sits (fixed height and angle) so look_target is centered.
func _ideal_position(look_target: Vector3) -> Vector3:
	return _ideal_position_for(look_target, view_basis)


## Where the camera sits (fixed height) with rotation `view` so look_target is centered.
func _ideal_position_for(look_target: Vector3, view: Basis) -> Vector3:
	var fixed_y: float = initial_transform.origin.y
	# The camera looks in direction -view.z (forward)
	var forward_dir: Vector3 = -view.z
	var height_diff: float = fixed_y - look_target.y
	
	# Calculate distance needed along forward direction to position camera correctly
	# We want: look_target = camera_pos + forward_dir * distance (projected)
	# Since forward_dir has a Y component, we need to solve for distance
	var distance: float = height_diff / -forward_dir.y if forward_dir.y < 0 else 30.0
	
	# Position camera so that when looking in fixed direction, look_target is centered
	var ideal_pos: Vector3 = look_target - forward_dir * distance
	ideal_pos.y = fixed_y
	return ideal_pos
