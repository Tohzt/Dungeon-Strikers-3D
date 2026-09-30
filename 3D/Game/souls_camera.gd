class_name SoulsCamera3D extends Node3D
## Third-person camera for the souls-like control scheme (Tab toggles it in
## single-player/online; see Game3D.toggle_control_scheme). Orbits `player`
## with the mouse or right stick, and the target action (middle mouse / R3)
## locks on to the boss or another player. Adapted from the Souls-Like
## Controller addon's camaramotion.gd.
##
## Built in code: this node is the yaw pivot, a SpringArm3D child pitches
## and keeps the camera out of walls, and the Camera3D rides its end.

@export var height: float = 1.6  # Pivot above the player's origin
@export var distance: float = 5.0
@export var pitch_min_deg: float = -60.0  # Looking down from above
@export var pitch_max_deg: float = 30.0  # Looking up from near the floor
@export var default_pitch_deg: float = -20.0
@export var mouse_sensitivity: float = 0.004
@export var stick_speed: float = 3.0  # Radians per second at full tilt
@export var follow_speed: float = 15.0
@export var rotate_ease: float = 12.0

@export_group("Lock-on")
@export var lock_range: float = 25.0
## Lock drops once the target gets this much further than lock_range.
@export var lock_break_ratio: float = 1.3
@export var lock_ease: float = 6.0
@export var lock_pitch_deg: float = -15.0

## Set before adding to the tree.
var player: PlayerClass3D
var lock_target: Node3D = null

var spring: SpringArm3D
var camera: Camera3D

## Where the mouse/stick want the camera; the pivot eases toward these.
var yaw: float = 0.0
var pitch: float = 0.0


func _init() -> void:
	# Releases the mouse while paused (see _process)
	process_mode = Node.PROCESS_MODE_ALWAYS
	top_level = true
	spring = SpringArm3D.new()
	spring.collision_mask = 1  # World only, never the players
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	spring.shape = shape
	add_child(spring)
	camera = Camera3D.new()
	camera.fov = 70.0
	spring.add_child(camera)


func _ready() -> void:
	spring.spring_length = distance
	# Start behind the player, looking where they face
	yaw = player.rotation.y + PI
	pitch = deg_to_rad(default_pitch_deg)
	rotation.y = yaw
	spring.rotation.x = pitch
	global_position = _pivot_point()


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if _menu_open():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not lock_target:
		yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity
	elif player.Input_Handler and event.is_action_pressed(player.Input_Handler.action("target")):
		_toggle_lock()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var menu_open: bool = _menu_open()
	var mouse_mode := Input.MOUSE_MODE_VISIBLE if menu_open else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != mouse_mode:
		Input.mouse_mode = mouse_mode
	if menu_open or not is_instance_valid(player):
		return

	_check_lock()
	if lock_target:
		var to_target: Vector3 = lock_target.global_position - player.global_position
		if Vector2(to_target.x, to_target.z).length() > 0.05:
			yaw = lerp_angle(yaw, atan2(-to_target.x, -to_target.z), clamp(delta * lock_ease, 0.0, 1.0))
		pitch = lerp_angle(pitch, deg_to_rad(lock_pitch_deg), clamp(delta * lock_ease, 0.0, 1.0))
	else:
		var handler: PlayerInputHandler3D = player.Input_Handler
		var stick: Vector2 = handler.get_aim_stick() if handler else Vector2.ZERO
		if handler:
			stick += Input.get_vector(handler.action("look_left"), handler.action("look_right"), handler.action("look_up"), handler.action("look_down"))
		if stick.length() > 0.1:
			yaw -= stick.x * stick_speed * delta
			pitch -= stick.y * stick_speed * delta
	pitch = clamp(pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))

	rotation.y = lerp_angle(rotation.y, yaw, clamp(delta * rotate_ease, 0.0, 1.0))
	spring.rotation.x = lerp_angle(spring.rotation.x, pitch, clamp(delta * rotate_ease, 0.0, 1.0))
	global_position = global_position.lerp(_pivot_point(), clamp(delta * follow_speed, 0.0, 1.0))


func _pivot_point() -> Vector3:
	return player.global_position + Vector3.UP * height


## `input` (from the move stick/keys) turned so up means away from the camera.
func camera_relative(input: Vector2) -> Vector3:
	return Basis(Vector3.UP, rotation.y) * Vector3(input.x, 0, input.y)


## Flat direction from `from` to the locked target; zero when not locked on.
func lock_direction(from: Vector3) -> Vector3:
	if not lock_target:
		return Vector3.ZERO
	var dir: Vector3 = lock_target.global_position - from
	dir.y = 0
	return dir.normalized() if dir.length() > 0.1 else Vector3.ZERO


## Paused, or a menu/perk pick wants the mouse.
func _menu_open() -> bool:
	if get_tree().paused:
		return true
	var game: Game3D_Class = Global.Game3D
	return game and (game.pause_menu.visible or game.perks.picker.is_open())


# ===== LOCK-ON =====

## Bosses still fighting and every other player.
func _lock_candidates() -> Array[Node3D]:
	var found: Array[Node3D] = []
	if not Global.Game3D:
		return found
	for boss: Boss3D in Global.Game3D.bosses:
		if is_instance_valid(boss):
			found.append(boss)
	for other: PlayerClass3D in Global.Game3D.players:
		if other != player and is_instance_valid(other) and not other.is_dead():
			found.append(other)
	return found


## Lock on to whatever in range is closest to the middle of the screen, or
## let go if already locked.
func _toggle_lock() -> void:
	if lock_target:
		_set_lock(null)
		return
	var forward: Vector3 = -camera.global_basis.z
	var best: Node3D = null
	var best_dot: float = 0.0  # Only things in front of the camera
	for candidate: Node3D in _lock_candidates():
		var offset: Vector3 = candidate.global_position - camera.global_position
		if player.global_position.distance_to(candidate.global_position) > lock_range:
			continue
		var dot: float = forward.dot(offset.normalized())
		if dot > best_dot:
			best_dot = dot
			best = candidate
	_set_lock(best)


## Let go of a target that's been defeated, left, or got too far away.
func _check_lock() -> void:
	if lock_target and (not is_instance_valid(lock_target) or not _lock_candidates().has(lock_target) \
			or player.global_position.distance_to(lock_target.global_position) > lock_range * lock_break_ratio):
		_set_lock(null)


func _set_lock(target: Node3D) -> void:
	lock_target = target
	# Weapon swings and throws aim at the Entity's target (PlayerClass3D._get_aim_direction)
	if player.Entity:
		player.Entity.target = target
	if not target:
		# Free-look picks up from wherever the lock left the camera
		yaw = rotation.y
		pitch = spring.rotation.x
