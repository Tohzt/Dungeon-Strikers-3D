class_name BotInputHandler3D extends PlayerInputHandler3D
## A computer player: instead of reading a device, it decides what to do
## and sets the same fields a person's input would (move_dir, look_dir,
## the Attack/Throw/Guard buttons, interact), so the player plays it exactly
## like anyone else. Offline only; Game3D swaps it in for slots with is_bot.
##
## Each think picks a goal - get a weapon, fight, play the ball toward the
## other team's goal (or carry a skull home to our altar), pick a perk -
## and every frame steers toward it.

## Seconds between decisions (a little random, so bots don't move in lockstep).
const THINK_TIME := 0.15
## How close to get to a melee target before swinging.
const MELEE_RANGE := 2.2
## Bosses are big: swing from a bit further out.
const BOSS_RANGE := 3.5
## Ranged weapons (that don't swing) hang back this far.
const RANGED_RANGE := 10.0
## An enemy this close gets fought even mid-objective.
const THREAT_RANGE := 4.0
## How far the bot will go for a loose weapon or a stand.
const WEAPON_SEARCH_RANGE := 30.0
## Throw the carried ball once the goal is this close.
const SHOT_RANGE := 16.0
## How long the Throw button is held, charging the shot.
const SHOT_CHARGE := 0.6
## Pause between swings: [min, max] seconds.
const ATTACK_GAP := Vector2(0.35, 0.8)
## Sprint to things further than this.
const SPRINT_DISTANCE := 18.0
## Keep this far from teammates so they don't stack up.
const SPACING := 2.5
## Seconds a bot waits before taking its perk, so it doesn't feel instant.
const PERK_DELAY := 1.0
## In the intermission, a bot that hasn't reached its altar after this long
## (stuck, or a long way off) picks anyway, so it never holds the game up.
const INTERMISSION_GIVE_UP := 10.0
## Below this much boost, a bot with nothing urgent to do grabs an orb this close.
const BOOST_WANT := 50.0
const BOOST_SEARCH_RANGE := 12.0
## Boost toward things further than this, but stop at BOOST_RESERVE so
## there's some left for a fight.
const BOOST_DISTANCE := 10.0
const BOOST_RESERVE := 25.0

var _think_left: float = 0.0
## Where we're heading this think (null = stand still).
var _move_target: Variant = null
## What we're facing and swinging at, if anything.
var _attack_target: Node3D = null
var _want_attack: bool = false
var _want_guard: bool = false
var _want_shot: bool = false
var _want_interact: bool = false

var _attack_gap_left: float = 0.0
var _attack_press_left: float = 0.0
## Which hand the current attack press uses, and which went last (a bot
## dual-wielding alternates).
var _attack_hand_left: bool = false
var _last_attack_left: bool = true
var _shot_hold: float = 0.0
var _interact_gap_left: float = 0.0
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
		_apply_simple_buttons(false, false, false, false)
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
	_want_guard = false
	_want_shot = false
	_want_interact = false

	if game.phase == Game3D_Class.Phase.INTERMISSION:
		_think_intermission(player, game)
		return
	_intermission_time = 0.0
	# A boss kill's perk: bots take it on the spot rather than walk back for it
	if game.perks.can_open(player):
		_take_perk_soon(player, game)
	if player.held_ball:
		_think_carry(player, game)
		return

	var enemy: PlayerClass3D = _nearest_enemy(player, game)
	var enemy_dist: float = _flat_dist(player, enemy) if enemy else INF
	var armed: bool = player.held_weapon_left != null or player.held_weapon_right != null

	# Someone's on top of us: deal with them first
	if enemy and enemy_dist < THREAT_RANGE and (armed or not _loose_ball(game)):
		_fight(player, enemy)
		return

	if _go_get_reward(player):
		return
	if _go_get_boost(player, enemy_dist):
		return

	var ball: Ball3D = _loose_ball(game)
	if ball and not armed:
		_go_grab_ball(player, ball)
		return
	if not armed and _go_get_weapon(player, game):
		return
	if ball:
		_go_hit_ball(player, ball)
		return
	if not game.bosses.is_empty():
		var boss: Boss3D = _nearest_boss(player, game)
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


## Carrying the ball: run at the goal and shoot once in range. A skull is
## walked all the way onto our altar.
func _think_carry(player: PlayerClass3D, game: Game3D_Class) -> void:
	if player.held_ball is Skull3D:
		var altar: Altar3D = game.altar_of_team(player.slot.team if player.slot else 0)
		if altar:
			_move_target = altar.global_position
		return
	var goal: Goal3D = _goal_to_attack(player)
	if not goal:
		return
	var aim: Vector3 = goal.net.global_position
	_move_target = aim
	_attack_target = goal.net
	_want_shot = _flat_dist_to(player, aim) < SHOT_RANGE


func _fight(player: PlayerClass3D, target: Node3D) -> void:
	_attack_target = target
	var reach: float = BOSS_RANGE if target is Boss3D else MELEE_RANGE
	if _has_ranged_weapon(player):
		reach = RANGED_RANGE
	var dist: float = _flat_dist(player, target)
	if dist > reach * 0.8:
		_move_target = target.global_position
	_want_attack = dist <= reach
	# Raise a shield against a swing that's coming
	if target is PlayerClass3D and dist < MELEE_RANGE * 1.5 and target.is_swinging() and _has_shield(player):
		_want_guard = true
		_want_attack = false
	# Hurt and pressed: roll out of it now and then
	if target is PlayerClass3D and dist < MELEE_RANGE and target.is_swinging() \
			and player.Entity and player.Entity.hp < player.Entity.hp_max * 0.35 and randf() < 0.3:
		dodge_request_msec = Time.get_ticks_msec()


func _go_grab_ball(player: PlayerClass3D, ball: Ball3D) -> void:
	_move_target = ball.global_position
	_want_interact = player.can_grab_ball(ball)


## Armed: get behind the ball (seen from the goal) and swing it goalwards.
## A skull gets knocked toward our altar instead.
func _go_hit_ball(player: PlayerClass3D, ball: Ball3D) -> void:
	var target: Node3D = null
	if ball is Skull3D:
		target = Global.Game3D.altar_of_team(player.slot.team if player.slot else 0)
	else:
		var goal: Goal3D = _goal_to_attack(player)
		target = goal.net if goal else null
	var to_goal: Vector3 = Vector3.ZERO
	if target:
		to_goal = target.global_position - ball.global_position
		to_goal.y = 0.0
		to_goal = to_goal.normalized()
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


## Low on boost with no enemy close: detour to a nearby orb. Returns
## false if we don't need one or there's none close.
func _go_get_boost(player: PlayerClass3D, enemy_dist: float) -> bool:
	if player.boost >= BOOST_WANT or enemy_dist < THREAT_RANGE * 2.0:
		return false
	var best: BoostOrb3D = null
	var best_dist: float = BOOST_SEARCH_RANGE
	for orb: BoostOrb3D in get_tree().get_nodes_in_group("BoostOrb"):
		if not orb.is_ready():
			continue
		var dist: float = _flat_dist(player, orb)
		if dist < best_dist:
			best = orb
			best_dist = dist
	if not best:
		return false
	_move_target = best.global_position
	return true


## A skull's reward is ready on our altar (wherever it is), or on a nearby
## enemy altar left unguarded: go take it. Returns false if there's none.
func _go_get_reward(player: PlayerClass3D) -> bool:
	var team: int = player.slot.team if player.slot else 0
	for node: Node in get_tree().get_nodes_in_group("WeaponStand"):
		var altar := node as Altar3D
		if not altar or not altar.has_reward_for(player):
			continue
		if altar.owner_team != team and _flat_dist(player, altar) > WEAPON_SEARCH_RANGE:
			continue
		_move_target = altar.global_position
		_want_interact = altar.can_give_to(player)
		return true
	return false


## Head for the nearest loose weapon or stocked stand. Returns false if
## there's none in range.
func _go_get_weapon(player: PlayerClass3D, game: Game3D_Class) -> bool:
	var best: Node3D = null
	var best_dist: float = WEAPON_SEARCH_RANGE
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
	move_dodge = dist > SPRINT_DISTANCE and not player.held_ball

	if _attack_target and is_instance_valid(_attack_target):
		var look: Vector3 = _attack_target.global_position - player.global_position
		look.y = 0.0
		look_dir = look.normalized() if look.length() > 0.1 else Vector3.ZERO
	else:
		look_dir = Vector3.ZERO  # Face where we walk

	# Far off: boost to close the gap
	boost_held = dist > BOOST_DISTANCE and not move_dir.is_zero_approx() and player.boost > BOOST_RESERVE


func _press_buttons(player: PlayerClass3D, delta: float) -> void:
	# Attack: short taps with a gap between, like a person mashing
	_attack_gap_left -= delta
	_attack_press_left -= delta
	if _want_attack and _attack_gap_left <= 0.0:
		_attack_press_left = 0.05
		_attack_gap_left = randf_range(ATTACK_GAP.x, ATTACK_GAP.y)
		_attack_hand_left = _pick_attack_hand(player)
		_last_attack_left = _attack_hand_left
	var attack: bool = _attack_press_left > 0.0

	# Shot: hold Throw and a hand's button to charge while lining up, then let go
	var throw: bool = false
	if _want_shot and player.held_ball:
		_shot_hold += delta
		throw = _shot_hold < SHOT_CHARGE
	else:
		_shot_hold = 0.0
	_apply_simple_buttons((attack and _attack_hand_left) or throw, attack and not _attack_hand_left, _want_guard, throw)

	_interact_gap_left -= delta
	if _want_interact and _interact_gap_left <= 0.0:
		interact = true
		_interact_gap_left = 0.3


## A push away from teammates who are too close.
## Which hand an attack press uses (true = left). Weapons beat shields (a
## shield only bashes when it's all we hold); two weapons, or two fists,
## take turns, skipping an arm that's still mid-swing.
func _pick_attack_hand(player: PlayerClass3D) -> bool:
	if player.held_ball:
		return false  # Either hand bonks the ball
	var left: Weapon3D = player.held_weapon_left
	var right: Weapon3D = player.held_weapon_right
	var left_attacks: bool = left != null and not left is ShieldClass3D
	var right_attacks: bool = right != null and not right is ShieldClass3D
	if left_attacks != right_attacks:
		return left_attacks
	if not left_attacks and (left != null) != (right != null):
		return left != null  # Just a shield: use it
	# Both hands alike: take turns, unless the next one is still busy
	var next_left: bool = not _last_attack_left
	if player.is_arm_swinging(next_left) and not player.is_arm_swinging(not next_left):
		next_left = not next_left
	return next_left


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

func _nearest_enemy(player: PlayerClass3D, game: Game3D_Class) -> PlayerClass3D:
	var best: PlayerClass3D = null
	for other: PlayerClass3D in game.players:
		if other == player or not is_instance_valid(other) or other.is_dead() or Combat.are_teammates(player, other):
			continue
		if not best or _flat_dist(player, other) < _flat_dist(player, best):
			best = other
	return best


func _nearest_boss(player: PlayerClass3D, game: Game3D_Class) -> Boss3D:
	var best: Boss3D = null
	for boss: Boss3D in game.bosses:
		if is_instance_valid(boss) and (not best or _flat_dist(player, boss) < _flat_dist(player, best)):
			best = boss
	return best


## The nearest ball in play that nobody is carrying.
func _loose_ball(game: Game3D_Class) -> Ball3D:
	var player := Master as PlayerClass3D
	var best: Ball3D = null
	for ball: Ball3D in game.balls:
		if not is_instance_valid(ball) or not ball.is_inside_tree() or ball.holder:
			continue
		if not best or _flat_dist(player, ball) < _flat_dist(player, best):
			best = ball
	return best


## The nearest goal that scores for our team.
func _goal_to_attack(player: PlayerClass3D) -> Goal3D:
	var team: int = player.slot.team if player.slot else 0
	var best: Goal3D = null
	for goal: Goal3D in get_tree().get_nodes_in_group("Goal"):
		var ours: bool = goal.scoring_team == team \
			or (goal.scoring_team == Goal3D.LAST_TOUCH and goal.owner_team != team)
		if ours and (not best or _flat_dist(player, goal) < _flat_dist(player, best)):
			best = goal
	return best


func _has_ranged_weapon(player: PlayerClass3D) -> bool:
	for weapon: Weapon3D in [player.held_weapon_left, player.held_weapon_right]:
		if weapon and not weapon is ShieldClass3D and not weapon.plays_swipe_animation:
			return true
	return false


func _has_shield(player: PlayerClass3D) -> bool:
	return player.held_weapon_left is ShieldClass3D or player.held_weapon_right is ShieldClass3D


func _flat_dist(player: PlayerClass3D, node: Node3D) -> float:
	return _flat_dist_to(player, node.global_position)


func _flat_dist_to(player: PlayerClass3D, pos: Vector3) -> float:
	return Vector2(player.global_position.x - pos.x, player.global_position.z - pos.z).length()
