class_name BallClass extends RigidBody2D

var max_ball_speed: float = 600.0 
var knockback_strength: float = 5.5
var min_velocity_for_knockback: float = 150.0

# Color settings
var color_slow: Color = Color.GREEN
var color_medium: Color = Color.YELLOW
var color_fast: Color = Color.ORANGE
var color_max: Color = Color.RED
var color_cur: Color = Color.RED
var speed_medium_threshold: float = max_ball_speed * 0.3
var speed_fast_threshold: float = max_ball_speed * 0.6

func _ready() -> void:
	# Set z_index so ball renders above the arena floor
	z_index = Global.Layers.PROJECTILES
	$Sprite2D.z_index = Global.Layers.PROJECTILES
	
	# Update collision mask to detect weapons (layer 5) in addition to layers 1 and 2
	# Current mask is 3 (layers 1 and 2), add layer 5: 3 | (1 << 4) = 19
	set_collision_mask_value(5, true)  # Enable detection of weapon layer
	
	# Enable ball in offline mode or if server
	if Server.OFFLINE or multiplayer.is_server():
		body_entered.connect(_on_body_entered)
		_update_ball_color(0)
	else:
		set_collision_layer_value(3, false)
		set_collision_mask_value(1, false)
		set_collision_mask_value(2, false)
		set_collision_mask_value(5, false)
		set_process(false)
		set_physics_process(false)


func _process(_delta: float) -> void:
	$Sprite2D.modulate = color_cur
	#_update_ball_color(linear_velocity.length())

func _physics_process(_delta: float) -> void:
	if linear_velocity.length() > max_ball_speed:
		linear_velocity = linear_velocity.normalized() * max_ball_speed


func _update_ball_color(speed: float) -> void:
	var new_color: Color
	if speed < speed_medium_threshold:
		var t: float = speed / speed_medium_threshold
		new_color = color_slow.lerp(color_medium, t)
	elif speed < speed_fast_threshold:
		var t: float = (speed - speed_medium_threshold) / (speed_fast_threshold - speed_medium_threshold)
		new_color = color_medium.lerp(color_fast, t)
	else:
		var t: float = (speed - speed_fast_threshold) / (max_ball_speed - speed_fast_threshold)
		t = min(t, 1.0)  
		new_color = color_fast.lerp(color_max, t)
	
	$Sprite2D.modulate = new_color


func _on_body_entered(body: Node) -> void:
	# Only process collisions in offline mode or if server
	if !Server.OFFLINE and !multiplayer.is_server(): return
	
	if body is BossClass:
		# Calculate damage and direction for boss collision
		var ball_speed: float = linear_velocity.length()
		var damage: float = ball_speed * 0.1  # Scale damage based on ball speed
		var direction: Vector2 = (body.global_position - global_position).normalized()
		body.under_attack(damage, direction)
	
	if body is PlayerClass:
		var ball_speed: float = linear_velocity.length()
		var ball_to_player: Vector2 = (body.global_position - global_position).normalized()
		
		var effective_min_velocity: float = min_velocity_for_knockback
		
		if ball_speed > effective_min_velocity:
			var knockback_force: float = ball_speed * knockback_strength
			# Call apply_knockback on EntityBehavior, handle offline vs multiplayer
			if Server.OFFLINE:
				body.EB.apply_knockback(ball_to_player, knockback_force)
			else:
				body.EB.apply_knockback.rpc(ball_to_player, knockback_force)
	
	if body is DoorClass:
		body.under_attack = true
	
	# Handle weapon/projectile collisions to move the ball (like dummy does)
	if body.is_in_group("Weapon"):
		var weapon: WeaponClass = body as WeaponClass
		if weapon:
			var weapon_damage: float = weapon.Properties.weapon_damage
			var weapon_mod_damage: float = weapon.Properties.weapon_mod_damage
			var weapon_total_damage: float = weapon_damage + weapon_mod_damage
			var weapon_velocity: Vector2 = weapon.linear_velocity
			
			# For melee attacks (held weapons with no velocity), calculate knockback differently
			var impact_force: Vector2
			if weapon_velocity.length() < 10.0:  # Very low velocity = held weapon
				# Calculate direction from weapon to ball
				var knockback_direction: Vector2 = (global_position - weapon.global_position).normalized()
				# Use damage-based knockback force for melee
				impact_force = knockback_direction * weapon_total_damage * 50.0
			else:
				# For projectiles, use velocity-based knockback
				impact_force = weapon_velocity * weapon_total_damage
			
			apply_central_impulse(impact_force)
