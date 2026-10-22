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
## With ball_redirect_speed: added to the ball's speed, so a bolt always
## speeds it up, even when it's already flying.
@export var ball_redirect_boost: float = 0.0
## With ball_redirect_speed: pops the ball up at least this fast (m/s).
@export var ball_redirect_lift: float = 0.0
## Safety net: an arrow that somehow never hits anything is removed after this.
@export var max_lifetime: float = 5.0
## What hitting a wall or the floor sounds like (an Sfx.SOUNDS id).
@export var wall_sound: StringName = &"arrow_wall"
## What hitting anything else sounds like, on top of its own hit sound.
## Empty = only the hit sound.
@export var body_sound: StringName = &""
## Shown as it instead of its Mesh and light: a HELD Vfx.EFFECTS id (a
## spell's bolt), `look_size` meters across, in `look_color`. Empty = its
## Mesh.
@export var look: StringName = &""
@export var look_size: float = 0.5
@export var look_color: Color = Color.TRANSPARENT

## Walls and floor. The HitArea can't be relied on for these: areas don't
## always report static bodies (Jolt skips them by default), and a fast arrow
## can pass a thin wall between two physics ticks. So each tick casts a ray
## along the distance just travelled instead.
const WORLD_MASK := 0b1

## False for online copies of someone else's shot, which only show it.
var deals_damage: bool = true
## Flies on through whoever it hits (a heavy shot), hitting each once; only
## a wall stops it.
var pierce: bool = false
var _pierced: Array[Node] = []

## The shot that breaks its weapon bursts where it lands, wall or body, in
## the weapon's break burst (see CrossbowClass3D). 0 = an ordinary shot.
var burst_radius: float = 0.0
var burst_damage: float = 0.0
var burst_knockback: float = 0.0
var burst_color: Color = Color.WHITE

@onready var hit_area: Area3D = $HitArea

var is_flying: bool = false
var _excluded_bodies: Array[Node] = []
## Who fired it, for perks and kill credit.
var shooter: Node3D = null
var _age: float = 0.0
var _last_tip: Vector3
var _look: Node3D = null
## Times its size, from enlarge() (which may come before its look is made).
var _size: float = 1.0


func _ready() -> void:
	if look == &"":
		return
	_look = Vfx.attach(look, self, Vector3.ZERO, 0.0, look_size * _size, look_color)
	if _look:
		for child: Node in get_children():
			if child is MeshInstance3D or child is OmniLight3D:
				child.visible = false


## Gone (landed, or flown too long): its look fades out where it is.
func _finish() -> void:
	Vfx.release(_look)
	queue_free()


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
	# Its shooter left the match (online): even `shooter is ...` errors on a
	# freed node
	if not is_instance_valid(shooter):
		shooter = null
	# Timed out even once it's stopped flying, in case a landing was cut
	# short before it got to _finish()
	_age += delta
	if _age > max_lifetime:
		_finish()
		return
	if not is_flying:
		return
	if _hit_world():
		Sfx.play(wall_sound, global_position)
		_burst(null)
		_finish()
		return
	if linear_velocity.length_squared() < 0.01:
		return
	_home(delta)
	_align_to_velocity(linear_velocity)


## The shooter's homing perk stat: turn a little toward the nearest enemy
## ahead, keeping speed (and any rise or fall).
func _home(delta: float) -> void:
	var flat := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	if flat.length_squared() < 0.01:
		return
	var turned: Vector3 = Combat.home(get_world_3d(), global_position, flat.normalized(), shooter, delta)
	turned *= flat.length()
	linear_velocity = Vector3(turned.x, linear_velocity.y, turned.z)


## The arrowhead: the front of the shaft along its flight direction.
func _tip() -> Vector3:
	return global_position + linear_velocity.normalized() * 0.5


func _hit_world() -> bool:
	var tip: Vector3 = _tip()
	var query := PhysicsRayQueryParameters3D.create(_last_tip, tip, WORLD_MASK)
	_last_tip = tip
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Make this shot burst where it lands.
func set_burst(radius: float, burst_dmg: float, burst_shove: float, color: Color) -> void:
	burst_radius = radius
	burst_damage = burst_dmg
	burst_knockback = burst_shove
	burst_color = color


## Burst, if this shot does, sparing `struck` (just hit by the shot itself).
## Everyone sees it; only a real shot hurts.
func _burst(struck: Node) -> void:
	if burst_radius <= 0.0 or not is_inside_tree():
		return
	if deals_damage:
		var exclude: Array[RID] = [get_rid()]
		if struck is CollisionObject3D:
			exclude.append(struck.get_rid())
		Weapon3D.burst(get_world_3d(), global_position, burst_radius, burst_damage, burst_knockback, shooter, exclude)
	Sfx.play(&"weapon_break", global_position)
	WeaponShatter3D.spawn(get_parent(), global_position, burst_color, burst_radius)
	Vfx.play(&"shatter", global_position, Vector3.FORWARD, false, burst_radius, burst_color)


func _align_to_velocity(velocity: Vector3) -> void:
	var dir: Vector3 = velocity.normalized()
	rotation.y = atan2(dir.x, dir.z)
	rotation.x = asin(clamp(dir.y, -1.0, 1.0))


## Everything about it this many times bigger (not the body itself: physics
## bodies mustn't be scaled).
func enlarge(factor: float) -> void:
	_size *= factor
	for child: Node in get_children():
		if child is Node3D:
			(child as Node3D).scale *= factor


func _on_body_entered(body: Node) -> void:
	if not is_flying or body in _excluded_bodies or body in _pierced: return
	if pierce:
		_pierced.append(body)
	else:
		is_flying = false
	if body_sound != &"":
		Sfx.play(body_sound, global_position)

	var travel_dir: Vector3 = Vector3.FORWARD
	if linear_velocity.length_squared() > 0.01:
		travel_dir = linear_velocity.normalized()

	# Players take damage + knockback (unless shield-blocked); physics props
	# (the ball, a placeholder dummy) just get shoved - same as every attack.
	if deals_damage:
		if body is Ball3D and ball_redirect_speed > 0.0:
			var power: float = shooter.perk_stat(&"ball_power") if shooter is PlayerClass3D else 1.0
			body.redirect(travel_dir, ball_redirect_speed * power, ball_redirect_boost * power, ball_redirect_lift)
			body.touched_by(shooter)
			Sfx.play_everywhere(&"hit_ball", body.global_position)
		else:
			Combat.strike(body, travel_dir, damage, knockback, 1.0, impact_impulse, shooter)
	if pierce:
		return
	_burst(body)

	_finish()
