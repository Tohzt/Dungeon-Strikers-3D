class_name PerkCatalog extends Resource
## Every perk that can be offered. Online, perks are sent by their index in
## this list, so every machine must use the same catalog.

@export var perks: Array[Perk] = []


func in_category(category: Perk.Category) -> Array[Perk]:
	var found: Array[Perk] = []
	for perk: Perk in perks:
		if perk.category == category:
			found.append(perk)
	return found
