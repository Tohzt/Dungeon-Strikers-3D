class_name WeaponBehavior3D extends Node

## Core behavior script for 3D weapons, similar to EntityBehavior3D for entities.
## Concrete weapons can extend this class or override its virtual methods.

@export_category("Core")
@export var weapon_name: String = ""
@export var base_damage: float = 10.0
@export var knockback_force: float = 5.0

@export_category("Owner & Attach")
@export var attach_bone_name: String = ""  # Optional: name of hand/attach point if using skeletons

var Master: Node3D
var wielder: Node3D = null


func _ready() -> void:
	# Cache owning weapon (RigidBody3D or scene root)
	Master = get_parent() as Node3D
	if Master and weapon_name.is_empty():
		weapon_name = Master.name


## Called when the weapon is equipped by a wielder (player, enemy, etc.)
## Override in child scripts for weapon-specific behavior.
func equip(new_wielder: Node3D) -> void:
	wielder = new_wielder


## Called when the weapon is unequipped / dropped.
func unequip() -> void:
	wielder = null


## Called when an attack is initiated while this weapon is equipped.
func on_attack_started() -> void:
	pass


## Called when an attack ends (swing finished, input released, etc).
func on_attack_ended() -> void:
	pass


## Called when this weapon successfully hits a target.
## You can apply damage/knockback here or just emit events.
func on_hit(_target: Node3D) -> void:
	pass


## Utility: get world damage value (base + any dynamic mods you add later)
func get_damage() -> float:
	return base_damage
