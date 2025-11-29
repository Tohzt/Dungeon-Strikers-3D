extends CanvasLayer


func _ready() -> void:
	visible = multiplayer.is_server()


func _p1_reset_pos() -> void:
	_reset_player_position(Server.Connected_Clients[0])
func _p2_reset_pos() -> void:
	_reset_player_position(Server.Connected_Clients[1])

func _reset_player_position(peer_id: int) -> void:
	var players: Array = get_tree().get_nodes_in_group("Player")
	for _player: PlayerClass in players:
		_player.rpc_id(peer_id, "reset")

func _spawn_ball() -> void:
	if multiplayer.get_unique_id() != 1: return
	var boss_inst: BossClass = Global.BOSS.instantiate()
	boss_inst.global_position = get_parent().get_node("Spawn Points/Ball Spawn").global_position
	get_parent().get_node("Entities").add_child(boss_inst, true)
	await get_tree().process_frame
	boss_inst.set_color.rpc(Color.RED)
	# var _ball: BallClass = Global.BALL.instantiate()
	# _ball.global_position = get_parent().get_node("Spawn Points/Ball Spawn").global_position
	# get_parent().get_node("Entities").add_child(_ball, true)
