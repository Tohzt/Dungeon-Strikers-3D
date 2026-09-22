class_name Weapon3D extends RigidBody3D

@export var Properties: WeaponProperties3D
@export var Behavior: WeaponBehavior3D
@onready var Collision := $CollisionShape3D

var wielder: Node3D = null
var held_hand: Area3D = null
var is_held: bool = false
var is_thrown: bool = false

var can_pickup: bool = true
var can_pickup_cd: float = 0.0
var can_pickup_dur_in_sec: float = 1.0

var throw_spin_direction: float = 1.0

const THROWN_SETTLE_SPEED: float = 0.4
const DEFAULT_THROW_FORCE: float = 15.0
const DEFAULT_THROW_UPWARD_RATIO: float = 0.15
const DEFAULT_THROW_SPIN_SPEED: float = 8.0


func _ready() -> void:
	_set_props()


func _process(delta: float) -> void:
	_handle_pickup_cooldown(delta)


func _physics_process(delta: float) -> void:
	_handle_thrown_settle()
	if is_thrown:
		var spin_speed: float = Properties.throw_spin_speed if Properties else DEFAULT_THROW_SPIN_SPEED
		# Spin around the weapon's own local Z axis (perpendicular to its
		# length, which runs along local Y for a capsule-shaped weapon), so
		# it tumbles end-over-end like a flicked frisbee no matter which way
		# it happened to be pointing at the moment it was released.
		rotate_object_local(Vector3.FORWARD, spin_speed * throw_spin_direction * delta)


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


func _handle_thrown_settle() -> void:
	if is_thrown and linear_velocity.length() < THROWN_SETTLE_SPEED:
		is_thrown = false
		_update_collisions("on-ground")


## High-level API: called by player/enemy when picking up this weapon.
## `hand` is the Area3D of the hand it's being equipped into, used by
## weapon behaviors (like the spring-follow sword) to know what to track.
func equip(new_wielder: Node3D, hand: Area3D = null) -> void:
	wielder = new_wielder
	held_hand = hand
	is_held = true
	is_thrown = false
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
	held_hand = null
	is_held = false
	_update_collisions("on-ground")


## High-level API: called to throw the weapon in a given (horizontal) direction.
## `spin_direction` lets the thrower flip which way it tumbles (e.g. mirrored
## for a left-hand vs right-hand throw) - pass -1.0 to reverse it.
## `force_multiplier` scales the resolved base throw force (e.g. for a
## charge-up-by-holding-the-button throw).
func throw(direction: Vector3, force: float = -1.0, spin_direction: float = 1.0, force_multiplier: float = 1.0) -> void:
	if !wielder: return

	throw_spin_direction = spin_direction

	if Behavior:
		Behavior.unequip()

	wielder = null
	held_hand = null
	is_held = false
	is_thrown = true
	can_pickup = false
	can_pickup_cd = can_pickup_dur_in_sec
	_update_collisions("projectile")

	var throw_force: float = force if force > 0.0 else DEFAULT_THROW_FORCE
	var upward_ratio: float = DEFAULT_THROW_UPWARD_RATIO
	if Properties:
		if Properties.throw_force > 0.0 and force <= 0.0:
			throw_force = Properties.throw_force
		upward_ratio = Properties.throw_upward_ratio
	throw_force *= force_multiplier

	var horizontal_dir: Vector3 = direction.normalized()
	var launch_dir: Vector3 = (horizontal_dir + Vector3.UP * upward_ratio).normalized()
	linear_velocity = launch_dir * throw_force
	angular_velocity = Vector3.ZERO


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
