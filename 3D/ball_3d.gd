extends RigidBody3D
@onready var starting_position: Vector3 = self.global_position

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

@onready var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D")

func _ready() -> void:
	# Find mesh instance if not directly named
	if not mesh_instance:
		mesh_instance = get_node_or_null("MeshInstance3D")
		if not mesh_instance:
			# Try to find any MeshInstance3D child
			for child in get_children():
				if child is MeshInstance3D:
					mesh_instance = child
					break
	
	# Update collision mask to detect weapons and entities
	set_collision_mask_value(1, true)  # World
	set_collision_mask_value(2, true)  # Player
	set_collision_mask_value(3, true)  # Enemy
	set_collision_mask_value(4, true)  # Weapon
	
	# Connect body entered signal
	body_entered.connect(_on_body_entered)
	_update_ball_color(0)


func _process(_delta: float) -> void:
	if mesh_instance:
		var material: StandardMaterial3D = mesh_instance.get_surface_override_material(0)
		if not material:
			material = StandardMaterial3D.new()
			mesh_instance.set_surface_override_material(0, material)
		material.albedo_color = color_cur


func _physics_process(_delta: float) -> void:
	if linear_velocity.length() > max_ball_speed:
		linear_velocity = linear_velocity.normalized() * max_ball_speed
	_update_ball_color(linear_velocity.length())


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
	
	color_cur = new_color


func _on_body_entered(body: Node) -> void:
	if body is CharacterBody3D:
		var player: CharacterBody3D = body as CharacterBody3D
		# Check if it has EB (EntityBehavior3D)
		if player.Entity:
			var ball_speed: float = linear_velocity.length()
			var ball_to_player: Vector3 = (player.global_position - global_position).normalized()
			
			var effective_min_velocity: float = min_velocity_for_knockback
			
			if ball_speed > effective_min_velocity:
				var knockback_force: float = ball_speed * knockback_strength
				# Apply knockback
				player.Entity.apply_knockback(ball_to_player, knockback_force)
	
	# Handle weapon/projectile collisions to move the ball
	if body.is_in_group("Weapon") and body is Weapon3D:
		var weapon: Weapon3D = body
		if weapon.Properties:
			var weapon_damage: float = weapon.Properties.weapon_damage
			var weapon_velocity: Vector3 = weapon.linear_velocity
			
			# For melee attacks (held weapons with no velocity), calculate knockback differently
			var impact_force: Vector3
			if weapon_velocity.length() < 10.0:  # Very low velocity = held weapon
				# Calculate direction from weapon to ball
				var knockback_direction: Vector3 = (global_position - weapon.global_position).normalized()
				# Use damage-based knockback force for melee
				impact_force = knockback_direction * weapon_damage * 50.0
			else:
				# For projectiles, use velocity-based knockback
				impact_force = weapon_velocity * weapon_damage
			
			apply_central_impulse(impact_force)
