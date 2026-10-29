class_name BotInputHandler3D extends PlayerInputHandler3D
## A computer player: instead of reading a device, it decides what to do
## and sets the same fields a person's input would (move_dir, look_dir,
## the Attack/Throw/Guard buttons, interact), so the player plays it exactly
## like anyone else. Game3D swaps it in for slots with is_bot; online the
## server runs every bot.
##
## Each think picks a goal - get a weapon, fight, pick up the ball and run
## it at the other team's goal (or a skull home to our altar), pick a perk -
## and every frame steers toward it.

## Seconds between decisions (a little random, so bots don't move in lockstep).
const THINK_TIME := 0.15
## How close to get to a melee target before swinging.
const MELEE_RANGE := 2.2
## Bosses are big: swing from a bit further out.
const BOSS_RANGE := 3.5
## Towers (Tower3D) are bigger still: swing from this far from the middle.
const TOWER_RANGE := 3.5
## Ranged weapons (that don't swing) hang back this far.
const RANGED_RANGE := 10.0
## An enemy this close gets fought even mid-objective.
const THREAT_RANGE := 4.0
## How far the bot will go for a loose weapon or a stand.
const WEAPON_SEARCH_RANGE := 30.0
## How far the bot will go for a pile of coins (see CoinPile3D).
const COIN_SEARCH_RANGE := 18.0
## With only its signature kit in hand, a bot still grabs a weapon this close.
const KIT_UPGRADE_RANGE := 8.0
## Pause between swings: [min, max] seconds.
const ATTACK_GAP := Vector2(0.35, 0.8)
## Share of attacks held to charge the weapon's heavy (see WeaponMove3D).
const HEAVY_CHANCE := 0.25
## Sprint to things further than this.
const SPRINT_DISTANCE := 10.0
## Keep this far from teammates so they don't stack up.
const SPACING := 2.5
# Carrying the ball (see PlayerClass3D.carry): run it at the goal and shoot
# once there's a clear line within SHOT_RANGE. Before the meter runs dry,
# pass to a teammate further up the field, or throw it on toward the goal.
## Shoot from this close to the net, if nothing's in the way.
const SHOT_RANGE := 22.0
## Throws need this much charge per metre to the target (0-1, see
## PlayerClass3D.THROW_CHARGE_MAX_DURATION), at least SHOT_MIN_CHARGE.
const SHOT_CHARGE_PER_METRE := 1.0 / SHOT_RANGE
const SHOT_MIN_CHARGE := 0.3
## Close to the net, any line will do: just shoot.
const POINT_BLANK := 6.0
## Pass only to a teammate at least this much nearer the goal than us, and
## no further off than PASS_RANGE.
const PASS_GAIN := 6.0
const PASS_RANGE := 24.0
## Shots come from in front of the goal mouth: within this angle of
## straight out from the net (toward the middle of the field). Further
## round, run out in front first, to about FRONT_DISTANCE from the net.
const SHOT_ANGLE := deg_to_rad(40.0)
const FRONT_DISTANCE := 9.0
## A teammate carrying: go after enemies this close to them.
const ESCORT_RANGE := 7.0
# Holding a throwable (see Throwable3D): throw it at an enemy within
# THROWABLE_RANGE (a healing flask: at ourselves if hurt, else a teammate).
# A bomb with under BOMB_PANIC_FUSE left goes anywhere.
const THROWABLE_RANGE := 14.0
const BOMB_PANIC_FUSE := 2.0
const HEAL_BELOW := 0.75

## Seconds a bot waits before taking its perk, so it doesn't feel instant.
const PERK_DELAY := 1.0
## In the intermission, a bot that hasn't reached its altar after this long
## (stuck, or a long way off) picks anyway, so it never holds the game up.
const INTERMISSION_GIVE_UP := 10.0

var _think_left: float = 0.0
## Where we're heading this think (null = stand still).
var _move_target: Variant = null
## What we're facing and swinging at, if anything.
var _attack_target: Node3D = null
var _want_attack: bool = false
var _want_interact: bool = false

var _attack_gap_left: float = 0.0
var _attack_press_left: float = 0.0
## The current press is the heavy button, held to charge.
var _attack_heavy: bool = false
var _interact_gap_left: float = 0.0
## Holding Throw to charge a shot: seconds left before letting go.
var _throw_press_left: float = 0.0
## Which way the shot being charged goes. Kept as a direction, not a point:
## we keep running while charging, and could run past a point.
var _shot_dir: Vector3 = Vector3.ZERO
## The charge is on Shoot (at the goal, aimed for us) rather than Throw
## (along our aim: passes, and throwing it on).
var _shooting: bool = false
var _perk_wait: float = 0.0
var _intermission_time: float = 0.0


func _ready() -> void:
	super()
	_think_left = randf() * THINK_TIME


func _input(_event: InputEvent) -> void:
	pass  # Devices don't drive bots


func _process(delta: float) -> void:
	var player := Master as PlayerClass3D
	var game: Game3D_Class = Global.Game3D
	if not player or not game or player.is_dead():
		release_all()
		return
	if _held_for_intro():
		return
	_think_left -= delta
	if _think_left <= 0.0:
		_think_left = THINK_TIME * randf_range(0.8, 1.2)
		_think(player, game)
	_steer(player, delta)
	_press_buttons(player, delta)


# ===== DECIDING =====

func _think(player: PlayerClass3D, game: Game3D_Class) -> void:
	_move_target = null
	_attack_target = null
	_want_attack = false
	_want_interact = false

	if game.phase == Game3D_Class.Phase.INTERMISSION:
		_think_intermission(player, game)
		return
	_intermission_time = 0.0
	# A boss kill's perk: bots take it on the spot rather than walk back for it
	if game.perks.can_open(player):
		_take_perk_soon(player, game)

	# Got the ball: nothing else matters
	if player.carries_ball():
		_carry_ball(player)
		return
	# A consumable card: a giant weapon at once, a throwable once there's
	# someone to use it on
	var card_slot: int = player.first_consumable()
	if card_slot >= 0 and player.can_use_consumable(card_slot):
		var card: Vector2i = player.consumables[card_slot]
		if not Consumable.is_throwable(card) \
				or _item_target(player, game, card.x as Throwable3D.Kind, card.y, false):
			use_item = true
	# Only ever aimed (locked on) for a throw, below
	if not player.holds_throwable():
		lock_target = null
	elif _throw_held_item(player, game):
		return

	var enemy: PlayerClass3D = _nearest_enemy(player, game)
	var enemy_dist: float = _flat_dist(player, enemy) if enemy else INF
	var armed: bool = player.held_weapon_left != null or player.held_weapon_right != null
	var found_weapon: bool = player.holds_found_weapon()

	# Someone's on top of us: deal with them first
	if enemy and enemy_dist < THREAT_RANGE:
		_fight(player, enemy)
		return
	# So is a monster (a skeleton) that's close
	var monster: SkeletonEnemy3D = SkeletonEnemy3D.nearest_to(player.global_position, THREAT_RANGE)
	if monster:
		_fight(player, monster)
		return

	if _go_get_reward(player):
		return
	if _go_get_coins(player):
		return

	if not found_weapon and _go_get_weapon(player, game, WEAPON_SEARCH_RANGE if not armed else KIT_UPGRADE_RANGE):
		return
	if _tower_job(player):
		return
	var ball: Ball3D = _nearest_ball(game)
	if ball:
		_go_for_ball(player, ball)
		return
	# The mode has a route (a race): stick to it, only fighting players who
	# get in the way (above)
	var goal: Node3D = game.bot_goal(player)
	if goal is Boss3D:
		_fight(player, goal)
		return
	if goal:
		_move_target = goal.global_position
		return
	var boss: Boss3D = _nearest_boss(player, game)
	if boss:
		# Go after a nearby player instead of a far-off boss now and then
		if enemy and enemy_dist < _flat_dist(player, boss) * 0.5:
			_fight(player, enemy)
		else:
			_fight(player, boss)
		return
	if enemy:
		_fight(player, enemy)


## The player walks itself to the altar (PlayerClass3D._walk_to_altar);
## once there (or after INTERMISSION_GIVE_UP), pick.
func _think_intermission(player: PlayerClass3D, game: Game3D_Class) -> void:
	_intermission_time += THINK_TIME
	if (player.at_altar or _intermission_time >= INTERMISSION_GIVE_UP) and game.perks.can_open(player):
		_take_perk_soon(player, game)


## Take a card from the waiting hand after PERK_DELAY.
func _take_perk_soon(player: PlayerClass3D, game: Game3D_Class) -> void:
	_perk_wait += THINK_TIME
	if _perk_wait >= PERK_DELAY:
		_perk_wait = 0.0
		game.perks.auto_pick(player)


func _fight(player: PlayerClass3D, target: Node3D) -> void:
	_attack_target = target
	var reach: float = BOSS_RANGE if target is Boss3D else MELEE_RANGE
	if target is Tower3D:
		reach = TOWER_RANGE
	if _has_ranged_weapon(player):
		reach = RANGED_RANGE
	var dist: float = _flat_dist(player, target)
	if dist > reach * 0.8:
		_move_target = target.global_position
	_want_attack = dist <= reach
	# Hurt and pressed: roll out of it now and then
	if target is PlayerClass3D and dist < MELEE_RANGE and target.is_swinging() \
			and player.Entity and player.Entity.hp < player.Entity.hp_max * 0.35 and randf() < 0.3:
		dodge_request_msec = Time.get_ticks_msec()


## The ball's loose: pick it up if the meter allows, else knock it along.
## Someone has it: an enemy gets tackled, a teammate gets escorted.
func _go_for_ball(player: PlayerClass3D, ball: Ball3D) -> void:
	var holder: PlayerClass3D = ball.holder
	if is_instance_valid(holder) and holder != player:
		if not Combat.are_teammates(player, holder):
			_fight(player, holder)
		else:
			_escort(player, holder, ball)
		return
	if player.carry < PlayerClass3D.CARRY_MIN_TO_GRAB:
		_go_hit_ball(player, ball)
		return
	_move_target = ball.global_position
	_want_interact = player.can_grab_ball(ball)


## A teammate has the ball: clear enemies off them, otherwise get up the
## field ahead of them.
func _escort(player: PlayerClass3D, holder: PlayerClass3D, ball: Ball3D) -> void:
	var threat: PlayerClass3D = null
	for other: PlayerClass3D in Global.Game3D.players:
		if is_instance_valid(other) and not other.is_dead() and not Combat.are_teammates(player, other) \
				and _flat_dist(holder, other) < ESCORT_RANGE \
				and (not threat or _flat_dist(holder, other) < _flat_dist(holder, threat)):
			threat = other
	if threat:
		_fight(player, threat)
		return
	var target: Node3D = _carry_target(player, ball)
	if target:
		_move_target = holder.global_position.lerp(target.global_position, 0.5)


## Where we take the ball: the net we attack, or our altar with a skull.
func _carry_target(player: PlayerClass3D, ball: Ball3D) -> Node3D:
	return Global.Game3D.shot_target(player, ball)


## We have the ball: run it home. A skull is delivered by walking it onto
## the altar; the ball has to be thrown in, so shoot when there's a clear
## line in range, and before the meter empties (or we're cornered) throw
## it on along the way to the goal.
func _carry_ball(player: PlayerClass3D) -> void:
	var ball: Ball3D = player.held_ball
	var target: Node3D = _carry_target(player, ball)
	if not target:
		return
	var aim_at: Vector3 = target.global_position
	var in_front: bool = ball is Skull3D or _in_front_of_goal(player, aim_at)
	_move_target = aim_at if in_front else aim_at + _goal_front(aim_at) * FRONT_DISTANCE
	if _throw_press_left > 0.0:
		return  # Mid-charge: _steer keeps aiming where we meant to
	var dist: float = _flat_dist_to(player, aim_at)
	var seconds_left: float = player.carry / PlayerClass3D.CARRY_DRAIN_PER_SEC
	var enemy: PlayerClass3D = _nearest_enemy(player, Global.Game3D)
	# An enemy on top of us and swinging: get rid of it before it's knocked loose
	var cornered: bool = enemy != null and _flat_dist(player, enemy) < MELEE_RANGE and enemy.is_swinging()
	if ball is Skull3D:
		# Walk it in, unless it'd be lost first
		if seconds_left < 0.4 or cornered:
			_start_throw(player, aim_at, NavPath.direction(player, aim_at))
		return
	if in_front and (dist < POINT_BLANK or (dist < SHOT_RANGE and _clear_line(player, aim_at))):
		_start_throw(player, aim_at, aim_at - player.global_position, true)
	elif seconds_left < PlayerClass3D.THROW_CHARGE_MAX_DURATION + 0.2 or cornered:
		# Can't hold on: pass it up the field, or send it on toward the goal
		var mate: PlayerClass3D = _pass_target(player, aim_at, dist)
		if mate:
			_start_throw(player, mate.global_position, mate.global_position - player.global_position)
		elif not cornered or dist < SHOT_RANGE * 2.0:
			_start_throw(player, aim_at, NavPath.direction(player, aim_at))


## Straight out from a net at `net`: toward the middle of the field.
func _goal_front(net: Vector3) -> Vector3:
	var out: Vector3 = Global.Game3D.ball_reset_point - net
	out.y = 0.0
	return out.normalized() if out.length() > 0.01 else Vector3.FORWARD


## Whether we're in front of the net at `net`, with the mouth to shoot at.
func _in_front_of_goal(player: PlayerClass3D, net: Vector3) -> bool:
	var from_net: Vector3 = player.global_position - net
	from_net.y = 0.0
	return from_net.length() > 0.01 and from_net.angle_to(_goal_front(net)) < SHOT_ANGLE


## The teammate furthest up the field (nearest `goal`) that's worth passing
## to and has nothing in the way, if any.
func _pass_target(player: PlayerClass3D, goal: Vector3, our_dist: float) -> PlayerClass3D:
	var best: PlayerClass3D = null
	var best_dist: float = our_dist - PASS_GAIN
	for mate: PlayerClass3D in Global.Game3D.players:
		if mate == player or not is_instance_valid(mate) or mate.is_dead() \
				or not Combat.are_teammates(player, mate) or _flat_dist(player, mate) > PASS_RANGE:
			continue
		var mate_dist: float = _flat_dist_to(mate, goal)
		if mate_dist < best_dist and _clear_line(player, mate.global_position):
			best = mate
			best_dist = mate_dist
	return best


## Hold Throw (or Shoot, a `shot` at the goal) long enough to reach
## `target`, facing along `dir`, as far as the meter allows.
func _start_throw(player: PlayerClass3D, target: Vector3, dir: Vector3, shot: bool = false) -> void:
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = player.global_basis.z
	_shot_dir = dir.normalized()
	_shooting = shot
	var charge: float = clampf(_flat_dist_to(player, target) * SHOT_CHARGE_PER_METRE, SHOT_MIN_CHARGE, 1.0)
	var hold: float = charge * PlayerClass3D.THROW_CHARGE_MAX_DURATION
	# Let go before the meter tosses it for us
	hold = minf(hold, player.carry / PlayerClass3D.CARRY_DRAIN_PER_SEC - 0.1)
	_throw_press_left = maxf(hold, 0.05)


## Throw what we hold, if there's anyone to throw it at (see
## THROWABLE_RANGE). Returns whether we did.
func _throw_held_item(player: PlayerClass3D, game: Game3D_Class) -> bool:
	var item: Throwable3D = player.held_throwable
	var target: Node3D = _item_target(player, game, item.kind, item.variant)
	var panic: bool = item.kind == Throwable3D.Kind.BOMB and item.fuse_left < BOMB_PANIC_FUSE
	if not target and not panic:
		return false
	lock_target = target
	_shot_dir = player.global_basis.z if not target or target == player else target.global_position - player.global_position
	_shot_dir.y = 0.0
	_shooting = false
	_throw_press_left = 0.05
	return true


## Who to use a throwable of `kind` (`variant` as in Throwable3D) on: a
## healing flask on us or a hurt teammate, anything else on an enemy within
## THROWABLE_RANGE. Null if there's nobody. Only `in_hand`, a healing flask
## nobody needs gets drunk anyway when a fight's on (our hands are wanted).
func _item_target(player: PlayerClass3D, game: Game3D_Class, kind: Throwable3D.Kind, variant: int, in_hand: bool = true) -> Node3D:
	var target: Node3D = null
	if kind == Throwable3D.Kind.FLASK and Potion.large(variant).get("allies", false):
		if player.Entity.hp < player.Entity.hp_max * HEAL_BELOW:
			target = player
		else:
			var mate: PlayerClass3D = player._nearest_teammate()
			if mate and _flat_dist(player, mate) <= THROWABLE_RANGE and mate.Entity.hp < mate.Entity.hp_max * HEAL_BELOW:
				target = mate
			elif in_hand:
				# Nobody needs it, but our hands are wanted: drink up anyway
				var enemy: PlayerClass3D = _nearest_enemy(player, game)
				if enemy and _flat_dist(player, enemy) < THREAT_RANGE:
					target = player
	else:
		var enemy: PlayerClass3D = _nearest_enemy(player, game)
		if enemy and _flat_dist(player, enemy) <= THROWABLE_RANGE:
			target = enemy
	return target


## Nothing solid between us and `point` (walls; players and the ball don't
## count).
func _clear_line(player: PlayerClass3D, point: Vector3) -> bool:
	var from: Vector3 = player.carry_point()
	var query := PhysicsRayQueryParameters3D.create(from, Vector3(point.x, from.y, point.z), 1)
	query.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Get behind the ball (seen from the goal) and swing or punch it goalwards.
## A skull gets knocked toward our altar instead. "Goalwards" follows the
## level's navigation from the ball, so in the dungeon it's knocked along
## the corridors rather than into the nearest wall.
func _go_hit_ball(player: PlayerClass3D, ball: Ball3D) -> void:
	var target: Node3D = null
	if ball is Skull3D:
		target = Global.Game3D.altar_of_team(player.slot.team if player.slot else 0)
	else:
		var goal: Goal3D = _goal_to_attack(player)
		target = goal.net if goal else null
	var to_goal: Vector3 = NavPath.direction(ball, target.global_position) if target else Vector3.ZERO
	var behind: Vector3 = ball.global_position - to_goal * 1.6
	var to_ball: Vector3 = ball.global_position - player.global_position
	to_ball.y = 0.0
	var lined_up: bool = to_goal.is_zero_approx() or to_ball.normalized().dot(to_goal) > 0.5
	if lined_up and to_ball.length() < MELEE_RANGE:
		_move_target = ball.global_position
		_attack_target = ball
		_want_attack = true
	else:
		_move_target = behind if not lined_up else ball.global_position


## A skull's reward is ready on our altar (wherever it is), or on a nearby
## enemy altar left unguarded: go take it. Returns false if there's none.
func _go_get_reward(player: PlayerClass3D) -> bool:
	var team: int = player.slot.team if player.slot else 0
	for node: Node in get_tree().get_nodes_in_group("WeaponStand"):
		var altar := node as Altar3D
		if not altar or not altar.has_reward_for(player):
			continue
		if altar.owner_team != team and altar.owner_team != Altar3D.NEUTRAL \
				and _flat_dist(player, altar) > WEAPON_SEARCH_RANGE:
			continue
		_move_target = altar.global_position
		_want_interact = altar.can_give_to(player)
		return true
	return false


## Head for the nearest coin pile, if there's one close. Standing on it is
## enough: the coins come to us.
func _go_get_coins(player: PlayerClass3D) -> bool:
	var best: Node3D = null
	var best_dist: float = COIN_SEARCH_RANGE
	for pile: Node3D in get_tree().get_nodes_in_group("CoinPile"):
		var dist: float = _flat_dist(player, pile)
		if dist < best_dist:
			best = pile
			best_dist = dist
	if not best:
		return false
	_move_target = best.global_position
	return true


## Head for the nearest loose weapon or stocked stand. Returns false if
## there's none in range.
func _go_get_weapon(player: PlayerClass3D, game: Game3D_Class, search_range: float = WEAPON_SEARCH_RANGE) -> bool:
	var best: Node3D = null
	var best_dist: float = search_range
	for weapon: Weapon3D in game.weapons():
		if not player.can_pick_up(weapon):
			continue
		var dist: float = _flat_dist(player, weapon)
		if dist < best_dist:
			best = weapon
			best_dist = dist
	for stand: WeaponStand3D in get_tree().get_nodes_in_group("WeaponStand"):
		if not stand.has_weapon_for(player):
			continue
		var dist: float = _flat_dist(player, stand)
		if dist < best_dist:
			best = stand
			best_dist = dist
	if not best:
		return false
	_move_target = best.global_position
	# Interact once in reach, of a loose weapon or a stand
	if best is WeaponStand3D:
		_want_interact = best.can_give_to(player)
	else:
		_want_interact = _flat_dist(player, best) <= PlayerClass3D.WEAPON_REACH
	return true


# ===== DOING =====

func _steer(player: PlayerClass3D, _delta: float) -> void:
	var dir: Vector3 = Vector3.ZERO
	var dist: float = 0.0
	if _move_target != null:
		var to: Vector3 = (_move_target as Vector3) - player.global_position
		to.y = 0.0
		dist = to.length()
		if dist > 0.6:
			dir = NavPath.direction(player, _move_target as Vector3)
	dir += _separation(player)
	move_dir = dir.normalized() if dir.length() > 0.1 else Vector3.ZERO
	move_dodge = dist > SPRINT_DISTANCE

	if _throw_press_left > 0.0 and player.hands_full():
		look_dir = _shot_dir.normalized() if _shot_dir.length() > 0.01 else Vector3.ZERO
	elif _attack_target and is_instance_valid(_attack_target):
		var look: Vector3 = _attack_target.global_position - player.global_position
		look.y = 0.0
		look_dir = look.normalized() if look.length() > 0.1 else Vector3.ZERO
	else:
		look_dir = Vector3.ZERO  # Face where we walk


func _press_buttons(player: PlayerClass3D, delta: float) -> void:
	# Attack: short taps of light with a gap between, like a person mashing,
	# and now and then the heavy held long enough to let it go
	_attack_gap_left -= delta
	_attack_press_left -= delta
	if _want_attack and _attack_gap_left <= 0.0:
		_attack_press_left = 0.05
		_attack_heavy = false
		var heavy: WeaponMove3D = player.heavy_move()
		if heavy and randf() < HEAVY_CHANCE:
			_attack_press_left = heavy.charge_time + 0.1
			_attack_heavy = true
		_attack_gap_left = _attack_press_left + randf_range(ATTACK_GAP.x, ATTACK_GAP.y)
	# Carrying, Light and Heavy throw and pass the ball: leave them be
	var pressing: bool = _attack_press_left > 0.0 and not player.hands_full()
	light_held = pressing and not _attack_heavy
	heavy_held = pressing and _attack_heavy
	# A shot: Throw held while it charges, let go once it's long enough
	_throw_press_left -= delta
	var charging: bool = _throw_press_left > 0.0 and player.hands_full()
	throw_held = charging and not _shooting
	shoot_held = charging and _shooting
	if not player.hands_full():
		_throw_press_left = 0.0

	_interact_gap_left -= delta
	if _want_interact and _interact_gap_left <= 0.0:
		interact = true
		_interact_gap_left = 0.3


## A push away from teammates who are too close.
func _separation(player: PlayerClass3D) -> Vector3:
	var push: Vector3 = Vector3.ZERO
	for other: PlayerClass3D in Global.Game3D.players:
		if other == player or not is_instance_valid(other) or other.is_dead() or not Combat.are_teammates(player, other):
			continue
		var away: Vector3 = player.global_position - other.global_position
		away.y = 0.0
		var dist: float = away.length()
		if dist < SPACING and dist > 0.01:
			push += away / dist * (1.0 - dist / SPACING)
	return push


# ===== LOOKING AROUND =====

## A tower to claim or knock down, if we're the one on our team nearest it
## (so one teammate peels off for it and the rest keep playing): stand in
## reach of one that's up for grabs, or go hit an enemy one. An enemy
## player inside its capture radius gets fought first, since they'd stall
## the claim (or defend the tower).
func _tower_job(player: PlayerClass3D) -> bool:
	var team: int = Combat.team_of(player)
	for tower: Tower3D in Tower3D.standing(get_tree()):
		var claim: bool = tower.is_capturable() and not (tower.capture_team == team and tower.capture >= 1.0)
		var attack: bool = tower.state == Tower3D.State.ACTIVE and tower.owner_team != team
		if not (claim or attack) or not _nearest_teammate_to(player, tower):
			continue
		var intruder: PlayerClass3D = _nearest_enemy_to(player, tower, tower.capture_radius)
		if intruder:
			_fight(player, intruder)
		elif attack:
			_fight(player, tower)
		elif _flat_dist(player, tower) > tower.capture_radius * 0.8:
			var out: Vector3 = player.global_position - tower.global_position
			out.y = 0.0
			_move_target = tower.global_position + out.normalized() * tower.capture_radius * 0.6
		return true
	return false


## Whether no living teammate is closer to `target` than `player`.
func _nearest_teammate_to(player: PlayerClass3D, target: Node3D) -> bool:
	var dist: float = _flat_dist(player, target)
	for other: PlayerClass3D in Global.Game3D.players:
		if other != player and is_instance_valid(other) and not other.is_dead() \
				and Combat.are_teammates(player, other) and _flat_dist(other, target) < dist:
			return false
	return true


func _nearest_enemy(player: PlayerClass3D, game: Game3D_Class) -> PlayerClass3D:
	var best: PlayerClass3D = null
	for other: PlayerClass3D in game.players:
		if other == player or not is_instance_valid(other) or other.is_dead() or Combat.are_teammates(player, other):
			continue
		if not best or _flat_dist(player, other) < _flat_dist(player, best):
			best = other
	return best


## The living enemy of `player` nearest `target`, within `radius` (flat) of it.
func _nearest_enemy_to(player: PlayerClass3D, target: Node3D, radius: float) -> PlayerClass3D:
	var best: PlayerClass3D = null
	var best_dist: float = radius
	for other: PlayerClass3D in Global.Game3D.players:
		if other == player or not is_instance_valid(other) or other.is_dead() or Combat.are_teammates(player, other):
			continue
		var dist: float = _flat_dist(other, target)
		if dist <= best_dist:
			best = other
			best_dist = dist
	return best


func _nearest_boss(player: PlayerClass3D, game: Game3D_Class) -> Boss3D:
	var best: Boss3D = null
	for boss: Boss3D in game.bosses:
		if not is_instance_valid(boss) or boss.penned:
			continue  # Can't be reached
		if not best or _flat_dist(player, boss) < _flat_dist(player, best):
			best = boss
	return best


## The nearest ball in play.
func _nearest_ball(game: Game3D_Class) -> Ball3D:
	var player := Master as PlayerClass3D
	var best: Ball3D = null
	for ball: Ball3D in game.balls:
		if not is_instance_valid(ball) or not ball.is_inside_tree():
			continue
		if not best or _flat_dist(player, ball) < _flat_dist(player, best):
			best = ball
	return best


## The nearest goal that scores for our team.
func _goal_to_attack(player: PlayerClass3D) -> Goal3D:
	return Global.Game3D.goal_to_attack(player)


func _has_ranged_weapon(player: PlayerClass3D) -> bool:
	for weapon: Weapon3D in [player.held_weapon_left, player.held_weapon_right]:
		if weapon and not weapon is ShieldClass3D and not weapon.plays_swipe_animation:
			return true
	return false


func _flat_dist(player: PlayerClass3D, node: Node3D) -> float:
	return _flat_dist_to(player, node.global_position)


func _flat_dist_to(player: PlayerClass3D, pos: Vector3) -> float:
	return Vector2(player.global_position.x - pos.x, player.global_position.z - pos.z).length()
