class_name PitchGame3D extends Game3D_Class
## Pitch mode: soccer with hazards and a boss. The first team to
## goals_to_win goals wins; kills only take someone out of play for a moment.
##
## Before kickoff everyone drafts perks: each player is dealt draft_size
## cards and keeps draft_picks of them, and again at halftime (the first
## time a team reaches half of goals_to_win). Those are the only times play
## stops for perks. Otherwise they're earned as hands to open from the HUD
## whenever you like: a comeback hand for conceding (a bigger one after
## conceding twice running), a striker hand every striker_every goals, and
## for a boss kill, an offense hand for the killer and a mobility hand for
## their teammates. The power-ups are on the field: neutral altars anyone
## can take weapons from.
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
## Halftime's draft: cards dealt, and kept (0 = no halftime draft).
@export_range(1, 8) var halftime_draft_size: int = 4
@export_range(0, 8) var halftime_draft_picks: int = 2
## A team earns a striker hand every this many goals (0 = never).
@export_range(0, 10) var striker_every: int = 2
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

## Halftime's draft has happened (or is on).
var _had_halftime: bool = false
## Server/offline: goals each team has let in without scoring since.
var _conceded_run: Dictionary[int, int] = {}


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


func _on_goal_scored(team: int) -> void:
	_refresh_leader()
	if not Net.decides() or match_over:
		return
	_deal_goal_hands(team)
	var halftime: bool = _is_halftime()
	if halftime:
		_had_halftime = true
		Net.everywhere(_announce_halftime)
	await get_tree().create_timer(kickoff_delay).timeout
	if match_over:
		return
	if halftime:
		perks.begin_draft(halftime_draft_size, halftime_draft_picks)
		if perks.in_draft:
			await perks.draft_finished
	if not match_over:
		Net.everywhere(_kickoff)


## Server/offline: the first time a team gets half of goals_to_win (rounded up).
func _is_halftime() -> bool:
	if _had_halftime or halftime_draft_picks <= 0 or goals_to_win < 2:
		return false
	var half: int = ceili(goals_to_win / 2.0)
	return scores.values().any(func(score: int) -> bool: return score >= half)


@rpc("authority", "call_local", "reliable")
func _announce_halftime() -> void:
	scoreboard.announce("Halftime! Everyone picks perks", Color(0.95, 0.8, 0.4))


## Server/offline: `team` scored. Everyone else gets a comeback hand (a
## bigger one once they've let in two running); `team` gets a striker hand
## every striker_every goals.
func _deal_goal_hands(team: int) -> void:
	_conceded_run[team] = 0
	for other: int in scores:
		if other != team:
			_conceded_run[other] = _conceded_run.get(other, 0) + 1
	var striker: bool = striker_every > 0 and scores.get(team, 0) % striker_every == 0
	for player: PlayerClass3D in players:
		var player_team: int = _team_of(player)
		if player_team == team:
			if striker:
				perks.grant_hand(player, [Perk.Category.STRIKER, Perk.Category.STRIKER, Perk.Category.GENERAL])
		elif _conceded_run.get(player_team, 0) >= 2:
			perks.grant_hand(player, [Perk.Category.COMEBACK, Perk.Category.COMEBACK, Perk.Category.GENERAL])
		else:
			perks.grant_hand(player, [Perk.Category.COMEBACK, Perk.Category.GENERAL])


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


## On every machine. The killer gets an offense hand and their teammates a
## mobility hand, all to open whenever they like.
func _reward_boss_kill(killer: PlayerClass3D) -> void:
	if not killer:
		return
	var team: int = _team_of(killer)
	scoreboard.announce("%s slew the boss! Perks for the %s" % [_player_label(killer), _team_name(team)], _team_color(team))
	if not Net.decides():
		return
	for player: PlayerClass3D in players:
		if player == killer:
			perks.grant_hand(player, [Perk.Category.OFFENSE, Perk.Category.OFFENSE, Perk.Category.OFFENSE])
		elif _team_of(player) == team:
			perks.grant_hand(player, [Perk.Category.MOBILITY, Perk.Category.MOBILITY, Perk.Category.GENERAL])


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
