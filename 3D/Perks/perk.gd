class_name Perk extends Resource
## One rogue-lite upgrade a player can take at their altar between rounds.
## Its effect is a set of stat modifiers (see PerkSet for what each stat
## does); taking the same perk again stacks it.

enum Category {
	OFFENSE,   ## Offered to whoever landed the killing blow on the boss
	MOBILITY,  ## Mobility/defense: offered to everyone else after a boss kill
	STRIKER,   ## Offered to the team that scored
	COMEBACK,  ## Offered to the teams that were scored on
	GENERAL,   ## Offered to everyone
}

const CATEGORY_NAMES: Dictionary[Category, String] = {
	Category.OFFENSE: "Offense",
	Category.MOBILITY: "Mobility",
	Category.STRIKER: "Striker",
	Category.COMEBACK: "Comeback",
	Category.GENERAL: "General",
}
const CATEGORY_COLORS: Dictionary[Category, Color] = {
	Category.OFFENSE: Color(0.9, 0.25, 0.2),
	Category.MOBILITY: Color(0.25, 0.7, 0.95),
	Category.STRIKER: Color(0.95, 0.7, 0.15),
	Category.COMEBACK: Color(0.65, 0.4, 0.95),
	Category.GENERAL: Color(0.75, 0.75, 0.75),
}

@export var title: String = ""
@export_multiline var description: String = ""
@export var category: Category = Category.GENERAL
## Stat name -> bonus added to that stat's multiplier, e.g. {"damage": 0.25}
## is +25% damage and {"damage_taken": -0.15} is 15% less damage taken.
## See PerkSet.STATS for the names.
@export var mods: Dictionary[StringName, float] = {}


func category_name() -> String:
	return CATEGORY_NAMES[category]


func category_color() -> Color:
	return CATEGORY_COLORS[category]
