class_name SpellController extends WeaponControllerBase

@onready var spell := weapon

func on_equip() -> void:
	super.on_equip()
	spell.throw_weapon(spell.Properties.weapon_mod_damage)

func update(delta: float) -> void:
	super.update(delta)
