class_name PerkSet extends RefCounted
## The perks one player has taken, and the stat multipliers they add up to.

## Every stat a perk can modify, and what it scales.
const STATS: Dictionary[StringName, String] = {
	&"damage": "Damage dealt by any attack",
	&"knockback": "Knockback dealt by any attack",
	&"boss_damage": "Extra damage dealt to bosses",
	&"damage_vs_leader": "Extra damage dealt to players whose team is ahead in kills",
	&"damage_vs_wounded": "Extra damage dealt to players below 30% HP",
	&"kill_heal": "Share of max HP healed on a player kill (starts at 0)",
	&"respawn_time": "How long you're out after dying (negative = less)",
	&"ball_power": "How hard hits send the ball",
	&"throw_power": "How hard weapons are thrown",
	&"move_speed": "Walking and sprinting speed",
	&"max_hp": "Max health",
	&"damage_taken": "Damage taken (negative = less)",
	&"knockback_taken": "Knockback taken (negative = less)",
	&"size": "How big the body looks (wild items: Giant, Pipsqueak)",
	&"dodge_cooldown": "Time between rolls, backsteps and slides (negative = less)",
	&"dodge_iframes": "How long rolls and backsteps are untouchable",
	&"dodge_speed": "How fast (so how far) rolls, backsteps and slides go",
	&"dodge_counter": "Extra damage for a moment after rolling through a hit (starts at 0)",
	&"slide_iframes": "Share of a slide tackle that's untouchable (starts at 0)",
	&"slide_damage": "Damage dealt by slide tackles",
	&"slide_reach": "How wide a slide tackle sweeps",
	&"knockdown_time": "How long your slide tackles keep players down",
	&"homing": "How hard attack waves and projectiles steer toward enemies (starts at 0)",
	&"double_cast": "Chance an attack's waves or shot go off again (starts at 0)",
	&"heavy_double_cast": "Extra chance a heavy's waves or shot go off again (starts at 0)",
	# Wild items' status buffs: on above 1 (see PlayerStatus3D)
	&"frost_touch": "Hits freeze whoever they land on",
	&"ablaze": "On fire: hits set people burning, touching the ball lights it",
	&"regen": "Heals over time",
}
## No stat goes below this multiplier, however many negatives stack up.
const MIN_MULTIPLIER := 0.1

var perks: Array[Perk] = []


func add(perk: Perk) -> void:
	perks.append(perk)


## Take one copy of `perk` back off (a wild item's effect wearing off).
func remove(perk: Perk) -> void:
	perks.erase(perk)


## The multiplier for `stat`: 1.0 plus every taken perk's bonus to it.
func stat(stat_name: StringName) -> float:
	var total: float = 1.0
	for perk: Perk in perks:
		total += perk.mods.get(stat_name, 0.0)
	return max(total, MIN_MULTIPLIER)


func count(perk: Perk) -> int:
	return perks.count(perk)


## If what we own makes one of `catalog`'s evolutions (see
## Perk.evolves_from), swap its ingredients for it and return it; else null.
func evolve(catalog: PerkCatalog) -> Perk:
	for result: Perk in catalog.perks:
		var needed: Array[Perk] = result.ingredients()
		if needed.is_empty():
			continue
		var owned: bool = needed.all(func(perk: Perk) -> bool:
			return count(perk) >= needed.count(perk))
		if owned:
			for perk: Perk in needed:
				remove(perk)
			add(result)
			return result
	return null
