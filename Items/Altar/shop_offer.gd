class_name ShopOffer extends RefCounted
## One thing a shop altar sells (see Altar3D.shop). Offers sharing a section
## title (SECTION_TITLES) make one row of the shop menu (ShopMenu3D), the
## rows in ORDER. A new kind goes here, in ORDER and SECTION_TITLES, in
## Altar3D's rolling/selling/pricing, and in ShopMenu3D's cards.
##
## Sent over the network as ENCODED_SIZE ints (see encode), and turned back
## into an offer by the altar that sells it (Altar3D._decode_offer).

## KIT upgrades the buyer's own signature kit (see PlayerClass3D.upgrade_kit),
## so what it is depends on who's looking. REPAIR isn't rolled: a team's
## altar sells it while the team has a tower up (see Altar3D.set_repair_offer).
## Values go over the network: append only.
enum Kind { WEAPON, PERK, REPAIR, KIT, THROWABLE }

## The menu's order, left to right and top to bottom: your own kit just
## before the breakable weapon, in the same row.
const ORDER: Array[Kind] = [Kind.KIT, Kind.WEAPON, Kind.PERK, Kind.THROWABLE, Kind.REPAIR]
## Each kind's row heading in the menu (kinds with the same one share a row).
const SECTION_TITLES: Dictionary[Kind, String] = {
	Kind.KIT: "Weapons",
	Kind.WEAPON: "Weapons",
	Kind.PERK: "Perks",
	Kind.THROWABLE: "Bombs & Flasks",
	Kind.REPAIR: "Towers",
}
const ENCODED_SIZE := 4

var kind: Kind = Kind.WEAPON
## WEAPON: what it is (from tiers[tier].weapons[pick]) and how rare.
var scene: PackedScene = null
var tier: int = 0
var pick: int = 0
var rarity: int = WeaponRarity.Tier.COMMON
## PERK: an index into the PerkCatalog.
var perk_index: int = -1
## KIT: how many rarities up it takes the buyer's kit.
var steps: int = 1
## THROWABLE: a Throwable3D.Kind, and which one of it (Potion.LARGE or
## Bomb3D.Type).
var throwable_kind: int = 0
var variant: int = 0
## Bought: it stays in the menu, sold out, until the next restock. Set
## on every machine (see Altar3D._sold), never sent.
var sold: bool = false


static func weapon(tier_index: int, weapon_pick: int, weapon_rarity: int) -> ShopOffer:
	var offer := ShopOffer.new()
	offer.kind = Kind.WEAPON
	offer.tier = tier_index
	offer.pick = weapon_pick
	offer.rarity = weapon_rarity
	return offer


static func perk(catalog_index: int) -> ShopOffer:
	var offer := ShopOffer.new()
	offer.kind = Kind.PERK
	offer.perk_index = catalog_index
	return offer


static func repair() -> ShopOffer:
	var offer := ShopOffer.new()
	offer.kind = Kind.REPAIR
	return offer


static func kit(kit_steps: int) -> ShopOffer:
	var offer := ShopOffer.new()
	offer.kind = Kind.KIT
	offer.steps = maxi(kit_steps, 1)
	return offer


static func throwable(of_kind: int, which: int) -> ShopOffer:
	var offer := ShopOffer.new()
	offer.kind = Kind.THROWABLE
	offer.throwable_kind = of_kind
	offer.variant = which
	return offer


## Where offers of `of_kind` sit in the menu (see ORDER).
static func order_of(of_kind: Kind) -> int:
	return ORDER.find(of_kind)


## [kind, a, b, c]: a weapon's [tier, pick, rarity], a perk's [catalog index, 0, 0],
## a kit's [steps, 0, 0], a throwable's [kind, variant, 0].
func encode() -> PackedInt32Array:
	match kind:
		Kind.WEAPON:
			return PackedInt32Array([kind, tier, pick, rarity])
		Kind.PERK:
			return PackedInt32Array([kind, perk_index, 0, 0])
		Kind.KIT:
			return PackedInt32Array([kind, steps, 0, 0])
		Kind.THROWABLE:
			return PackedInt32Array([kind, throwable_kind, variant, 0])
	return PackedInt32Array([kind, 0, 0, 0])
