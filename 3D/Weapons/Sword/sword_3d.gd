class_name WeaponClass3D extends Weapon3D

# How strongly the weapon is pulled toward the hand
@export var follow_strength: float = 300.0
# How much to damp / stabilize motion
@export var follow_damping: float = 8.0
# Distance at which we just damp and stop applying big forces
@export var follow_max_distance: float = 0.02
# Velocity prediction factor (helps anticipate hand movement)
@export var velocity_prediction: float = 0.1
# Local X rotation applied while held (not blocking/thrown). A blade needs to
# tip up to point forward from a Y-aligned mesh; a flat shield should stay
# upright facing outward instead, so subclasses override this.
@export var held_pitch: float = deg_to_rad(90)

var prev_hand_pos: Vector3


## Reset the hand-follow tracking to the real hand position the moment we're
## equipped, otherwise the first frame's velocity-prediction sees a jump from
## Vector3.ZERO to the hand and flings the weapon away before it corrects.
func equip(new_wielder: Node3D, hand: Area3D = null) -> void:
	super.equip(new_wielder, hand)
	if hand:
		prev_hand_pos = hand.global_position


#func _process(_delta: float) -> void:

func _physics_process(delta: float) -> void:
	super._physics_process(delta)

	if not is_held or is_thrown or not held_hand:
		return

	var target_pos: Vector3 = held_hand.global_position
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

	# Orient the weapon: Y rotation matches the angle from the wielder to the
	# hand it's equipped into. This makes the weapon rotate as that hand swings.
	if wielder:
		var player_pos: Vector3 = wielder.global_position
		var direction: Vector3 = (target_pos - player_pos).normalized()

		# Get the horizontal (X/Z) direction and compute yaw angle
		var horizontal_dir: Vector2 = Vector2(direction.x, direction.z)
		if horizontal_dir.length() > 0.001:
			# atan2(x, z) gives us the yaw angle in Godot's coordinate system
			var yaw: float = atan2(horizontal_dir.x, horizontal_dir.y)
			rotation.y = yaw
			rotation.x = held_pitch
