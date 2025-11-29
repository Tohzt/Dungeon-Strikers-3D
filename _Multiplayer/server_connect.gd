extends Node

var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()

# Host Code
func Host(PORT: int, MAX_CLIENTS: int) -> void: 
	_establish_host(PORT, MAX_CLIENTS)
	get_tree().change_scene_to_file(Global.GAME)

func _establish_host(PORT: int, MAX_CLIENTS: int) -> void:
	var error: Error = peer.create_server(PORT, MAX_CLIENTS)
	if error != OK:
		print_debug("Host cannot host: " + str(error))
		return 
	
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(client_connected)
	multiplayer.peer_disconnected.connect(client_disconnected)

func client_connected(peer_id: int) -> void:
	Server.Connected_Clients.append(peer_id)
	Server.Spawn.spawn_player(peer_id)
	
	# Send boss state to new client
	var boss: BossClass = get_tree().get_first_node_in_group("Boss")
	if boss:
		boss.set_color.rpc_id(peer_id, boss.color)

func client_disconnected(peer_id: int) -> void:
	print_debug("Peer " + str(peer_id) + " Disonnected!")


# Client Code
func Client(IP_ADDRESS: String, PORT: int) -> void:
	_establish_client(IP_ADDRESS, PORT)
	get_tree().change_scene_to_file(Global.GAME)

func _establish_client(IP_ADDRESS: String, PORT: int) -> void:
	print_debug("Client connecting to server...")
	var error: Error = peer.create_client(IP_ADDRESS, PORT)
	if error != OK:
		print_debug("Client cannot connect: " + str(error))
		return
	
	multiplayer.multiplayer_peer = peer
	#multiplayer.connected_to_server.connect(_on_connected_to_server)
	#multiplayer.connection_failed.connect(_on_connection_failed)
	#multiplayer.server_disconnected.connect(_on_server_disconnected)
