##TODO: Add/Get swing props from properties
class_name SwordController extends WeaponControllerBase

@onready var sword := weapon

var is_charging: bool = false
var charge_complete: bool = false
var charge_duration: float = 0.0
var charge_limit_in_sec: float = 1.00

var is_slashing: bool = false
var slash_duration: float = 0.0
var slash_limit_in_sec: float = 0.05

func on_equip() -> void:
	super.on_equip()

func handle_click() -> void:
	super.handle_click()
	if is_slashing or slash_duration > 0.0: return
	_slash_start()

func handle_hold(_duration: float = 0.0) -> void:
	hold_position = true
	if is_slashing or slash_duration > 0.0: return
	if !is_charging:
		_charge_start()
	super.handle_hold()

func handle_release(_duration: float = 0.0) -> void:
	super.handle_release()
	sword.mod_angle = 0.0
	hold_position = false
	if is_charging and !is_slashing:
		_charge_end()

func update(delta: float) -> void:
	super.update(delta)
	cooldown_duration = max(0, cooldown_duration - delta)
	if is_slashing: _slashing(delta)
	elif is_charging: _charging(delta)
	else:
		reset_arm_rotation(delta, 8.0)
		reset_arm_position(delta, 8.0) 


func _move_to_ready_position() -> void:
	var forward_rotation := deg_to_rad(180)
	var sword_distance := 50.0
	sword.mod_angle = 90-sword.Properties.weapon_angle
	set_arm_rotation(forward_rotation, 0.016, 15.0)
	set_arm_position(sword_distance, 0.016, 15.0)


func _slash_start(mod_dur: float = 0.0) -> void:
	if cooldown_duration > 0.0: return
	is_slashing = true
	slash_duration = slash_limit_in_sec + mod_dur
	sword._update_collisions("projectile")

func _slash_end(delta: float) -> void:
	cooldown_duration = cooldown_limit_in_sec
	is_slashing = false
	slash_duration = 0.0
	reset_arm_rotation(delta, 10.0)
	reset_arm_position(delta, 10.0)
	sword._update_collisions("in-hand")

func _slashing(delta: float) -> void:
		slash_duration -= delta
		var swing_direction := 1.0 if !in_offhand else -1.0
		var slash_position := get_default_arm_length() * 1.6
		swing_arm(swing_direction, delta, 50.0)
		set_arm_position(slash_position, delta, 6.0)
		
		if slash_duration <= 0:
			_slash_end(delta)


func _charge_start() -> void:
	is_charging = true

func _charging(delta: float) -> void:
	if in_offhand:
		var other_hand_weapon: WeaponClass = get_offhand_weapon()
		if other_hand_weapon: 
			if sword.Properties.weapon_synergies.has(get_offhand_weapon().Properties.weapon_type):
				_move_to_ready_position()
				return
	
	charge_duration += delta
	if charge_duration >= charge_limit_in_sec:
		charge_duration = charge_limit_in_sec
		charge_complete = true
	else:
		var charge_rotation := deg_to_rad(45)
		var charge_position := get_default_arm_length() * 0.6
		set_arm_rotation(charge_rotation, delta, charge_duration)
		set_arm_position(charge_position, delta, charge_duration)

func _charge_end() -> void:
	if charge_complete:
		_slash_start(charge_duration)
	is_charging = false
	charge_duration = 0.0
