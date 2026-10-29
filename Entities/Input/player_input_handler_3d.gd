class_name PlayerInputHandler3D extends Node
@onready var Master: CharacterBody3D = get_parent()

var move_dir: Vector3
var look_dir: Vector3 = Vector3.ZERO
## The attack buttons, held this frame (see PlayerClass3D's BUTTONS): light
## (left click / RB) attacks on press, heavy (right click / LB) charges while
## held and goes off on release, and Throw (Q / Y) charges a throw of the
## weapon in hand (or the ball we carry), and Shoot (E / LT) charges a shot
## of the carried ball at the goal. Carrying the ball, light throws it and
## heavy passes it (see PlayerClass3D.pass_ball). Bots press them too.
var light_held: bool = false
var heavy_held: bool = false
var throw_held: bool = false
var shoot_held: bool = false
var interact: bool = false
var interact_held: bool = false
## Use Item (G / D-pad Down): take what's in the item slot out into our
## hands (see PlayerClass3D.stored_item). Stays set until the player acts on it.
var use_item: bool = false
# The roll button (Space / A) rolls on press, or slides while sprinting.
# The controller's dodge button (B) also rolls on a quick tap (on release)
# and sprints while held; keyboard sprints with Shift.
## Sprinting: Shift held, or the dodge button held past DODGE_TAP_TIME.
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

# Lock-on (middle mouse / R3): face and aim at a boss, skeleton or enemy
# player instead of the cursor or right stick, until pressed again or the
# target dies or gets away. Locking picks whatever's nearest the cursor (or
# where the right stick / the player points); the mouse wheel, or flicking
# the right stick toward another target, switches. Tab toggles it too, but
# locks on to whatever's nearest. While carrying the ball, teammates can be
# locked on to as well (to pass to; see PlayerClass3D.shoot_ball).
## What we're locked on to, if anything. Only people lock on (not bots).
var lock_target: Node3D = null
const LOCK_RANGE := 20.0
## The lock drops once the target gets this much further than LOCK_RANGE.
const LOCK_BREAK_RATIO := 1.3
## Flicking the right stick this far switches target; it has to come back
## under LOCK_FLICK_RESET before the next flick.
const LOCK_FLICK := 0.7
const LOCK_FLICK_RESET := 0.3
var _flick_held: bool = false
var _lock_marker: LockOnMarker3D = null

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
	light_held = false
	heavy_held = false
	throw_held = false
	shoot_held = false
	move_dodge = false
	dodge_dur = 0.0
	dodge_request_msec = -1
	look_dir = Vector3.ZERO
	aim_release_timer = 0.0
	interact = false
	use_item = false


func _process(delta: float) -> void:
	if _held_for_intro():
		return
	# Get 2D input and convert to 3D (X/Z plane)
	var input_2d: Vector2 = Input.get_vector(action("move_left"), action("move_right"), action("move_up"), action("move_down"))
	move_dir = Vector3(input_2d.x, 0, input_2d.y).normalized()
	
	light_held = Input.is_action_pressed(action("attack_light"))
	heavy_held = Input.is_action_pressed(action("attack_heavy"))
	throw_held = Input.is_action_pressed(action("throw"))
	shoot_held = Input.is_action_pressed(action("shoot"))
	# Stays set until the player acts on it
	if Input.is_action_just_pressed(action("interact")):
		interact = true
	if Input.is_action_just_pressed(action("use_item")):
		use_item = true
	_handle_input_dodge(delta)
	_handle_lock_on()
	_handle_input_look(delta)


## The match's opening camera move isn't done: stand still and let go of
## everything until it is.
func _held_for_intro() -> bool:
	if not Global.Game3D or Global.Game3D.camera_active:
		return false
	release_all()
	move_dir = Vector3.ZERO
	return true


## Space / A rolls on press, Shift sprints while held. Controller: B tap =
## roll, hold = sprint; that roll goes off on release (like the
## souls games), since until then a tap can't be told apart from a hold.
func _handle_input_dodge(delta: float) -> void:
	if Input.is_action_just_pressed(action("roll")):
		dodge_request_msec = Time.get_ticks_msec()
	var dodge_held_long: bool = false
	if Input.is_action_pressed(action("move_dodge")):
		dodge_dur += delta
		dodge_held_long = dodge_dur >= DODGE_TAP_TIME
	elif dodge_dur > 0.0:
		if dodge_dur < DODGE_TAP_TIME:
			dodge_request_msec = Time.get_ticks_msec()
		dodge_dur = 0.0
	move_dodge = dodge_held_long or Input.is_action_pressed(action("sprint"))

## look_dir is where the player wants to face; zero means "face the walking
## direction". Locked on, it's the target. Otherwise mouse players aim at
## the cursor, except while holding face_movement (Alt); controller players
## aim with the right stick.
func _handle_input_look(delta: float) -> void:
	if lock_target:
		var to_target: Vector3 = lock_target.global_position - Master.global_position
		to_target.y = 0.0
		look_dir = to_target.normalized() if to_target.length() > 0.1 else look_dir
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


# ===== LOCK-ON =====

func _unhandled_input(event: InputEvent) -> void:
	# The wheel switches target: up = counter-clockwise round us, down = clockwise.
	# Only the mouse seat has the wheel (bots and pads have no copy of the action).
	if lock_target and uses_mouse() and event is InputEventMouseButton and event.is_action_pressed(action("target_scroll")):
		_cycle_lock(-1 if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_UP else 1)


func _handle_lock_on() -> void:
	if Input.is_action_just_pressed(action("target")):
		_set_lock(null if lock_target else _pick_lock(_lock_aim()))
	if Input.is_action_just_pressed(action("target_nearest")):
		_set_lock(null if lock_target else _nearest_lock())
	if lock_target and not _can_lock(lock_target, LOCK_RANGE * LOCK_BREAK_RATIO):
		_set_lock(null)
	# Controller: flick the right stick toward another target to switch
	if uses_mouse():
		return
	var stick: Vector2 = get_aim_stick()
	if _flick_held:
		_flick_held = stick.length() > LOCK_FLICK_RESET
	elif lock_target and stick.length() >= LOCK_FLICK:
		_flick_held = true
		var picked: Node3D = _pick_lock(Vector3(stick.x, 0.0, stick.y), lock_target)
		if picked:
			_set_lock(picked)


## Bosses still fighting, living skeletons, and players on other teams (and
## our own, while we carry the ball).
func _lock_candidates() -> Array[Node3D]:
	var found: Array[Node3D] = []
	var game: Game3D_Class = Global.Game3D
	if not game:
		return found
	for boss: Boss3D in game.bosses:
		found.append(boss)
	for node: Node in get_tree().get_nodes_in_group(SkeletonEnemy3D.GROUP):
		found.append(node as Node3D)
	for other: PlayerClass3D in game.players:
		found.append(other)
	return found.filter(func(node: Node3D) -> bool: return _can_lock(node, LOCK_RANGE))


func _can_lock(node: Node3D, max_range: float) -> bool:
	if not is_instance_valid(node) or node == Master or (Master as PlayerClass3D).is_dead():
		return false
	if node is PlayerClass3D and (node.is_dead() \
			or (Combat.are_teammates(node, Master) and not (Master as PlayerClass3D).carries_ball())):
		return false
	if node is SkeletonEnemy3D and node.is_dead:
		return false
	if node is Boss3D and not Global.Game3D.bosses.has(node):
		return false
	return Master.global_position.distance_to(node.global_position) <= max_range


## Which way from us the player means to lock: toward the cursor, the right
## stick, or the way we face.
func _lock_aim() -> Vector3:
	if uses_mouse() and camera:
		var cursor: Vector3 = _get_mouse_aim()
		if not cursor.is_zero_approx():
			return cursor
	var stick: Vector2 = get_aim_stick()
	if stick.length() > 0.3:
		return Vector3(stick.x, 0.0, stick.y).normalized()
	return Master.global_basis.z


## The candidate closest to `aim` (a flat direction from us): mostly by
## angle, with nearer ones winning a close call. `except` is left out.
func _pick_lock(aim: Vector3, except: Node3D = null) -> Node3D:
	var best: Node3D = null
	var best_score: float = INF
	for candidate: Node3D in _lock_candidates():
		if candidate == except:
			continue
		var offset: Vector3 = candidate.global_position - Master.global_position
		offset.y = 0.0
		var angle: float = absf(aim.signed_angle_to(offset, Vector3.UP)) if offset.length() > 0.1 else 0.0
		if except and angle > PI / 3.0:
			continue  # A flick only switches to something roughly that way
		var score: float = angle + offset.length() * 0.03
		if score < best_score:
			best_score = score
			best = candidate
	return best


## The candidate closest to us, if any.
func _nearest_lock() -> Node3D:
	var best: Node3D = null
	var best_dist: float = INF
	for candidate: Node3D in _lock_candidates():
		var dist: float = Master.global_position.distance_to(candidate.global_position)
		if dist < best_dist:
			best_dist = dist
			best = candidate
	return best


## Switch to the next target round us, clockwise (direction 1) or
## counter-clockwise (-1) as seen from above, wrapping around.
func _cycle_lock(direction: int) -> void:
	var around: Array[Node3D] = _lock_candidates()
	if not around.has(lock_target):
		around.append(lock_target)
	if around.size() < 2:
		return
	var angle_of := func(node: Node3D) -> float:
		var offset: Vector3 = node.global_position - Master.global_position
		return atan2(offset.x, -offset.z)
	around.sort_custom(func(a: Node3D, b: Node3D) -> bool: return angle_of.call(a) < angle_of.call(b))
	_set_lock(around[posmod(around.find(lock_target) + direction, around.size())])


func _set_lock(target: Node3D) -> void:
	lock_target = target
	# A stick already pushed out when locking on isn't a flick
	_flick_held = true
	if target and not _lock_marker:
		_lock_marker = LockOnMarker3D.new()
		_lock_marker.name = "LockOnMarker"
		_lock_marker.handler = self
		if slot:
			_lock_marker.color = slot.color
		add_child(_lock_marker)
