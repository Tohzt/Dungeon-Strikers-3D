@tool
class_name Chest3D extends WeaponStand3D
## A treasure chest, good for one find. The first player to interact with it
## throws the lid open, and inside is either:
## - a weapon, spinning over the open chest like one on an altar, taken with
##   interact like any stand's (by anyone, once), or
## - a perk: the opener picks one of `perk_choices` cards on the spot.
## Online the server rolls what's inside and tells everyone.

enum Contents { RANDOM, WEAPON, PERK }

## What's inside. RANDOM rolls `perk_chance` when the chest is opened.
@export var contents: Contents = Contents.RANDOM
@export_range(0.0, 1.0) var perk_chance: float = 0.5
## Cards to choose between when it holds a perk.
@export_range(1, 3) var perk_choices: int = 2
## Weapons it can hold (one is picked at random when opened).
@export var loot_weapons: Array[PackedScene] = []
## Chance of each rarity (Common, Uncommon, Rare, Legendary) for its weapon,
## as relative weights. See WeaponRarity.
@export var loot_rarity_weights: Array[float] = [30.0, 45.0, 20.0, 5.0]

const LID_OPEN_DEGREES := -110.0
const LID_OPEN_TIME := 0.45

@onready var lid: Node3D = $Lid
@onready var glow: OmniLight3D = $Glow

var is_open: bool = false
## Its weapon has been taken: nothing left inside.
var is_emptied: bool = false


func _ready() -> void:
	# What's inside is only decided when it's opened.
	if not Engine.is_editor_hint():
		weapon_scene = null
	super()


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
	if Net.in_session():
		_request_open.rpc_id(Net.SERVER_ID)
	else:
		_roll_contents(player)
	return true


func _is_stocked() -> bool:
	return is_open and not is_emptied and super()


@rpc("any_peer", "reliable")
func _request_open() -> void:
	if not Net.is_server or is_open:
		return
	var player: PlayerClass3D = Global.Game3D.player_of_peer(multiplayer.get_remote_sender_id())
	if player:
		_roll_contents(player)


## Server/offline: decide what's inside and open it for everyone.
func _roll_contents(player: PlayerClass3D) -> void:
	if is_open:
		return
	var is_perk: bool = contents == Contents.PERK \
		or (contents == Contents.RANDOM and randf() < perk_chance) \
		or loot_weapons.is_empty()
	var pick: int = -1 if is_perk else randi() % loot_weapons.size()
	var tier: int = WeaponRarity.roll(loot_rarity_weights)
	if Net.in_session():
		_opened.rpc(player.name, pick, tier)
	else:
		_opened(player.name, pick, tier)
	if is_perk and Global.Game3D:
		Global.Game3D.perks.grant_bonus_hand(player, perk_choices)


## Every machine: swing the lid open and show the weapon (pick < 0 = a perk).
@rpc("authority", "call_local", "reliable")
func _opened(player_name: String, pick: int, tier: int) -> void:
	is_open = true
	var tween: Tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(lid, "rotation_degrees:x", LID_OPEN_DEGREES, LID_OPEN_TIME)
	tween.parallel().tween_property(glow, "light_energy", 0.0, 1.5)
	var player: PlayerClass3D = Global.Game3D.get_node_or_null(player_name) as PlayerClass3D if Global.Game3D else null
	if pick >= 0 and pick < loot_weapons.size():
		rarity = tier
		weapon_scene = loot_weapons[pick]
		if player and Global.Game3D:
			Global.Game3D.scoreboard.announce("%s found a %s weapon!" % [_label(player), WeaponRarity.NAMES[tier]],
				WeaponRarity.COLORS[tier])
	elif player and Global.Game3D:
		Global.Game3D.scoreboard.announce("%s found a perk!" % _label(player),
			player.slot.color if player.slot else Color.WHITE)


## Its one weapon is gone: it stays empty for good (no restock to wait for).
func _cooldown_after_take() -> float:
	return 0.0


func _after_given() -> void:
	is_emptied = true


func _label(player: PlayerClass3D) -> String:
	return "P%d" % (player.slot.index + 1) if player.slot else String(player.name)
