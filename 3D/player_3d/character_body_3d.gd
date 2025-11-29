extends CharacterBody3D
@onready var hold_anchor: Node3D = $Hold
@onready var Entity: EntityBehavior3D = $Entity
@onready var mesh_instance_3d: Array[MeshInstance3D] = [$Body/MeshInstance3D, $Appendages/Hand_Left/CollisionShape3D/MeshInstance3D, $Appendages/Hand_Right/CollisionShape3D/MeshInstance3D]

@export var Properties: PlayerResource
@export var Input_Handler: PlayerInputHandler3D

var held_ball: RigidBody3D = null
var original_ball_parent: Node = null
var original_collision_layer: int = 0
var original_collision_mask: int = 0
var was_mouse_pressed: bool = false

const THROW_FORCE = 10.0
const UPWARD_FORCE = 3.0

const JUMP_VELOCITY = 4.5
const ROTATION_SPEED = 10.0


func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# Use Input_Handler if available, otherwise fall back to direct input
	var direction: Vector3
	if Input_Handler:
		direction = Input_Handler.move_dir
	else:
		# Fallback to direct input
		var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		direction = Vector3(input_dir.x, 0, input_dir.y).normalized()
	
	if direction:
		var speed: float = Entity.SPEED if Entity else 5.0
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		
		# Rotate player to face movement direction (or look direction if available)
		if Input_Handler and Input_Handler.look_dir.length() > 0.1:
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

	move_and_slide()
	
	# Update held ball position to follow the hold anchor
	if held_ball:
		held_ball.global_position = hold_anchor.global_position
		held_ball.linear_velocity = Vector3.ZERO
		held_ball.angular_velocity = Vector3.ZERO
	
	# Check for collisions with objects in the "Ball" group
	if held_ball: return

	for i in range(get_slide_collision_count()):
		var collision: KinematicCollision3D = get_slide_collision(i)
		var collider: Node3D = collision.get_collider()
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
	# Handle throwing the ball on mouse click
	var mouse_pressed: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if held_ball and mouse_pressed and not was_mouse_pressed:
		throw_ball()
	was_mouse_pressed = mouse_pressed
	
	# Handle targeting
	if Input_Handler:
		_handle_target()
		_handle_rotation(delta)

func throw_ball() -> void:
	if not held_ball: return
	
	var ball: RigidBody3D = held_ball
	
	# Reparent back to original parent (or scene root)
	ball.reparent(get_parent())
	
	# Restore original collision properties
	ball.collision_layer = original_collision_layer
	ball.collision_mask = original_collision_mask
	
	# Unfreeze the ball
	ball.freeze = false
	
	# Calculate forward direction based on player's rotation
	# In 3D, forward is typically -Z when rotation.y is 0
	var forward_direction: Vector3 = Vector3(
		sin(rotation.y),
		0,
		cos(rotation.y)
	).normalized()
	
	# Add upward component
	var throw_direction: Vector3 = (forward_direction + Vector3.UP * (UPWARD_FORCE / THROW_FORCE)).normalized()
	
	# Apply impulse
	ball.apply_impulse(throw_direction * THROW_FORCE)
	
	# Clear held ball reference
	held_ball = null
	original_ball_parent = null

func _ready() -> void:
	# Initialize spawn position
	if Entity:
		Entity.spawn_pos = global_position
		# Initialize Entity with Properties if available
		if Properties:
			Entity.reset(true)

func _handle_target() -> void:
	if not Input_Handler or not Entity:
		return
	
	# Handle target scrolling (cycle through targets)
	if Entity.target and Input_Handler.target_scroll:
		Input_Handler.target_scroll = false
		# Get nearest entity, excluding the current target if it's still valid
		var exclude_target: Node3D = Entity.target if is_instance_valid(Entity.target) else null
		var nearest := Global.get_nearest_3d(global_position, "Entity", INF, exclude_target)
		if nearest.get("found", false):
			Entity.target = nearest["inst"]
	
	# Handle target toggle (target nearest or clear current)
	if Input_Handler.target_toggle:
		Input_Handler.target_toggle = false
		if Entity.target and is_instance_valid(Entity.target):
			# Clear current target
			Entity.target = null
		else:
			# Find nearest entity
			var nearest := Global.get_nearest_3d(global_position, "Entity", INF)
			if nearest.get("found", false):
				Entity.target = nearest["inst"]

func _handle_rotation(delta: float) -> void:
	if not Entity:
		return
	
	# Rotate to face target if locked
	if Entity.target and is_instance_valid(Entity.target):
		var direction: Vector3 = (Entity.target.global_position - global_position)
		var horizontal_dir: Vector3 = Vector3(direction.x, 0, direction.z).normalized()
		if horizontal_dir.length() > 0.1:
			var target_angle: float = atan2(horizontal_dir.x, horizontal_dir.z)
			rotation.y = lerp_angle(rotation.y, target_angle, ROTATION_SPEED * delta)
	elif Input_Handler and Input_Handler.look_dir.length() > 0.1:
		# Face look direction
		var look_dir: Vector3 = Input_Handler.look_dir
		var target_angle: float = atan2(look_dir.x, look_dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, ROTATION_SPEED * delta)
