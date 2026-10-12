class_name PitchGame3D extends Game3D_Class
## Pitch mode: soccer with hazards and a boss. The first team to
## goals_to_win goals wins; kills only take someone out of play for a moment.
##
## Before kickoff everyone drafts perks: each player is dealt draft_size
## cards and keeps draft_picks of them. After that, the power-ups are on
## the field: neutral altars anyone can take weapons from.
##
## A boss waits in its lair behind a giant door in the north wall (a
## BossPen3D) until the door opens on a timer. The door stays open while the
## boss is out, so players can run in for the altar and item boxes inside;
## anyone still in there is put out when the next boss arrives. It
## swallows the ball if it gets to it (Boss3D.swallows_ball), and only
## gives it back when beaten. A beaten boss is back in its lair after
## boss_return_time, tougher each time (Game3D.boss_hp_growth). The boss
## and the crown both go after the team leading on goals.

## Cards each player is dealt before kickoff.
@export_range(1, 8) var draft_size: int = 5
## Cards each player keeps from them (0 = no draft).
@export_range(0, 8) var draft_picks: int = 2
## Seconds after a goal before the ball drops in for the next kickoff.
@export var kickoff_delay: float = 3.0
## The first boss's max HP.
@export var boss_hp: float = 900.0
## Seconds after a boss is beaten before the next one is in the pen.
@export var boss_return_time: float = 15.0

## Bots find their way around the pen (and anything else solid) with a
## navigation mesh baked from the nodes in this group (see NavPath).
const NAV_GROUP := "pitch_nav"

@onready var pen: BossPen3D = $BossPen


func _ready() -> void:
	# Made the same way on every machine, before Game3D sets up, so it's
	# tracked like a boss placed in the level
	_bosses_made = 1
	_pen_new_boss("Boss_1", boss_hp)
	_add_navigation()
	goal_scored.connect(_on_goal_scored)
	super()  # Returns at its first await; the match is set up by then
	if not Net.decides():
		return
	if Net.in_session() and not Net.match_synced:
		await Net.all_loaded
	if draft_picks > 0:
		perks.begin_draft(draft_size, draft_picks)
		if perks.in_draft:
			await perks.draft_finished
	if not match_over:
		Net.everywhere(_kickoff)


## Drop a ball in the middle of the field.
@rpc("authority", "call_local", "reliable")
func _kickoff() -> void:
	spawn_ball(ball_reset_point, Vector3.ZERO, BossDrop.Kind.BALL)
	scoreboard.announce("Kickoff!", Color(0.6, 1.0, 0.5))


func _on_goal_scored(_team: int) -> void:
	_refresh_leader()
	if not Net.decides() or match_over:
		return
	await get_tree().create_timer(kickoff_delay).timeout
	if not match_over:
		Net.everywhere(_kickoff)


## Baked from the walls, the altars and the pen with its gate shut, so
## bots walk around them and never route into the pen.
func _add_navigation() -> void:
	$Walls.add_to_group(NAV_GROUP)
	pen.add_to_group(NAV_GROUP)
	for child: Node in get_children():
		if child is Altar3D:
			child.add_to_group(NAV_GROUP)
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	mesh.geometry_source_group_name = NAV_GROUP
	mesh.agent_radius = 0.5
	mesh.agent_height = 2.0
	mesh.agent_max_climb = 0.25
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	var nav := AutoBakeNavigation3D.new()
	nav.name = "Navigation"
	nav.navigation_mesh = mesh
	add_child(nav)


# ===== BOSS =====

## A new boss, shut in the pen.
func _pen_new_boss(boss_name: String, max_hp: float) -> Boss3D:
	var boss: Boss3D = boss_scene.instantiate()
	boss.name = boss_name
	boss.max_hp = max_hp
	boss.drop = BossDrop.Kind.NONE
	boss.swallows_ball = true
	boss.wait_for_players = true
	boss.position = pen.position
	add_child(boss)
	pen.shut(boss)
	return boss


@rpc("authority", "call_local", "reliable")
func _spawn_penned_boss(boss_name: String, max_hp: float) -> void:
	_track_boss(_pen_new_boss(boss_name, max_hp))
	_update_phase()
	scoreboard.announce("Something stirs behind the door...", Color(1.0, 0.45, 0.35))


func _on_boss_defeated(killer: PlayerClass3D, boss: Boss3D) -> void:
	super(killer, boss)
	if Net.decides() and not match_over:
		_return_boss()


## Server/offline: a fresh, tougher boss in the pen after a while.
func _return_boss() -> void:
	await get_tree().create_timer(boss_return_time).timeout
	if match_over:
		return
	boss_round += 1
	_bosses_made += 1
	var hp: float = boss_hp * pow(1.0 + boss_hp_growth, boss_round - 1)
	Net.everywhere(_spawn_penned_boss, "Boss_%d" % _bosses_made, hp)


## Perks only come from the draft here, so a boss kill is just announced.
func _reward_boss_kill(killer: PlayerClass3D) -> void:
	if killer:
		scoreboard.announce("%s slew the boss!" % _player_label(killer), _team_color(_team_of(killer)))


## Item boxes (in the lair) roll wilder items for a team that's behind on
## goals, and tamer ones for a team that's ahead.
func item_luck(player: PlayerClass3D) -> float:
	var team: int = _team_of(player)
	var best_other: int = 0
	for other: int in scores:
		if other != team:
			best_other = max(best_other, scores[other])
	return clampf(0.5 + 0.2 * (best_other - scores.get(team, 0)), 0.1, 1.0)


## The team with strictly the most goals, or -1 when nobody leads.
func _leading_team() -> int:
	var best: int = -1
	var tied: bool = false
	for team: int in scores:
		if best < 0 or scores[team] > scores[best]:
			best = team
			tied = false
		elif scores[team] == scores[best]:
			tied = true
	return -1 if tied or best < 0 or scores[best] == 0 else best
