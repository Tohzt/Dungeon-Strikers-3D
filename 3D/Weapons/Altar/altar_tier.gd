class_name AltarTier extends Resource
## One step of an altar's power curve: which weapons it can stock and how
## long they take to appear and to become takeable.

## Weapons this tier can stock; the server picks one at random each restock.
@export var weapons: Array[PackedScene] = []
## Seconds a new weapon sits on the altar, visibly charging, before it can be
## taken. Lets both sides see a power spike coming.
@export var arming_time: float = 0.0
## Seconds the altar stays empty after its weapon is taken.
@export var respawn_delay: float = 3.0
## Chance of each rarity (Common, Uncommon, Rare, Legendary) for a weapon
## this tier stocks, as relative weights. See WeaponRarity.
@export var rarity_weights: Array[float] = [1.0, 0.0, 0.0, 0.0]
