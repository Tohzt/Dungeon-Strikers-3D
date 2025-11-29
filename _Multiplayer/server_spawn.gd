extends Node


func spawn_player(peer_id: int) -> void:
	if Player(peer_id):
		var entities_node: Node = get_tree().current_scene.get_node("Entities").get_node(str(peer_id))
		if entities_node:
			var player_node: PlayerClass = entities_node
			var _colors := [Color.MEDIUM_AQUAMARINE, Color.DARK_KHAKI]
			var player_color: Color = _colors[Server.Connected_Clients.size()-1]
			var spawn_position: Vector2 = player_node.spawn_pos
			var spawn_rotation: float = player_node.spawn_rot
			
			if  multiplayer.has_multiplayer_peer() \
			and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
				##TODO: There has to be a way to handle this in the player ready
				player_node.set_pos_and_sprite.rpc_id(peer_id, spawn_position, spawn_rotation, player_color)
				get_tree().current_scene.set_loading.rpc_id(peer_id, false)


func Player(peer_id: int) -> PlayerClass:
	var Game: GameClass = get_tree().current_scene
	var Entities: Node = Game.get_node("Entities")
	var id: int = Server.Connected_Clients.size()-1
	var spawn_point: Marker2D = Game.get_node("Spawn Points").get_child(id)
	var _player: PlayerClass = Global.PLAYER.instantiate()
	_player.name = str(peer_id)
	_player.spawn_pos = spawn_point.global_position
	_player.spawn_rot = spawn_point.rotation
	
	Entities.add_child(_player)
	return _player
