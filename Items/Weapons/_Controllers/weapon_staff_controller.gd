class_name StaffController extends WeaponControllerBase
@onready var SPELL: Resource = preload("res://Items/Weapons/Staff/Spell.tres")
@onready var staff := weapon

var is_casting: bool = false
var is_charging: bool = false
var charge_complete: bool = false
var charge_duration: float = 0.0
var charge_limit_in_sec: float = 0.5

func handle_click() -> void:
	super.handle_click()
	if cooldown_duration <= 0.0:
		is_casting = true
		
func handle_hold() -> void:
	super.handle_hold()
	is_charging = true
	
func handle_release() -> void:
	super.handle_release()
	is_charging = false
	charge_duration = 0.0
	if charge_complete:
		charge_complete = false
		is_casting = true


func update(delta: float) -> void:
	super.update(delta)
	
	if is_casting:
		var block_rotation := deg_to_rad(180)
		var block_position := get_default_arm_length() * 0.6
		set_arm_rotation(block_rotation, delta, 8.0)
		set_arm_position(block_position, delta, 8.0)
		_cast_spell()
	elif is_charging:
		charge_duration = min(charge_limit_in_sec, charge_duration + delta)
		if charge_duration >= charge_limit_in_sec:
			charge_complete = true
	else:
		reset_arm_rotation(delta, 8.0)
		reset_arm_position(delta, 8.0) 

func _cast_spell() -> void:
	is_casting = false
	is_charging = false
	charge_duration = 0.0
	cooldown_duration = cooldown_limit_in_sec
	var spell: WeaponClass = Global.WEAPON.instantiate()
	spell.Properties = SPELL
	spell.Properties.weapon_mod_damage = staff.Properties.weapon_damage
	spell.wielder = staff.wielder
	spell.destroy_on_impact = true
	spell.global_position = staff.global_position
	var Entities: Node2D = get_tree().get_first_node_in_group("Entities")
	Entities.add_child(spell)
