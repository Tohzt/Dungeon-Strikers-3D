class_name PitchGame3D extends Game3D_Class
## Pitch mode: soccer with hazards and a boss. The first team to
## goals_to_win goals wins; kills only take someone out of play for a moment.
## With bombs (see Game3D.bombs) a bomb kicks off instead of the ball, and
## another after each one goes off; blowing up the enemy base wins.
##
## Perks and weapons are all bought with coins at the shop altars (each
## team's in front of its goal, and one in the boss's lair); nothing is
## dealt for free, and play never stops for perks. Everyone starts with
## Game3D.starting_coins, enough for something right away. More come from
## the chests around the field (which fill again after a while), from boss
## kills (boss_coins for the whole team), and from the piles players spill
## when they die (half of what they held).
##
## A boss waits in its lair behind a giant door in the north wall (a
## BossPen3D) until the door opens on a timer. The door stays open while the
## boss is out, so players can run in for the altar and item boxes inside;
## anyone still in there is put out when the next boss arrives. It
## swallows the ball if it gets to it (Boss3D.swallows_ball), and only
## gives it back when beaten. A beaten boss is back in its lair after
## boss_return_time, tougher each time (Game3D.boss_hp_growth). The boss
## and the crown both go after the team leading on goals.
##
## Partway in, towers (Tower3D) start coming up at random spots on the
## field, buried all but their tops. A team claims one by standing around it
## until it's filled with their color; it then rises and works for them.
## Knocking down an enemy tower is worth tower_points goals (or that many
## points' worth of the enemy base, with bombs) and tower_coins each.

## Seconds after a goal before the ball drops in for the next kickoff.
@export var kickoff_delay: float = 3.0
## The first boss's max HP.
@export var boss_hp: float = 900.0
## Seconds after a boss is beaten before the next one is in the pen.
@export var boss_return_time: float = 15.0
@export_group("Towers")
@export var tower_scene: PackedScene = preload("res://3D/Game/Towers/tower.tscn")
## Seconds into the match before the first tower comes up (0 = no towers).
@export var tower_first_time: float = 60.0
## Seconds between towers after that (while there's room for another).
@export var tower_interval: float = 60.0
## Towers on the field at once, claimed or not.
@export var max_towers: int = 2
## Goals for knocking down an enemy tower. With bombs, it takes this many
## points' worth of HP (Bomb3D.BASE_HP_PER_POINT) off their base instead.
@export var tower_points: int = 2
## Coins each for the team that knocks it down.
@export var tower_coins: int = 25
## Towers come up within this far (m) of the middle, along X and Z.
@export var tower_area: Vector2 = Vector2(34, 26)
## And no closer than this to the kickoff spot, another tower, or anything
## else on the field (players, chests, altars, hazards, pickups...).
@export var tower_clearance_middle: float = 10.0
@export var tower_clearance_towers: float = 16.0
@export var tower_clearance: float = 3.0
@export_group("")

## Bots find their way around the pen (and anything else solid) with a
## navigation mesh baked from the nodes in this group (see NavPath).
const NAV_GROUP := "pitch_nav"
## Tries at a random spot for a tower before waiting for the next chance.
const TOWER_SPOT_TRIES := 40

## Names towers, the same on every machine.
var _towers_made: int = 0

@onready var pen: BossPen3D = $BossPen



func _ready() -> void:
	# Made the same way on every machine, before Game3D sets up, so it's
	# tracked like a boss placed in the level
	_bosses_made = 1
	_pen_new_boss("Boss_1", boss_hp)
	_add_navigation()
	goal_scored.connect(_on_goal_scored)
	bomb_detonated.connect(_on_bomb_detonated)
	super()  # Returns at its first await; the match is set up by then
	if not Net.decides():
		return
	if Net.in_session() and not Net.match_synced:
		await Net.all_loaded
	if not match_over:
		_send_kickoff()
		_run_towers()


## Server/offline: kick off everywhere, with a bomb of a random type if
## it's a bomb match.
func _send_kickoff() -> void:
	Net.everywhere(_kickoff, randi() % Bomb3D.Type.size())


## Drop a ball (or a bomb of `bomb_type`) in the middle of the field.
@rpc("authority", "call_local", "reliable")
func _kickoff(bomb_type: int) -> void:
	var ball: Ball3D = spawn_ball(ball_reset_point, Vector3.ZERO, BossDrop.Kind.BOMB if bombs else BossDrop.Kind.BALL)
	if ball is Bomb3D:
		ball.setup(bomb_type as Bomb3D.Type, Bomb3D.FUSE_TIME)
		scoreboard.announce("Kickoff! A %s bomb, %ds on the fuse" % [Bomb3D.NAMES[bomb_type], Bomb3D.FUSE_TIME],
			Bomb3D.COLORS[bomb_type])
	else:
		scoreboard.announce("Kickoff!", Color(0.6, 1.0, 0.5))


func _on_goal_scored(_team: int) -> void:
	_refresh_leader()
	if not Net.decides() or match_over:
		return
	if not bombs:
		_next_kickoff()  # A bomb kicks off once it's gone off (see _on_bomb_detonated)


## A bomb went off, in a goal or out on the field: the next one.
func _on_bomb_detonated(_defender: int) -> void:
	if Net.decides() and not match_over:
		_next_kickoff()


## Server/offline: kickoff_delay after the ball's gone, the next kickoff.
func _next_kickoff() -> void:
	await get_tree().create_timer(kickoff_delay).timeout
	if not match_over:
		_send_kickoff()


## Baked from the walls, the altars, the chests and the pen with its gate
## shut, so bots walk around them and never route into the pen.
func _add_navigation() -> void:
	$Walls.add_to_group(NAV_GROUP)
	pen.add_to_group(NAV_GROUP)
	for child: Node in get_children():
		if child is Altar3D or child is Chest3D:
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


## Bake the navigation again (a tower came up or went), so bots walk round
## what's there now.
func _rebake_navigation() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	var nav: AutoBakeNavigation3D = get_node_or_null("Navigation") as AutoBakeNavigation3D
	if nav and not nav.is_baking():
		nav.bake_navigation_mesh(true)


# ===== TOWERS =====

## Server/offline: after tower_first_time, a tower now and then while
## there's room for one.
func _run_towers() -> void:
	if tower_first_time <= 0.0 or not tower_scene:
		return
	await get_tree().create_timer(tower_first_time).timeout
	while is_inside_tree() and not match_over:
		if Tower3D.standing(get_tree()).size() < max_towers:
			var spot: Variant = _tower_spot()
			if spot != null:
				_towers_made += 1
				Net.everywhere(_raise_tower, "Tower%d" % _towers_made, spot, randi() % Tower3D.Kind.size())
		await get_tree().create_timer(tower_interval).timeout


## Server/offline: a random spot on the field with room for a tower, or
## null if none turned up.
func _tower_spot() -> Variant:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape := CylinderShape3D.new()
	shape.height = 3.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collide_with_areas = true
	query.collision_mask = 0xFFFFFFFF
	var probe: Tower3D = tower_scene.instantiate()
	shape.radius = probe.capture_radius * 0.5 + tower_clearance
	probe.free()
	for i in TOWER_SPOT_TRIES:
		var spot := Vector3(randf_range(-tower_area.x, tower_area.x), 0.0, randf_range(-tower_area.y, tower_area.y))
		if Vector2(spot.x, spot.z).length() < tower_clearance_middle:
			continue
		var crowded: bool = false
		for tower: Tower3D in Tower3D.standing(get_tree()):
			if tower.global_position.distance_to(Vector3(spot.x, tower.global_position.y, spot.z)) < tower_clearance_towers:
				crowded = true
		# Hazards' areas are on no layer, so the query below can't see them
		for hazard: Node in $Hazards.get_children():
			if hazard is Node3D and &"size" in hazard:
				var half: Vector2 = hazard.size * 0.5 + Vector2.ONE * shape.radius
				var offset: Vector3 = spot - hazard.global_position
				crowded = crowded or (absf(offset.x) < half.x and absf(offset.z) < half.y)
		# Nor can it see item boxes (also on no layer)
		for box: Node in get_tree().get_nodes_in_group("ItemBox"):
			var off: Vector3 = spot - (box as Node3D).global_position
			crowded = crowded or Vector2(off.x, off.z).length() < shape.radius + 1.5
		if crowded:
			continue
		# Clear of the floor (its top is at 0), touching anything standing there
		query.transform = Transform3D(Basis(), spot + Vector3.UP * (shape.height * 0.5 + 0.1))
		if space.intersect_shape(query, 1).is_empty():
			return spot
	return null


## Every machine: a tower of `kind` comes up (buried) at `spot`.
@rpc("authority", "call_local", "reliable")
func _raise_tower(tower_name: String, spot: Vector3, kind: int) -> void:
	var tower: Tower3D = tower_scene.instantiate()
	tower.name = tower_name
	tower.kind = kind as Tower3D.Kind
	add_child(tower)
	tower.position = Vector3(spot.x, tower.position.y, spot.z)  # As deep as its scene has it
	tower.add_to_group(NAV_GROUP)
	tower.fell.connect(_on_tower_fell.bind(tower))
	_rebake_navigation()
	Sfx.play(&"boss_stomp", tower.global_position)
	Vfx.play(&"smoke", tower.global_position, Vector3.FORWARD, false, 6.0)
	scoreboard.call_out("A %s appears!" % Tower3D.NAMES[tower.kind], Color(0.95, 0.85, 0.6))
	scoreboard.announce("A %s broke through the field! Stand by it to claim it" % Tower3D.NAMES[tower.kind],
		Color(0.95, 0.85, 0.6))


## Every machine: `tower` was knocked down by `by_team`. The server works
## out what they get.
func _on_tower_fell(by_team: int, tower: Tower3D) -> void:
	tower.remove_from_group(NAV_GROUP)
	tower.tree_exited.connect(_rebake_navigation)
	if not Net.decides() or match_over or by_team < 0 or by_team == tower.owner_team:
		return
	var owner_team: int = tower.owner_team
	var new_value: int
	if bombs:
		new_value = maxi(base_hp.get(owner_team, 0) - tower_points * Bomb3D.BASE_HP_PER_POINT, 0)
	else:
		new_value = scores.get(by_team, 0) + tower_points
	Net.everywhere(_tower_reward, by_team, owner_team, Tower3D.NAMES[tower.kind], new_value)
	if tower_coins > 0:
		Net.everywhere(_award_team_coins, by_team, tower_coins, tower.global_position + Vector3.UP * 4.0)


## Every machine: `team` knocked down `owner_team`'s tower. `new_value` is
## their goals now, or with bombs the HP left in the owner's base.
@rpc("authority", "call_local", "reliable")
func _tower_reward(team: int, owner_team: int, tower_name: String, new_value: int) -> void:
	var color: Color = _team_color(team)
	scoreboard.call_out("%s TOPPLED!" % tower_name.to_upper(), color)
	if bombs:
		base_hp[owner_team] = new_value
		scoreboard.set_score(owner_team, new_value)
		scoreboard.announce("The %s toppled the %s' %s! Their base shakes" % [_team_name(team), _team_name(owner_team), tower_name], color)
		if new_value <= 0 and not match_over:
			_win(team, "The %s base is destroyed!" % _team_name(owner_team))
		return
	scores[team] = new_value
	if goals_to_win > 0:
		scoreboard.set_score(team, new_value)
	scoreboard.announce("The %s toppled the %s' %s! +%d goals" % [_team_name(team), _team_name(owner_team), tower_name, tower_points], color)
	_refresh_leader()
	if goals_to_win > 0 and new_value >= goals_to_win and not match_over:
		_win(team)


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


## On every machine. No perks: the killer's team gets boss_coins each
## (see Game3D._on_boss_defeated) to spend at the shop.
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
