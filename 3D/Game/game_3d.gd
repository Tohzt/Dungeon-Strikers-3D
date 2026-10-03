class_name Game3D_Class extends Node3D
## The match: the first team to `kills_to_win` player kills wins. Around
## that it runs in rounds: a boss fight, then soccer with the ball the boss
## drops, then (once every ball is scored and no boss is left) an
## intermission where each player picks a perk at their altar, then the
## next, tougher boss.
## A goal is a comeback tool: a team behind on kills takes one back from
## the leader; otherwise it earns a bounty shield that soaks the next
## killing blow on one of its players.

signal set_camera_active(TorF: bool)
## A point was just awarded to `team`. On every machine.
signal goal_scored(team: int)
## The round moved on (see Phase). On every machine.
signal phase_changed(phase: Phase)
## `victim` died; `killer` gets the kill (null = nobody). On every machine.
signal player_killed(victim: PlayerClass3D, killer: PlayerClass3D)
## Someone reached kills_to_win. On every machine.
signal match_won(team: int)

## Matches Players.TEAM_COLORS.
const TEAM_NAMES: Array[String] = ["Blue", "Red", "Green", "Yellow"]
## Which side of the arena each team starts on and defends (its goal and
## altar): Blue left, Red right, Green nearest the camera, Yellow far.
const TEAM_SIDES: Array[Vector3] = [Vector3.LEFT, Vector3.RIGHT, Vector3.BACK, Vector3.FORWARD]

enum Phase {
	BOSS,          ## A boss is alive
	SOCCER,        ## No boss, but a ball is in play
	INTERMISSION,  ## Everything's scored: players pick perks at their altars
}

@export var player_scene: PackedScene
## How many players to seat automatically when no menu has joined anyone
## (controllers first, then keyboard/mouse). Set to 1 for single-player.
@export_range(1, 4) var default_player_count: int = 2
## How far from the middle, towards its own side, each team starts.
@export var spawn_distance: float = 8.0
## Gap between teammates' starting spots.
@export var spawn_spacing: float = 6.0
## Floor for two teams (a goal at each end) and for four (one per side).
@export var field_2p: Texture2D = preload("res://Assets/Textures/soccer field.png")
@export var field_4p: Texture2D = preload("res://Assets/Textures/soccer field 4P.png")

@export var ball_scene: PackedScene = preload("res://3D/ball_3d.tscn")
## Where "Reset Ball" (pause menu) puts every ball.
@export var ball_reset_point: Vector3 = Vector3(0, 4.6, 0)
## Spawned after each intermission.
@export var boss_scene: PackedScene = preload("res://3D/Entities/Boss_Slime/boss.tscn")
@export var boss_spawn_point: Vector3 = Vector3.ZERO
## Each boss after the first has this much more max HP than the one before
## (0.25 = +25%), to keep up with the players' perks.
@export var boss_hp_growth: float = 0.25

@export_group("Kills")
## Player kills a team needs to win the match.
@export_range(1, 20) var kills_to_win: int = 5
## Seconds a killed player sits out before respawning.
@export var respawn_delay: float = 4.0
## Bounty shields a team can bank at once.
@export_range(0, 5) var max_bounty_shields: int = 1
## Offline: seconds after the win before the match restarts.
@export var restart_delay: float = 6.0
@export_group("")

@onready var HUD: HUD3D = $HUD
@onready var scoreboard: Scoreboard3D = $Scoreboard
@onready var perks: PerkDirector = $Perks
@onready var boss_health_bar: BossHealthBar3D = $BossHealthBar
@onready var pause_menu: CanvasLayer = $PauseMenu
@onready var game_camera: Camera3D = $Camera3D
@onready var floor_mesh: MeshInstance3D = $Walls/Floor/CollisionShape3D/MeshInstance3D

## Souls-like third-person camera, while that control scheme is on (Tab).
var souls_camera: SoulsCamera3D = null

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
## Goals per team, for every team that has a goal to attack.
var scores: Dictionary[int, int] = {}
## Player kills per team, for every team in the match. Decides the winner.
var kills: Dictionary[int, int] = {}
## Bounty shields each team has banked (see try_use_shield).
var shields: Dictionary[int, int] = {}
var match_over: bool = false
## First player, kept for code that only knows about one.
var Player: PlayerClass3D:
	get: return players[0] if not players.is_empty() else null

func _enter_tree() -> void: Global.Game3D = self

func _ready() -> void:
	_setup_arena()
	if Net.in_session():
		_spawn_online_players()
	else:
		if Players.slots.is_empty():
			Players.join_default_devices(default_player_count)
		for slot: PlayerSlot in Players.slots:
			_spawn_player(slot)
	_setup_scores()
	for child: Node in get_children():
		if child is Boss3D:
			_track_boss(child)
	perks.intermission_started.connect(_on_intermission_started)
	perks.intermission_finished.connect(_on_intermission_finished)
	_update_phase()
	# Solo/online starts in the souls-like view; Tab switches to top-down
	if not Net.is_server:
		toggle_control_scheme()

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
			slot.team = Players.team_for_seat(seat)
			slot.color = Players.team_color(slot.team)
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
	player.position = _spawn_position(slot)
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


## Where `slot` starts: on its team's side, spread out from its teammates.
func _spawn_position(slot: PlayerSlot) -> Vector3:
	var side: Vector3 = TEAM_SIDES[slot.team % TEAM_SIDES.size()]
	var seat_count: int = Net.peers.size() if Net.in_session() else Players.slots.size()
	var team_size: int = 0
	for seat: int in maxi(seat_count, slot.index + 1):
		if Players.team_for_seat(seat) == slot.team:
			team_size += 1
	var rank: int = slot.index / Players.team_count
	var across: Vector3 = side.cross(Vector3.UP)
	return side * spawn_distance + across * (rank - (team_size - 1) / 2.0) * spawn_spacing + Vector3.UP


## Lay the arena out for Players.team_count: two teams get the 2P field and
## the left/right goals and altars; four get the 4P field and every side's,
## and their goals go to whoever last played the ball (Goal3D.LAST_TOUCH).
## Goals and altars for teams not in the match are removed.
func _setup_arena() -> void:
	var team_count: int = Players.team_count
	var field_material: StandardMaterial3D = floor_mesh.get_active_material(0) as StandardMaterial3D
	if field_material:
		field_material.albedo_texture = field_4p if team_count > 2 else field_2p
	var team_nodes: Array[Node] = get_tree().get_nodes_in_group("Goal")
	for child: Node in get_children():
		if child is Altar3D:
			team_nodes.append(child)
	for node: Node in team_nodes:
		if node.owner_team >= team_count:
			node.get_parent().remove_child(node)
			node.queue_free()
		elif node is Goal3D and team_count > 2:
			node.scoring_team = Goal3D.LAST_TOUCH


## Tab: swap between souls-like third-person controls (the default) and the
## shared top-down camera. Only with a single local player (single-player or
## online); local co-op shares one screen, so it keeps the top-down camera.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_controls") and not event.is_echo():
		toggle_control_scheme()
		get_viewport().set_input_as_handled()


func toggle_control_scheme() -> void:
	var local_players: Array[PlayerClass3D] = []
	for p: PlayerClass3D in players:
		if is_instance_valid(p) and not p.is_remote:
			local_players.append(p)
	if local_players.size() != 1:
		return
	var player: PlayerClass3D = local_players[0]
	if souls_camera:
		souls_camera.queue_free()
		souls_camera = null
		player.set_souls_camera(null)
		game_camera.make_current()
	else:
		souls_camera = SoulsCamera3D.new()
		souls_camera.name = "SoulsCamera"
		souls_camera.player = player
		add_child(souls_camera)
		player.set_souls_camera(souls_camera)
		souls_camera.camera.make_current()


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
		_refresh_leader()
		if huds.get(player) != HUD:
			huds[player].queue_free()
		huds.erase(player)
		player.queue_free()


## Every team with a goal to attack or a player in the match.
func _setup_scores() -> void:
	var teams: Array[int] = []
	for goal: Goal3D in get_tree().get_nodes_in_group("Goal"):
		if goal.scoring_team == Goal3D.LAST_TOUCH:
			continue  # Four teams: only the teams with players are listed
		if not teams.has(goal.scoring_team):
			teams.append(goal.scoring_team)
		scores[goal.scoring_team] = 0
	for player: PlayerClass3D in players:
		if player.slot and not teams.has(player.slot.team):
			teams.append(player.slot.team)
	teams.sort()
	for team: int in teams:
		kills[team] = 0
		shields[team] = 0
	scoreboard.setup(teams, kills_to_win)


## Server/offline: `scored_ball` went into a goal attacked by `team`. Award
## the point everywhere and take that ball out of play.
func score_goal(team: int, scored_ball: Ball3D) -> void:
	if Net.in_session() and not (Net.is_server and Net.match_synced):
		return
	if not balls.has(scored_ball):
		return  # Already counted
	var new_score: int = scores.get(team, 0) + 1
	# Behind on kills: take one back from the leader. Otherwise bank a shield.
	var erased_team: int = _top_team_ahead_of(team)
	if Net.in_session():
		_goal_scored.rpc(team, new_score, scored_ball.name, erased_team)
	else:
		_goal_scored(team, new_score, scored_ball.name, erased_team)


@rpc("authority", "call_local", "reliable")
func _goal_scored(team: int, new_score: int, ball_name: String, erased_team: int) -> void:
	scores[team] = new_score
	var scored_ball: Ball3D = get_node_or_null(ball_name) as Ball3D
	if scored_ball:
		_remove_ball(scored_ball)
	var color: Color = _team_color(team)
	if erased_team >= 0 and not match_over:
		_set_kills(erased_team, kills[erased_team] - 1)
		scoreboard.announce("%s scores! A kill taken back from %s" % [_team_name(team), _team_name(erased_team)], color)
	elif shields.get(team, 0) < max_bounty_shields and not match_over:
		_set_shields(team, shields.get(team, 0) + 1)
		scoreboard.announce("%s scores! Bounty shield earned" % _team_name(team), color)
	else:
		scoreboard.announce("%s scores!" % _team_name(team), color)
	perks.record_goal(team)
	goal_scored.emit(team)
	_update_phase()
	_check_round_over()


## The team with the most kills among those with more than `team`, or -1
## if nobody is ahead of it.
func _top_team_ahead_of(team: int) -> int:
	var best: int = -1
	for other: int in kills:
		if other != team and kills[other] > kills.get(team, 0) and (best < 0 or kills[other] > kills[best]):
			best = other
	return best


# ===== KILLS =====

## Called by a player's owner the moment they die. `killer_name` is the
## opponent who gets the kill ("" = nobody). The server (or offline game)
## decides the result and tells everyone.
func report_death(victim: PlayerClass3D, killer_name: String) -> void:
	if not Net.in_session() or Net.is_server:
		_resolve_death(victim.name, killer_name)
	elif Net.match_synced:
		_request_death.rpc_id(Net.SERVER_ID, killer_name)


@rpc("any_peer", "reliable")
func _request_death(killer_name: String) -> void:
	if not Net.is_server:
		return
	var victim: PlayerClass3D = player_of_peer(multiplayer.get_remote_sender_id())
	if victim:
		_resolve_death(victim.name, killer_name)


func _resolve_death(victim_name: String, killer_name: String) -> void:
	var victim: PlayerClass3D = get_node_or_null(victim_name) as PlayerClass3D
	var killer: PlayerClass3D = get_node_or_null(killer_name) as PlayerClass3D if killer_name != "" else null
	if not victim:
		return
	# No credit for team kills or once the match is decided
	if killer and (match_over or killer == victim or _team_of(killer) == _team_of(victim)):
		killer = null
	var new_kills: int = -1
	var bounty: bool = false
	if killer:
		var team: int = _team_of(killer)
		new_kills = kills.get(team, 0) + 1
		# Headhunter: killing the leader banks a shield
		bounty = killer.perk_stat(&"leader_bounty") > 1.0 and _leading_team() == _team_of(victim)
	var sent_killer: String = String(killer.name) if killer else ""
	if Net.in_session():
		_player_died.rpc(victim_name, sent_killer, new_kills, bounty)
	else:
		_player_died(victim_name, sent_killer, new_kills, bounty)


@rpc("authority", "call_local", "reliable")
func _player_died(victim_name: String, killer_name: String, new_kills: int, bounty: bool) -> void:
	var victim: PlayerClass3D = get_node_or_null(victim_name) as PlayerClass3D
	var killer: PlayerClass3D = get_node_or_null(killer_name) as PlayerClass3D if killer_name != "" else null
	if not victim:
		return
	victim.die()
	if not killer:
		scoreboard.announce("%s went down" % _player_label(victim), Color.WHITE)
		player_killed.emit(victim, null)
		return
	var team: int = _team_of(killer)
	_set_kills(team, new_kills)
	if bounty and shields.get(team, 0) < max_bounty_shields:
		_set_shields(team, shields.get(team, 0) + 1)
	killer.on_kill()
	perks.record_kill(killer)
	scoreboard.announce("%s killed %s" % [_player_label(killer), _player_label(victim)], _team_color(team))
	player_killed.emit(victim, killer)
	if new_kills >= kills_to_win and not match_over:
		_win(team)


func _win(team: int) -> void:
	match_over = true
	scoreboard.show_winner("%s wins!" % _team_name(team), _team_color(team))
	match_won.emit(team)
	if Net.in_session():
		return  # Online the pause menu leaves the match
	await get_tree().create_timer(restart_delay).timeout
	get_tree().reload_current_scene()


## Owner of `player`, on a hit that would give an opponent the kill: if
## their team has a bounty shield, use it up and return true (they live).
func try_use_shield(player: PlayerClass3D) -> bool:
	var team: int = _team_of(player)
	if shields.get(team, 0) <= 0:
		return false
	# Spent here at once, so a second hit before the server replies can't reuse it
	shields[team] -= 1
	if not Net.in_session() or Net.is_server:
		_shield_used(team, shields[team], player.name)
	elif Net.match_synced:
		_request_use_shield.rpc_id(Net.SERVER_ID)
	return true


@rpc("any_peer", "reliable")
func _request_use_shield() -> void:
	if not Net.is_server:
		return
	var player: PlayerClass3D = player_of_peer(multiplayer.get_remote_sender_id())
	if player:
		var team: int = _team_of(player)
		_shield_used.rpc(team, max(shields.get(team, 0) - 1, 0), player.name)


@rpc("authority", "call_local", "reliable")
func _shield_used(team: int, left: int, player_name: String) -> void:
	_set_shields(team, left)
	var player: PlayerClass3D = get_node_or_null(player_name) as PlayerClass3D
	if player:
		scoreboard.announce("%s's bounty shield broke!" % _player_label(player), _team_color(team))


func _set_kills(team: int, value: int) -> void:
	kills[team] = max(value, 0)
	scoreboard.set_kills(team, kills[team])
	_refresh_leader()


func _set_shields(team: int, value: int) -> void:
	shields[team] = max(value, 0)
	scoreboard.set_shields(team, shields[team])


## The team with strictly the most kills, or -1 when nobody leads.
func _leading_team() -> int:
	var best: int = -1
	var tied: bool = false
	for team: int in kills:
		if best < 0 or kills[team] > kills[best]:
			best = team
			tied = false
		elif kills[team] == kills[best]:
			tied = true
	return -1 if tied or best < 0 or kills[best] == 0 else best


## Crown the leading team's players (the boss hunts them too).
func _refresh_leader() -> void:
	var leader: int = _leading_team()
	for player: PlayerClass3D in players:
		if is_instance_valid(player):
			player.set_leader(leader >= 0 and _team_of(player) == leader)


## Players the boss should go after: the leading team's, if any team leads.
func leader_players() -> Array[PlayerClass3D]:
	var found: Array[PlayerClass3D] = []
	var leader: int = _leading_team()
	if leader < 0:
		return found
	for player: PlayerClass3D in players:
		if is_instance_valid(player) and _team_of(player) == leader and not player.is_dead():
			found.append(player)
	return found


func _team_of(player: PlayerClass3D) -> int:
	return player.slot.team if player.slot else 0


func _team_color(team: int) -> Color:
	return Players.TEAM_COLORS[team % Players.TEAM_COLORS.size()]



func _team_name(team: int) -> String:
	return TEAM_NAMES[team % TEAM_NAMES.size()]


func _player_label(player: PlayerClass3D) -> String:
	return "P%d" % (player.slot.index + 1) if player.slot else String(player.name)


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


## Server/offline: `ball` went into a goal without counting (an own goal,
## or nobody had played it yet): back to the middle with it.
func return_ball(ball: Ball3D) -> void:
	if not balls.has(ball):
		return
	ball.last_team = -1
	# Called from the net's physics callback, so move it once the step is done
	_move_ball_to_middle.call_deferred(ball)
	if Net.in_session():
		_ball_returned.rpc()
	else:
		_ball_returned()


func _move_ball_to_middle(ball: Ball3D) -> void:
	if not is_instance_valid(ball):
		return
	ball.global_position = ball_reset_point
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO


@rpc("authority", "call_local", "reliable")
func _ball_returned() -> void:
	scoreboard.announce("No goal! Ball back to the middle", Color.WHITE)


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
