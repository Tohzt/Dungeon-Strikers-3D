class_name PerkDirector extends Node
## Runs the rogue-lite perk picks. Over a round it notes who earned what:
## the boss's killer an offensive card and everyone else a mobility/defense
## card; the scoring team a striker card and everyone else a comeback card;
## the round's top player killer a hunter card. At the intermission each
## player is dealt three cards (boss card, goal card, and a hunter card for
## the top killer or a general card for everyone else), and picks one by
## activating their altar. Like
## Rounds, the whole game pauses while one player picks; the next boss
## comes once everyone has.
## Online the server deals and approves picks; every machine applies them.

signal intermission_started
## Everyone has picked. On every machine.
signal intermission_finished
signal perk_taken(player: PlayerClass3D, perk: Perk)

const OFFER_SIZE := 3

@export var catalog: PerkCatalog = preload("res://3D/Perks/perk_catalog.tres")
@export var picker: PerkPicker3D

var in_intermission: bool = false
## Player name -> catalog indices on offer, for everyone yet to pick.
var offers: Dictionary[String, PackedInt32Array] = {}
## The player at the picker right now ("" = nobody).
var picking: String = ""
## What each player (by name) has earned since the last intermission.
var _boss_rewards: Dictionary[String, Perk.Category] = {}
var _goal_rewards: Dictionary[String, Perk.Category] = {}
## Player kills each player (by name) has made since the last intermission.
var _round_kills: Dictionary[String, int] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if picker:
		picker.chosen.connect(_on_picker_chosen)


func _process(_delta: float) -> void:
	# Keep the game paused while someone picks, even if the pause menu
	# was opened and closed in the meantime
	if picking != "" and not get_tree().paused:
		get_tree().paused = true


# ===== EARNING =====

func record_boss_kill(killer: PlayerClass3D) -> void:
	for player: PlayerClass3D in _players():
		# A kill earned this round isn't lost to someone else's later kill
		if _boss_rewards.get(player.name) == Perk.Category.OFFENSE:
			continue
		_boss_rewards[player.name] = Perk.Category.OFFENSE if player == killer else Perk.Category.MOBILITY


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
## card instead. No card twice in one hand.
func _deal(player_name: String) -> PackedInt32Array:
	var categories: Array[Perk.Category] = [
		_boss_rewards.get(player_name, Perk.Category.GENERAL),
		_goal_rewards.get(player_name, Perk.Category.GENERAL),
		Perk.Category.HUNTER if _is_top_killer(player_name) else Perk.Category.GENERAL,
	]
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
	offers.clear()
	for player_name: String in dealt:
		offers[player_name] = dealt[player_name]
	in_intermission = true
	_update_waiting()
	intermission_started.emit()
	if offers.is_empty():
		_finish_intermission()


func _finish_intermission() -> void:
	in_intermission = false
	picker.show_waiting([])
	intermission_finished.emit()


# ===== PICKING =====

## Whether `player` has cards waiting and the picker is free.
func can_open(player: PlayerClass3D) -> bool:
	return in_intermission and picking == "" and offers.has(player.name)


## Whether anyone on `team` still has cards to pick from (lights the altar).
func team_has_offer(team: int) -> bool:
	if not in_intermission:
		return false
	for player: PlayerClass3D in _players():
		if player.slot and player.slot.team == team and offers.has(player.name):
			return true
	return false


## `player` activated their altar: pause everyone and show their cards.
## Call on the machine that controls the player.
func open_for(player: PlayerClass3D) -> void:
	if not can_open(player):
		return
	if Net.in_session():
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
	if not player or not offers.has(player_name):
		return
	picking = player_name
	get_tree().paused = true
	var hand: Array[Perk] = []
	for index: int in offers[player_name]:
		hand.append(catalog.perks[index])
	var local: bool = not Net.in_session() or player.is_multiplayer_authority()
	picker.open(player, hand, local)


## The picking player chose card `card` of their hand.
func _on_picker_chosen(card: int) -> void:
	if picking == "" or card < 0 or card >= offers[picking].size():
		return
	if Net.in_session():
		_request_pick.rpc_id(Net.SERVER_ID, card)
	else:
		_apply_pick(picking, offers[picking][card])


@rpc("any_peer", "reliable")
func _request_pick(card: int) -> void:
	if not Net.is_server or picking == "":
		return
	var player: PlayerClass3D = Global.Game3D.player_of_peer(multiplayer.get_remote_sender_id())
	if player and player.name == picking and card >= 0 and card < offers[picking].size():
		_apply_pick.rpc(picking, offers[picking][card])


@rpc("authority", "call_local", "reliable")
func _apply_pick(player_name: String, catalog_index: int) -> void:
	var player: PlayerClass3D = _player_named(player_name)
	var perk: Perk = catalog.perks[catalog_index]
	if player:
		player.add_perk(perk)
	offers.erase(player_name)
	_end_pick()
	if player:
		perk_taken.emit(player, perk)
	if in_intermission and offers.is_empty():
		_finish_intermission()


func _end_pick() -> void:
	picking = ""
	picker.close()
	get_tree().paused = false
	# Buttons pressed or let go while paused never reached the players
	for player: PlayerClass3D in _players():
		if player.Input_Handler:
			player.Input_Handler.release_all()
	_update_waiting()


## An online player left: they no longer hold anyone up.
func forget_player(player: PlayerClass3D) -> void:
	offers.erase(player.name)
	_boss_rewards.erase(player.name)
	_goal_rewards.erase(player.name)
	_round_kills.erase(player.name)
	if picking == player.name:
		_end_pick()
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
