class_name Weapon3D extends RigidBody3D

@export var Properties: WeaponProperties3D
@export var Behavior: WeaponBehavior3D
@onready var Collision := $CollisionShape3D

var wielder: Node3D = null
var can_pickup: bool = true
var can_pickup_cd: float = 0.0
var can_pickup_dur_in_sec: float = 1.0


func _ready() -> void: 
	_set_props()


func _process(delta: float) -> void: 
	_handle_pickup_cooldown(delta)


func _set_props() -> void:
	if !Properties: 
		print("No Propertied found")
		queue_free()
		return
	
	# Set name from properties
	if Properties.weapon_name.is_empty():
		Properties.weapon_name = "Weapon3D"
	self.name = Properties.weapon_name
	
	# Setup collision if available
	if Collision:
		# Collision shape should be set up in the scene
		pass
	
	_update_collisions("on-ground")


func _handle_pickup_cooldown(delta: float) -> void:
	if wielder:
		return  # Don't update cooldown if held
	
	can_pickup_cd = max(can_pickup_cd - delta, 0.0)
	if can_pickup_cd == 0.0:
		can_pickup = true
	else:
		can_pickup = false


## High-level API: called by player/enemy when picking up this weapon.
func equip(new_wielder: Node3D) -> void:
	wielder = new_wielder
	can_pickup = false
	can_pickup_cd = can_pickup_dur_in_sec
	_update_collisions("in-hand")
	
	if Behavior:
		Behavior.equip(new_wielder)


## High-level API: called when the weapon is dropped/unequipped.
func unequip() -> void:
	if Behavior:
		Behavior.unequip()
	
	wielder = null
	_update_collisions("on-ground")


func _update_collisions(state: String) -> void:
	match state:
		"on-ground":
			set_collision_layer_value(2, false) 
			set_collision_layer_value(4, true)
			set_collision_mask_value(1, true)  # World
			set_collision_mask_value(2, true)  # Player
			set_collision_mask_value(3, true)  # Enemy
			set_collision_mask_value(4, true)  # Weapon
			
		"in-hand":
			set_collision_layer_value(2, true) 
			set_collision_layer_value(4, false)
			set_collision_mask_value(1, false)  # World
			set_collision_mask_value(2, false)  # Player
			set_collision_mask_value(3, true)   # Enemy
			set_collision_mask_value(4, true)   # Weapon
			
		"projectile":
			set_collision_layer_value(2, false) 
			set_collision_layer_value(4, true)
			set_collision_mask_value(1, true)   # World
			set_collision_mask_value(2, false)  # Player
			set_collision_mask_value(3, true)   # Enemy
			set_collision_mask_value(4, true)   # Weapon
