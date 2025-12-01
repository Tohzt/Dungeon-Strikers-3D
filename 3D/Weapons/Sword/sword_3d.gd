class_name WeaponClass3D extends Weapon3D
@onready var mesh_instance_3d := $CollisionShape3D/MeshInstance3D

# How strongly the weapon is pulled toward the hand
@export var follow_strength: float = 300.0
# How much to damp / stabilize motion
@export var follow_damping: float = 8.0
# Distance at which we just damp and stop applying big forces
@export var follow_max_distance: float = 0.02
# Velocity prediction factor (helps anticipate hand movement)
@export var velocity_prediction: float = 0.1

var is_held: bool = false
var held_by: PlayerClass3D
var prev_hand_pos: Vector3

#func _process(_delta: float) -> void:

func _physics_process(_delta: float) -> void:
	if not is_held or not held_by:
		return
	
	var target_pos: Vector3 = held_by.hand_left.global_position
	var current_pos: Vector3 = global_position
	
	# Calculate hand velocity (estimate from previous frame)
	var hand_velocity: Vector3 = Vector3.ZERO
	var delta_time: float = get_physics_process_delta_time()
	if delta_time > 0.0 and prev_hand_pos.distance_to(target_pos) > 0.001:
		hand_velocity = (target_pos - prev_hand_pos) / delta_time
	
	# Predict where hand will be (velocity prediction)
	var predicted_target: Vector3 = target_pos + hand_velocity * velocity_prediction
	
	# Store current hand position for next frame
	prev_hand_pos = target_pos
	
	var offset: Vector3 = predicted_target - current_pos
	var distance: float = offset.length()
	
	# If we're close enough, just damp velocity so it settles nicely
	if distance < follow_max_distance:
		linear_velocity *= 0.8
		angular_velocity *= 0.8
		return
	
	# Spring + damping forces with higher strength for faster response
	var spring_force: Vector3 = offset * follow_strength
	var damping_force: Vector3 = -linear_velocity * follow_damping
	var total_force: Vector3 = spring_force + damping_force
	
	apply_central_force(total_force)
	
	# Orient the weapon: Y rotation matches the angle from player to the swiping hand (left hand)
	# This makes the weapon rotate as the hand swings around the player
	if is_held and held_by and held_by.hand_left:
		var player_pos: Vector3 = held_by.global_position
		var hand_pos: Vector3 = held_by.hand_left.global_position
		var direction: Vector3 = (hand_pos - player_pos).normalized()
		
		# Get the horizontal (X/Z) direction and compute yaw angle
		var horizontal_dir: Vector2 = Vector2(direction.x, direction.z)
		if horizontal_dir.length() > 0.001:
			# atan2(x, z) gives us the yaw angle in Godot's coordinate system
			var yaw: float = atan2(horizontal_dir.x, horizontal_dir.y)
			rotation.y = yaw
			rotation.x = deg_to_rad(90)
