class_name Consumable extends RefCounted
## A card in a player's consumable slots (PlayerClass3D.consumables): a bomb
## or big flask bought at a shop or found in an item box, or an item box's
## giant weapon. Each is a Vector2i(Kind, variant), the same on every
## machine, until it's used: a throwable comes out into both hands (see
## Throwable3D), a giant weapon goes into a hand.

## FLASK and BOMB match Throwable3D.Kind, so a throwable's variant is its own.
enum Kind { FLASK, BOMB, GIANT_WEAPON }

## A giant weapon's variant packs the WildItem it came from (Giant or
## Colossal Weapon) above this many bits of its WildItem.GIANT_WEAPONS pick.
const WEAPON_PICK_BITS := 8
const WEAPON_PICK_MASK := (1 << WEAPON_PICK_BITS) - 1


static func throwable(kind_: Throwable3D.Kind, variant_: int) -> Vector2i:
	return Vector2i(kind_, variant_)


## `item` (a WildItem.Kind.WEAPON) as a card, holding WildItem.GIANT_WEAPONS[pick].
static func giant_weapon(item: int, pick: int) -> Vector2i:
	return Vector2i(Kind.GIANT_WEAPON, (item << WEAPON_PICK_BITS) | pick)


static func is_throwable(card: Vector2i) -> bool:
	return card.x == Kind.FLASK or card.x == Kind.BOMB


static func _weapon_item(card: Vector2i) -> int:
	return card.y >> WEAPON_PICK_BITS


static func _weapon_scene(card: Vector2i) -> PackedScene:
	return WildItem.GIANT_WEAPONS[clampi(card.y & WEAPON_PICK_MASK, 0, WildItem.GIANT_WEAPONS.size() - 1)]


## What it's called ("Fire Bomb", "Colossal Greatsword").
static func title_of(card: Vector2i) -> String:
	if is_throwable(card):
		return Throwable3D.title_of(card.x as Throwable3D.Kind, card.y)
	var size: String = WildItem.title(_weapon_item(card)).trim_suffix(" Weapon")
	return "%s %s" % [size, Altar3D.weapon_info(_weapon_scene(card))[0]]


static func color_of(card: Vector2i) -> Color:
	if is_throwable(card):
		return Throwable3D.color_of(card.x as Throwable3D.Kind, card.y)
	return WildItem.color(_weapon_item(card))


## The small heading over its name.
static func kind_name(card: Vector2i) -> String:
	match card.x:
		Kind.FLASK:
			return "FLASK"
		Kind.BOMB:
			return "BOMB"
	return "GIANT WEAPON"


## What it does, in a line.
static func text_of(card: Vector2i) -> String:
	if is_throwable(card):
		return ItemCards.throwable_text(card.x as Throwable3D.Kind, card.y)
	return "%s. Goes in your hand when used." % WildItem.ITEMS[_weapon_item(card)].blurb.trim_suffix(".")


## Every machine: `player` uses `card`, taking it in hand.
static func use(player: PlayerClass3D, card: Vector2i) -> void:
	if is_throwable(card):
		Throwable3D.give(player, card.x as Throwable3D.Kind, card.y)
		return
	var item: int = _weapon_item(card)
	player.giant_weapons_made += 1
	var weapon: Weapon3D = _weapon_scene(card).instantiate()
	weapon.name = "%s_Giant%d" % [player.name, player.giant_weapons_made]
	Global.Game3D.add_weapon(weapon)
	weapon.set_rarity(WeaponRarity.Tier.LEGENDARY)
	weapon.make_giant(WildItem.ITEMS[item].get("size", WildItem.GIANT_WEAPON_SIZE),
		WildItem.ITEMS[item].get("power", WildItem.GIANT_WEAPON_POWER))
	weapon.global_position = player.carry_point()
	weapon.hand_to(player, player.free_hand_for(weapon.grip))
	Sfx.play(&"spell_impact", player.global_position)
