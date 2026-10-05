class_name PlayerInputHandler3D extends Node
@onready var Master: CharacterBody3D = get_parent()

## The boost button is held (see PlayerClass3D.boost).
var boost_held: bool = false
var move_dir: Vector3
var look_dir: Vector3 = Vector3.ZERO
## Each hand's presses, worked out from the Attack and Off-hand buttons (see
## _buttons_to_hands); the player acts on them per hand.
var action_left: bool = false
var action_right: bool = false
var action_heavy_left: bool = false
var action_heavy_right: bool = false
## Simple controls: hold Throw and press Attack or Off-hand to throw that
## hand's weapon; held to charge, thrown on release.
var throw_left: bool = false
var throw_right: bool = false
## Throw tapped without pressing either hand: drop the main hand's weapon
## (the off hand's if the main is empty). Stays set until the player acts on it.
var drop_weapon: bool = false
var interact: bool = false
## Swap what's in each hand (R / Select); stays set until the player acts on it.
var swap_hands: bool = false
var interact_held: bool = false
var target_toggle: bool = false
var target_scroll: bool = false
# The controller's dodge button: a quick tap rolls (on release), holding it
# sprints. Keyboard has its own roll (Ctrl) and sprint (Shift) keys.
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

## Which local player/device this handler listens to; set by the owning
## player. Null = legacy mode that reads the shared actions from any device.
var slot: PlayerSlot = null

## Simple controls: the hand buttons as of last frame.
var _left_click_was_pressed: bool = false
var _right_click_was_pressed: bool = false
## Which hand the Attack button works, settled while neither button is held
## so a hand can't change mid-press (see PlayerClass3D.main_hand_is_left).
var _main_is_left: bool = false
## A hand button was pressed while Throw was held, so letting go of Throw
## isn't a drop.
var _throw_used: bool = false

## Set while this player uses the souls-like controls: movement turns with
## this camera, and the player faces where they walk or their lock-on target.
var souls_camera: SoulsCamera3D = null


## The input action this handler should read for a project action name.
func action(base: StringName) -> StringName:
	return slot.action(base) if slot else base


## Buttons aren't tied to a hand. Attack (left click / RB) uses the main
## weapon, normally the right hand's; Off-hand (right click / LB) the other
## hand, and a shield there blocks.
## Simple controls (the default): both swing on press and a shield blocks
## while Off-hand is held; holding Throw turns them into throws instead.
## With a weapon in each hand, Off-hand does a special (see WeaponCombo3D).
## Advanced: both swing on a tap and throw on a hold, and either guard
## button raises a shield. See PlayerSlot.advanced_controls.
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
	drop_weapon = false
	_throw_used = false
	move_dodge = false
	dodge_dur = 0.0
	dodge_request_msec = -1
	look_dir = Vector3.ZERO
	aim_release_timer = 0.0
	interact = false
	swap_hands = false
	boost_held = false


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
		_handle_advanced_controls()
	boost_held = Input.is_action_pressed(action("boost"))
	# Stays set until the player acts on it
	if Input.is_action_just_pressed(action("interact")):
		interact = true
	if Input.is_action_just_pressed(action("swap_hands")):
		swap_hands = true
	_handle_input_dodge(delta)
	_handle_input_look(delta)

## Attack and Off-hand press their hands' buttons; a shield in the off hand
## rises while Off-hand is held. While Throw is held, they throw that hand's
## weapon instead.
func _handle_simple_controls() -> void:
	var throw_mode: bool = Input.is_action_pressed(action("throw"))
	# Throwing, Attack throws a lone shield too
	var hands: Array[bool] = _buttons_to_hands(throw_mode)
	if Input.is_action_just_pressed(action("throw")):
		_throw_used = false
	if throw_mode and (hands[0] or hands[1]):
		_throw_used = true
	if Input.is_action_just_released(action("throw")) and not _throw_used:
		drop_weapon = true
	_apply_simple_buttons(hands[0], hands[1], false, throw_mode)


## Advanced controls: each button swings its hand on a tap and throws on a
## hold (the player times it), and either guard button raises a shield.
func _handle_advanced_controls() -> void:
	var hands: Array[bool] = _buttons_to_hands(true)
	var guard: bool = Input.is_action_pressed(action("attack_heavy_left")) \
		or Input.is_action_pressed(action("attack_heavy_right"))
	# The mouse's guard is Alt+click: that click is the guard, not an attack
	var swallow: bool = guard and uses_mouse()
	action_left = hands[0] and not swallow
	action_right = hands[1] and not swallow
	action_heavy_left = guard
	action_heavy_right = guard


## [left hand, right hand] held, from the Attack and Off-hand buttons.
## `shield_too`: a lone shield is Attack's (see PlayerClass3D.main_hand_is_left).
func _buttons_to_hands(shield_too: bool) -> Array[bool]:
	var main: bool = Input.is_action_pressed(action("attack_main"))
	var off: bool = Input.is_action_pressed(action("attack_off"))
	if not main and not off:
		var player := Master as PlayerClass3D
		_main_is_left = player != null and player.main_hand_is_left(shield_too)
	if _main_is_left:
		return [main, off]
	return [off, main]


## Simple controls' per-hand buttons (held or not) into the presses the
## player reads. `guard` raises any shield held (bots only); `throw_mode` is
## Throw held; the hand buttons then throw that hand.
## Only presses that start in the right mode count, so letting go of Throw
## mid-click doesn't swing, and a click held from before doesn't throw.
## Bots press them through here too.
func _apply_simple_buttons(left: bool, right: bool, guard: bool, throw_mode: bool) -> void:
	var player := Master as PlayerClass3D
	var shield_left: bool = player != null and player.held_weapon_left is ShieldClass3D and not player.held_ball
	var shield_right: bool = player != null and player.held_weapon_right is ShieldClass3D and not player.held_ball
	action_left = left and not throw_mode and not shield_left and (action_left or not _left_click_was_pressed)
	action_right = right and not throw_mode and not shield_right and (action_right or not _right_click_was_pressed)
	throw_left = throw_mode and left and (throw_left or not _left_click_was_pressed)
	throw_right = throw_mode and right and (throw_right or not _right_click_was_pressed)
	_left_click_was_pressed = left
	_right_click_was_pressed = right
	action_heavy_left = shield_left and not throw_mode and (guard or left)
	action_heavy_right = shield_right and not throw_mode and (guard or right)


## Keyboard: Ctrl rolls on press, Shift sprints while held. Controller:
## dodge tap = roll, hold = sprint; that roll goes off on release (like the
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
## direction". Mouse players always aim at the cursor, except while holding
## face_movement (Alt); controller players aim with the right stick.
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
	if event.is_action(action("target")):
		target_toggle = event.is_action_pressed(action("target"))
	
	if event.is_action(action("target_scroll")):
		if event.is_action_pressed(action("target_scroll")):
			target_scroll = true
