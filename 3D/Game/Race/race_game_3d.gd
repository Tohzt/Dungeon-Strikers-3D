class_name RaceGame3D extends Game3D_Class
## Race mode: kills don't win, getting there first does. Each team starts
## sealed in its own room; after a countdown the gates open together onto
## an arena whose boss holds the key to the rest of the dungeon. Somewhere
## past it is the altar, behind a second boss: the first player to touch
## it wins for their team. Dying is a knockout: you get back up where you
## fell, and each knockout keeps you down longer (Game3D.knockouts).
##
## The level comes from a RaceLayout, built when the match loads (see
## RaceLevel3D), so the map can later be generated instead of hand-made.

## Seconds counted down before the start gates open.
@export_range(0, 10) var countdown: int = 3
## Killing a boss deals its killer this many perk cards on the spot.
@export_range(0, 3) var boss_perk_cards: int = 3

@onready var level: RaceLevel3D = $Level

var layout: RaceLayout


func _ready() -> void:
	layout = RaceLayout.test_layout()
	for problem: String in layout.validate():
		push_error("Race layout: " + problem)
	# Before Game3D sets up, so it finds the bosses, altars and spawn points
	level.build(layout, self)
	super()  # Returns at its first await; the match is set up by then
	scoreboard.set_caption("Race to the altar!")
	if not Net.decides():
		return
	if Net.in_session() and not Net.match_synced:
		await Net.all_loaded
	_begin_race()


## Server/offline: count down everywhere, then open the gates everywhere.
func _begin_race() -> void:
	Net.everywhere(_show_countdown, countdown)
	await get_tree().create_timer(countdown + 1.0).timeout
	Net.everywhere(_open_start_gates)


@rpc("authority", "call_local", "reliable")
func _show_countdown(seconds: int) -> void:
	scoreboard.announce("Find the altar! The gates open soon...", Color.WHITE)
	await get_tree().create_timer(1.0).timeout
	for left in range(seconds, 0, -1):
		scoreboard.announce(str(left), Color(1.0, 0.85, 0.4))
		await get_tree().create_timer(1.0).timeout


@rpc("authority", "call_local", "reliable")
func _open_start_gates() -> void:
	for node: Node in get_tree().get_nodes_in_group("StartGate"):
		if node is Door3D:
			node.open()
	scoreboard.announce("GO!", Color(0.6, 1.0, 0.5))


## Server/offline: `player` touched the finish altar.
func reach_finish(player: PlayerClass3D) -> void:
	if match_over or not Net.decides():
		return
	match_over = true  # Nobody else can win while the news goes out
	Net.everywhere(_race_won, _team_of(player), String(player.name))


@rpc("authority", "call_local", "reliable")
func _race_won(team: int, player_name: String) -> void:
	var player: PlayerClass3D = player_named(player_name)
	if player:
		scoreboard.announce("%s reached the altar!" % _player_label(player), _team_color(team))
	Sfx.play(&"altar_reward", player.global_position if player else Vector3.ZERO)
	_win(team)


## Bots follow the race: each boss in turn (the level lists them in the
## order the route reaches them), then the altar.
func bot_goal(_player: PlayerClass3D) -> Node3D:
	for boss: Boss3D in bosses:
		if is_instance_valid(boss):
			return boss
	return get_node_or_null(^"FinishAltar") as Node3D


## A boss kill pays out right away: there are no intermissions to wait for.
func _reward_boss_kill(killer: PlayerClass3D) -> void:
	if killer and boss_perk_cards > 0:
		perks.grant_bonus_hand(killer, boss_perk_cards)
