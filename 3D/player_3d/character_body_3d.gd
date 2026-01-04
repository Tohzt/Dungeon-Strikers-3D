class_name PlayerClass3D extends CharacterBody3D
@onready var hold_anchor: Node3D = $Hold
@onready var Entity: EntityBehavior3D = $Entity
@onready var mesh_instance_3d: Array[MeshInstance3D] = [$Body/MeshInstance3D, $Appendages/Shoulder_Left/Hand_Left/CollisionShape3D/MeshInstance3D, $Appendages/Shoulder_Right/Hand_Right/CollisionShape3D/MeshInstance3D]
@onready var hand_right: Area3D = $Appendages/Shoulder_Right/Hand_Right
@onready var hand_left: Area3D = $Appendages/Shoulder_Left/Hand_Left
@onready var shoulder_left: Node3D = hand_left.get_parent() if hand_left else null
@onready var shoulder_right: Node3D = hand_right.get_parent() if hand_right else null
@onready var hand_left_mesh: MeshInstance3D = hand_left.get_node_or_null("CollisionShape3D/MeshInstance3D") if hand_left else null

@export var Properties: PlayerResource
@export var Input_Handler: PlayerInputHandler3D

var held_weapon: WeaponClass3D = null
var held_ball: RigidBody3D = null
var original_ball_parent: Node = null
var original_collision_layer: int = 0
var original_collision_mask: int = 0
var was_mouse_pressed: bool = false
var was_attack_left: bool = false
var was_action_left_ball: bool = false  # Track action_left state for ball throwing

# Simple swipe parameters for the hand that holds the weapon
var swipe_timer: float = 0.0
const SWIPE_DURATION := 0.25
var original_shoulder_rotation: Vector3

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
	
	# Cache original rotation of the left shoulder (weapon shoulder)
	if shoulder_left:
		original_shoulder_rotation = shoulder_left.rotation


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
	
	_update_weapon_swipe(delta)
	_update_hand_mesh_position()
	
	if held_ball:
		held_ball.global_position = hold_anchor.global_position
		held_ball.linear_velocity = Vector3.ZERO
		held_ball.angular_velocity = Vector3.ZERO
		return
	
	for i in range(get_slide_collision_count()):
		var collision: KinematicCollision3D = get_slide_collision(i)
		var collider: Node3D = collision.get_collider()
		if collider.is_in_group("Weapon") and collider is WeaponClass3D:
			collider.held_by = self
			collider.is_held = true
			held_weapon = collider
			# Call equip() to update collision layers/masks so weapon doesn't collide with player
			if collider.has_method("equip"):
				collider.equip(self)
		if !!held_weapon: return
		
		if collider.is_in_group("Ball") and collider is RigidBody3D:
			var ball: RigidBody3D = collider as RigidBody3D
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
	
	# Keep was_mouse_pressed for weapon swipe compatibility
	var mouse_pressed: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	was_mouse_pressed = mouse_pressed

	# Handle weapon swipe input while holding a weapon (independent of Input_Handler wiring)
	if held_weapon:
		var attack_input_now: bool = Input.is_action_pressed("attack_left") or mouse_pressed
		if attack_input_now and not was_attack_left and swipe_timer <= 0.0:
			swipe_timer = SWIPE_DURATION
		elif attack_input_now and not was_attack_left:
			pass
		was_attack_left = attack_input_now
	
	# Handle targeting
	if Input_Handler:
		_handle_target()
		_handle_rotation(delta)

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
	# When holding a weapon, set hand mesh to top_level and sync to weapon position
	if held_weapon and hand_left_mesh:
		if not hand_left_mesh.top_level:
			hand_left_mesh.top_level = true
		hand_left_mesh.global_position = held_weapon.global_position
	elif hand_left_mesh and hand_left_mesh.top_level:
		# When not holding weapon, restore normal behavior
		hand_left_mesh.top_level = false

func _update_weapon_swipe(delta: float) -> void:
	if not shoulder_left: return
	
	if swipe_timer > 0.0:
		swipe_timer -= delta
		var swipe_angle := deg_to_rad(100)
		var t: float = clamp(1.0 - (swipe_timer / SWIPE_DURATION), 0.0, 1.0)
		
		# Rotate the shoulder 90 degrees during the swipe, then back to original
		# Use a smooth curve: go to 90 degrees, then return
		var target_rotation: float
		if t < 0.5:
			# First half: rotate to 90 degrees
			var progress: float = t * 2.0  # 0 to 1 over first half
			target_rotation = lerp(0.0, swipe_angle, progress)
		else:
			# Second half: rotate back to 0
			var progress: float = (t - 0.5) * 2.0  # 0 to 1 over second half
			target_rotation = lerp(swipe_angle, 0.0, progress)
		
		# Apply rotation to the shoulder (assuming rotation around Y axis, adjust as needed)
		shoulder_left.rotation.y = original_shoulder_rotation.y - target_rotation
	else:
		# When not swiping, restore original shoulder rotation
		shoulder_left.rotation = original_shoulder_rotation
