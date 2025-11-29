class_name WeaponClass extends RigidBody2D

@export var Properties: WeaponResource
@onready var Sprite := $Sprite2D
@onready var Collision := $CollisionShape2D
@onready var Controller: WeaponControllerBase = $Controller

var wielder: Node2D
var is_attacking: bool = false
var things_nearby: Array[Node2D] = []
var destroy_on_impact: bool = false
var is_thrown: bool = false
var throw_clone: bool = false
var throw_force: float = 800.0
var throw_torque: float = 10.0
var mod_angle: float = 0.0
var has_synergy: bool

var can_pickup: bool = true
var can_pickup_cd: float = 0.0
var can_pickup_dur_in_sec: float = 1.0


func _ready() -> void: _set_props()
func _process(delta: float) -> void: _handle_held_or_pickup(delta)
func _physics_process(_delta: float) -> void: _handle_thrown()


func _set_props() -> void:
	if !Properties: 
		queue_free()
		return
	
	Sprite.texture = Properties.weapon_sprite[0]
	Sprite.position = Properties.weapon_sprite_offset
	
	if Properties.weapon_controller:
		if Controller.get_script() != Properties.weapon_controller:
			Controller.set_script(Properties.weapon_controller)
			Controller._ready()
	
	if Properties.weapon_name.is_empty():
		var regex := RegEx.new()
		regex.compile("([^/]+)\\.png")
		var result := regex.search(Sprite.texture.load_path)
		if result:
			Properties.weapon_name = result.get_string(1)
	self.name = Properties.weapon_name
	
	if Collision:
		if Collision.shape is CapsuleShape2D:
			Collision.shape.radius = Properties.weapon_col_radius
			Collision.shape.height = Properties.weapon_col_height
			Collision.rotation = Properties.weapon_col_rotation
		Collision.position = Properties.weapon_col_offset
	else:
		print_debug("DEBUG: Collision is null")
	
	if wielder:
		modulate = wielder.EB.Sprite.modulate
		_update_collisions("in-hand")
	else:
		_update_collisions("on-ground")


func _handle_held_or_pickup(delta: float) -> void:
	if wielder and !is_thrown:
		# Weapons are now children of hands, so they automatically follow hand movement
		# Only handle rotation if needed for weapon-specific behavior
		var weapon_angle: float = Properties.weapon_angle
		if Controller.is_either_handed() and Controller.in_offhand:
			weapon_angle = 180 - Properties.weapon_angle
		rotation = deg_to_rad(weapon_angle + mod_angle)
		
		if Properties.weapon_controller:
			# Script should already be set during initialization, just update
			Controller.update(delta)
	else:
		can_pickup_cd = max(can_pickup_cd - delta, 0.0)
		if can_pickup_cd == 0.0:
			can_pickup = true
			if !is_thrown:
				modulate = Color.WHITE
		else:
			modulate = lerp(modulate, modulate.lightened(0.1), can_pickup_dur_in_sec-can_pickup_cd)
		


func _handle_thrown() -> void:
	if is_thrown:
		wielder = null
		var collisions := get_colliding_bodies()
		for collider: Node2D in collisions:
			if collider:
				if wielder:
					if collider == wielder:
						continue
					if collider.is_in_group("Weapon") and collider.wielder == wielder:
						continue
				reset_to_ground_state()


func throw_weapon(mod_damage: float = 0.0, force_throw_original: bool = false) -> void:
	if !wielder: return
	var throw_direction := _calculate_throw_direction(wielder)
	var projectile: WeaponClass
	
	# Force throw_clone to false when throwing via interact
	if force_throw_original:
		throw_clone = false
	
	if throw_clone:
		projectile = self.duplicate() as WeaponClass
		if !projectile: return
		projectile.Properties = projectile.Properties.duplicate()
		if !projectile.Properties: return
		
		wielder.get_parent().add_child(projectile)
		projectile.throw_clone = true
		projectile.wielder = wielder
		projectile.Sprite.position = Vector2.ZERO
		projectile.Collision.position = Vector2.ZERO
		projectile.Properties.weapon_mod_damage = mod_damage
		projectile._update_collisions("projectile")
	else:
		projectile = self
		# Remove from hand
		var hand_holding_weapon: PlayerHandClass = null
		if wielder.Hands.Left.held_weapon == self:
			hand_holding_weapon = wielder.Hands.Left
		elif wielder.Hands.Right.held_weapon == self:
			hand_holding_weapon = wielder.Hands.Right
		if hand_holding_weapon:
			hand_holding_weapon.held_weapon = null
		
		projectile.is_thrown = true
		projectile.Sprite.position = Vector2.ZERO
		projectile.Collision.position = Vector2.ZERO
		projectile._update_collisions("projectile")
		projectile.Controller.reset_arm_position(get_process_delta_time(), 10.0)

	
	var throw_style := projectile.Properties.weapon_throw_style
	if projectile.Controller.in_offhand and projectile.Controller.hold_position:
		throw_style = Properties.ThrowStyle.STRAIGHT
		projectile.Controller.handle_release()
	match throw_style:
		Properties.ThrowStyle.STRAIGHT:
			projectile.global_rotation = throw_direction.angle()
			projectile.angular_velocity = 0.0
		Properties.ThrowStyle.SPIN:
			projectile.global_rotation = throw_direction.angle()
			projectile.angular_velocity = throw_torque * 2.0
		Properties.ThrowStyle.TUMBLE:
			projectile.global_rotation = throw_direction.angle()
			projectile.angular_velocity = throw_torque * 0.5
	
	if !throw_clone: call_deferred("reparent", wielder.get_parent())
	
	projectile.wielder = null
	projectile.global_position = global_position
	projectile.linear_velocity = throw_direction.normalized() * throw_force
	projectile.is_thrown = true
	

func reset_to_ground_state() -> void:
	destroy_on_impact = destroy_on_impact or throw_clone
	if destroy_on_impact: 
		queue_free()
		return
	can_pickup = false
	can_pickup_cd = can_pickup_dur_in_sec
	wielder = null
	is_thrown = false
	angular_velocity = 0.0
	linear_velocity = Vector2.ZERO
	Sprite.position = Vector2.ZERO
	Controller.in_offhand = false
	Controller.hold_position = false
	Controller.cooldown_duration = 0.0
	Collision.position = Vector2.ZERO
	Properties.weapon_mod_damage = 0.0
	_update_collisions("on-ground")
	var Entities := get_tree().get_first_node_in_group("Entities")
	call_deferred("reparent", Entities)


#func _set_held_sprite_position() -> void:
	## Safely set sprite position when weapon is held
	#if Sprite and Properties:
		#Sprite.position = Properties.weapon_offset

# Weapon input handling methods
func handle_input(input_type: String, duration: float = 0.0) -> void:
	if !wielder or !input_type: return
	match input_type:
		"click":
			Controller.handle_click()
		"hold":
			Controller.handle_hold()
		"release":
			Controller.handle_release()
		_:
			Controller.handle_input(input_type, duration)


# Called deferred after restore to complete weapon setup
func _restore_on_equip() -> void:
	_update_collisions("in-hand")
	if Controller and Controller.has_method("on_equip"):
		Controller.on_equip()


func _calculate_throw_direction(player: Node2D) -> Vector2:
	# Prioritize target direction when target locking is active
	if player.EB.target and is_instance_valid(player.EB.target):
		return (player.EB.target.global_position - player.global_position).normalized()
	elif !player.Input_Handler.look_dir.is_zero_approx():
		return player.Input_Handler.look_dir
	else:
		return Vector2(cos(player.rotation - PI/2), sin(player.rotation - PI/2))


func _update_collisions(state: String) -> void:
	match state:
		"on-ground":
			#modulate = Color.WEB_GRAY
			set_collision_layer_value(4, true)  # Item
			set_collision_layer_value(5, false) # Weapon
			set_collision_mask_value(2, false)  # Player
			set_collision_mask_value(1, true)  # World
			set_collision_mask_value(3, false)  # Enemy
			set_collision_mask_value(4, true)  # Item
			set_collision_mask_value(5, false)  # Weapon
			set_z_index(Global.Layers.WEAPON_ON_GROUND)
			
		"in-hand":
			#modulate = Color.BLUE
			set_collision_layer_value(4, false) # Item
			set_collision_layer_value(5, false)  # Weapon
			set_collision_mask_value(2, false)  # Player
			set_collision_mask_value(1, false)  # World
			set_collision_mask_value(3, false)   # Enemy
			set_collision_mask_value(4, false)  # Item
			set_collision_mask_value(5, false)  # Weapon
			set_z_index(Global.Layers.WEAPON_IN_HAND)
			
		"projectile":
			#modulate = Color.RED
			set_collision_layer_value(4, false) # Item
			set_collision_layer_value(5, true)  # Weapon
			set_collision_mask_value(1, true)  # World
			set_collision_mask_value(2, false)  # Player
			set_collision_mask_value(3, true)   # Enemy
			set_collision_mask_value(4, false)  # Item
			set_collision_mask_value(5, false)  # Weapon
			set_z_index(Global.Layers.PROJECTILES)
