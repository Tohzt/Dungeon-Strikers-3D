class_name PerkDirector extends Node
## Runs the rogue-lite perk picks. Whoever lands the killing blow on a boss
## is dealt a hand of offensive cards on the spot, to pick from at their
## altar whenever they like; nobody else's game stops for it. Over a round
## it also notes who earned what: everyone a mobility/defense card for the
## boss going down; the scoring team a striker card and everyone else a
## comeback card; the round's top player killer a hunter card. At the
## intermission each player is dealt three cards (boss card, goal card, and
## a hunter card for the top killer or a general card for everyone else).
## Every player walks back to their altar on their own (see
## PlayerClass3D._walk_to_altar) and picks there, all at the same time, each
## seeing only their own cards; the next boss comes once everyone has.
## Online the server deals and approves picks; every machine applies them.

signal intermission_started
## Everyone has picked. On every machine.
signal intermission_finished
signal perk_taken(player: PlayerClass3D, perk: Perk)

const OFFER_SIZE := 3
## Online: don't ask the server to open the cards again this soon.
const OPEN_RETRY_MSEC := 500

@export var catalog: PerkCatalog = preload("res://3D/Perks/perk_catalog.tres")
@export var picker: PerkPicker3D

var in_intermission: bool = false
## Player name -> the hands of catalog indices they have yet to pick from,
## oldest first (a boss-kill hand can still be waiting at the intermission).
var offers: Dictionary[String, Array] = {}
## Players looking at their cards right now, by name.
var picking: Dictionary[String, bool] = {}
## Online: when this machine last asked to open each player's cards.
var _open_requested_msec: Dictionary[String, int] = {}
## What each player (by name) has earned since the last intermission.
var _boss_rewards: Dictionary[String, Perk.Category] = {}
var _goal_rewards: Dictionary[String, Perk.Category] = {}
## Player kills each player (by name) has made since the last intermission.
var _round_kills: Dictionary[String, int] = {}


func _ready() -> void:
	if picker:
		picker.chosen.connect(_on_picker_chosen)


# ===== EARNING =====

## On every machine. The killer (server/offline decides) gets a hand of
## offensive cards right away; everyone gets a mobility card at the
## intermission.
func record_boss_kill(killer: PlayerClass3D) -> void:
	for player: PlayerClass3D in _players():
		_boss_rewards[player.name] = Perk.Category.MOBILITY
	if not killer or (Net.in_session() and not Net.is_server):
		return
	var categories: Array[Perk.Category] = []
	categories.resize(OFFER_SIZE)
	categories.fill(Perk.Category.OFFENSE)
	var hand: PackedInt32Array = _deal_hand(categories)
	if Net.in_session():
		_grant_hand.rpc(killer.name, hand)
	else:
		_grant_hand(killer.name, hand)


@rpc("authority", "call_local", "reliable")
func _grant_hand(player_name: String, hand: PackedInt32Array) -> void:
	_add_hand(player_name, hand)
	var player: PlayerClass3D = _player_named(player_name)
	if player and Global.Game3D:
		var label: String = "P%d" % (player.slot.index + 1) if player.slot else player_name
		Global.Game3D.scoreboard.announce("%s slew the boss! A perk awaits at their altar" % label,
			player.slot.color if player.slot else Color.WHITE)


## Server/offline: a find (e.g. a chest) deals `player` a hand of `size`
## cards from any category, put first in line, and opens it for them on the
## spot (bots pick theirs on their own).
func grant_bonus_hand(player: PlayerClass3D, size: int) -> void:
	if Net.in_session() and not Net.is_server:
		return
	var hand := PackedInt32Array()
	var choices: Array[int] = []
	for i in catalog.perks.size():
		choices.append(i)
	choices.shuffle()
	for i in mini(size, choices.size()):
		hand.append(choices[i])
	if Net.in_session():
		_grant_bonus_hand.rpc(player.name, hand)
	else:
		_grant_bonus_hand(player.name, hand)


@rpc("authority", "call_local", "reliable")
func _grant_bonus_hand(player_name: String, hand: PackedInt32Array) -> void:
	if hand.is_empty():
		return
	if not offers.has(player_name):
		offers[player_name] = []
	offers[player_name].push_front(hand)
	var player: PlayerClass3D = _player_named(player_name)
	if not player or (player.slot and player.slot.is_bot):
		return
	if not Net.in_session() or player.is_multiplayer_authority():
		open_for(player)


func _add_hand(player_name: String, hand: PackedInt32Array) -> void:
	if hand.is_empty():
		return
	if not offers.has(player_name):
		offers[player_name] = []
	offers[player_name].append(hand)


func record_goal(team: int) -> void:
	for player: PlayerClass3D in _players():
		var scored: bool = player.slot != null and player.slot.team == team
		if _goal_rewards.get(player.name) == Perk.Category.STRIKER:
			continue
		_goal_rewards[player.name] = Perk.Category.STRIKER if scored else Perk.Category.COMEBACK


## On every machine, so any of them could deal.
func record_kill(killer: PlayerClass3D) -> void:
	_round_kills[killer.name] = _round_kills.get(killer.name, 0) + 1


# ===== INTERMISSION =====

## Server/offline: deal everyone their cards and open the altars.
func begin_intermission() -> void:
	if in_intermission or (Net.in_session() and not Net.is_server):
		return
	var dealt: Dictionary = {}
	for player: PlayerClass3D in _players():
		dealt[player.name] = _deal(player.name)
	_boss_rewards.clear()
	_goal_rewards.clear()
	_round_kills.clear()
	if Net.in_session():
		_start_intermission.rpc(dealt)
	else:
		_start_intermission(dealt)


## One card per source: the boss result, the goal result, and a hunter
## card for the round's top killer (ties included) or a general one. A
## source that didn't happen this round (no boss, no goal) gives a general
## card instead.
func _deal(player_name: String) -> PackedInt32Array:
	var categories: Array[Perk.Category] = [
		_boss_rewards.get(player_name, Perk.Category.GENERAL),
		_goal_rewards.get(player_name, Perk.Category.GENERAL),
		Perk.Category.HUNTER if _is_top_killer(player_name) else Perk.Category.GENERAL,
	]
	return _deal_hand(categories)


## A card of each category, none twice in one hand.
func _deal_hand(categories: Array[Perk.Category]) -> PackedInt32Array:
	var hand := PackedInt32Array()
	for category: Perk.Category in categories:
		var choices: Array[int] = []
		for i in catalog.perks.size():
			if catalog.perks[i].category == category and not hand.has(i):
				choices.append(i)
		if choices.is_empty():  # Category ran dry: anything not in the hand yet
			for i in catalog.perks.size():
				if not hand.has(i):
					choices.append(i)
		if not choices.is_empty():
			hand.append(choices.pick_random())
	return hand


func _is_top_killer(player_name: String) -> bool:
	var mine: int = _round_kills.get(player_name, 0)
	if mine == 0:
		return false
	for other: String in _round_kills:
		if _round_kills[other] > mine:
			return false
	return true


@rpc("authority", "call_local", "reliable")
func _start_intermission(dealt: Dictionary) -> void:
	for player_name: String in dealt:
		_add_hand(player_name, dealt[player_name])
	in_intermission = true
	picker.set_full_screen(true)
	_update_waiting()
	intermission_started.emit()
	if offers.is_empty():
		_finish_intermission()


func _finish_intermission() -> void:
	in_intermission = false
	picker.set_full_screen(false)
	picker.show_waiting([])
	intermission_finished.emit()


# ===== PICKING =====

## Whether `player` has cards waiting and isn't looking at them already.
func can_open(player: PlayerClass3D) -> bool:
	return offers.has(player.name) and not picking.has(player.name)


## `player` is looking at their cards (they stand still meanwhile).
func is_picking(player: PlayerClass3D) -> bool:
	return picking.has(player.name)


## Whether anyone on `team` still has cards to pick from (lights the altar).
func team_has_offer(team: int) -> bool:
	for player: PlayerClass3D in _players():
		if player.slot and player.slot.team == team and offers.has(player.name):
			return true
	return false


## Offline: a bot takes a random card from its oldest hand.
func auto_pick(player: PlayerClass3D) -> void:
	if Net.in_session() or not can_open(player):
		return
	var hand: PackedInt32Array = offers[player.name][0]
	_apply_pick(player.name, hand[randi() % hand.size()])


## Show `player` their oldest hand (at their altar). Nobody else's game
## stops. Call on the machine that controls the player.
func open_for(player: PlayerClass3D) -> void:
	if not can_open(player):
		return
	if Net.in_session():
		var now: int = Time.get_ticks_msec()
		if now - _open_requested_msec.get(player.name, -OPEN_RETRY_MSEC) < OPEN_RETRY_MSEC:
			return
		_open_requested_msec[player.name] = now
		_request_open.rpc_id(Net.SERVER_ID)
	else:
		_begin_pick(player.name)


@rpc("any_peer", "reliable")
func _request_open() -> void:
	if not Net.is_server:
		return
	var player: PlayerClass3D = Global.Game3D.player_of_peer(multiplayer.get_remote_sender_id())
	if player and can_open(player):
		_begin_pick.rpc(player.name)


@rpc("authority", "call_local", "reliable")
func _begin_pick(player_name: String) -> void:
	var player: PlayerClass3D = _player_named(player_name)
	_open_requested_msec.erase(player_name)
	if not player or not offers.has(player_name):
		return
	picking[player_name] = true
	# Only the picker's own machine shows their cards
	if Net.in_session() and not player.is_multiplayer_authority():
		return
	var hand: Array[Perk] = []
	for index: int in offers[player_name][0]:
		hand.append(catalog.perks[index])
	picker.open(player, hand)


## `player` chose card `card` of the hand they were shown.
func _on_picker_chosen(player: PlayerClass3D, card: int) -> void:
	if not picking.has(player.name) or card < 0 or card >= offers[player.name][0].size():
		return
	if Net.in_session():
		_request_pick.rpc_id(Net.SERVER_ID, card)
	else:
		_apply_pick(player.name, offers[player.name][0][card])


@rpc("any_peer", "reliable")
func _request_pick(card: int) -> void:
	if not Net.is_server:
		return
	var player: PlayerClass3D = Global.Game3D.player_of_peer(multiplayer.get_remote_sender_id())
	if player and picking.has(player.name) and card >= 0 and card < offers[player.name][0].size():
		_apply_pick.rpc(player.name, offers[player.name][0][card])


@rpc("authority", "call_local", "reliable")
func _apply_pick(player_name: String, catalog_index: int) -> void:
	var player: PlayerClass3D = _player_named(player_name)
	var perk: Perk = catalog.perks[catalog_index]
	if player:
		player.add_perk(perk)
	if offers.has(player_name):
		offers[player_name].pop_front()
		if offers[player_name].is_empty():
			offers.erase(player_name)
	_end_pick(player_name)
	if player:
		perk_taken.emit(player, perk)
	if in_intermission and offers.is_empty():
		_finish_intermission()


func _end_pick(player_name: String) -> void:
	picking.erase(player_name)
	var player: PlayerClass3D = _player_named(player_name)
	if player:
		picker.close(player)
		# The button that took the card shouldn't also swing
		if player.Input_Handler:
			player.Input_Handler.release_all()
	_update_waiting()


## An online player left: they no longer hold anyone up.
func forget_player(player: PlayerClass3D) -> void:
	offers.erase(player.name)
	_boss_rewards.erase(player.name)
	_goal_rewards.erase(player.name)
	_round_kills.erase(player.name)
	if picking.has(player.name):
		_end_pick(player.name)
	elif in_intermission:
		_update_waiting()
	if in_intermission and offers.is_empty():
		_finish_intermission()


# ===== HELPERS =====

func _update_waiting() -> void:
	var waiting: Array[PlayerClass3D] = []
	if in_intermission:
		for player: PlayerClass3D in _players():
			if offers.has(player.name):
				waiting.append(player)
	picker.show_waiting(waiting)


func _players() -> Array[PlayerClass3D]:
	if Global.Game3D:
		return Global.Game3D.players
	return []


func _player_named(player_name: String) -> PlayerClass3D:
	for player: PlayerClass3D in _players():
		if player.name == player_name:
			return player
	return null
