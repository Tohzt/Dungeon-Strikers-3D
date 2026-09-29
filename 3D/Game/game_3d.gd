class_name Game3D_Class extends Node3D
## The match. It runs in rounds: a boss fight, then soccer with the ball the
## boss drops, then (once every ball is scored and no boss is left) an
## intermission where each player picks a perk at their altar, then the
## next, tougher boss.

signal set_camera_active(TorF: bool)
## A point was just awarded to `team`. On every machine.
signal goal_scored(team: int)
## The round moved on (see Phase). On every machine.
signal phase_changed(phase: Phase)

enum Phase {
	BOSS,          ## A boss is alive
	SOCCER,        ## No boss, but a ball is in play
	INTERMISSION,  ## Everything's scored: players pick perks at their altars
}

@export var player_scene: PackedScene
## How many players to seat automatically when no menu has joined anyone
## (controllers first, then keyboard/mouse). Set to 1 for single-player.
@export_range(1, 4) var default_player_count: int = 2
## Indexed by player slot; ordered to match the HUD corners (P1 left,
## P2 right, P3/P4 nearer the camera, i.e. the bottom of the screen).
@export var spawn_points: Array[Vector3] = [
	Vector3(-8, 1, 0), Vector3(8, 1, 0), Vector3(-8, 1, 6), Vector3(8, 1, 6),
]

@export var ball_scene: PackedScene = preload("res://3D/ball_3d.tscn")
## Where "Reset Ball" (pause menu) puts every ball.
@export var ball_reset_point: Vector3 = Vector3(0, 4.6, 0)
## Spawned after each intermission.
@export var boss_scene: PackedScene = preload("res://3D/Entities/Boss/boss.tscn")
@export var boss_spawn_point: Vector3 = Vector3.ZERO
## Each boss after the first has this much more max HP than the one before
## (0.25 = +25%), to keep up with the players' perks.
@export var boss_hp_growth: float = 0.25

@onready var HUD: HUD3D = $HUD
@onready var scoreboard: Scoreboard3D = $Scoreboard
@onready var perks: PerkDirector = $Perks
@onready var boss_health_bar: BossHealthBar3D = $BossHealthBar

var phase: Phase = Phase.BOSS
## Balls in play (bosses drop them; scoring removes them).
var balls: Array[Ball3D] = []
## Bosses still fighting.
var bosses: Array[Boss3D] = []
## Which boss fight this is, counting from 1.
var boss_round: int = 1
## Names new balls/bosses, the same on every machine.
var _balls_made: int = 0
var _bosses_made: int = 0

var players: Array[PlayerClass3D] = []
## Each player's HUD, so it can go when an online player leaves.
var huds: Dictionary[PlayerClass3D, HUD3D] = {}
## Points per team, for every team that has a goal to attack.
var scores: Dictionary[int, int] = {}
## First player, kept for code that only knows about one.
var Player: PlayerClass3D:
	get: return players[0] if not players.is_empty() else null

func _enter_tree() -> void: Global.Game3D = self

func _ready() -> void:
	_setup_scores()
	if Net.in_session():
		_spawn_online_players()
	else:
		if Players.slots.is_empty():
			Players.join_default_devices(default_player_count)
		for slot: PlayerSlot in Players.slots:
			_spawn_player(slot)
	for child: Node in get_children():
		if child is Boss3D:
			_track_boss(child)
	perks.intermission_started.connect(_on_intermission_started)
	perks.intermission_finished.connect(_on_intermission_finished)
	_update_phase()

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


## A weapon made mid-match (e.g. taken off a stand) joins the others, so
## it's looked after like them when its owner leaves.
func add_weapon(weapon: Weapon3D) -> void:
	$Weapons.add_child(weapon)


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
		for ball: Ball3D in balls:
			if ball.holder == player:
				ball.release(Vector3.ZERO)
		perks.forget_player(player)
		players.erase(player)
		if huds.get(player) != HUD:
			huds[player].queue_free()
		huds.erase(player)
		player.queue_free()


func _process(_delta: float) -> void: pass


func _setup_scores() -> void:
	var teams: Array[int] = []
	for goal: Goal3D in get_tree().get_nodes_in_group("Goal"):
		if not teams.has(goal.scoring_team):
			teams.append(goal.scoring_team)
	teams.sort()
	for team: int in teams:
		scores[team] = 0
	scoreboard.setup(teams)


## Server/offline: `scored_ball` went into a goal attacked by `team`. Award
## the point everywhere and take that ball out of play.
func score_goal(team: int, scored_ball: Ball3D) -> void:
	if Net.in_session() and not (Net.is_server and Net.match_synced):
		return
	if not balls.has(scored_ball):
		return  # Already counted
	var new_score: int = scores.get(team, 0) + 1
	if Net.in_session():
		_goal_scored.rpc(team, new_score, scored_ball.name)
	else:
		_goal_scored(team, new_score, scored_ball.name)


@rpc("authority", "call_local", "reliable")
func _goal_scored(team: int, new_score: int, ball_name: String) -> void:
	scores[team] = new_score
	scoreboard.set_score(team, new_score)
	var scored_ball: Ball3D = get_node_or_null(ball_name) as Ball3D
	if scored_ball:
		_remove_ball(scored_ball)
	perks.record_goal(team)
	goal_scored.emit(team)
	_update_phase()
	_check_round_over()


# ===== BALLS =====

## A new ball enters play at `pos`, launched with `impulse` (by whoever
## simulates it). Call on every machine, in the same order (e.g. from a
## boss's defeat), so the balls get the same names everywhere.
func spawn_ball(pos: Vector3, impulse: Vector3) -> Ball3D:
	_balls_made += 1
	var new_ball: Ball3D = ball_scene.instantiate()
	new_ball.name = "Ball%d" % _balls_made
	new_ball.position = pos
	balls.append(new_ball)
	# Often called mid physics step (a hit's callback), when bodies can't be added
	_add_ball.call_deferred(new_ball, impulse)
	_update_phase()
	return new_ball


func _add_ball(new_ball: Ball3D, impulse: Vector3) -> void:
	add_child(new_ball)
	if Net.in_session():
		new_ball.setup_network()
	if not Net.in_session() or Net.is_server:
		new_ball.apply_central_impulse(impulse)


func _remove_ball(old_ball: Ball3D) -> void:
	if old_ball.holder:
		old_ball.release(Vector3.ZERO)
	balls.erase(old_ball)
	old_ball.queue_free()


## Put every ball back in the middle, taking them from whoever holds them.
func reset_ball() -> void:
	for ball: Ball3D in balls:
		if ball.holder:
			ball.holder.drop_ball()
		ball.global_position = ball_reset_point
		ball.linear_velocity = Vector3.ZERO
		ball.angular_velocity = Vector3.ZERO


# ===== BOSSES & ROUNDS =====

func _track_boss(boss: Boss3D) -> void:
	bosses.append(boss)
	boss.defeated.connect(_on_boss_defeated.bind(boss))
	boss_health_bar.bind(boss)


func _on_boss_defeated(killer: PlayerClass3D, boss: Boss3D) -> void:
	bosses.erase(boss)
	perks.record_boss_kill(killer)
	_update_phase()
	_check_round_over()


## Server/offline: once no boss is left and every ball has been scored,
## it's time to pick perks.
func _check_round_over() -> void:
	if Net.in_session() and not Net.is_server:
		return
	if phase != Phase.INTERMISSION and bosses.is_empty() and balls.is_empty():
		perks.begin_intermission()


func _on_intermission_started() -> void:
	_set_phase(Phase.INTERMISSION)


## Everyone has picked: bring on the next boss.
func _on_intermission_finished() -> void:
	boss_round += 1
	if Net.in_session() and not Net.is_server:
		return
	_bosses_made += 1
	var boss_name: String = "Boss_%d" % _bosses_made
	var probe: Boss3D = boss_scene.instantiate()
	var hp: float = probe.max_hp * pow(1.0 + boss_hp_growth, boss_round - 1)
	probe.free()
	if Net.in_session():
		_spawn_boss.rpc(boss_name, hp)
	else:
		_spawn_boss(boss_name, hp)


@rpc("authority", "call_local", "reliable")
func _spawn_boss(boss_name: String, max_hp: float) -> void:
	var boss: Boss3D = boss_scene.instantiate()
	boss.name = boss_name
	boss.max_hp = max_hp
	boss.position = boss_spawn_point
	add_child(boss)
	_track_boss(boss)
	_set_phase(Phase.BOSS)


func _update_phase() -> void:
	if phase == Phase.INTERMISSION:
		return  # Only the perk picks end this
	_set_phase(Phase.BOSS if not bosses.is_empty() else Phase.SOCCER)


func _set_phase(new_phase: Phase) -> void:
	if new_phase == phase:
		return
	phase = new_phase
	phase_changed.emit(phase)
