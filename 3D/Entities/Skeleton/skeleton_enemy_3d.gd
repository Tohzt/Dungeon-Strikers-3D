class_name SkeletonEnemy3D extends CharacterBody3D
## An undead soldier that fights with real weapons: the same Weapon3D scenes
## players use, held on its hand bones and swung with the same KayKit clips.
## It starts with its kind's gear (see LOADOUTS). A worn-out weapon breaks
## like anyone's, and then it goes looking for another one on the floor
## (even one a player threw at it), or fights with its fists. It drops
## whatever it holds when it falls, for players to take.
##
## Its attacks are telegraphed: it winds up (glowing) for a moment before
## each strike, then stands open while it recovers. Shield-bearers guard
## when a player is close, and blocked hits from the front barely hurt them.
## Archers and mages keep their distance and shoot.
##
## Online the server runs it and streams where it is; everyone else just
## plays that back. Each machine makes its starting gear itself, named
## after it, so weapons line up everywhere.

enum Kind {
	WARRIOR,  ## Bone blade and shield: guards, then cuts
	MINION,   ## Bone axe: quick and fragile
	ARCHER,   ## Bow: keeps away and shoots
	MAGE,     ## Bone staff: keeps away and casts
}

enum State {
	IDLE,     ## Standing about, or wandering near home
	CHASE,    ## Going after its target (or a weapon to pick up)
	ATTACK,   ## Winding up, striking, recovering
	STAGGER,  ## Poise broken: reeling
	DEAD,     ## Collapsed
}

## Every living skeleton is in this group (bots).
const GROUP := "Enemy"

const MODELS: Dictionary[Kind, PackedScene] = {
	Kind.WARRIOR: preload("res://Assets/Skeleton/Characters/Skeleton_Warrior.glb"),
	Kind.MINION: preload("res://Assets/Skeleton/Characters/Skeleton_Minion.glb"),
	Kind.ARCHER: preload("res://Assets/Skeleton/Characters/Skeleton_Rogue.glb"),
	Kind.MAGE: preload("res://Assets/Skeleton/Characters/Skeleton_Mage.glb"),
}
## What each kind starts with: [right hand, left hand] (null = empty).
const LOADOUTS: Dictionary[Kind, Array] = {
	Kind.WARRIOR: [preload("res://3D/Weapons/Bone/bone_blade_3d.tscn"), preload("res://3D/Weapons/Bone/bone_shield_3d.tscn")],
	Kind.MINION: [preload("res://3D/Weapons/Bone/bone_axe_3d.tscn"), null],
	Kind.ARCHER: [preload("res://3D/Weapons/Bow and Arrow/bow_3d.tscn"), null],
	Kind.MAGE: [preload("res://3D/Weapons/Bone/bone_staff_3d.tscn"), null],
}
## [max HP, walk speed, poise]. Players have 250 HP; a sword hit is 40.
const STATS: Dictionary[Kind, Vector3] = {
	Kind.WARRIOR: Vector3(160.0, 3.4, 70.0),
	Kind.MINION: Vector3(80.0, 4.2, 30.0),
	Kind.ARCHER: Vector3(90.0, 3.8, 35.0),
	Kind.MAGE: Vector3(90.0, 3.2, 35.0),
}

@export var kind: Kind = Kind.WARRIOR
## Scales its kind's HP (tougher ones deeper in a dungeon, say).
@export var hp_scale: float = 1.0

@export_category("Senses")
## Notices players this close that it can see.
@export var aggro_range: float = 12.0
## Notices players this close even without seeing them.
@export var hearing_range: float = 3.0
## Gives up on a target this far away, and walks back home.
@export var leash_range: float = 24.0
## Getting hit (or noticing someone) alerts other skeletons this close.
@export var alert_range: float = 8.0

@export_category("Attacks")
## Telegraph before every strike, on top of the weapon's own swing_windup.
@export var windup_time: float = 0.5
## Standing open after a strike.
@export var recover_time: float = 0.5
@export var attack_cooldown_min: float = 0.8
@export var attack_cooldown_max: float = 1.8
## Ranged kinds back off from anyone closer than this...
@export var keep_away_range: float = 6.0
## ...and shoot from up to this far.
@export var shoot_range: float = 15.0

# ===== BODY =====
const HEIGHT := 1.8
const TURN_SPEED := 8.0
## Turns this fast while winding up, so a sidestep late in the wind-up works.
const WINDUP_TURN_SPEED := 4.0
const ACCELERATION := 20.0
const GRAVITY_SCALE := 2.0
const KNOCKBACK_FRICTION := 14.0
## Light: hits shove it this fraction of their knockback.
const KNOCKBACK_RATIO := 0.7
## Steps into a melee strike this fast.
const LUNGE_SPEED := 4.0
## Wanders this far from home while idle.
const WANDER_RADIUS := 3.0
const THINK_TIME := 0.25

# ===== COMBAT =====
const STAGGER_TIME := 1.2
## Poise comes back this long after the last hit.
const POISE_RESET_TIME := 2.0
## Like players' shields (see PlayerClass3D).
const BLOCK_FACING_DOT := 0.3
const BLOCK_DAMAGE_RATIO := 0.2
const BLOCK_KNOCKBACK_RATIO := 0.35
## Raises its shield against players this close.
const GUARD_RANGE := 5.0
const GUARD_SPEED_RATIO := 0.5
## Shortest strike: a swing's hit window is its weapon's swing_duration.
const MIN_STRIKE_TIME := 0.15
## A melee weapon reaches its blade's length past this.
const BASE_REACH := 1.0
## Unarmed: a punch.
const FIST_REACH := 0.5
const FIST_DAMAGE := 8.0
const FIST_KNOCKBACK := 8.0
const FIST_POP := 2.0
const FIST_RANGE := 1.4
## Looks for a loose weapon this close when its own breaks.
const WEAPON_SEARCH_RANGE := 12.0
const PICKUP_REACH := 1.4
## Lies there this long once dead, then sinks into the floor.
const CORPSE_TIME := 4.0
const SINK_TIME := 1.5

# ===== LOOKS =====
const MODEL_SCALE := 0.85  # Same as players
const SKELETON_PATH := "Rig_Medium/Skeleton3D"
const IDLE_CLIP := &"General/Idle_A"
const WALK_CLIP := &"MovementBasic/Walking_A"
const RUN_CLIP := &"MovementBasic/Running_A"
const HIT_CLIP := &"General/Hit_A"
const STAGGER_CLIP := &"General/Hit_B"
const DEATH_CLIP := &"General/Death_A"
const PUNCH_CLIP := &"CombatMelee/Melee_Unarmed_Attack_Punch_A"
const HIT_FLASH_TIME := 0.12
const HIT_FLASH_COLOR := Color(1.0, 1.0, 1.0, 0.6)
## The wind-up glow: pulsing brighter the closer the strike.
const TELEGRAPH_COLOR := Color(1.0, 0.45, 0.1, 0.45)
const ACT_BLEND_IN := 0.05
const ACT_BLEND_OUT := 0.15

signal died(killer: PlayerClass3D)

var hp: float = 100.0
var max_hp: float = 100.0
var is_dead: bool = false
var state: State = State.IDLE
var _state_time: float = 0.0

## Each hand's weapon (Weapon3D clears these itself when one breaks).
var held_weapon_left: Weapon3D = null
var held_weapon_right: Weapon3D = null

var _speed: float = 3.5
var _poise_max: float = 50.0
var _poise_damage: float = 0.0
var _poise_reset: float = 0.0
var _home: Vector3
var _target: PlayerClass3D = null
var _wander_to: Vector3
var _think_left: float = 0.0
var _attack_cooldown: float = 0.0
var _knockback: Vector3 = Vector3.ZERO
var _hitstop: float = 0.0
var _last_attacker: PlayerClass3D = null
var _gear_made: int = 0

## The attack under way: which hand, and how long each part takes.
var _attack_left: bool = false
var _attack_windup: float = 0.5
var _attack_strike: float = 0.2
var _attack_recover: float = 0.5
var _struck: bool = false
var _punched: Array[Node] = []

@onready var visual: Node3D = $Visual
var body_model: Node3D = null
var skeleton: Skeleton3D = null
var tree: AnimationTree = null
var _playback: AnimationNodeStateMachinePlayback = null
var _hand_left := Node3D.new()
var _hand_right := Node3D.new()
var _hand_bone_left: int = -1
var _hand_bone_right: int = -1
var _act_clip: StringName = &""
var _act_weight: float = 0.0
var _overlay := StandardMaterial3D.new()
var _overlay_on: bool = false
var _flash: float = 0.0
## Clients: how fast it's moving, from how its played-back position changes.
var _seen_velocity: Vector3 = Vector3.ZERO
var _last_position: Vector3

## Online: the server sends where it is; clients play it back.
var _motion := NetMotion.new()


func _ready() -> void:
	add_to_group(GROUP)
	var stats: Vector3 = STATS[kind]
	max_hp = stats.x * hp_scale
	hp = max_hp
	_speed = stats.y
	_poise_max = stats.z
	_home = global_position
	_wander_to = _home
	_last_position = global_position
	_think_left = randf() * THINK_TIME  # So a group doesn't all think on the same frame
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_set_model(MODELS[kind])
	# After the level has finished adding things, so Game3D's weapons are there
	_arm.call_deferred()


## The nearest living skeleton within `range_` of `pos`, if any.
static func nearest_to(pos: Vector3, range_: float) -> SkeletonEnemy3D:
	var best: SkeletonEnemy3D = null
	var best_dist: float = range_
	for node: Node in Engine.get_main_loop().get_nodes_in_group(GROUP):
		var enemy := node as SkeletonEnemy3D
		if not enemy or enemy.is_dead:
			continue
		var dist: float = pos.distance_to(enemy.global_position)
		if dist < best_dist:
			best_dist = dist
			best = enemy
	return best


func _physics_process(delta: float) -> void:
	if not Net.decides():
		return
	if is_dead:
		_apply_gravity(delta)
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	if _hitstop > 0.0:
		_hitstop -= delta
		return
	_state_time += delta
	_attack_cooldown = max(_attack_cooldown - delta, 0.0)
	_poise_reset -= delta
	if _poise_reset <= 0.0:
		_poise_damage = 0.0

	var want := Vector3.ZERO
	match state:
		State.IDLE: want = _state_idle(delta)
		State.CHASE: want = _state_chase(delta)
		State.ATTACK: want = _state_attack(delta)
		State.STAGGER:
			if _state_time >= STAGGER_TIME:
				_set_state(State.CHASE if _target else State.IDLE)
	_update_guard()
	if _guarding():
		want *= GUARD_SPEED_RATIO
	_move(want, delta)
	_send_state()


func _process(delta: float) -> void:
	if not Net.decides():
		_motion.play(self, delta)
		if delta > 0.0:
			_seen_velocity = _seen_velocity.lerp((global_position - _last_position) / delta, minf(10.0 * delta, 1.0))
		_last_position = global_position
		if state == State.ATTACK or state == State.STAGGER:
			_state_time += delta  # Clients don't run the states, but the clips time them
	_update_animation(delta)
	_update_overlay(delta)


# ===== GEAR =====

## Every machine: make this kind's starting weapons and take them in hand.
func _arm() -> void:
	var loadout: Array = LOADOUTS[kind]
	for i in loadout.size():
		var scene: PackedScene = loadout[i]
		if not scene:
			continue
		var weapon: Weapon3D = scene.instantiate()
		var weapon_name: String = "%s_Gear%d" % [name, _gear_made]
		_gear_made += 1
		weapon.name = weapon_name
		if Global.Game3D:
			Global.Game3D.add_weapon(weapon)
		else:
			get_parent().add_child(weapon)
		weapon.name = weapon_name  # Its _ready renames it after its Properties
		weapon.global_position = global_position + Vector3.UP
		if Net.in_session():
			weapon.setup_network()  # The server runs it, like the skeleton
		equip_weapon(weapon, i == 1)


## Take `weapon` in hand (Weapon3D.hand_to calls this online).
func equip_weapon(weapon: Weapon3D, is_left: bool) -> void:
	if is_left:
		held_weapon_left = weapon
	else:
		held_weapon_right = weapon
	weapon.equip(self, hand(is_left or weapon.rides_left_hand))


## Where `is_left`'s hand holds things: its handslot bone, posed this frame.
func hand(is_left: bool) -> Node3D:
	return _hand_left if is_left else _hand_right


## The weapon it attacks with: the right hand's, else the left's unless
## that's a shield. Null = fists.
func _main_weapon() -> Weapon3D:
	if held_weapon_right:
		return held_weapon_right
	if held_weapon_left and not held_weapon_left is ShieldClass3D:
		return held_weapon_left
	return null


func _shield() -> ShieldClass3D:
	return held_weapon_left as ShieldClass3D


func _is_ranged(weapon: Weapon3D) -> bool:
	return weapon != null and not weapon.plays_swipe_animation


## Which hand `weapon` would go in, or -1 if neither is free for it:
## 0 = right, 1 = left.
func _free_hand_for(weapon: Weapon3D) -> int:
	var right_free: bool = held_weapon_right == null
	var left_free: bool = held_weapon_left == null
	match weapon.grip:
		Weapon3D.Grip.OFF_HAND:
			return 1 if left_free else -1
		Weapon3D.Grip.TWO_HANDED:
			return 0 if right_free and left_free else -1
	if right_free:
		return 0
	return 1 if left_free else -1


## The nearest loose weapon it could pick up.
func _nearest_loose_weapon() -> Weapon3D:
	if not Global.Game3D:
		return null
	var best: Weapon3D = null
	var best_dist: float = WEAPON_SEARCH_RANGE
	for weapon: Weapon3D in Global.Game3D.weapons():
		if weapon.wielder or weapon.is_broken or not weapon.can_pickup or weapon.is_thrown or weapon.kit_owner:
			continue
		if _free_hand_for(weapon) < 0:
			continue
		var dist: float = global_position.distance_to(weapon.global_position)
		if dist < best_dist:
			best_dist = dist
			best = weapon
	return best


## Server/offline: pick `weapon` up, on every machine.
func _take(weapon: Weapon3D) -> void:
	var slot: int = _free_hand_for(weapon)
	if slot >= 0:
		Net.everywhere(_net_take, String(weapon.name), slot == 1)


@rpc("authority", "call_local", "reliable")
func _net_take(weapon_name: String, is_left: bool) -> void:
	if not Global.Game3D:
		return
	for weapon: Weapon3D in Global.Game3D.weapons():
		if String(weapon.name) == weapon_name:
			weapon.hand_to(self, is_left)
			return


# ===== BEHAVIOR (server/offline) =====

func _set_state(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	if Net.in_session() and Net.is_server and Net.match_synced:
		_net_phase.rpc(new_state)
	_on_state_entered(new_state)


## Every machine.
func _on_state_entered(new_state: State) -> void:
	match new_state:
		State.STAGGER:
			_go(&"Stagger")
		State.DEAD:
			_go(&"Down")


func _state_idle(_delta: float) -> Vector3:
	if _think():
		_target = _find_target()
		if _target:
			_alert_others(_target)
			_set_state(State.CHASE)
			return Vector3.ZERO
		if _flat(_wander_to - global_position).length() < 0.5 and randf() < 0.1:
			_wander_to = _home + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * WANDER_RADIUS
	var to: Vector3 = _flat(_wander_to - global_position)
	if to.length() < 0.5:
		return Vector3.ZERO
	var dir: Vector3 = NavPath.direction(self, _wander_to)
	_face(dir, TURN_SPEED)
	# Strolls; walks straight back home if it was led far off
	var far: bool = _flat(_home - global_position).length() > WANDER_RADIUS * 2.0
	return dir * _speed * (1.0 if far else 0.35)


func _state_chase(_delta: float) -> Vector3:
	if not _is_valid_target(_target) or _flat(_target.global_position - global_position).length() > leash_range:
		_target = null
		_wander_to = _home
		_set_state(State.IDLE)
		return Vector3.ZERO

	# Weaponless: arm itself first, if there's anything about
	var weapon: Weapon3D = _main_weapon()
	if not weapon:
		var loose: Weapon3D = _nearest_loose_weapon()
		if loose:
			var to_weapon: Vector3 = _flat(loose.global_position - global_position)
			if to_weapon.length() < PICKUP_REACH:
				_take(loose)
				return Vector3.ZERO
			var dir_to: Vector3 = NavPath.direction(self, loose.global_position)
			_face(dir_to, TURN_SPEED)
			return dir_to * _speed

	var to_target: Vector3 = _flat(_target.global_position - global_position)
	var dist: float = to_target.length()
	var facing: Vector3 = to_target.normalized() if dist > 0.01 else global_basis.z
	_face(facing, TURN_SPEED)
	if _is_ranged(weapon):
		var sees: bool = _can_see(_target)
		if dist < keep_away_range:
			return -facing * _speed  # Back off
		if dist > shoot_range or not sees:
			return NavPath.direction(self, _target.global_position) * _speed
		if _attack_cooldown <= 0.0:
			_begin_attack()
		return Vector3.ZERO
	var reach: float = _reach(weapon)
	if dist <= reach and _attack_cooldown <= 0.0 and global_basis.z.dot(facing) > 0.7:
		_begin_attack()
		return Vector3.ZERO
	if dist > reach * 0.8:
		return NavPath.direction(self, _target.global_position) * _speed
	return Vector3.ZERO


## Winding up (turning slowly after its target), striking (stepping into
## a melee one), then standing open.
func _state_attack(_delta: float) -> Vector3:
	var want := Vector3.ZERO
	if _state_time < _attack_windup:
		if _is_valid_target(_target):
			var to_target: Vector3 = _flat(_target.global_position - global_position)
			if to_target.length() > 0.01:
				_face(to_target.normalized(), WINDUP_TURN_SPEED)
	elif not _struck:
		_struck = true
		_strike()
	elif _state_time < _attack_windup + _attack_strike:
		var weapon: Weapon3D = _attack_weapon()
		if not _is_ranged(weapon):
			want = global_basis.z * LUNGE_SPEED
		if not weapon:
			_punch()
	if _state_time >= _attack_windup + _attack_strike + _attack_recover:
		_attack_cooldown = randf_range(attack_cooldown_min, attack_cooldown_max)
		_set_state(State.CHASE if _target else State.IDLE)
	return want


## Start an attack with the main weapon (or fists), timed by its weapon.
func _begin_attack() -> void:
	var weapon: Weapon3D = _main_weapon()
	var left: bool = weapon != null and weapon == held_weapon_left
	var windup: float = windup_time
	var strike: float = MIN_STRIKE_TIME
	if weapon and weapon.Properties:
		windup += weapon.Properties.swing_windup
		strike = maxf(weapon.Properties.swing_duration, MIN_STRIKE_TIME)
	if _is_ranged(weapon):
		windup += 0.2  # Aiming
	_attack_cooldown = INF  # Set for real once it's over
	Net.everywhere(_net_attack, left, windup, strike, recover_time)


## Every machine: the attack begins.
@rpc("authority", "call_local", "reliable")
func _net_attack(left: bool, windup: float, strike: float, recover: float) -> void:
	_attack_left = left
	_attack_windup = windup
	_attack_strike = strike
	_attack_recover = recover
	_struck = false
	_punched.clear()
	state = State.ATTACK
	_state_time = 0.0


func _attack_weapon() -> Weapon3D:
	return held_weapon_left if _attack_left else held_weapon_right


## The moment the strike goes out: a melee weapon goes live, a ranged one
## fires at the target.
func _strike() -> void:
	var weapon: Weapon3D = _attack_weapon()
	if not weapon:
		return  # Fists: see _punch
	if _is_ranged(weapon):
		weapon.attack(_aim())
		return
	weapon.start_swing(_attack_strike)


## Where to shoot: at the target, a little ahead of where it's going.
func _aim() -> Vector3:
	if not _is_valid_target(_target):
		return global_basis.z
	var lead: Vector3 = _target.velocity * 0.15
	var to: Vector3 = _flat(_target.global_position + lead - global_position)
	return to.normalized() if to.length() > 0.01 else global_basis.z


## Unarmed strike: whoever the right fist passes through gets hit (once).
func _punch() -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = FIST_REACH
	var at := Transform3D(Basis(), _hand_right.global_position)
	for body: Node3D in Combat.overlaps(get_world_3d(), sphere, at, [get_rid()]):
		if body in _punched or not body is PlayerClass3D:
			continue
		_punched.append(body)
		Combat.strike(body, body.global_position - global_position, FIST_DAMAGE, FIST_KNOCKBACK, FIST_POP, -1.0, self)


## A held weapon's swing met something (see Weapon3D): stop for a moment.
func swing_contact(_weapon: Weapon3D, solid: bool) -> void:
	_hitstop = Combat.HITSTOP if solid else Combat.HITSTOP_LIGHT


## Mid-attack (for bots raising their guard).
func is_swinging() -> bool:
	return state == State.ATTACK


func _update_guard() -> void:
	var shield: ShieldClass3D = _shield()
	if not shield:
		return
	var guard: bool = state == State.CHASE and _is_valid_target(_target) \
		and _flat(_target.global_position - global_position).length() < GUARD_RANGE
	if guard:
		shield.start_block()
	else:
		shield.stop_block()


func _guarding() -> bool:
	var shield: ShieldClass3D = _shield()
	return shield != null and shield.is_blocking


## How far its melee attack reaches: its blade's length past BASE_REACH.
func _reach(weapon: Weapon3D) -> float:
	if not weapon:
		return FIST_RANGE
	var box := weapon.Collision.shape as BoxShape3D if weapon.Collision else null
	return BASE_REACH + (box.size[box.size.max_axis_index()] if box else 1.0) * 0.8


## Time to think again (it doesn't look around every frame).
func _think() -> bool:
	_think_left -= get_physics_process_delta_time()
	if _think_left > 0.0:
		return false
	_think_left = THINK_TIME
	return true


## The nearest player it notices: seen within aggro_range, or heard close by.
func _find_target() -> PlayerClass3D:
	var best: PlayerClass3D = null
	var best_dist: float = aggro_range
	for player: PlayerClass3D in _players():
		if not _is_valid_target(player):
			continue
		var dist: float = global_position.distance_to(player.global_position)
		if dist >= best_dist:
			continue
		if dist > hearing_range and not _can_see(player):
			continue
		best_dist = dist
		best = player
	return best


## Others near it join in on `target` (if they've nobody already).
func _alert_others(target: PlayerClass3D) -> void:
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		var other := node as SkeletonEnemy3D
		if other and other != self and not other.is_dead and not other._target \
				and other.global_position.distance_to(global_position) < alert_range:
			other._notice(target)


func _notice(target: PlayerClass3D) -> void:
	if is_dead or not _is_valid_target(target):
		return
	_target = target
	if state == State.IDLE:
		_set_state(State.CHASE)


func _can_see(target: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.5,
		target.global_position + Vector3.UP * 0.5, Combat.WORLD_MASK)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _is_valid_target(player: PlayerClass3D) -> bool:
	return player != null and is_instance_valid(player) and not player.is_dead()


func _players() -> Array[PlayerClass3D]:
	if Global.Game3D:
		return Global.Game3D.players
	return []


# ===== MOVEMENT =====

func _move(want: Vector3, delta: float) -> void:
	_apply_gravity(delta)
	var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(want, ACCELERATION * delta)
	velocity = Vector3(flat.x, velocity.y, flat.z) + _knockback
	move_and_slide()
	velocity -= _knockback
	_knockback = _knockback.move_toward(Vector3.ZERO, KNOCKBACK_FRICTION * delta)


func _face(dir: Vector3, turn_speed: float) -> void:
	if dir.length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), minf(turn_speed * get_physics_process_delta_time(), 1.0))


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * GRAVITY_SCALE * delta


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# ===== DAMAGE =====

## Called by Combat.strike for every attack that lands on it. Online the
## server keeps its HP, so other machines pass their hits on to it.
func receive_hit(dir: Vector3, damage: float, knockback_velocity: Vector3, attacker: Node3D = null) -> bool:
	if is_dead:
		return false
	if not Net.decides():
		if Net.match_synced:
			_request_hit.rpc_id(Net.SERVER_ID, dir, damage, knockback_velocity)
		return true
	var player := attacker as PlayerClass3D
	if player:
		_last_attacker = player
		if not _target or state == State.IDLE:
			_notice(player)
		_alert_others(player)
	var shield: ShieldClass3D = _shield()
	var blocked: bool = shield != null and shield.is_blocking and global_basis.z.dot(-_flat(dir).normalized()) > BLOCK_FACING_DOT
	if blocked:
		damage *= BLOCK_DAMAGE_RATIO
		knockback_velocity *= BLOCK_KNOCKBACK_RATIO
		shield.wear()
		Sfx.play_everywhere(&"block", shield.global_position)
	else:
		Sfx.play_everywhere(&"hit_player", global_position + Vector3.UP)
	_knockback = _flat(knockback_velocity) * KNOCKBACK_RATIO
	velocity.y = maxf(velocity.y, knockback_velocity.y * KNOCKBACK_RATIO)
	hp -= damage
	if hp <= 0.0:
		_die()
		return not blocked
	Net.everywhere(_net_hurt, blocked)
	_poise_damage += damage
	_poise_reset = POISE_RESET_TIME
	if _poise_damage >= _poise_max:
		_poise_damage = 0.0
		_stagger()
	return not blocked


## Poise broken: drop whatever it was doing and reel.
func _stagger() -> void:
	for weapon: Weapon3D in [held_weapon_left, held_weapon_right]:
		if weapon:
			weapon.cancel_swing()
	_attack_cooldown = 0.0
	_set_state(State.STAGGER)


## Loose physics pushes (see Combat.push) shove it a little.
func receive_impulse(impulse: Vector3) -> void:
	if Net.decides():
		_knockback += _flat(impulse) * 0.5
	elif Net.match_synced:
		_request_push.rpc_id(Net.SERVER_ID, impulse)


func _die() -> void:
	var killer: String = String(_last_attacker.name) if is_instance_valid(_last_attacker) else ""
	for weapon: Weapon3D in [held_weapon_left, held_weapon_right]:
		if weapon:
			weapon.drop()  # Tells everyone
	held_weapon_left = null
	held_weapon_right = null
	Net.everywhere(_net_die, killer)


@rpc("authority", "call_local", "reliable")
func _net_die(killer_name: String) -> void:
	if is_dead:
		return
	is_dead = true
	remove_from_group(GROUP)
	collision_layer = 0
	_set_state_local(State.DEAD)
	Sfx.play(&"weapon_break", global_position + Vector3.UP)  # Bones clattering
	var killer: PlayerClass3D = Global.Game3D.player_named(killer_name) if Global.Game3D and killer_name != "" else null
	died.emit(killer)
	var tween: Tween = create_tween()
	tween.tween_interval(CORPSE_TIME)
	tween.tween_property(visual, "position:y", -1.5, SINK_TIME)
	tween.tween_callback(queue_free)


func _set_state_local(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	_on_state_entered(new_state)


@rpc("authority", "call_local", "unreliable")
func _net_hurt(blocked: bool) -> void:
	_flash = HIT_FLASH_TIME
	if not blocked and tree and state != State.STAGGER:
		tree.set(&"parameters/hit/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


# ===== LOOKS =====

func _set_model(scene: PackedScene) -> void:
	body_model = scene.instantiate()
	body_model.name = "Character"
	body_model.scale = Vector3.ONE * MODEL_SCALE
	visual.add_child(body_model)
	skeleton = body_model.get_node(SKELETON_PATH) as Skeleton3D
	_hand_bone_left = skeleton.find_bone("handslot.l")
	_hand_bone_right = skeleton.find_bone("handslot.r")
	_hand_left.name = "HandLeft"
	_hand_right.name = "HandRight"
	visual.add_child(_hand_left)
	visual.add_child(_hand_right)
	skeleton.skeleton_updated.connect(_on_skeleton_updated)
	_build_tree()


## Locomotion (or reeling, or lying dead) underneath; a flinch and the
## attack or guard clip over the upper body, so the legs keep walking.
func _build_tree() -> void:
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	for library_name: StringName in PlayerVisual3D.LIBRARIES:
		tree.add_animation_library(library_name, PlayerVisual3D.LIBRARIES[library_name])

	var move := AnimationNodeBlendSpace1D.new()
	move.min_space = 0.0
	move.max_space = PlayerVisual3D.RUN_SPEED
	move.add_blend_point(_clip(IDLE_CLIP), 0.0, -1, &"idle")
	move.add_blend_point(_clip(WALK_CLIP), PlayerVisual3D.WALK_SPEED, -1, &"walk")
	move.add_blend_point(_clip(RUN_CLIP), PlayerVisual3D.RUN_SPEED, -1, &"run")
	var states := AnimationNodeStateMachine.new()
	states.add_node(&"Move", move)
	states.add_node(&"Stagger", _clip(STAGGER_CLIP, STAGGER_TIME))
	states.add_node(&"Down", _clip(DEATH_CLIP))  # Holds its last frame
	states.add_transition(&"Start", &"Move", _transition(0.0, true))
	states.add_transition(&"Move", &"Stagger", _transition(0.1))
	var back := _transition(0.15, true)
	back.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
	states.add_transition(&"Stagger", &"Move", back)
	states.add_transition(&"Move", &"Down", _transition(0.1))
	states.add_transition(&"Stagger", &"Down", _transition(0.1))

	var root := AnimationNodeBlendTree.new()
	root.add_node(&"base", states)
	var hit := AnimationNodeOneShot.new()
	hit.fadein_time = 0.05
	hit.fadeout_time = 0.15
	_filter_upper_body(hit)
	root.add_node(&"hit", hit)
	root.add_node(&"hit_clip", _clip(HIT_CLIP, PlayerVisual3D.HIT_DURATION))
	root.connect_node(&"hit", 0, &"base")
	root.connect_node(&"hit", 1, &"hit_clip")
	# The attack clip doesn't play by itself: it's moved to where the attack
	# is each frame (see _update_animation), so hitstop and online playback
	# come out of the attack's own timing.
	var act := AnimationNodeBlend2.new()
	_filter_upper_body(act)
	var act_clip := AnimationNodeAnimation.new()
	act_clip.animation = PUNCH_CLIP
	root.add_node(&"act", act)
	root.add_node(&"act_clip", act_clip)
	root.add_node(&"act_scale", AnimationNodeTimeScale.new())
	root.add_node(&"act_seek", AnimationNodeTimeSeek.new())
	root.connect_node(&"act_scale", 0, &"act_clip")
	root.connect_node(&"act_seek", 0, &"act_scale")
	root.connect_node(&"act", 0, &"hit")
	root.connect_node(&"act", 1, &"act_seek")
	root.connect_node(&"output", 0, &"act")

	tree.tree_root = root
	visual.add_child(tree)
	tree.root_node = tree.get_path_to(body_model)
	tree.active = true
	tree.set(&"parameters/act_scale/scale", 0.0)
	_playback = tree.get(&"parameters/base/playback")


func _filter_upper_body(node: AnimationNode) -> void:
	node.filter_enabled = true
	for bone: String in PlayerVisual3D.UPPER_BODY_BONES:
		node.set_filter_path(NodePath("%s:%s" % [SKELETON_PATH, bone]), true)


func _clip(clip: StringName, duration: float = 0.0) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	if duration > 0.0:
		node.use_custom_timeline = true
		node.timeline_length = duration
		node.stretch_time_scale = true
	return node


func _transition(xfade: float, auto: bool = false) -> AnimationNodeStateMachineTransition:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = xfade
	transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO if auto \
		else AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	return transition


func _go(node: StringName) -> void:
	if _playback:
		_playback.travel(node)


func _update_animation(delta: float) -> void:
	if not tree:
		return
	var moving: Vector3 = velocity if Net.decides() else _seen_velocity
	tree.set(&"parameters/base/Move/blend_position", Vector2(moving.x, moving.z).length())

	# What the upper body acts out: the attack, else a raised guard or drawn bow
	var clip: StringName = &""
	var time: float = 0.0
	if state == State.ATTACK:
		var phase: float = _attack_phase()
		clip = _attack_clip(phase)
		time = _clip_time(clip, phase)
	elif not is_dead and state != State.STAGGER:
		var shield: ShieldClass3D = _shield()
		if shield and shield.is_blocking:
			clip = shield.hold_clip
			time = _clip_time(clip, 0.0)
	var target: float = 1.0 if clip != &"" else 0.0
	_act_weight = move_toward(_act_weight, target, delta / (ACT_BLEND_IN if target > _act_weight else ACT_BLEND_OUT))
	if clip != &"":
		if clip != _act_clip:
			_act_clip = clip
			((tree.tree_root as AnimationNodeBlendTree).get_node(&"act_clip") as AnimationNodeAnimation).animation = clip
		tree.set(&"parameters/act_seek/seek_request", time)
	tree.set(&"parameters/act/blend_amount", _act_weight)


## The attack's phase as in PlayerVisual3D.CLIP_KEYS: 0-1 winding up, 1-2
## striking, 2-3 recovering.
func _attack_phase() -> float:
	var t: float = _state_time
	if t < _attack_windup:
		return t / _attack_windup
	t -= _attack_windup
	if t < _attack_strike:
		return 1.0 + t / _attack_strike
	t -= _attack_strike
	return 2.0 + minf(t / maxf(_attack_recover, 0.01), 1.0)


## The clip for the attack: the weapon's swing (aiming a drawn bow while
## winding up), or a punch.
func _attack_clip(phase: float) -> StringName:
	var weapon: Weapon3D = _attack_weapon()
	if not weapon:
		return PUNCH_CLIP
	if phase < 1.0 and weapon.hold_clip != &"" and _is_ranged(weapon):
		return weapon.hold_clip
	return weapon.offhand_swing_clip if _attack_left else weapon.swing_clip


## Seconds into `clip` at an action `phase` (see PlayerVisual3D.CLIP_KEYS).
func _clip_time(clip: StringName, phase: float) -> float:
	var keys: Vector4 = PlayerVisual3D.CLIP_KEYS.get(clip, Vector4(0.0, 0.3, 0.5, 1.0))
	if phase <= 1.0:
		return lerpf(keys.x, keys.y, maxf(phase, 0.0))
	if phase <= 2.0:
		return lerpf(keys.y, keys.z, phase - 1.0)
	return lerpf(keys.z, keys.w, minf(phase - 2.0, 1.0))


## The skeleton has just been posed: move the hands, and what they hold.
func _on_skeleton_updated() -> void:
	if not is_inside_tree():
		return
	_hand_left.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(_hand_bone_left)
	_hand_right.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(_hand_bone_right)
	for weapon: Weapon3D in [held_weapon_left, held_weapon_right]:
		if weapon:
			weapon.on_hand_posed()


## A white flash when hit; an orange glow, pulsing faster, while winding up.
func _update_overlay(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	var color := Color(0, 0, 0, 0)
	if _flash > 0.0:
		color = Color(HIT_FLASH_COLOR, HIT_FLASH_COLOR.a * _flash / HIT_FLASH_TIME)
	elif state == State.ATTACK and _state_time < _attack_windup:
		var t: float = _state_time / _attack_windup
		var pulse: float = 0.5 + 0.5 * sin(_state_time * lerpf(12.0, 30.0, t))
		color = Color(TELEGRAPH_COLOR, TELEGRAPH_COLOR.a * lerpf(0.3, 1.0, t) * pulse)
	var on: bool = color.a > 0.01
	_overlay.albedo_color = color
	if on != _overlay_on and body_model:
		_overlay_on = on
		for mesh: MeshInstance3D in body_model.find_children("*", "MeshInstance3D", true, false):
			mesh.material_overlay = _overlay if on else null


# ===== NETWORK =====

func _send_state() -> void:
	if Net.in_session() and Net.is_server and Net.match_synced and _motion.should_send(global_transform):
		_net_state.rpc(NetInterpolator.now(), global_transform)


@rpc("authority", "unreliable_ordered")
func _net_state(time: float, xform: Transform3D) -> void:
	_motion.push(time, xform)


@rpc("authority", "reliable")
func _net_phase(new_state: State) -> void:
	if not is_dead:
		_set_state_local(new_state)


## A client's player hit it; the sender's player gets the credit.
@rpc("any_peer", "reliable")
func _request_hit(dir: Vector3, damage: float, knockback_velocity: Vector3) -> void:
	if Net.is_server:
		receive_hit(dir, damage, knockback_velocity, Global.Game3D.rpc_sender() if Global.Game3D else null)


@rpc("any_peer", "reliable")
func _request_push(impulse: Vector3) -> void:
	if Net.is_server:
		receive_impulse(impulse)
