class_name Combat
## Shared hit resolution for fists, swung weapons, thrown weapons and arrows,
## so every attack damages, shoves and gets blocked the same way.

const HIT_MASK := 0b110  # Player + Enemy layers (the ball is on Enemy)
## Loose physics objects (ball, enemies) get this fraction of the knockback
## speed as an impulse, unless the attack passes its own.
const OBJECT_IMPULSE_RATIO := 0.45


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


## Hit `body` with an attack travelling along `dir`. Players take damage and
## get shoved (unless a raised shield faces the attack); other unfrozen
## physics bodies just get pushed. Returns true if a player took the hit.
static func strike(body: Node3D, dir: Vector3, damage: float, knockback: float, pop: float, object_impulse: float = -1.0) -> bool:
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	if body is PlayerClass3D:
		return body.receive_hit(dir, damage, dir * knockback + Vector3.UP * pop)
	if body is RigidBody3D and not body.freeze:
		var impulse: float = object_impulse if object_impulse >= 0.0 else knockback * OBJECT_IMPULSE_RATIO
		body.apply_central_impulse((dir + Vector3.UP * 0.3) * impulse)
	return false
