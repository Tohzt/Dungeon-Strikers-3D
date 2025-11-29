class_name ArrowController extends WeaponControllerBase

@onready var arrow := weapon


func handle_click() -> void:
	super.handle_click()
	#var stab_length := get_default_arm_length(arrow) * 1.4  # 140% of adjusted default length
	#set_arm_length(arrow, stab_length, 0.016, 20.0)

func handle_hold() -> void:
	super.handle_hold()
	hold_position = true

func handle_release() -> void:
	super.handle_release()
	print("Arrow handle_release() called - setting hold_position to false")
	hold_position = false
	#if is_in_ready_position:
		#is_in_ready_position = false
		
		# Reset only the arrow
		#reset_arm_rotation(arrow, 0.016, 10.0)
		#reset_arm_length(arrow, 0.016, 10.0)


func update(delta: float) -> void:
	super.update(delta)
	if hold_position:
		arrow.throw_clone = true
		_move_to_ready_position()
	
	else:
		arrow.throw_clone = false
		arrow.mod_angle = 0
		reset_arm_rotation(delta, 8.0)
		reset_arm_position(delta, 8.0)


func _move_to_ready_position() -> void:
	var forward_rotation := deg_to_rad(180)
	var arrow_distance := 50.0
	arrow.mod_angle = 90 - arrow.Properties.weapon_angle
	set_arm_rotation(forward_rotation, 0.016, 15.0)
	set_arm_position(arrow_distance, 0.016, 15.0)
