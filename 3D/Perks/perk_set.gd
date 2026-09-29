class_name PerkSet extends RefCounted
## The perks one player has taken, and the stat multipliers they add up to.

## Every stat a perk can modify, and what it scales.
const STATS: Dictionary[StringName, String] = {
	&"damage": "Damage dealt by any attack",
	&"knockback": "Knockback dealt by any attack",
	&"boss_damage": "Extra damage dealt to bosses",
	&"damage_vs_leader": "Extra damage dealt to players whose team is ahead",
	&"ball_power": "How hard hits send the ball",
	&"throw_power": "How hard weapons and the ball are thrown",
	&"ball_grip": "How big a hit it takes to knock the ball loose",
	&"move_speed": "Walking and sprinting speed",
	&"jump": "Jump height",
	&"max_hp": "Max health",
	&"max_stamina": "Max stamina",
	&"stamina_regen": "Stamina regeneration speed",
	&"damage_taken": "Damage taken (negative = less)",
	&"knockback_taken": "Knockback taken (negative = less)",
}
## No stat goes below this multiplier, however many negatives stack up.
const MIN_MULTIPLIER := 0.1

var perks: Array[Perk] = []


func add(perk: Perk) -> void:
	perks.append(perk)


## The multiplier for `stat`: 1.0 plus every taken perk's bonus to it.
func stat(stat_name: StringName) -> float:
	var total: float = 1.0
	for perk: Perk in perks:
		total += perk.mods.get(stat_name, 0.0)
	return max(total, MIN_MULTIPLIER)


func count(perk: Perk) -> int:
	return perks.count(perk)
