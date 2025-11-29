## TODO: Delete offline node on server connection
extends Node

func Play() -> void:
	Server.OFFLINE = true
	_enter_weapon_select()
	#get_tree().change_scene_to_file(Global.GAME)
	#await get_tree().tree_changed
	#Spawn_Player()


func _enter_weapon_select() -> void:
	var player: PlayerClass = get_tree().get_first_node_in_group("Player")
	player.EB._is_active(true)
	player.EB.has_control = true
	pass


func Spawn_Player() -> void:
	var Game: GameClass = get_tree().current_scene
	if !Game: return
	
	var player: PlayerClass = Global.PLAYER.instantiate()
	Game.Entities.add_child(player)
	var player_spawn_pos: Vector2 = Game.Spawn_Points.Player_One.global_position
	var player_spawn_col: Color = Color(randf(), randf(), randf())
	player.set_pos_and_sprite(player_spawn_pos, 0.0, player_spawn_col)
	
	var boss: BossClass = Global.BOSS.instantiate()
	Game.Entities.add_child(boss)
	var boss_spawn_pos: Vector2 = Game.Spawn_Points.Ball.global_position
	var col_redish := randf()
	var boss_spawn_col: Color = Color(col_redish, col_redish/2, col_redish/2)
	boss.reset_position(boss_spawn_pos)
	boss.set_color(boss_spawn_col)   
	boss.set_hand_color(boss_spawn_col) 
	
