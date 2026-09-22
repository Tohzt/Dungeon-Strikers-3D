class_name PlayerClass3D extends CharacterBody3D
@onready var hold_anchor: Node3D = $Hold
@onready var Entity: EntityBehavior3D = $Entity
@onready var mesh_instance_3d: Array[MeshInstance3D] = [$Body/MeshInstance3D, $Appendages/Shoulder_Left/Hand_Left/CollisionShape3D/MeshInstance3D, $Appendages/Shoulder_Right/Hand_Right/CollisionShape3D/MeshInstance3D]
@onready var hand_right: Area3D = $Appendages/Shoulder_Right/Hand_Right
@onready var hand_left: Area3D = $Appendages/Shoulder_Left/Hand_Left
@onready var shoulder_left: Node3D = hand_left.get_parent() if hand_left else null
@onready var shoulder_right: Node3D = hand_right.get_parent() if hand_right else null
@onready var hand_left_mesh: MeshInstance3D = hand_left.get_node_or_null("CollisionShape3D/MeshInstance3D") if hand_left else null
@onready var hand_right_mesh: MeshInstance3D = hand_right.get_node_or_null("CollisionShape3D/MeshInstance3D") if hand_right else null

@export var Properties: PlayerResource
@export var Input_Handler: PlayerInputHandler3D

var held_weapon_left: Weapon3D = null
var held_weapon_right: Weapon3D = null
var held_ball: RigidBody3D = null
var original_ball_parent: Node = null
var original_collision_layer: int = 0
var original_collision_mask: int = 0
var was_attack_left: bool = false
var was_attack_right: bool = false
var was_action_left_ball: bool = false  # Track action_left state for ball throwing

# Tap-to-swing, hold-to-throw: track when each attack button was pressed so
# we can measure hold duration on release.
const HOLD_THRESHOLD := 0.2
var attack_left_press_time: float = 0.0
var attack_right_press_time: float = 0.0

# How long past HOLD_THRESHOLD you can charge a throw for max power, and the
# force multiplier range that charge maps to (0.0 charge = just past the
# threshold, 1.0 charge = held for THROW_CHARGE_MAX_DURATION or longer).
const THROW_CHARGE_MAX_DURATION := 1.0
const THROW_FORCE_MIN_RATIO := 0.5
const THROW_FORCE_MAX_RATIO := 1.5

# Simple swipe parameters for whichever hand holds a weapon
var swipe_timer_left: float = 0.0
var swipe_timer_right: float = 0.0
const SWIPE_DURATION := 0.25
var original_shoulder_rotation_left: Vector3
var original_shoulder_rotation_right: Vector3

const THROW_FORCE = 10.0
const UPWARD_FORCE = 3.0

const JUMP_VELOCITY = 4.5
const ROTATION_SPEED = 10.0


func _ready() -> void:
	# Initialize spawn position
	if Entity:
		Entity.spawn_pos = global_position
		# Initialize Entity with Properties if available
		if Properties:
			Entity.reset(true)

	# Cache original rotation of both shoulders (used to reset after swipes)
	if shoulder_left:
		original_shoulder_rotation_left = shoulder_left.rotation
	if shoulder_right:
		original_shoulder_rotation_right = shoulder_right.rotation


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Apply jump velocity multiplier only when jump is initiated, not every frame
	if Input_Handler.move_jump and is_on_floor():
		var jump_multiplier: float = 1.0
		if Input_Handler.move_dodge:
			jump_multiplier = 1.5  # Sprint jump multiplier
		velocity.y = JUMP_VELOCITY * jump_multiplier

	if Input_Handler.move_dodge:
		Properties.speed_mod.x = 2.0
		Properties.speed_mod.z = 2.0
	else:
		Properties.speed_mod = Vector3.ONE

	var direction: Vector3 = Vector3.ZERO
	if Input_Handler:
		direction = Input_Handler.move_dir

	if !direction.is_zero_approx():
		var speed: float = Entity.SPEED if Entity else 5.0
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed

		# Rotate player to face movement direction (or look direction if available)
		if Input_Handler and !Input_Handler.look_dir.is_zero_approx():
			# Face look direction
			var look_dir: Vector3 = Input_Handler.look_dir
			var target_angle: float = atan2(look_dir.x, look_dir.z)
			rotation.y = lerp_angle(rotation.y, target_angle, ROTATION_SPEED * delta)
		else:
			# Face movement direction
			var horizontal_velocity: Vector3 = Vector3(velocity.x, 0, velocity.z)
			if horizontal_velocity.length() > 0.1:
				var target_angle: float = atan2(horizontal_velocity.x, horizontal_velocity.z)
				rotation.y = lerp_angle(rotation.y, target_angle, ROTATION_SPEED * delta)
	else:
		var speed: float = Entity.SPEED if Entity else 5.0
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	# Apply speed_mod only to horizontal velocity, not vertical
	if Properties:
		velocity.x *= Properties.speed_mod.x
		velocity.z *= Properties.speed_mod.z
	move_and_slide()

	_update_weapon_swipes(delta)
	_update_hand_mesh_position()

	if held_ball:
		held_ball.global_position = hold_anchor.global_position
		held_ball.linear_velocity = Vector3.ZERO
		held_ball.angular_velocity = Vector3.ZERO
		return

	for i in range(get_slide_collision_count()):
		var collision: KinematicCollision3D = get_slide_collision(i)
		var collider: Node3D = collision.get_collider()
		if not collider:
			continue

		if collider.is_in_group("Weapon") and collider is Weapon3D and collider.can_pickup:
			_pickup_weapon(collider)
		elif collider.is_in_group("Ball") and collider is RigidBody3D and not held_weapon_left and not held_weapon_right:
			_pickup_ball(collider)


func _pickup_weapon(weapon: Weapon3D) -> void:
	if not held_weapon_left:
		held_weapon_left = weapon
		weapon.equip(self, hand_left)
	elif not held_weapon_right:
		held_weapon_right = weapon
		weapon.equip(self, hand_right)
	# else both hands are full - leave it on the ground


func _pickup_ball(ball: RigidBody3D) -> void:
	held_ball = ball
	# Store original properties
	original_ball_parent = ball.get_parent()
	original_collision_layer = ball.collision_layer
	original_collision_mask = ball.collision_mask
	# Freeze the ball's physics and disable collision
	ball.freeze = true
	ball.collision_layer = 0
	ball.collision_mask = 0
	ball.global_position = hold_anchor.global_position
	ball.reparent(hold_anchor)


func _process(delta: float) -> void:
	# Handle throwing the ball on action_left press
	if held_ball and Input_Handler:
		var action_left_now: bool = Input_Handler.action_left
		if action_left_now and not was_action_left_ball:
			throw_ball()
		was_action_left_ball = action_left_now

	# Handle each hand's weapon independently: a quick tap swings the weapon,
	# holding the button past HOLD_THRESHOLD and releasing throws it.
	_handle_hand_attack(held_weapon_left, Input_Handler.action_left, was_attack_left, true)
	was_attack_left = Input_Handler.action_left

	_handle_hand_attack(held_weapon_right, Input_Handler.action_right, was_attack_right, false)
	was_attack_right = Input_Handler.action_right

	# Handle targeting
	if Input_Handler:
		_handle_target()
		_handle_rotation(delta)


func _handle_hand_attack(weapon: Weapon3D, is_pressed: bool, was_pressed: bool, is_left: bool) -> void:
	if not weapon: return
	var now: float = Time.get_ticks_msec() / 1000.0

	if is_pressed and not was_pressed:
		# Press started - just record when; swing-vs-throw is decided on release
		if is_left:
			attack_left_press_time = now
		else:
			attack_right_press_time = now
		return

	if not is_pressed and was_pressed:
		# Released - a quick tap swings, a hold past the threshold throws.
		# The longer it's held past the threshold (up to THROW_CHARGE_MAX_DURATION),
		# the harder the throw.
		var press_time: float = attack_left_press_time if is_left else attack_right_press_time
		var hold_duration: float = now - press_time
		if hold_duration >= HOLD_THRESHOLD:
			var charge_ratio: float = clamp((hold_duration - HOLD_THRESHOLD) / THROW_CHARGE_MAX_DURATION, 0.0, 1.0)
			_throw_weapon(weapon, is_left, charge_ratio)
		elif is_left and swipe_timer_left <= 0.0:
			swipe_timer_left = SWIPE_DURATION
		elif not is_left and swipe_timer_right <= 0.0:
			swipe_timer_right = SWIPE_DURATION


func _throw_weapon(weapon: Weapon3D, is_left: bool, charge_ratio: float = 1.0) -> void:
	var spin_direction: float = -1.0 if is_left else 1.0
	var force_multiplier: float = lerp(THROW_FORCE_MIN_RATIO, THROW_FORCE_MAX_RATIO, charge_ratio)
	weapon.throw(_get_aim_direction(), -1.0, spin_direction, force_multiplier)
	if is_left:
		held_weapon_left = null
	else:
		held_weapon_right = null


func _get_aim_direction() -> Vector3:
	if Entity and Entity.target and is_instance_valid(Entity.target):
		return (Entity.target.global_position - global_position).normalized()
	if Input_Handler and not Input_Handler.look_dir.is_zero_approx():
		return Input_Handler.look_dir
	return Vector3(sin(rotation.y), 0, cos(rotation.y))


func throw_ball() -> void:
	if not held_ball: return

	var ball: RigidBody3D = held_ball
	ball.reparent(get_parent())
	ball.collision_layer = original_collision_layer
	ball.collision_mask = original_collision_mask
	ball.freeze = false

	# Calculate forward direction based on player's rotation
	var forward_direction: Vector3 = Vector3(
		sin(rotation.y),
		0,
		cos(rotation.y)
	).normalized()

	var throw_direction: Vector3 = (forward_direction + Vector3.UP * (UPWARD_FORCE / THROW_FORCE)).normalized()
	ball.apply_impulse(throw_direction * THROW_FORCE)

	# Clear held ball reference
	held_ball = null
	original_ball_parent = null

func _handle_target() -> void:
	if not Input_Handler or not Entity: return
	## Handle target scrolling (cycle through targets)
	#if Entity.target and Input_Handler.target_scroll:
		#Input_Handler.target_scroll = false
		## Get nearest entity, excluding the current target if it's still valid
		#var exclude_target: Node3D = Entity.target if is_instance_valid(Entity.target) else null
		#var nearest := Global.get_nearest_3d(global_position, "Entity", INF, exclude_target)
		#if nearest.get("found", false):
			#Entity.target = nearest["inst"]
	#
	## Handle target toggle (target nearest or clear current)
	#if Input_Handler.target_toggle:
		#Input_Handler.target_toggle = false
		#if Entity.target and is_instance_valid(Entity.target):
			## Clear current target
			#Entity.target = null
		#else:
			## Find nearest entity
			#var nearest := Global.get_nearest_3d(global_position, "Entity", INF)
			#if nearest.get("found", false):
				#Entity.target = nearest["inst"]


func _handle_rotation(_delta: float) -> void:
	if not Entity: return
	## Rotate to face target if locked
	#if Entity.target and is_instance_valid(Entity.target):
		#var direction: Vector3 = (Entity.target.global_position - global_position)
		#var horizontal_dir: Vector3 = Vector3(direction.x, 0, direction.z).normalized()
		#if horizontal_dir.length() > 0.1:
			#var target_angle: float = atan2(horizontal_dir.x, horizontal_dir.z)
			#rotation.y = lerp_angle(rotation.y, target_angle, ROTATION_SPEED * delta)
	#elif Input_Handler and Input_Handler.look_dir.length() > 0.1:
		## Face look direction
		#var look_dir: Vector3 = Input_Handler.look_dir
		#var target_angle: float = atan2(look_dir.x, look_dir.z)
		#rotation.y = lerp_angle(rotation.y, target_angle, ROTATION_SPEED * delta)


func _update_hand_mesh_position() -> void:
	_sync_hand_mesh(held_weapon_left, hand_left_mesh)
	_sync_hand_mesh(held_weapon_right, hand_right_mesh)


func _sync_hand_mesh(weapon: Weapon3D, mesh: MeshInstance3D) -> void:
	if not mesh: return
	# When holding a weapon, set hand mesh to top_level and sync to weapon position
	if weapon:
		if not mesh.top_level:
			mesh.top_level = true
		mesh.global_position = weapon.global_position
	elif mesh.top_level:
		# When not holding weapon, restore normal behavior
		mesh.top_level = false


func _update_weapon_swipes(delta: float) -> void:
	swipe_timer_left = _update_shoulder_swipe(delta, shoulder_left, original_shoulder_rotation_left, swipe_timer_left, 1.0)
	swipe_timer_right = _update_shoulder_swipe(delta, shoulder_right, original_shoulder_rotation_right, swipe_timer_right, -1.0)


func _update_shoulder_swipe(delta: float, shoulder: Node3D, base_rotation: Vector3, timer: float, direction: float) -> float:
	if not shoulder: return timer

	if timer > 0.0:
		timer -= delta
		var swipe_angle := deg_to_rad(100) * direction
		var t: float = clamp(1.0 - (timer / SWIPE_DURATION), 0.0, 1.0)

		# Rotate the shoulder out during the swipe, then back to original
		var target_rotation: float
		if t < 0.5:
			# First half: rotate out
			var progress: float = t * 2.0  # 0 to 1 over first half
			target_rotation = lerp(0.0, swipe_angle, progress)
		else:
			# Second half: rotate back
			var progress: float = (t - 0.5) * 2.0  # 0 to 1 over second half
			target_rotation = lerp(swipe_angle, 0.0, progress)

		shoulder.rotation.y = base_rotation.y - target_rotation
	else:
		shoulder.rotation = base_rotation

	return timer
