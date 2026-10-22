class_name PerkCatalog extends Resource
## Every perk that can be offered. Online, perks are sent by their index in
## this list, so every machine must use the same catalog.

@export var perks: Array[Perk] = []


## What `perk` evolves into, and with what: "+ Ghost Step = Blink", or
## "x2 = Heat Seeker" for two of it. One line per evolution; empty = none.
func evolution_hint(perk: Perk) -> String:
	var lines: PackedStringArray = []
	for result: Perk in perks:
		var needed: Array[Perk] = result.ingredients()
		if not needed.has(perk):
			continue
		if needed.count(perk) == needed.size():
			lines.append("x%d = %s" % [needed.size(), result.title])
		else:
			var others: PackedStringArray = []
			for other: Perk in needed:
				if other != perk:
					others.append(other.title)
			lines.append("+ %s = %s" % [" + ".join(others), result.title])
	return "\n".join(lines)


func in_category(category: Perk.Category) -> Array[Perk]:
	var found: Array[Perk] = []
	for perk: Perk in perks:
		if perk.category == category:
			found.append(perk)
	return found
