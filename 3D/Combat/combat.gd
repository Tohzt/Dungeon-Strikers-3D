class_name Combat
## Shared hit resolution for fists, swung weapons, thrown weapons and arrows,
## so every attack damages, shoves and gets blocked the same way.

const HIT_MASK := 0b110  # Player + Enemy layers (the ball is on Enemy)
## Loose physics objects (ball, enemies) get this fraction of the knockback
## speed as an impulse, unless the attack passes its own.
const OBJECT_IMPULSE_RATIO := 0.45
const WORLD_MASK := 0b1
## A swing that connects freezes the arm (and whoever got hit) this long, so
## the contact reads as a solid thunk instead of the blade passing through.
const HITSTOP := 0.08
## Light things (the ball) barely slow a swing down.
const HITSTOP_LIGHT := 0.04
## A player below this share of their max HP counts as wounded (see the
## damage_vs_wounded perk stat).
const WOUNDED_HP_RATIO := 0.3
## The homing perk stat (see home): each point over 1 turns an attack this
## fast (radians/s) toward an enemy up to HOMING_RANGE away, within
## HOMING_CONE (radians) of where it's headed.
const HOMING_TURN_RATE := deg_to_rad(240.0)
const HOMING_RANGE := 10.0
const HOMING_CONE := deg_to_rad(60.0)
static var _homing_shape := SphereShape3D.new()


## Physics bodies overlapping `shape` placed at `xform`, minus `exclude`.
static func overlaps(world: World3D, shape: Shape3D, xform: Transform3D, exclude: Array[RID]) -> Array[Node3D]:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = xform
	query.collision_mask = HIT_MASK
	query.exclude = exclude
	var bodies: Array[Node3D] = []
	for result: Dictionary in world.direct_space_state.intersect_shape(query):
		var body: Node3D = result.collider
		if body and not bodies.has(body):
			bodies.append(body)
	return bodies


## Whether a swing stops dead on `body` and springs back (players, blades,
## walls, skeletons), rather than following through it (the ball, minions).
static func is_solid(body: Node3D) -> bool:
	return not body is Ball3D and not body is SlimeMinion3D


## Whether `shape` at `xform` is inside a wall. Floors don't count, so a low
## swing can graze the ground.
static func touches_wall(world: World3D, shape: Shape3D, xform: Transform3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = xform
	query.collision_mask = WORLD_MASK
	var exclude: Array[RID] = []
	for i in 4:
		query.exclude = exclude
		var info: Dictionary = world.direct_space_state.get_rest_info(query)
		if info.is_empty():
			return false
		if info.normal.y < 0.7:
			return true
		exclude.append(info.rid)
	return false


## Hit `body` with an attack travelling along `dir`. Players take damage and
## get shoved (a raised shield facing the attack takes most of it), bosses and minions take damage;
## other unfrozen physics bodies just get pushed. Returns true if a player,
## boss or minion took the hit.
## `attacker` is the player behind the attack, if any: their perks scale it,
## and whoever it hits remembers them (a boss's or player's killer gets
## the credit).
## Online, a hit on someone else's player is sent to its owner, who decides
## whether it was blocked, so remote hits always report true.
## Teammates pass through each other's attacks untouched.
## Above 0, `knock_down` knocks a player down if it gets through, for that
## many times as long as a slide tackle (1).
static func strike(body: Node3D, dir: Vector3, damage: float, knockback: float, pop: float, object_impulse: float = -1.0, attacker: Node3D = null, knock_down: float = 0.0) -> bool:
	if are_teammates(body, attacker):
		return false
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	var impulse: float = object_impulse if object_impulse >= 0.0 else knockback * OBJECT_IMPULSE_RATIO
	if attacker is PlayerClass3D:
		damage *= attacker.perk_stat(&"damage") * attacker.counter_multiplier()
		knockback *= attacker.perk_stat(&"knockback")
		impulse *= attacker.perk_stat(&"ball_power" if body is Ball3D else &"knockback")
		if body is Boss3D:
			damage *= attacker.perk_stat(&"boss_damage")
		elif body is PlayerClass3D:
			if _is_ahead_of(body, attacker):
				damage *= attacker.perk_stat(&"damage_vs_leader")
			if body.Entity and body.Entity.hp < body.Entity.hp_max * WOUNDED_HP_RATIO:
				damage *= attacker.perk_stat(&"damage_vs_wounded")
	if body is PlayerClass3D:
		return body.receive_hit(dir, damage, dir * knockback + Vector3.UP * pop, attacker, knock_down)
	if body is Boss3D or body is SlimeMinion3D or body is SkeletonEnemy3D or body is Tower3D:
		return body.receive_hit(dir, damage, dir * knockback + Vector3.UP * pop, attacker)
	if body is Ball3D:
		body.touched_by(attacker)
		Sfx.play_everywhere(&"hit_ball", body.global_position)
	push(body, (dir + Vector3.UP * 0.3) * impulse)
	return false


## `dir` (flat) turned toward the nearest enemy of `attacker` ahead of
## `from`, by as much as its homing perk stat turns it in `delta` seconds.
## Unchanged if it has none or there's no one to turn to.
static func home(world: World3D, from: Vector3, dir: Vector3, attacker: Node3D, delta: float) -> Vector3:
	if not attacker is PlayerClass3D:
		return dir
	var rate: float = (attacker.perk_stat(&"homing") - 1.0) * HOMING_TURN_RATE
	if rate <= 0.0:
		return dir
	var target: Node3D = _homing_target(world, from, dir, attacker)
	if not target:
		return dir
	var to: Vector3 = target.global_position - from
	to.y = 0.0
	var angle: float = dir.signed_angle_to(to.normalized(), Vector3.UP)
	return dir.rotated(Vector3.UP, clampf(angle, -rate * delta, rate * delta))


## The nearest player or monster `attacker` could hurt, within HOMING_RANGE
## of `from` and HOMING_CONE of `dir`.
static func _homing_target(world: World3D, from: Vector3, dir: Vector3, attacker: Node3D) -> Node3D:
	_homing_shape.radius = HOMING_RANGE
	var exclude: Array[RID] = []
	if attacker is CollisionObject3D:
		exclude.append(attacker.get_rid())
	var best: Node3D = null
	var best_distance: float = INF
	for body: Node3D in overlaps(world, _homing_shape, Transform3D(Basis(), from), exclude):
		if not (body is PlayerClass3D or is_monster(body)) or are_teammates(body, attacker):
			continue
		if body is PlayerClass3D and body.is_dead():
			continue
		var to: Vector3 = body.global_position - from
		to.y = 0.0
		var distance: float = to.length()
		if distance < 0.3 or distance >= best_distance or absf(dir.angle_to(to)) > HOMING_CONE:
			continue
		best = body
		best_distance = distance
	return best


## Whether `a` and `b` are two different things on the same team (players,
## towers and towers' slimes), or both monsters (they don't fight each other).
static func are_teammates(a: Node3D, b: Node3D) -> bool:
	if is_monster(a) and is_monster(b):
		return true
	if not a or not b or a == b:
		return false
	var team: int = team_of(a)
	return team >= 0 and team == team_of(b)


## The team `node` fights for: a player's, a tower's (Tower3D) or one of its
## slimes'. -1 for monsters and everything else.
static func team_of(node: Node3D) -> int:
	if node is PlayerClass3D:
		return node.slot.team if node.slot else -1
	if node is Tower3D:
		return node.owner_team
	if node is SlimeMinion3D:
		return node.team
	return -1


## Bosses, skeletons and the boss's slimes (not a tower's).
static func is_monster(node: Node3D) -> bool:
	return node is Boss3D or (node is SlimeMinion3D and node.team < 0) or node is SkeletonEnemy3D


## Whether `player`'s team has more kills than `other`'s.
static func _is_ahead_of(player: PlayerClass3D, other: PlayerClass3D) -> bool:
	if not Global.Game3D or not player.slot or not other.slot:
		return false
	var kills: Dictionary[int, int] = Global.Game3D.kills
	return kills.get(player.slot.team, 0) > kills.get(other.slot.team, 0)


## Shove a loose physics object. Networked ones (ball, weapons) pass the push
## on to whichever machine simulates them.
static func push(body: Node3D, impulse: Vector3) -> void:
	if body.has_method("receive_impulse"):
		body.receive_impulse(impulse)
	elif body is RigidBody3D and not body.freeze:
		body.apply_central_impulse(impulse)
