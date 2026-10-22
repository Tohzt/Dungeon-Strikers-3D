class_name Perk extends Resource
## One rogue-lite upgrade a player can take at their altar between rounds.
## Its effect is a set of stat modifiers (see PerkSet for what each stat
## does); taking the same perk again stacks it. A relic can also be evolved
## into: owning everything in its evolves_from swaps them for it.

enum Category {
	OFFENSE,   ## Offered to whoever landed the killing blow on the boss
	MOBILITY,  ## Mobility/defense: offered to everyone else after a boss kill
	STRIKER,   ## Offered to the team that scored
	COMEBACK,  ## Offered to the teams that were scored on
	GENERAL,   ## Offered to everyone
	HUNTER,    ## Offered to whoever got the most player kills in the round
	RELIC,     ## Rare and strong: only from a skull's altar reward (Altar3D)
}

const CATEGORY_NAMES: Dictionary[Category, String] = {
	Category.OFFENSE: "Offense",
	Category.MOBILITY: "Mobility",
	Category.STRIKER: "Striker",
	Category.COMEBACK: "Comeback",
	Category.GENERAL: "General",
	Category.HUNTER: "Hunter",
	Category.RELIC: "Relic",
}
const CATEGORY_COLORS: Dictionary[Category, Color] = {
	Category.OFFENSE: Color(0.9, 0.25, 0.2),
	Category.MOBILITY: Color(0.25, 0.7, 0.95),
	Category.STRIKER: Color(0.95, 0.7, 0.15),
	Category.COMEBACK: Color(0.65, 0.4, 0.95),
	Category.GENERAL: Color(0.75, 0.75, 0.75),
	Category.HUNTER: Color(0.85, 0.15, 0.45),
	Category.RELIC: Color(1.0, 0.78, 0.25),
}

@export var title: String = ""
@export_multiline var description: String = ""
@export var category: Category = Category.GENERAL
## Stat name -> bonus added to that stat's multiplier, e.g. {"damage": 0.25}
## is +25% damage and {"damage_taken": -0.15} is 15% less damage taken.
## See PerkSet.STATS for the names.
@export var mods: Dictionary[StringName, float] = {}
## What evolves into this (see PerkSet.evolve): two perks, or one listed
## once meaning two of it. Empty = nothing does. Perks only (an Array[Perk]
## here would be the script referring to itself, which leaks it).
@export var evolves_from: Array[Resource] = []


## Everything that's used up to evolve into this: evolves_from, with a
## lone entry doubled.
func ingredients() -> Array[Perk]:
	var needed: Array[Perk] = []
	for ingredient: Resource in evolves_from:
		if ingredient is Perk:
			needed.append(ingredient)
	if needed.size() == 1:
		needed.append(needed[0])
	return needed


func category_name() -> String:
	return CATEGORY_NAMES[category]


func category_color() -> Color:
	return CATEGORY_COLORS[category]
