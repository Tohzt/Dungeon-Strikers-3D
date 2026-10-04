class_name WeaponProperties3D extends Node

@export var weapon_name := "Weapon"
@export var weapon_damage := 0.1
@export var throw_force := 15.0
@export var throw_upward_ratio := 0.15  # how much of the throw arcs upward
@export var throw_spin_speed := 8.0  # radians/sec of tumble while airborne
## Scales how many uses its rarity gives it (see WeaponRarity.DURABILITY),
## e.g. higher for weapons whose uses come often, like shots or blocks.
@export var durability_scale := 1.0

@export_group("Breaking")
## When it breaks it shatters in a burst this wide (meters), hurting and
## shoving everyone in it except its wielder's team (see Weapon3D._break).
@export var break_burst_radius := 2.5
@export var break_burst_damage := 25.0
@export var break_burst_knockback := 12.0

@export_group("Swing")
## Seconds from the strike until the arm is back at rest; the strike is the
## first half (committed), the follow-through the second (can be rolled out
## of). The sword's 0.25 is the baseline: heavier weapons swing slower.
@export var swing_duration := 0.2
## Seconds the arm draws back before the strike, so a heavy swing can be seen
## coming (and dodged). Committed: it can't be rolled out of. 0 = strikes at once.
@export var swing_windup := 0.0
## Scales the stamina a swing costs, e.g. higher for heavy weapons so they
## can't be spammed, lower for quick ones like the dagger.
@export var swing_stamina_scale := 1.0
