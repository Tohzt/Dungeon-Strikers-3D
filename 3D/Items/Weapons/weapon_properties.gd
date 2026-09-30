class_name WeaponProperties3D extends Node

@export var weapon_name := "Weapon"
@export var weapon_damage := 0.1
@export var throw_force := 15.0
@export var throw_upward_ratio := 0.15  # how much of the throw arcs upward
@export var throw_spin_speed := 8.0  # radians/sec of tumble while airborne
## Scales how many uses its rarity gives it (see WeaponRarity.DURABILITY),
## e.g. higher for weapons whose uses come often, like shots or blocks.
@export var durability_scale := 1.0
