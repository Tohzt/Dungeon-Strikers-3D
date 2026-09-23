class_name Arrow3D extends RigidBody3D
## Fired projectile: flies in a straight line (arcing under gravity like any
## RigidBody3D) and orients itself to match its flight path. On its first
## impact it damages/knocks back whatever it hit - anything with an `Entity`
## (EntityBehavior3D) like a player, or any other RigidBody3D like the ball -
## then destroys itself. (No stick-in-place; an impact effect will replace
## that visually later.)
##
## Hit detection goes through a child HitArea (Area3D) rather than this
## body's own collision: the arrow's own RigidBody3D has no collision layer
## at all, so it never physically collides with anything itself. Two fast
## solid RigidBody3Ds colliding get their own physics-engine bounce response
## on top of (and fighting with, in an unpredictable direction) any impulse
## applied from script - an Area3D overlap never generates that.

@export var damage: float = 10.0
@export var impact_impulse: float = 6.0

@onready var hit_area: Area3D = $HitArea

var is_flying: bool = false
var _excluded_bodies: Array[Node] = []


## Exempts a body from ever registering as a hit. Used to keep the arrow
## from immediately "hitting" its own shooter or the weapon it was just
## fired from - a held weapon is tagged with the Player collision layer (see
## Weapon3D._update_collisions), which the hit mask below deliberately
## includes so arrows can hit other players later, so without this the arrow
## detects the crossbow it just spawned next to as an instant hit.
## (Area3D has no add_collision_exception_with - that's PhysicsBody3D-only -
## so this is a plain manual skip-list instead.)
func exclude_body(body: Node) -> void:
	_excluded_bodies.append(body)


## Launches the arrow. `direction` only needs a horizontal component; gravity
## handles the vertical arc from there.
func fire(direction: Vector3, speed: float) -> void:
	is_flying = true
	linear_velocity = direction.normalized() * speed
	angular_velocity = Vector3.ZERO
	hit_area.body_entered.connect(_on_body_entered)
	# Orient immediately rather than waiting for the next _physics_process:
	# attack() fires from _process (idle frame), so one or more rendered
	# frames can pass before physics next ticks, during which the arrow
	# would otherwise sit at its default spawn rotation - a visible flash of
	# the wrong orientation before it snaps to match its velocity.
	_align_to_velocity(linear_velocity)


func _physics_process(_delta: float) -> void:
	if not is_flying or linear_velocity.length_squared() < 0.01:
		return
	_align_to_velocity(linear_velocity)


func _align_to_velocity(velocity: Vector3) -> void:
	var dir: Vector3 = velocity.normalized()
	rotation.y = atan2(dir.x, dir.z)
	rotation.x = asin(clamp(dir.y, -1.0, 1.0))


func _on_body_entered(body: Node) -> void:
	if not is_flying or body in _excluded_bodies: return
	is_flying = false

	var travel_dir: Vector3 = Vector3.FORWARD
	if linear_velocity.length_squared() > 0.01:
		travel_dir = linear_velocity.normalized()

	# Anything with an Entity (EntityBehavior3D) - players, and eventually
	# other entities - takes real damage + knockback through that shared API.
	# Anything else that's just a physics prop (the ball, a placeholder
	# dummy) gets a plain impulse shove instead.
	var entity: Object = body.get("Entity")
	if entity and entity.has_method("take_damage"):
		entity.take_damage(damage, travel_dir)
	elif body is RigidBody3D:
		body.apply_central_impulse(travel_dir * impact_impulse)

	queue_free()
