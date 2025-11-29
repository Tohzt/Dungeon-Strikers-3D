class_name BowController extends WeaponControllerBase

@onready var bow := weapon
# Remove the problematic is_drawn reference - use hold_position directly

var ammo: WeaponClass
var is_attacking: bool = false
var attack_duration: float = 0.0
var attack_limit_in_sec: float = 0.15
var is_charging: bool = false
var charge_duration: float = 0.0
var charge_limit_in_sec: float = 1.0




func handle_click() -> void:
	super.handle_click()
	# Attack on click - this is needed for shooting arrows
	_attack()

func handle_hold() -> void:
	super.handle_hold()
	is_charging = true

func handle_release() -> void:
	super.handle_release()
	print("Bow handle_release() called - is_charging: ", is_charging, ", charge_duration: ", charge_duration)
	if charge_duration == charge_limit_in_sec: _attack()
	is_charging = false
	charge_duration = 0.0
	is_attacking = false
	attack_duration = 0.0
	bow._update_collisions("in-hand")


func update(delta: float) -> void:
	super.update(delta)
	
	# Get the offhand weapon (arrow)
	ammo = get_offhand_weapon()
	
	# Check if we have ammo and if it's a synergy weapon
	if ammo and bow.Properties.weapon_synergies.has(ammo.Properties.weapon_type):
		# If the arrow is in hold position, the bow should also be in hold position
		if ammo.Controller.hold_position:
			if not hold_position:
				print("Bow: Arrow is in hold position, setting bow hold_position to true")
			hold_position = true
		else:
			if hold_position:
				print("Bow: Arrow released hold position, setting bow hold_position to false")
			hold_position = false
			# Reset charging state when arrow is released
			if is_charging:
				print("Bow: Resetting charging state due to arrow release")
				is_charging = false
				charge_duration = 0.0
	else:
		ammo = null
		if hold_position:
			print("Bow: No ammo, setting hold_position to false")
		hold_position = false
		# Reset charging state when no arrow
		if is_charging:
			print("Bow: No ammo, resetting charging state")
			is_charging = false
			charge_duration = 0.0
	
	# Handle bow positioning based on hold_position
	if hold_position:
		_move_to_ready_position(delta)
	elif is_attacking:
		attack_duration = min(attack_limit_in_sec, attack_duration+delta)
		_move_to_ready_position(delta*7)
	elif is_charging:
		charge_duration = min(charge_limit_in_sec, charge_duration+delta)
	else:
		reset_arm_rotation(delta, 8.0)
		reset_arm_position(delta, 8.0)
	
	if attack_duration >= attack_limit_in_sec:
		is_attacking = false
		attack_duration = 0.0
		# Reset hand attacking state so arm can move naturally
		if hand:
			hand.is_attacking = false
		# Ensure bow is back in normal collision mode after attack
		bow._update_collisions("in-hand")


func _move_to_ready_position(delta: float) -> void:
	var forward_rotation := deg_to_rad(180)
	var bow_distance := 100.0
	set_arm_rotation(forward_rotation, delta)
	set_arm_position(bow_distance, delta)


func _attack() -> void:
	if !bow.wielder or !ammo: return
	
	# Check if the arrow is in hold position (right hand)
	if ammo.Controller.hold_position:
		# Arrow is held, so fire it
		ammo.throw_weapon(bow.Properties.weapon_damage)
		# After firing, ensure we're not stuck in any special state
		is_attacking = false
		attack_duration = 0.0
		is_charging = false
		charge_duration = 0.0
		# Reset hand attacking state so arm can move naturally
		if hand:
			hand.is_attacking = false
		# Force bow out of hold position after shooting
		hold_position = false
	else:
		# No arrow in hold position - do basic bow attack
		# But only if we're not just doing a regular click
		if is_charging:
			# We were charging, so this is a click to shoot
			# Try to fire the arrow even if not in perfect hold position
			if ammo:
				ammo.throw_weapon(bow.Properties.weapon_damage)
				# Reset states
				is_attacking = false
				attack_duration = 0.0
				is_charging = false
				charge_duration = 0.0
				if hand:
					hand.is_attacking = false
				hold_position = false
		else:
			# Regular click without charging - basic attack
			is_attacking = true
			bow._update_collisions("projectile")
