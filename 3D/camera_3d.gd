extends Camera3D
@export var target: Node3D

@export var fov_sensitivity: float = 5.0
@export var min_fov: float = 10.0
@export var max_fov: float = 120.0

var initial_transform: Transform3D
var initial_offset: Vector3
var initial_fov: float = 0.0


func _ready() -> void:
	# Store the initial transform and calculate offset from target
	initial_transform = global_transform
	initial_fov = fov
	
	if not target:
		# Try to find the player if target is not set
		var player: Node = get_tree().get_first_node_in_group("player")
		if player:
			target = player as Node3D
	
	# Calculate initial offset from target (in world space)
	if target:
		initial_offset = global_position - target.global_position


func _input(event: InputEvent) -> void:
	# Handle mouse wheel scroll to adjust FOV
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			fov = clamp(fov - fov_sensitivity, min_fov, max_fov)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			fov = clamp(fov + fov_sensitivity, min_fov, max_fov)


func _process(_delta: float) -> void:
	if not target:
		return
	
	# Calculate where camera should be to maintain the same relative position
	# This keeps the target centered in the view
	var target_pos: Vector3 = target.global_position
	
	# Maintain the full offset, updating X and Z based on target movement
	# This ensures the target stays centered in the camera's view
	global_position = target_pos + initial_offset
	
	# Keep the rotation fixed
	global_rotation = initial_transform.basis.get_euler()
