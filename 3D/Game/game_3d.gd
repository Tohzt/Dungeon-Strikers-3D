class_name Game3D_Class extends Node3D

signal set_camera_active(TorF: bool)

@export var player_scene: PackedScene
## How many players to seat automatically when no menu has joined anyone
## (controllers first, then keyboard/mouse). Set to 1 for single-player.
@export_range(1, 4) var default_player_count: int = 2
## Indexed by player slot; ordered to match the HUD corners (P1 left,
## P2 right, P3/P4 nearer the camera, i.e. the bottom of the screen).
@export var spawn_points: Array[Vector3] = [
	Vector3(-8, 1, 0), Vector3(8, 1, 0), Vector3(-8, 1, 6), Vector3(8, 1, 6),
]

@onready var ball: Ball3D = $Ball_3D
@onready var HUD: HUD3D = $HUD

var players: Array[PlayerClass3D] = []
## Each player's HUD, so it can go when an online player leaves.
var huds: Dictionary[PlayerClass3D, HUD3D] = {}
## First player, kept for code that only knows about one.
var Player: PlayerClass3D:
	get: return players[0] if not players.is_empty() else null

func _enter_tree() -> void: Global.Game3D = self

func _ready() -> void:
	if Net.in_session():
		_spawn_online_players()
	else:
		if Players.slots.is_empty():
			Players.join_default_devices(default_player_count)
		for slot: PlayerSlot in Players.slots:
			_spawn_player(slot)

	await get_tree().create_timer(3.0).timeout
	set_camera_active.emit(true)


## Online: one player per session seat, named the same on every machine so
## their synchronizers line up. Only our own seat reads local input.
func _spawn_online_players() -> void:
	var my_seat: int = Net.local_seat()
	for seat in Net.peers.size():
		var slot: PlayerSlot = null
		if seat == my_seat and not Players.slots.is_empty():
			slot = Players.slots[0]
		else:
			slot = PlayerSlot.new()
			slot.index = seat
			slot.team = seat
			slot.color = Players.TEAM_COLORS[seat % Players.TEAM_COLORS.size()]
		_spawn_player(slot, Net.peers[seat])
	ball.setup_network()
	for weapon: Weapon3D in weapons():
		weapon.setup_network()
	Net.all_loaded.connect(_on_net_all_loaded)
	Net.peers_changed.connect(_on_net_peers_changed)
	Net.report_loaded()


## peer_id = the online peer that controls this player (0 = local game).
func _spawn_player(slot: PlayerSlot, peer_id: int = 0) -> void:
	var player: PlayerClass3D = player_scene.instantiate()
	player.slot = slot
	player.name = "Player%d" % (slot.index + 1)
	player.position = spawn_points[slot.index % spawn_points.size()]
	if peer_id:
		player.setup_network(peer_id)
	add_child(player)
	if peer_id and not player.is_multiplayer_authority():
		player.set_remote()
	players.append(player)

	# The scene's HUD serves the first player; the rest get copies.
	var hud: HUD3D = HUD if players.size() == 1 else HUD.duplicate()
	if hud != HUD:
		add_child(hud)
	hud.setup(player, slot)
	huds[player] = hud


func _on_net_all_loaded() -> void:
	for player: PlayerClass3D in players:
		player.start_network_sync()


## Loose and held weapons in the arena.
func weapons() -> Array[Weapon3D]:
	var found: Array[Weapon3D] = []
	for child: Node in $Weapons.get_children():
		if child is Weapon3D:
			found.append(child)
	return found


## Online: the player controlled by this peer, if they're still here.
func player_of_peer(peer_id: int) -> PlayerClass3D:
	for player: PlayerClass3D in players:
		if player.get_multiplayer_authority() == peer_id:
			return player
	return null


## An online player left mid-match: remove their player and HUD, dropping
## whatever they held. Every machine does this for itself.
func _on_net_peers_changed() -> void:
	for weapon: Weapon3D in weapons():
		weapon.forget_departed_owner()
	for player: PlayerClass3D in players.duplicate():
		if Net.peers.has(player.get_multiplayer_authority()):
			continue
		if ball.holder == player:
			ball.release(Vector3.ZERO)
		players.erase(player)
		if huds.get(player) != HUD:
			huds[player].queue_free()
		huds.erase(player)
		player.queue_free()


func _process(_delta: float) -> void: pass


## Put the ball back at its starting spot, taking it from whoever holds it.
func reset_ball() -> void:
	if not ball: return
	for player: PlayerClass3D in players:
		if player.held_ball == ball:
			player.drop_ball()
	ball.global_position = ball.starting_position
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
