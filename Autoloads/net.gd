extends Node
## Online play through the dedicated server on the droplet.
##
## Menus only talk to this autoload, never to ENet directly. A headless copy
## of the game runs on the droplet (started with `-- --server`) and holds one
## session at a time: the first player to host claims it with their code,
## friends join with the same code, and whoever got in first is the leader
## who starts the match. The server isn't a player; it checks codes, relays
## everyone's player syncing, sends everyone back to the lobby a little
## after a match is won, and frees the session when the last player leaves.
##
## To test against a server on this machine, run one with
##   godot --headless --path . -- --server
## and start each game copy with `-- --address=127.0.0.1`.

signal hosted(code: String)
signal joined(code: String)
signal failed(reason: String)
signal peers_changed
signal session_ended(reason: String)
signal match_started
## The match is over and everyone is headed back to the lobby, still in the
## session.
signal match_ended
## Every machine has loaded the match scene, so player syncing can begin.
signal all_loaded

## Random codes skip look-alikes (O/0, I/1) so they are easy to read out.
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const RANDOM_CODE_LENGTH := 6
const MIN_CODE_LENGTH := 4
const MAX_CODE_LENGTH := 8
const MAX_PLAYERS := Players.MAX_PLAYERS
const JOIN_TIMEOUT := 8.0
## Server: seconds a new connection gets to ask to host or join before it's
## dropped, so idle or stray connections can't sit on the slots.
const SERVER_JOIN_TIMEOUT := JOIN_TIMEOUT + 2.0
const MAIN_MENU := "res://UI/Menus/MainMenu/main_menu.tscn"

## The droplet. Override with `-- --address=<ip>` to test elsewhere.
const SERVER_ADDRESS := "64.225.4.250"
const PORT := 25565
## A few spare connections past a full session, so extra joiners can be
## told why they were turned away instead of just timing out.
const MAX_CONNECTIONS := MAX_PLAYERS + 4
const SERVER_ID := 1
## Bump whenever networked code changes shape (RPC arguments, synced
## properties, node names), so a game and server that don't match are told
## so instead of silently ignoring each other's updates.
const PROTOCOL_VERSION := 30

var access_code := ""
## Whether we lead the session (first in), which lets us start the match.
var is_host := false
## Verified players' peer ids in seat order (leader first). Never the server.
var peers: Array[int] = []
## What each player picked in the lobby: peer id -> [team, character,
## name] (see PlayerNames). Kept
## by the server and sent to everyone with the peer list, along with the
## leader's match format (Players.team_count, map, boss_drop and score_to_win).
var loadouts: Dictionary = {}
## Bots the leader added in the lobby, as [team, character, name] each. They sit
## in the seats after the players' and are run by the server.
var bots: Array = []
var in_match := false
## Every machine has the match scene loaded, so match nodes (players, ball,
## weapons) can send each other updates without hitting missing nodes.
var match_synced := false
## True on the headless server.
var is_server := false
## Why the session ended mid-match, for the main menu to show once it's
## back (it wasn't around to hear session_ended). Cleared once shown.
var end_reason := ""

## While connecting, what we asked the server for: "host" or "join".
var _request := ""
## Server only: machines that have finished loading the match scene.
var _loaded: Array[int] = []
var _all_loaded_sent := false
## Seconds after a match is won before the server sends everyone back to
## the lobby (enough to read the result and everyone's stats).
const LOBBY_RETURN_DELAY := 20.0
## Server only: each map's scene, loaded once at startup so Start is quick.
var _map_scenes: Dictionary[MatchMap.Map, PackedScene] = {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if OS.has_feature("dedicated_server") or OS.get_cmdline_user_args().has("--server"):
		# Deferred so the main menu finishes loading before we drop it.
		_start_server.call_deferred()


func in_session() -> bool:
	return not peers.is_empty()


## Whether this machine decides how the match goes and runs the shared
## world (the ball, bosses, minions, who scores, what gets dealt): the
## local game offline, the server online.
func decides() -> bool:
	return not in_session() or is_server


## Online, until every machine has loaded the match: nothing in it may act
## yet, since what it did wouldn't reach whoever is still loading.
func waiting_for_load() -> bool:
	return in_session() and not match_synced


## Run `method` (a "call_local" RPC) on every machine: as an RPC online, or
## just here offline. How the deciding machine (see decides()) tells
## everyone what happened.
func everywhere(method: Callable, ...args: Array) -> void:
	if in_session():
		method.get_object().callv(&"rpc", [method.get_method()] + args)
	else:
		method.callv(args)


## Our seat (0 = leader), which is also our player index in the match.
func local_seat() -> int:
	return peers.find(multiplayer.get_unique_id())


## Everyone in the session: players, then bots.
func seat_count() -> int:
	return peers.size() + bots.size()


# ===== CODES =====

func generate_code() -> String:
	var code := ""
	for i in RANDOM_CODE_LENGTH:
		code += CODE_ALPHABET[randi() % CODE_ALPHABET.length()]
	return code


## Uppercase and drop anything that isn't a letter or digit (spaces, dashes).
func normalize_code(code: String) -> String:
	var out := ""
	for c: String in code.to_upper():
		if (c >= "A" and c <= "Z") or (c >= "0" and c <= "9"):
			out += c
	return out


func is_valid_code(code: String) -> bool:
	return code == normalize_code(code) \
		and code.length() >= MIN_CODE_LENGTH and code.length() <= MAX_CODE_LENGTH


func code_rules() -> String:
	return "Codes are %d-%d letters or numbers." % [MIN_CODE_LENGTH, MAX_CODE_LENGTH]


# ===== SESSION =====

## Open a session on the server with the given code, or a random one if blank.
func host(code: String) -> void:
	code = normalize_code(code)
	_open_connection("host", code if not code.is_empty() else generate_code())


func join(code: String) -> void:
	_open_connection("join", normalize_code(code))


func leave() -> void:
	if is_server:
		return
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	access_code = ""
	is_host = false
	peers.clear()
	loadouts.clear()
	bots.clear()
	in_match = false
	match_synced = false
	_request = ""


## Leader only: ask the server to send everyone into the match.
func start_match() -> void:
	if is_host:
		_request_start.rpc_id(SERVER_ID)


## Our team and character in the lobby (sent to everyone through the
## server). Applied here straight away, so quick changes build on each
## other instead of on what the server last said.
func set_loadout(team: int, character: int) -> void:
	if in_session() and not in_match:
		var id: int = multiplayer.get_unique_id()
		loadouts[id] = _clamp_loadout(team, character) + [name_in(loadout_of(id))]
		peers_changed.emit()
		_request_loadout.rpc_id(SERVER_ID, team, character)


## What we're called (sent to everyone through the server). Blank gets a
## random name. Applied here straight away, like set_loadout.
func set_player_name(text: String) -> void:
	if in_session() and not in_match:
		var loadout: Array = local_loadout()
		loadouts[multiplayer.get_unique_id()] = [loadout[0], loadout[1], PlayerNames.clean(text)]
		peers_changed.emit()
		_request_name.rpc_id(SERVER_ID, text)


## Leader only: seat a bot on the smallest team (the server runs it).
func add_bot() -> void:
	if is_host and not in_match:
		_request_add_bot.rpc_id(SERVER_ID)


## Leader only: remove the last bot added.
func remove_bot() -> void:
	if is_host and not in_match:
		_request_remove_bot.rpc_id(SERVER_ID)


## Leader only: the number of teams to play with.
func set_team_count(count: int) -> void:
	if is_host and not in_match:
		_request_team_count.rpc_id(SERVER_ID, count)


## Leader only: the level to play on.
func set_map(map: MatchMap.Map) -> void:
	if is_host and not in_match:
		_request_map.rpc_id(SERVER_ID, map)


## Leader only: the goals (or kills) that win the match.
func set_score_to_win(score: int) -> void:
	if is_host and not in_match:
		_request_score_to_win.rpc_id(SERVER_ID, score)


## Leader only: what the bosses drop.
func set_boss_drop(kind: BossDrop.Kind) -> void:
	if is_host and not in_match:
		_request_boss_drop.rpc_id(SERVER_ID, kind)


## [team, character, name] picked by `peer_id`.
func loadout_of(peer_id: int) -> Array:
	return loadouts.get(peer_id, [0, 0, ""])


## Our own [team, character, name].
func local_loadout() -> Array:
	return loadout_of(multiplayer.get_unique_id())


## The name in a player's or bot's loadout.
func name_in(loadout: Array) -> String:
	return str(loadout[2]) if loadout.size() > 2 else ""


## Everyone in the session's names, players then bots.
func _taken_names() -> Array:
	return (loadouts.values() + bots).map(name_in)


## A team in play, and a character that team can play.
func _clamp_loadout(team: int, character: int) -> Array:
	var clamped_team: int = posmod(team, Players.team_count)
	return [clamped_team, Roster.for_team(character, clamped_team)]


## The team of everyone seated, players then bots.
func seat_teams() -> Array[int]:
	var teams: Array[int] = []
	for id: int in peers:
		teams.append(loadout_of(id)[0])
	for bot: Array in bots:
		teams.append(bot[0])
	return teams


## Whether the players and bots are on at least two different teams.
func _teams_split() -> bool:
	return Players.team_split(seat_teams()) != ""


## Call once the match scene has spawned everyone.
func report_loaded() -> void:
	if is_server:
		_mark_loaded(SERVER_ID)
	else:
		_peer_loaded.rpc_id(SERVER_ID)


func _open_connection(request: String, code: String) -> void:
	leave()
	if not is_valid_code(code):
		failed.emit(code_rules())
		return

	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(_server_address(), PORT)
	if err != OK:
		failed.emit("Couldn't connect: %s." % error_string(err))
		return
	multiplayer.multiplayer_peer = peer
	access_code = code
	_request = request
	get_tree().create_timer(JOIN_TIMEOUT).timeout.connect(_on_join_timeout.bind(peer))


func _server_address() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--address="):
			return arg.trim_prefix("--address=")
	return SERVER_ADDRESS


# ===== SERVER =====

func _start_server() -> void:
	get_tree().unload_current_scene()
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(PORT, MAX_CONNECTIONS)
	if err != OK:
		push_error("Couldn't start server on port %d: %s." % [PORT, error_string(err)])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	is_server = true
	for map: MatchMap.Map in MatchMap.MAPS:
		_map_scenes[map] = load(MatchMap.scene_of(map))
	print("Server listening on UDP port %d." % PORT)


## Server: someone won. After LOBBY_RETURN_DELAY, unless the match is gone
## by then (everyone left), end it and send everyone back to the lobby,
## where the session (code, players, picks, bots, format) carries on.
func finish_match() -> void:
	if not is_server or not in_match:
		return
	var scene: Node = get_tree().current_scene
	await get_tree().create_timer(LOBBY_RETURN_DELAY).timeout
	if not in_match or get_tree().current_scene != scene:
		return
	print("Session %s finished its match." % access_code)
	_to_session(_return_to_lobby)
	_broadcast_peers()  # Anything that changed meanwhile (someone left)


## The last player left, so free the session for the next host.
func _close_session() -> void:
	print("Session %s closed." % access_code)
	access_code = ""
	peers.clear()
	loadouts.clear()
	bots.clear()
	Players.set_match_format(Players.TEAM_COUNTS[0], MatchMap.MAPS[0] as MatchMap.Map, MatchMap.DROPS[0] as BossDrop.Kind, 5)
	in_match = false
	match_synced = false
	_loaded.clear()
	_all_loaded_sent = false
	get_tree().unload_current_scene()


## Server: run `method` (a "call_local" RPC) here and on every player in the
## session, but not on machines still connecting or being turned away.
func _to_session(method: Callable, ...args: Array) -> void:
	for id: int in peers:
		if multiplayer.get_peers().has(id):
			method.get_object().callv(&"rpc_id", [id, method.get_method()] + args)
	method.callv(args)


func _broadcast_peers() -> void:
	for id: int in peers:
		# Skip anyone whose connection just dropped but isn't cleaned up yet.
		if multiplayer.get_peers().has(id):
			_sync_peers.rpc_id(id, peers, loadouts, bots, _format())
	peers_changed.emit()


## [team_count, map, boss_drop, score_to_win], as sent to everyone.
func _format() -> Array:
	return [Players.team_count, Players.map, Players.boss_drop, Players.score_to_win]


func _apply_format(format: Array) -> void:
	Players.set_match_format(format[0], format[1], format[2], format[3])


## A new player starts on the smallest team, as the seat's usual character.
func _add_loadout(id: int) -> void:
	var teams: Array[int] = []
	for loadout: Array in loadouts.values() + bots:
		teams.append(loadout[0])
	var team: int = Players.smallest_team(teams)
	loadouts[id] = [team, Roster.for_team(Players.default_character(peers.find(id)), team),
		PlayerNames.random(_taken_names())]


## Tell the joiner why, then drop them (after a beat so the message arrives).
func _reject(id: int, reason: String) -> void:
	_join_rejected.rpc_id(id, reason)
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	await get_tree().create_timer(0.5).timeout
	if multiplayer.multiplayer_peer == peer and peer is ENetMultiplayerPeer and multiplayer.get_peers().has(id):
		(peer as ENetMultiplayerPeer).disconnect_peer(id)


func _mark_loaded(id: int) -> void:
	if not _loaded.has(id):
		_loaded.append(id)
	_check_all_loaded()


## The server's own copy counts too: syncing before it has the players
## would send it updates for nodes it doesn't have yet.
func _check_all_loaded() -> void:
	if _all_loaded_sent or not _loaded.has(SERVER_ID) \
			or not peers.all(func(id: int) -> bool: return _loaded.has(id)):
		return
	_all_loaded_sent = true
	_to_session(_all_loaded)


# ===== CONNECTION EVENTS =====

func _on_connected_to_server() -> void:
	if _request == "host":
		_request_host.rpc_id(SERVER_ID, access_code, PROTOCOL_VERSION)
	else:
		_request_join.rpc_id(SERVER_ID, access_code, PROTOCOL_VERSION)


func _on_connection_failed() -> void:
	if _request:
		_fail("Couldn't reach the server.")


func _on_join_timeout(peer: MultiplayerPeer) -> void:
	if not _request or multiplayer.multiplayer_peer != peer:
		return
	# Connected but never answered: most likely a server too old to
	# understand our request (and too old to say so itself).
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_fail("The server didn't answer. It may be running a different version of the game.")
	else:
		_fail("Couldn't reach the server.")


func _on_server_disconnected() -> void:
	if in_session():
		_end("Lost connection to the server.")
	elif _request:
		_fail("Couldn't reach the server.")


## Server: drop `id` unless it's in the session by SERVER_JOIN_TIMEOUT.
func _on_peer_connected(id: int) -> void:
	if not is_server:
		return
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	await get_tree().create_timer(SERVER_JOIN_TIMEOUT).timeout
	if multiplayer.multiplayer_peer == peer and not peers.has(id) and multiplayer.get_peers().has(id):
		print("Peer %d never joined a session; dropped." % id)
		(peer as ENetMultiplayerPeer).disconnect_peer(id)


func _on_peer_disconnected(id: int) -> void:
	if not is_server or not peers.has(id):
		return
	peers.erase(id)
	loadouts.erase(id)
	print("Peer %d left session %s." % [id, access_code])
	if peers.is_empty():
		_close_session()
		return
	_broadcast_peers()
	if in_match:
		_check_all_loaded()


func _fail(reason: String) -> void:
	leave()
	failed.emit(reason)


## Session dropped out from under us: tidy up and, mid-match, go back to the menu.
func _end(reason: String) -> void:
	leave()
	session_ended.emit(reason)
	var scene: Node = get_tree().current_scene
	if scene and scene.scene_file_path != MAIN_MENU:
		end_reason = reason
		get_tree().change_scene_to_file(MAIN_MENU)


# ===== RPCS: players -> server =====

@rpc("any_peer", "reliable")
func _request_host(code: String, version: int) -> void:
	if not is_server:
		return
	var id: int = multiplayer.get_remote_sender_id()
	if version != PROTOCOL_VERSION:
		_reject(id, _version_mismatch(version))
	elif not is_valid_code(code):
		_reject(id, code_rules())
	elif access_code:
		_reject(id, "The server already has a session going. Try again later.")
	else:
		access_code = code
		peers.assign([id])
		_add_loadout(id)
		print("Peer %d opened session %s." % [id, code])
		_broadcast_peers()


@rpc("any_peer", "reliable")
func _request_join(code: String, version: int) -> void:
	if not is_server:
		return
	var id: int = multiplayer.get_remote_sender_id()
	if version != PROTOCOL_VERSION:
		_reject(id, _version_mismatch(version))
	elif not access_code or code != access_code:
		_reject(id, "No session with that code.")
	elif in_match:
		_reject(id, "That match has already started.")
	elif peers.size() >= MAX_PLAYERS:
		_reject(id, "That session is full.")
	elif not peers.has(id):
		# A person takes a bot's seat if that's all that's left
		if seat_count() >= MAX_PLAYERS:
			bots.pop_back()
		peers.append(id)
		_add_loadout(id)
		print("Peer %d joined session %s." % [id, code])
		_broadcast_peers()


func _version_mismatch(version: int) -> String:
	return "Your game (v%d) doesn't match the server (v%d). %s" % [version, PROTOCOL_VERSION,
		"Update the game." if version < PROTOCOL_VERSION else "The server needs updating."]


@rpc("any_peer", "reliable")
func _request_loadout(team: int, character: int) -> void:
	var id: int = multiplayer.get_remote_sender_id()
	if is_server and not in_match and peers.has(id):
		loadouts[id] = _clamp_loadout(team, character) + [name_in(loadout_of(id))]
		_broadcast_peers()


@rpc("any_peer", "reliable")
func _request_name(text: String) -> void:
	var id: int = multiplayer.get_remote_sender_id()
	if is_server and not in_match and peers.has(id):
		var clean: String = PlayerNames.clean(text)
		var loadout: Array = loadout_of(id)
		loadouts[id] = [loadout[0], loadout[1], clean if clean != "" else PlayerNames.random(_taken_names())]
		_broadcast_peers()


@rpc("any_peer", "reliable")
func _request_team_count(count: int) -> void:
	if _from_leader_in_lobby() and Players.TEAM_COUNTS.has(count):
		Players.set_team_count(count)
		_format_changed()


@rpc("any_peer", "reliable")
func _request_map(map: MatchMap.Map) -> void:
	if _from_leader_in_lobby() and MatchMap.MAPS.has(map):
		Players.set_map(map)
		_format_changed()


@rpc("any_peer", "reliable")
func _request_boss_drop(kind: BossDrop.Kind) -> void:
	if _from_leader_in_lobby() and MatchMap.DROPS.has(kind):
		Players.set_boss_drop(kind)
		_format_changed()


@rpc("any_peer", "reliable")
func _request_score_to_win(score: int) -> void:
	if _from_leader_in_lobby():
		Players.set_score_to_win(score)
		_broadcast_peers()


@rpc("any_peer", "reliable")
func _request_add_bot() -> void:
	if _from_leader_in_lobby() and seat_count() < MAX_PLAYERS:
		var team: int = Players.smallest_team(seat_teams())
		bots.append([team, _unused_character(team), PlayerNames.random(_taken_names())])
		_broadcast_peers()


## The first of `team`'s characters nobody in the session is playing (the
## next in turn if all are).
func _unused_character(team: int) -> int:
	var taken: Array = (loadouts.values() + bots).map(func(loadout: Array) -> int: return loadout[1])
	var choices: Array[int] = Roster.characters_of_team(team)
	for character: int in choices:
		if not taken.has(character):
			return character
	return choices[bots.size() % choices.size()]


@rpc("any_peer", "reliable")
func _request_remove_bot() -> void:
	if _from_leader_in_lobby() and not bots.is_empty():
		bots.pop_back()
		_broadcast_peers()


func _from_leader_in_lobby() -> bool:
	return is_server and not in_match and peers and multiplayer.get_remote_sender_id() == peers[0]


## Teams no longer in play (e.g. a map with fewer sides) wrap around onto
## ones that are, then everyone hears the new format.
func _format_changed() -> void:
	for loadout: Array in loadouts.values() + bots:
		loadout[0] = posmod(loadout[0], Players.team_count)
		loadout[1] = Roster.for_team(loadout[1], loadout[0])
	_broadcast_peers()


@rpc("any_peer", "reliable")
func _request_start() -> void:
	if is_server and not in_match and peers and multiplayer.get_remote_sender_id() == peers[0] \
			and _teams_split():
		print("Session %s started a match with %d players and %d bots in %d teams on %s (%s, first to %d)." % [access_code,
			peers.size(), bots.size(), Players.team_count, MatchMap.name_of(Players.map), MatchMap.drop_name(Players.boss_drop),
			Players.score_to_win])
		_to_session(_start_match, _format(), randi())


@rpc("any_peer", "reliable")
func _peer_loaded() -> void:
	if is_server and in_match:
		_mark_loaded(multiplayer.get_remote_sender_id())


# ===== RPCS: server -> players =====

@rpc("authority", "reliable")
func _join_rejected(reason: String) -> void:
	_fail(reason)


@rpc("authority", "reliable")
func _sync_peers(ids: Array, new_loadouts: Dictionary, new_bots: Array, format: Array) -> void:
	peers.assign(ids)
	loadouts = new_loadouts
	bots = new_bots
	_apply_format(format)
	is_host = peers[0] == multiplayer.get_unique_id()
	var request := _request
	_request = ""
	if request == "host":
		hosted.emit(access_code)
	elif request == "join":
		joined.emit(access_code)
	peers_changed.emit()


@rpc("authority", "call_local", "reliable")
func _start_match(format: Array, match_seed: int) -> void:
	in_match = true
	_apply_format(format)
	Players.match_seed = match_seed
	if is_server:
		get_tree().change_scene_to_packed(_map_scenes[Players.map])
	match_started.emit()


@rpc("authority", "call_local", "reliable")
func _return_to_lobby() -> void:
	in_match = false
	match_synced = false
	if is_server:
		_loaded.clear()
		_all_loaded_sent = false
		get_tree().unload_current_scene()
	else:
		get_tree().change_scene_to_file(MAIN_MENU)
	match_ended.emit()


@rpc("authority", "call_local", "reliable")
func _all_loaded() -> void:
	match_synced = true
	all_loaded.emit()
