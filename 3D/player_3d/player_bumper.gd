class_name PlayerBumper extends RigidBody3D

@onready var Master: Node3D = get_parent()

@export var spring_strength: float = 50.0
@export var damping_factor: float = 8.0
@export var max_distance: float = 0.1


func _ready() -> void:
	# Ensure the bumper can move (unlock axes if needed)
	axis_lock_linear_x = false
	axis_lock_linear_y = false
	axis_lock_linear_z = false
	
	# Set collision mask to detect other rigid bodies (layer 1 is default for RigidBody3D)
	# This allows the bumper to collide with the ball and other objects
	set_collision_mask_value(1, true)
	
	# Increase mass so the bumper can push objects effectively
	# Higher mass = more momentum when colliding
	mass = 10.0
	
	# Add linear damping to reduce bouncing and overshooting
	linear_damp = 5.0
	
	# Enable continuous collision detection to prevent tunneling through fast-moving objects
	# 1 = CAST_SHAPE mode (recommended for fast-moving objects)
	continuous_cd = 1


# Called every physics frame to move toward parent position using physics
func _physics_process(_delta: float) -> void:
	if not Master:
		return
	
	var target_position: Vector3 = Master.global_position
	var current_position: Vector3 = global_position
	var offset: Vector3 = target_position - current_position
	var distance: float = offset.length()
	
	# If we're close enough, apply damping to stop
	if distance < max_distance:
		linear_velocity *= 0.9  # Strong damping when close
		return
	
	# Spring-damper system: applies spring force toward target with damping
	# This creates smooth, stable following without overshooting
	var spring_force: Vector3 = offset * spring_strength
	var damping_force: Vector3 = -linear_velocity * damping_factor
	var total_force: Vector3 = spring_force + damping_force
	
	apply_central_force(total_force)
