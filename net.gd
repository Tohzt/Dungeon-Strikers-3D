extends Node
## Online play through the dedicated server on the droplet.
##
## Menus only talk to this autoload, never to ENet directly. A headless copy
## of the game runs on the droplet (started with `-- --server`) and holds one
## session at a time: the first player to host claims it with their code,
## friends join with the same code, and whoever got in first is the leader
## who starts the match. The server isn't a player; it checks codes, relays
## everyone's player syncing, and frees the session when the last player
## leaves.
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
## Every machine has loaded the match scene, so player syncing can begin.
signal all_loaded

## Random codes skip look-alikes (O/0, I/1) so they are easy to read out.
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const RANDOM_CODE_LENGTH := 6
const MIN_CODE_LENGTH := 4
const MAX_CODE_LENGTH := 8
const MAX_PLAYERS := 4
const JOIN_TIMEOUT := 8.0
const MAIN_MENU := "res://Menus/MainMenu/main_menu.tscn"
const MATCH_SCENE := "res://3D/Game/Game3D.tscn"

## The droplet. Override with `-- --address=<ip>` to test elsewhere.
const SERVER_ADDRESS := "64.225.4.250"
const PORT := 25565
## A few spare connections past a full session, so extra joiners can be
## told why they were turned away instead of just timing out.
const MAX_CONNECTIONS := MAX_PLAYERS + 4
const SERVER_ID := 1

var access_code := ""
## Whether we lead the session (first in), which lets us start the match.
var is_host := false
## Verified players' peer ids in seat order (leader first). Never the server.
var peers: Array[int] = []
var in_match := false
## Every machine has the match scene loaded, so match nodes (players, ball,
## weapons) can send each other updates without hitting missing nodes.
var match_synced := false
## True on the headless server.
var is_server := false

## While connecting, what we asked the server for: "host" or "join".
var _request := ""
## Server only: machines that have finished loading the match scene.
var _loaded: Array[int] = []
var _all_loaded_sent := false
## Server only: the match scene, loaded once at startup so Start is quick.
var _match_scene: PackedScene


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if OS.has_feature("dedicated_server") or OS.get_cmdline_user_args().has("--server"):
		# Deferred so the main menu finishes loading before we drop it.
		_start_server.call_deferred()


func in_session() -> bool:
	return not peers.is_empty()


## Our seat (0 = leader), which is also our player index in the match.
func local_seat() -> int:
	return peers.find(multiplayer.get_unique_id())


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
	in_match = false
	match_synced = false
	_request = ""


## Leader only: ask the server to send everyone into the match.
func start_match() -> void:
	if is_host:
		_request_start.rpc_id(SERVER_ID)


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
	_match_scene = load(MATCH_SCENE)
	print("Server listening on UDP port %d." % PORT)


## The last player left, so free the session for the next host.
func _close_session() -> void:
	print("Session %s closed." % access_code)
	access_code = ""
	peers.clear()
	in_match = false
	match_synced = false
	_loaded.clear()
	_all_loaded_sent = false
	get_tree().unload_current_scene()


func _broadcast_peers() -> void:
	for id: int in peers:
		# Skip anyone whose connection just dropped but isn't cleaned up yet.
		if multiplayer.get_peers().has(id):
			_sync_peers.rpc_id(id, peers)
	peers_changed.emit()


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
	_all_loaded.rpc()


# ===== CONNECTION EVENTS =====

func _on_connected_to_server() -> void:
	if _request == "host":
		_request_host.rpc_id(SERVER_ID, access_code)
	else:
		_request_join.rpc_id(SERVER_ID, access_code)


func _on_connection_failed() -> void:
	if _request:
		_fail("Couldn't reach the server.")


func _on_join_timeout(peer: MultiplayerPeer) -> void:
	if _request and multiplayer.multiplayer_peer == peer:
		_fail("Couldn't reach the server.")


func _on_server_disconnected() -> void:
	if in_session():
		_end("Lost connection to the server.")
	elif _request:
		_fail("Couldn't reach the server.")


func _on_peer_disconnected(id: int) -> void:
	if not is_server or not peers.has(id):
		return
	peers.erase(id)
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
		get_tree().change_scene_to_file(MAIN_MENU)


# ===== RPCS: players -> server =====

@rpc("any_peer", "reliable")
func _request_host(code: String) -> void:
	if not is_server:
		return
	var id: int = multiplayer.get_remote_sender_id()
	if not is_valid_code(code):
		_reject(id, code_rules())
	elif access_code:
		_reject(id, "The server already has a session going. Try again later.")
	else:
		access_code = code
		peers.assign([id])
		print("Peer %d opened session %s." % [id, code])
		_broadcast_peers()


@rpc("any_peer", "reliable")
func _request_join(code: String) -> void:
	if not is_server:
		return
	var id: int = multiplayer.get_remote_sender_id()
	if not access_code or code != access_code:
		_reject(id, "No session with that code.")
	elif in_match:
		_reject(id, "That match has already started.")
	elif peers.size() >= MAX_PLAYERS:
		_reject(id, "That session is full.")
	elif not peers.has(id):
		peers.append(id)
		print("Peer %d joined session %s." % [id, code])
		_broadcast_peers()


@rpc("any_peer", "reliable")
func _request_start() -> void:
	if is_server and not in_match and peers and multiplayer.get_remote_sender_id() == peers[0]:
		print("Session %s started a match with %d players." % [access_code, peers.size()])
		_start_match.rpc()


@rpc("any_peer", "reliable")
func _peer_loaded() -> void:
	if is_server and in_match:
		_mark_loaded(multiplayer.get_remote_sender_id())


# ===== RPCS: server -> players =====

@rpc("authority", "reliable")
func _join_rejected(reason: String) -> void:
	_fail(reason)


@rpc("authority", "reliable")
func _sync_peers(ids: Array) -> void:
	peers.assign(ids)
	is_host = peers[0] == multiplayer.get_unique_id()
	var request := _request
	_request = ""
	if request == "host":
		hosted.emit(access_code)
	elif request == "join":
		joined.emit(access_code)
	peers_changed.emit()


@rpc("authority", "call_local", "reliable")
func _start_match() -> void:
	in_match = true
	if is_server:
		get_tree().change_scene_to_packed(_match_scene)
	match_started.emit()


@rpc("authority", "call_local", "reliable")
func _all_loaded() -> void:
	match_synced = true
	all_loaded.emit()
