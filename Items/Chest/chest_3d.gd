@tool
class_name Chest3D extends WeaponStand3D
## A treasure chest, good for one find. The first player to interact with it
## throws the lid open, and inside is either:
## - a weapon, spinning over the open chest like one on an altar, taken with
##   interact like any stand's (by anyone, once), or
## - a perk: the opener picks one of `perk_choices` cards on the spot, or
## - coins (COINS only, never rolled by RANDOM): they spill out in a pile in
##   front of it (see CoinPile3D) for whoever's standing there.
## Whatever's inside, a small potion or two may pop out too (potion_chance),
## drunk by whoever runs through them first (see PotionPickup3D).
## With a respawn_time it shuts again after a while, full once more.
## Online the server rolls what's inside and tells everyone.

enum Contents { RANDOM, WEAPON, PERK, COINS }

## What's inside. RANDOM rolls `perk_chance` (weapon or perk) when the chest is opened.
@export var contents: Contents = Contents.RANDOM
@export_range(0.0, 1.0) var perk_chance: float = 0.5
## Cards to choose between when it holds a perk.
@export_range(1, 3) var perk_choices: int = 2
## Weapons it can hold (one is picked at random when opened).
@export var loot_weapons: Array[PackedScene] = []
## Chance of each rarity (Common, Uncommon, Rare, Legendary) for its weapon,
## as relative weights. See WeaponRarity.
@export var loot_rarity_weights: Array[float] = [30.0, 45.0, 20.0, 5.0]
## COINS: how many spill out, picked at random in this range.
@export var coin_min: int = 8
@export var coin_max: int = 15
## Seconds after it's opened before it shuts, full again (0 = never).
@export var respawn_time: float = 0.0
## Chance some small potions (Potion.SMALL) pop out as well when it's
## opened, and at most how many.
@export_range(0.0, 1.0) var potion_chance: float = 0.0
@export_range(1, 4) var potion_max: int = 2

## How far in front of the chest its coins land.
const COIN_PILE_OFFSET := 1.7
## Its potions land this far in front, spread this far apart sideways.
const POTION_OFFSET := 2.8
const POTION_SPREAD := 1.5

const LID_OPEN_DEGREES := -110.0
const LID_OPEN_TIME := 0.45

@onready var lid: Node3D = $Lid
@onready var glow: OmniLight3D = $Glow

var is_open: bool = false
## Its weapon has been taken: nothing left inside.
var is_emptied: bool = false
## Server/offline: seconds until it shuts again (see respawn_time).
var _respawn_left: float = -1.0
var _glow_energy: float = 0.0
## Names the potions it pops out, the same on every machine.
var _potions_made: int = 0


func _ready() -> void:
	# What's inside is only decided when it's opened.
	if not Engine.is_editor_hint():
		weapon_scene = null
	super()
	_glow_energy = glow.light_energy


func _process(delta: float) -> void:
	super(delta)
	if Engine.is_editor_hint() or _respawn_left < 0.0:
		return
	_respawn_left -= delta
	if _respawn_left <= 0.0:
		_respawn_left = -1.0
		Net.everywhere(_shut)


## Closed: anyone in reach can open it. Open: its weapon, like a stand.
func can_give_to(player: PlayerClass3D) -> bool:
	if not is_open:
		return reach.overlaps_body(player)
	return super(player)


## Bots walk to unopened chests too (it might be a weapon).
func has_weapon_for(player: PlayerClass3D) -> bool:
	return not is_open or super(player)


func request_take(player: PlayerClass3D) -> bool:
	if is_open:
		return super(player)
	if not reach.overlaps_body(player):
		return false
	if Net.decides():
		_roll_contents(player)
	else:
		_request_open.rpc_id(Net.SERVER_ID)
	return true


func _is_stocked() -> bool:
	return is_open and not is_emptied and super()


@rpc("any_peer", "reliable")
func _request_open() -> void:
	if not Net.is_server or is_open:
		return
	var player: PlayerClass3D = Global.Game3D.rpc_sender()
	if player:
		_roll_contents(player)


## Server/offline: decide what's inside and open it for everyone.
func _roll_contents(player: PlayerClass3D) -> void:
	if is_open:
		return
	if respawn_time > 0.0:
		_respawn_left = respawn_time
	if randf() < potion_chance:
		var kinds := PackedInt32Array()
		for i in randi_range(1, potion_max):
			kinds.append(Potion.roll_small())
		Net.everywhere(_potions_popped, kinds)
	if contents == Contents.COINS:
		Net.everywhere(_opened, player.name, -1, 0, true)
		if Global.Game3D:
			var amount: int = randi_range(coin_min, maxi(coin_min, coin_max))
			Global.Game3D.drop_coins(global_transform * (Vector3.BACK * COIN_PILE_OFFSET), amount,
				global_position + Vector3.UP * 1.2)
		return
	var is_perk: bool = contents == Contents.PERK \
		or (contents == Contents.RANDOM and randf() < perk_chance) \
		or loot_weapons.is_empty()
	var pick: int = -1 if is_perk else randi() % loot_weapons.size()
	var tier: int = WeaponRarity.roll(loot_rarity_weights)
	Net.everywhere(_opened, player.name, pick, tier, false)
	if is_perk and Global.Game3D:
		Global.Game3D.perks.grant_bonus_hand(player, perk_choices)


## Every machine: swing the lid open and show the weapon (pick < 0 = a
## perk, or with `coins`, the coins the server's spilling out).
@rpc("authority", "call_local", "reliable")
func _opened(player_name: String, pick: int, tier: int, coins: bool) -> void:
	is_open = true
	is_emptied = coins
	Sfx.play(&"chest_open", global_position)
	var tween: Tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(lid, "rotation_degrees:x", LID_OPEN_DEGREES, LID_OPEN_TIME)
	tween.parallel().tween_property(glow, "light_energy", 0.0, 1.5)
	var player: PlayerClass3D = Global.Game3D.player_named(player_name) if Global.Game3D else null
	if coins:
		return
	if pick >= 0 and pick < loot_weapons.size():
		rarity = tier as WeaponRarity.Tier
		weapon_scene = loot_weapons[pick]
		if player and Global.Game3D:
			Global.Game3D.scoreboard.announce("%s found a %s weapon!" % [_label(player), WeaponRarity.NAMES[tier]],
				WeaponRarity.COLORS[tier])
	elif player and Global.Game3D:
		Global.Game3D.scoreboard.announce("%s found a perk!" % _label(player),
			player.slot.color if player.slot else Color.WHITE)


## Every machine: potions of `kinds` pop out and land in a row in front.
@rpc("authority", "call_local", "reliable")
func _potions_popped(kinds: PackedInt32Array) -> void:
	if not Global.Game3D:
		return
	for i in kinds.size():
		_potions_made += 1
		var across: float = (i - (kinds.size() - 1) * 0.5) * POTION_SPREAD
		var to: Vector3 = global_transform * Vector3(across, 0.0, POTION_OFFSET)
		PotionPickup3D.pop(Global.Game3D, "%s_Potion%d" % [name, _potions_made], kinds[i],
			global_position + Vector3.UP * 1.2, to)


## Every machine: the lid swings shut, and it's full again.
@rpc("authority", "call_local", "reliable")
func _shut() -> void:
	is_open = false
	is_emptied = false
	weapon_scene = null
	var tween: Tween = create_tween().set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(lid, "rotation_degrees:x", 0.0, LID_OPEN_TIME * 1.5)
	tween.parallel().tween_property(glow, "light_energy", _glow_energy, 0.8)


## Its one weapon is gone: it stays empty (until it shuts again, if it does).
func _cooldown_after_take() -> float:
	return 0.0


func _after_given() -> void:
	is_emptied = true


func _label(player: PlayerClass3D) -> String:
	return player.slot.label() if player.slot else String(player.name)
