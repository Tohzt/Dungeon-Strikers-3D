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
## walls), rather than following through it (the ball).
static func is_solid(body: Node3D) -> bool:
	return not body is Ball3D


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
## get shoved (unless a raised shield faces the attack), bosses take damage;
## other unfrozen physics bodies just get pushed. Returns true if a player
## or boss took the hit.
## Online, a hit on someone else's player is sent to its owner, who decides
## whether it was blocked, so remote hits always report true.
static func strike(body: Node3D, dir: Vector3, damage: float, knockback: float, pop: float, object_impulse: float = -1.0) -> bool:
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	if body is PlayerClass3D:
		return body.receive_hit(dir, damage, dir * knockback + Vector3.UP * pop)
	if body is Boss3D:
		return body.receive_hit(dir, damage, dir * knockback + Vector3.UP * pop)
	var impulse: float = object_impulse if object_impulse >= 0.0 else knockback * OBJECT_IMPULSE_RATIO
	push(body, (dir + Vector3.UP * 0.3) * impulse)
	return false


## Shove a loose physics object. Networked ones (ball, weapons) pass the push
## on to whichever machine simulates them.
static func push(body: Node3D, impulse: Vector3) -> void:
	if body.has_method("receive_impulse"):
		body.receive_impulse(impulse)
	elif body is RigidBody3D and not body.freeze:
		body.apply_central_impulse(impulse)
