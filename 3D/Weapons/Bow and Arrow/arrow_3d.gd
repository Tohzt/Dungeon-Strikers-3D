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

@export var damage: float = 20.0
@export var impact_impulse: float = 6.0
@export var knockback: float = 10.0  # Shove speed given to a player it hits
## Above 0, hitting the ball turns it to fly the way this was going, at
## least this fast (m/s), instead of just shoving it (the staff's bolt).
@export var ball_redirect_speed: float = 0.0
## Safety net: an arrow that somehow never hits anything is removed after this.
@export var max_lifetime: float = 5.0

## Walls and floor. The HitArea can't be relied on for these: areas don't
## always report static bodies (Jolt skips them by default), and a fast arrow
## can pass a thin wall between two physics ticks. So each tick casts a ray
## along the distance just travelled instead.
const WORLD_MASK := 0b1

## False for online copies of someone else's shot, which only show it.
var deals_damage: bool = true

@onready var hit_area: Area3D = $HitArea

var is_flying: bool = false
var _excluded_bodies: Array[Node] = []
## Who fired it, for perks and kill credit.
var shooter: Node3D = null
var _age: float = 0.0
var _last_tip: Vector3


## Exempts a body from ever registering as a hit. Used to keep the arrow
## from immediately "hitting" its own shooter or the weapon it was just
## fired from - a held weapon is tagged with the Player collision layer (see
## Weapon3D._update_collisions), which the hit mask below deliberately
## includes so arrows can hit other players later, so without this the arrow
## detects the bow it just spawned next to as an instant hit.
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
	_last_tip = _tip()


func _physics_process(delta: float) -> void:
	if not is_flying:
		return
	_age += delta
	if _age > max_lifetime:
		queue_free()
		return
	if _hit_world():
		queue_free()
		return
	if linear_velocity.length_squared() < 0.01:
		return
	_align_to_velocity(linear_velocity)


## The arrowhead: the front of the shaft along its flight direction.
func _tip() -> Vector3:
	return global_position + linear_velocity.normalized() * 0.5


func _hit_world() -> bool:
	var tip: Vector3 = _tip()
	var query := PhysicsRayQueryParameters3D.create(_last_tip, tip, WORLD_MASK)
	_last_tip = tip
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


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

	# Players take damage + knockback (unless shield-blocked); physics props
	# (the ball, a placeholder dummy) just get shoved - same as every attack.
	if deals_damage:
		if body is Ball3D and ball_redirect_speed > 0.0:
			body.redirect(travel_dir, ball_redirect_speed)
			body.touched_by(shooter)
		else:
			Combat.strike(body, travel_dir, damage, knockback, 1.0, impact_impulse, shooter)

	queue_free()
