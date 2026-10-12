class_name WildItem extends RefCounted
## The silly stuff an ItemBox3D hands out, Mario Kart style: short wild
## buffs, instant effects and giant weapons. Players behind in the race
## (luck near 1, see Game3D.item_luck) roll the wildest ones more often.
##
## Items are listed by index, which is what gets sent online, so only ever
## append to ITEMS.

enum Kind {
	BUFF,     ## A timed perk (see PlayerClass3D.add_timed_perk)
	INSTANT,  ## Happens on the spot (see ItemBox3D._apply)
	WEAPON,   ## A giant weapon, straight into a free hand
}

const GIANT_WEAPON_SIZE := 1.8
const GIANT_WEAPON_POWER := 1.75
const GIANT_WEAPONS: Array[PackedScene] = [
	preload("res://3D/Weapons/Hammer/hammer_3d.tscn"),
	preload("res://3D/Weapons/Hammer/mace_3d.tscn"),
	preload("res://3D/Weapons/Axe/greataxe_3d.tscn"),
	preload("res://3D/Weapons/Sword/greatsword_3d.tscn"),
	preload("res://3D/Weapons/Sword/sword_3d.tscn"),
	preload("res://3D/Weapons/Halberd/halberd_3d.tscn"),
	preload("res://3D/Weapons/Spear/spear_3d.tscn"),
	preload("res://3D/Weapons/Knuckles/knuckles_3d.tscn"),
	preload("res://3D/Weapons/Dagger/dagger_3d.tscn"),
]

## Thunderclap: everyone else this close gets blasted.
const THUNDERCLAP_RADIUS := 7.0
const THUNDERCLAP_DAMAGE := 25.0
const THUNDERCLAP_KNOCKBACK := 22.0
const THUNDERCLAP_POP := 8.0

## Each item: title, blurb, kind, color, seconds (buffs), perk mods (buffs),
## and how often it comes up for the race leader and for whoever's last.
const ITEMS: Array[Dictionary] = [
	{"title": "Giant!", "blurb": "Huge, heavy and hits like a truck",
		"kind": Kind.BUFF, "color": Color(1.0, 0.45, 0.2), "seconds": 12.0,
		"mods": {&"size": 0.7, &"damage": 0.5, &"knockback": 1.5, &"knockback_taken": -0.6, &"move_speed": -0.1},
		"front": 1.0, "back": 3.0},
	{"title": "Pipsqueak", "blurb": "Tiny and zippy (and fragile)",
		"kind": Kind.BUFF, "color": Color(0.6, 1.0, 0.5), "seconds": 12.0,
		"mods": {&"size": -0.45, &"move_speed": 0.5, &"damage_taken": 0.25},
		"front": 3.0, "back": 1.0},
	{"title": "Rocket Fists", "blurb": "Everything you hit goes flying",
		"kind": Kind.BUFF, "color": Color(1.0, 0.25, 0.25), "seconds": 15.0,
		"mods": {&"knockback": 3.0},
		"front": 2.0, "back": 2.0},
	{"title": "Iron Skin", "blurb": "Shrug off hits and shoves",
		"kind": Kind.BUFF, "color": Color(0.7, 0.75, 0.85), "seconds": 10.0,
		"mods": {&"damage_taken": -0.75, &"knockback_taken": -0.9},
		"front": 2.0, "back": 2.0},
	{"title": "Sugar Rush", "blurb": "Go go go!",
		"kind": Kind.BUFF, "color": Color(1.0, 0.5, 0.9), "seconds": 10.0,
		"mods": {&"move_speed": 0.6, &"stamina_regen": 2.0},
		"front": 2.0, "back": 3.0},
	{"title": "Berserk", "blurb": "Hit way harder, get hit way harder",
		"kind": Kind.BUFF, "color": Color(0.85, 0.1, 0.1), "seconds": 12.0,
		"mods": {&"damage": 1.5, &"damage_taken": 1.0},
		"front": 1.0, "back": 2.0},
	{"title": "Snack", "blurb": "Full health and stamina",
		"kind": Kind.INSTANT, "color": Color(1.0, 0.85, 0.4),
		"front": 2.0, "back": 1.0},
	{"title": "Thunderclap", "blurb": "Blast everyone nearby away",
		"kind": Kind.INSTANT, "color": Color(0.5, 0.8, 1.0),
		"front": 2.0, "back": 2.0},
	{"title": "Giant Weapon", "blurb": "Big. Very big.",
		"kind": Kind.WEAPON, "color": Color(1.0, 0.65, 0.1),
		"front": 1.0, "back": 3.0},
]
const SNACK := 6
const THUNDERCLAP := 7

## Each buff's Perk, made once (the same object every time, so getting a
## buff again restarts it instead of stacking a copy).
static var _perks: Dictionary[int, Perk] = {}


static func title(index: int) -> String:
	return ITEMS[index].title


static func color(index: int) -> Color:
	return ITEMS[index].color


static func kind(index: int) -> Kind:
	return ITEMS[index].kind


static func seconds(index: int) -> float:
	return ITEMS[index].get("seconds", 0.0)


static func perk_of(index: int) -> Perk:
	if not _perks.has(index):
		var perk := Perk.new()
		perk.title = ITEMS[index].title
		perk.description = ITEMS[index].blurb
		perk.mods.assign(ITEMS[index].mods)
		_perks[index] = perk
	return _perks[index]


## A random item, weighted between the leader's odds (luck 0) and the
## last player's (luck 1). Items `allowed` says no to are skipped.
static func roll(luck: float, allowed: Callable) -> int:
	var weights: Array[float] = []
	var total: float = 0.0
	for i in ITEMS.size():
		var w: float = lerpf(ITEMS[i].front, ITEMS[i].back, clampf(luck, 0.0, 1.0)) if allowed.call(i) else 0.0
		weights.append(w)
		total += w
	var pick: float = randf() * total
	for i in weights.size():
		pick -= weights[i]
		if pick < 0.0:
			return i
	return SNACK
