class_name ShieldController extends WeaponControllerBase

var is_blocking: bool = false


func handle_click() -> void:
	super.handle_click()
func handle_hold() -> void:
	super.handle_hold()
	is_blocking = true
func handle_release() -> void:
	super.handle_release()
	is_blocking = false


func update(delta: float) -> void:
	super.update(delta)
	
	if is_blocking:
		var block_rotation := deg_to_rad(180)
		var block_position := get_default_arm_length() * 0.6
		set_arm_rotation(block_rotation, delta, 8.0)
		set_arm_position(block_position, delta, 8.0)
	else:
		reset_arm_rotation(delta, 8.0)
		reset_arm_position(delta, 8.0) 
