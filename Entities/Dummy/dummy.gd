extends RigidBody2D

var invincible: bool = false
var i_frame_duration: float = 0.1

func _ready() -> void:
	body_entered.connect(_on_weapon_hit)

func _process(_delta: float) -> void:
	z_index = Global.Layers.ENEMIES

func _on_weapon_hit(body: Node2D) -> void:
	if body and body.is_in_group("Weapon") and !invincible:
		var weapon_damage: float = body.Properties.weapon_damage
		var weapon_mod_damage: float = body.Properties.weapon_mod_damage
		var weapon_total_damage: float = weapon_damage + weapon_mod_damage
		var weapon_velocity: Vector2 = body.linear_velocity
		
		# For melee attacks (held weapons with no velocity), calculate knockback differently
		var impact_force: Vector2
		if weapon_velocity.length() < 10.0:  # Very low velocity = held weapon
			# Calculate direction from weapon to dummy
			var knockback_direction: Vector2 = (global_position - body.global_position).normalized()
			# Use damage-based knockback force for melee
			impact_force = knockback_direction * weapon_total_damage * 50.0
		else:
			# For projectiles, use velocity-based knockback (existing behavior)
			impact_force = weapon_velocity * weapon_total_damage
		
		apply_central_impulse(impact_force)
		
		Global.display_damage(weapon_total_damage, global_position)
		
		_start_i_frames()

func _start_i_frames() -> void:
	modulate = Color.RED
	invincible = true
	
	var timer := Timer.new()
	add_child(timer)
	timer.timeout.connect(_end_i_frames)
	timer.start(i_frame_duration)
	timer.one_shot = true

func _end_i_frames() -> void:
	modulate = Color.WHITE
	invincible = false
