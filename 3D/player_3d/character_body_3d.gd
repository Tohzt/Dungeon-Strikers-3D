class_name PlayerClass3D extends CharacterBody3D
@onready var Entity: EntityBehavior3D = $Entity
@onready var mesh_instance_3d: Array[MeshInstance3D] = [$Body/MeshInstance3D, $Appendages/Shoulder_Left/Hand_Left/CollisionShape3D/MeshInstance3D, $Appendages/Shoulder_Right/Hand_Right/CollisionShape3D/MeshInstance3D]
@onready var hand_right: Area3D = $Appendages/Shoulder_Right/Hand_Right
@onready var hand_left: Area3D = $Appendages/Shoulder_Left/Hand_Left
@onready var shoulder_left: Node3D = hand_left.get_parent() if hand_left else null
@onready var shoulder_right: Node3D = hand_right.get_parent() if hand_right else null
@onready var hand_left_mesh: MeshInstance3D = hand_left.get_node_or_null("CollisionShape3D/MeshInstance3D") if hand_left else null
@onready var hand_right_mesh: MeshInstance3D = hand_right.get_node_or_null("CollisionShape3D/MeshInstance3D") if hand_right else null

@export var Properties: PlayerResource
@export var Input_Handler: PlayerInputHandler3D

## Which local player this is (device, team, color). Assigned by Game3D
## before the player enters the tree; null = listen to every device.
var slot: PlayerSlot = null

var held_weapon_left: Weapon3D = null
var held_weapon_right: Weapon3D = null
var held_ball: RigidBody3D = null
var held_ball_hand_is_left: bool = false
var original_collision_layer: int = 0
var original_collision_mask: int = 0
var was_attack_left: bool = false
var was_attack_right: bool = false

# Tap-to-swing, hold-to-throw: track when each attack button was pressed so
# we can measure hold duration on release.
const HOLD_THRESHOLD := 0.35
var attack_left_press_time: float = 0.0
var attack_right_press_time: float = 0.0
# A release only acts if its press was seen by the attack logic. Presses made
# while blocking are swallowed, so e.g. Alt+click (which is both heavy and
# plain attack) doesn't throw the shield when the button comes back up.
var attack_left_armed: bool = false
var attack_right_armed: bool = false

# How long past HOLD_THRESHOLD you can charge a throw for max power, and the
# force multiplier range that charge maps to (0.0 charge = just past the
# threshold, 1.0 charge = held for THROW_CHARGE_MAX_DURATION or longer).
const THROW_CHARGE_MAX_DURATION := 1.0
const THROW_FORCE_MIN_RATIO := 0.5
const THROW_FORCE_MAX_RATIO := 1.5

# Simple swipe parameters for whichever hand holds a weapon
var swipe_timer_left: float = 0.0
var swipe_timer_right: float = 0.0
const SWIPE_DURATION := 0.25
var original_shoulder_rotation_left: Vector3
var original_shoulder_rotation_right: Vector3

# Wind-up: while a hand holding something throwable (weapon or ball) is
# pressed, the arm pulls back progressively instead of sitting static, so a
# throw doesn't just fire from a resting pose. Ramps up over the same
# press-and-hold window that charges throw force, so a fully wound-up arm
# means a fully-charged throw is coming.
const WINDUP_RAMP_DURATION := HOLD_THRESHOLD + THROW_CHARGE_MAX_DURATION
const WINDUP_MAX_ANGLE := deg_to_rad(35)
const WINDUP_LERP_SPEED := 6.0
var windup_left: float = 0.0
var windup_right: float = 0.0

# Walk sway: arms swing forward/back in opposition while moving on the ground.
# The cycle advances with distance travelled, so running (higher speed)
# naturally swings faster; amplitude eases in/out with speed so starting and
# stopping blend smoothly instead of popping.
const SWAY_MAX_ANGLE := deg_to_rad(12)
const SWAY_CYCLES_PER_METER := 0.32
const SWAY_RUN_AMPLITUDE_RATIO := 1.3
const SWAY_BLEND_SPEED := 6.0
var sway_phase: float = 0.0
var sway_amount: float = 0.0
# Per-arm fade so an arm that's busy (aiming a crossbow, blocking, winding up)
# settles to rest instead of swinging while the other arm keeps swaying.
var sway_weight_left: float = 0.8
var sway_weight_right: float = 0.8

# Local rest pose of each hand mesh, restored when it stops following a
# held weapon (see _sync_hand_mesh).
var hand_left_mesh_rest: Transform3D
var hand_right_mesh_rest: Transform3D

const THROW_FORCE = 10.0
const UPWARD_FORCE = 3.0

const JUMP_VELOCITY = 4.5
const ROTATION_SPEED = 10.0

# Knockback: shoves (bumps, punches, hits) live in their own velocity that's
# added on top of walking and slides to a stop, instead of being overwritten
# by movement the next frame. While being shoved you only get partial control,
# which is where the clumsy stumble comes from.
const KNOCKBACK_MAX := 16.0  # Horizontal speed cap for any single shove
const KNOCKBACK_POP_MAX := 5.0  # Upward pop cap
const KNOCKBACK_FRICTION := 18.0  # How fast a shove slides to a stop on the ground
const KNOCKBACK_AIR_FRICTION := 4.0
const KNOCKBACK_CONTROL_LOSS := 10.0  # Shove speed at which walking control bottoms out
const KNOCKBACK_MIN_CONTROL := 0.25
const KNOCKBACK_WALL_BOUNCE := 0.5  # Fraction of a shove kept when bouncing off a wall
var knockback: Vector3 = Vector3.ZERO

# Bumping into other players: both get shoved apart, harder the faster you
# were closing in (so a sprinting player bowls a walking one over).
const BODY_RADIUS := 0.5
const BUMP_BASE := 3.0
const BUMP_CLOSING_TRANSFER := 0.9  # Share of closing speed passed on as shove
const BUMP_SELF_RATIO := 0.5  # Bumper recoils with this fraction of the shove
const BUMP_POP := 1.5
const BUMP_COOLDOWN := 0.3
const BUMP_SEPARATION := 6.0  # Gentle push apart while still overlapping during cooldown
var bump_cooldown: float = 0.0

# Fists: attacking with an empty hand swings it (same shoulder swing as a
# weapon) and punches whatever the fist passes through, once per swing.
const FIST_REACH := 0.4  # Radius around the hand that counts as a hit
const FIST_DAMAGE := 10.0  # Players have 500 HP; a sword hit is 40
const FIST_KNOCKBACK := 9.0
const FIST_POP := 3.0
const FIST_RECOIL := 2.0  # Puncher is nudged back a little on a hit
const FIST_OBJECT_IMPULSE := 4.0  # Shove given to loose physics objects (ball, enemies)

# Raised shield: hits from the front (within this cosine of facing) are
# blocked - no damage, and only this fraction of the shove gets through.
const BLOCK_FACING_DOT := 0.3
const BLOCK_KNOCKBACK_RATIO := 0.35

# Stamina (the Entity's stamina pool, shown on the HUD): sprinting drains it,
# attacks and throws cost a chunk. Running dry stops sprinting until it's
# recovered a bit. It refills on its own shortly after you stop using it.
const SPRINT_STAMINA_PER_SEC := 2.5
const SPRINT_RECOVER_RATIO := 0.3  # Must refill to this share after running dry
const PUNCH_STAMINA := 1.0
const SWING_STAMINA := 1.5
const THROW_STAMINA := 2.0  # Too tired to pay = weakest possible throw
var is_sprinting: bool = false
var sprint_exhausted: bool = false

var punching_left: bool = false
var punching_right: bool = false
var punch_hits_left: Array[Node] = []
var punch_hits_right: Array[Node] = []


func _ready() -> void:
	# Properties is a sub-resource of player_3d.tscn, so every instance would
	# share it (and speed_mod is written every frame) - give each player its own.
	if Properties:
		Properties = Properties.duplicate()
		if slot:
			Properties.player_id = slot.index
			Properties.player_color = slot.color
	if Input_Handler:
		Input_Handler.slot = slot

	# Initialize spawn position
	if Entity:
		Entity.spawn_pos = global_position
		# Initialize Entity with Properties if available
		if Properties:
			Entity.reset(true)

	# Cache original rotation of both shoulders (used to reset after swipes)
	if shoulder_left:
		original_shoulder_rotation_left = shoulder_left.rotation
	if shoulder_right:
		original_shoulder_rotation_right = shoulder_right.rotation
	if hand_left_mesh:
		hand_left_mesh_rest = hand_left_mesh.transform
	if hand_right_mesh:
		hand_right_mesh_rest = hand_right_mesh.transform


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	var direction: Vector3 = Vector3.ZERO
	if Input_Handler:
		direction = Input_Handler.move_dir
	_update_sprint(direction, delta)

	# Apply jump velocity multiplier only when jump is initiated, not every frame
	if Input_Handler.move_jump and is_on_floor():
		var jump_multiplier: float = 1.0
		if is_sprinting:
			jump_multiplier = 1.5  # Sprint jump multiplier
		velocity.y = JUMP_VELOCITY * jump_multiplier

	if is_sprinting:
		Properties.speed_mod.x = 2.0
		Properties.speed_mod.z = 2.0
	else:
		Properties.speed_mod = Vector3.ONE

	# Walking velocity (speed_mod applies only to horizontal, not vertical)
	var speed: float = Entity.SPEED if Entity else 5.0
	var walk: Vector3 = direction * speed
	if Properties:
		walk.x *= Properties.speed_mod.x
		walk.z *= Properties.speed_mod.z
	# Being shoved takes some control away until the shove dies down
	var control: float = clamp(1.0 - knockback.length() / KNOCKBACK_CONTROL_LOSS, KNOCKBACK_MIN_CONTROL, 1.0)
	velocity.x = walk.x * control + knockback.x
	velocity.z = walk.z * control + knockback.z

	# Face the aim direction if aiming (works while standing still too),
	# otherwise face the direction we're trying to walk (not the shove).
	if Input_Handler and !Input_Handler.look_dir.is_zero_approx():
		var look_dir: Vector3 = Input_Handler.look_dir
		var target_angle: float = atan2(look_dir.x, look_dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, ROTATION_SPEED * delta)
	elif !direction.is_zero_approx():
		var target_angle: float = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_angle, ROTATION_SPEED * delta)

	move_and_slide()
	_update_knockback(delta)
	_bump_other_players(delta)

	_update_weapon_windups(delta)
	_update_arm_sway(delta)
	_update_weapon_swipes(delta)
	_update_punches()
	_update_hand_mesh_position()

	if held_ball:
		_update_held_ball_position()
		held_ball.linear_velocity = Vector3.ZERO
		held_ball.angular_velocity = Vector3.ZERO

	for i in range(get_slide_collision_count()):
		var collision: KinematicCollision3D = get_slide_collision(i)
		var collider: Node3D = collision.get_collider()
		if not collider:
			continue

		if collider.is_in_group("Weapon") and collider is Weapon3D and collider.can_pickup:
			_pickup_weapon(collider)
		elif collider.is_in_group("Ball") and collider is RigidBody3D and not held_ball and (not _is_hand_occupied(false) or not _is_hand_occupied(true)):
			_pickup_ball(collider)


## A hand is occupied if it holds a weapon or is the hand currently gripping the ball.
func _is_hand_occupied(is_left: bool) -> bool:
	if is_left:
		return held_weapon_left != null or (held_ball != null and held_ball_hand_is_left)
	else:
		return held_weapon_right != null or (held_ball != null and not held_ball_hand_is_left)


func _pickup_weapon(weapon: Weapon3D) -> void:
	if not _is_hand_occupied(false):
		held_weapon_right = weapon
		weapon.equip(self, hand_right)
	elif not _is_hand_occupied(true):
		held_weapon_left = weapon
		weapon.equip(self, hand_left)
	# else both hands are full - leave it on the ground


func _pickup_ball(ball: RigidBody3D) -> void:
	held_ball = ball
	# Prefer the right hand, same as weapons; fall back to the left if it's taken.
	held_ball_hand_is_left = _is_hand_occupied(false)
	original_collision_layer = ball.collision_layer
	original_collision_mask = ball.collision_mask
	# Freeze the ball's physics and disable collision
	ball.freeze = true
	ball.collision_layer = 0
	ball.collision_mask = 0
	_update_held_ball_position()


## Keeps the ball's surface resting against the hand instead of the hand
## sitting inside the ball's center: offset the ball outward from the hand,
## away from the player's body, by its own radius.
func _update_held_ball_position() -> void:
	if not held_ball: return
	var ball_hand: Area3D = hand_left if held_ball_hand_is_left else hand_right
	var radius: float = _get_ball_radius(held_ball)
	var outward_dir: Vector3 = ball_hand.global_position - global_position
	outward_dir.y = 0
	if outward_dir.length() < 0.01:
		outward_dir = -global_transform.basis.z
	outward_dir = outward_dir.normalized()
	held_ball.global_position = ball_hand.global_position + outward_dir * radius


func _get_ball_radius(ball: RigidBody3D) -> float:
	var collision: CollisionShape3D = ball.get_node_or_null("CollisionShape3D")
	if collision and collision.shape is SphereShape3D:
		return (collision.shape as SphereShape3D).radius
	return 0.5


func _process(delta: float) -> void:
	# Heavy input takes priority: if the hand holds a shield, it raises to
	# block instead of following its usual tap-bump/hold-throw behavior.
	_handle_hand_block(Input_Handler.action_heavy_left, true)
	_handle_hand_block(Input_Handler.action_heavy_right, false)

	# Handle each hand independently: whichever hand holds the ball throws it
	# on release (charged by hold duration); whichever holds a weapon swings
	# it on a quick tap or throws it on a hold-then-release past the threshold.
	_handle_hand_input(Input_Handler.action_left, was_attack_left, true)
	was_attack_left = Input_Handler.action_left

	_handle_hand_input(Input_Handler.action_right, was_attack_right, false)
	was_attack_right = Input_Handler.action_right

	# Handle targeting
	if Input_Handler:
		_handle_target()
		_handle_rotation(delta)


func _handle_hand_block(is_heavy_pressed: bool, is_left: bool) -> void:
	var weapon: Weapon3D = held_weapon_left if is_left else held_weapon_right
	if weapon is ShieldClass3D:
		if is_heavy_pressed:
			weapon.start_block()
		else:
			weapon.stop_block()


func _handle_hand_input(is_pressed: bool, was_pressed: bool, is_left: bool) -> void:
	var weapon: Weapon3D = held_weapon_left if is_left else held_weapon_right
	if weapon is ShieldClass3D and weapon.is_blocking:
		_set_attack_armed(is_left, false)
		return  # Raised to block - ignore tap/hold-throw for this hand.

	if is_pressed and not was_pressed:
		_set_attack_armed(is_left, true)
	elif not is_pressed and was_pressed:
		if not (attack_left_armed if is_left else attack_right_armed):
			return  # Pressed while blocking - nothing to release
		_set_attack_armed(is_left, false)

	if held_ball and held_ball_hand_is_left == is_left:
		_handle_ball_hand(is_pressed, was_pressed, is_left)
	else:
		_handle_hand_attack(weapon, is_pressed, was_pressed, is_left)


func _set_attack_armed(is_left: bool, armed: bool) -> void:
	if is_left:
		attack_left_armed = armed
	else:
		attack_right_armed = armed


func _handle_ball_hand(is_pressed: bool, was_pressed: bool, is_left: bool) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0

	if is_pressed and not was_pressed:
		# Press started - just record when; swing-vs-throw is decided on release
		if is_left:
			attack_left_press_time = now
		else:
			attack_right_press_time = now
		return

	if not is_pressed and was_pressed:
		# Released - a quick tap swings the ball (bonk), a hold past the
		# threshold throws it, charged by hold duration just like a weapon.
		var press_time: float = attack_left_press_time if is_left else attack_right_press_time
		var hold_duration: float = now - press_time
		if hold_duration >= HOLD_THRESHOLD:
			var charge_ratio: float = clamp((hold_duration - HOLD_THRESHOLD) / THROW_CHARGE_MAX_DURATION, 0.0, 1.0)
			if not _use_stamina(THROW_STAMINA):
				charge_ratio = 0.0
			var force_multiplier: float = lerp(THROW_FORCE_MIN_RATIO, THROW_FORCE_MAX_RATIO, charge_ratio)
			throw_ball(force_multiplier)
		elif is_left and swipe_timer_left <= 0.0:
			swipe_timer_left = SWIPE_DURATION
		elif not is_left and swipe_timer_right <= 0.0:
			swipe_timer_right = SWIPE_DURATION


func _handle_hand_attack(weapon: Weapon3D, is_pressed: bool, was_pressed: bool, is_left: bool) -> void:
	if not weapon:
		# Empty hand: swing the fist as soon as the button goes down
		if is_pressed and not was_pressed:
			_start_punch(is_left)
		return
	var now: float = Time.get_ticks_msec() / 1000.0

	if is_pressed and not was_pressed:
		# Press started - just record when; swing-vs-throw is decided on release
		if is_left:
			attack_left_press_time = now
		else:
			attack_right_press_time = now
		return

	if not is_pressed and was_pressed:
		# Released - a quick tap swings, a hold past the threshold throws.
		# The longer it's held past the threshold (up to THROW_CHARGE_MAX_DURATION),
		# the harder the throw.
		var press_time: float = attack_left_press_time if is_left else attack_right_press_time
		var hold_duration: float = now - press_time
		if hold_duration >= HOLD_THRESHOLD:
			var charge_ratio: float = clamp((hold_duration - HOLD_THRESHOLD) / THROW_CHARGE_MAX_DURATION, 0.0, 1.0)
			if not _use_stamina(THROW_STAMINA):
				charge_ratio = 0.0
			_throw_weapon(weapon, is_left, charge_ratio)
		else:
			var swing_timer: float = swipe_timer_left if is_left else swipe_timer_right
			if swing_timer > 0.0 or not _use_stamina(SWING_STAMINA):
				return  # Mid-swing already, or too tired
			weapon.attack(_get_aim_direction())
			if weapon.plays_swipe_animation:
				if is_left:
					swipe_timer_left = SWIPE_DURATION
				else:
					swipe_timer_right = SWIPE_DURATION
				weapon.start_swing(SWIPE_DURATION)


func _throw_weapon(weapon: Weapon3D, is_left: bool, charge_ratio: float = 1.0) -> void:
	var spin_direction: float = -1.0 if is_left else 1.0
	var force_multiplier: float = lerp(THROW_FORCE_MIN_RATIO, THROW_FORCE_MAX_RATIO, charge_ratio)
	weapon.throw(_get_aim_direction(), -1.0, spin_direction, force_multiplier)
	if is_left:
		held_weapon_left = null
	else:
		held_weapon_right = null


func _get_aim_direction() -> Vector3:
	if Entity and Entity.target and is_instance_valid(Entity.target):
		return (Entity.target.global_position - global_position).normalized()
	if Input_Handler and not Input_Handler.look_dir.is_zero_approx():
		return Input_Handler.look_dir
	return Vector3(sin(rotation.y), 0, cos(rotation.y))


func throw_ball(force_multiplier: float = 1.0) -> void:
	if not held_ball: return

	var ball: RigidBody3D = held_ball
	ball.collision_layer = original_collision_layer
	ball.collision_mask = original_collision_mask
	ball.freeze = false

	# Calculate forward direction based on player's rotation
	var forward_direction: Vector3 = Vector3(
		sin(rotation.y),
		0,
		cos(rotation.y)
	).normalized()

	var throw_direction: Vector3 = (forward_direction + Vector3.UP * (UPWARD_FORCE / THROW_FORCE)).normalized()
	ball.apply_impulse(throw_direction * THROW_FORCE * force_multiplier)

	# Clear held ball reference
	held_ball = null


## Let go of the ball without throwing it (e.g. when the ball is reset).
func drop_ball() -> void:
	if not held_ball: return
	held_ball.collision_layer = original_collision_layer
	held_ball.collision_mask = original_collision_mask
	held_ball.freeze = false
	held_ball = null


# ===== KNOCKBACK, BUMPING & FISTS =====

## Shove this player: the horizontal part slides them (and fades with
## friction), the upward part pops them off the ground.
func add_knockback(impulse: Vector3) -> void:
	knockback += Vector3(impulse.x, 0, impulse.z)
	knockback = knockback.limit_length(KNOCKBACK_MAX)
	if impulse.y > 0.0:
		velocity.y = max(velocity.y, min(impulse.y, KNOCKBACK_POP_MAX))


func _update_knockback(delta: float) -> void:
	if knockback.is_zero_approx():
		knockback = Vector3.ZERO
		return
	# Bounce off walls instead of sticking to them
	for i in range(get_slide_collision_count()):
		var normal: Vector3 = get_slide_collision(i).get_normal()
		normal.y = 0
		if normal.length() > 0.5 and knockback.dot(normal) < 0.0:
			knockback = knockback.bounce(normal.normalized()) * KNOCKBACK_WALL_BOUNCE
	var friction: float = KNOCKBACK_FRICTION if is_on_floor() else KNOCKBACK_AIR_FRICTION
	knockback = knockback.move_toward(Vector3.ZERO, friction * delta)


## Players don't physically collide (held weapons share the Player layer, and
## a swinging sword under someone's feet would launch them), so overlap is
## resolved here instead: bodies are pushed apart, and on first contact each
## gets shoved by how fast the other was moving into them.
func _bump_other_players(delta: float) -> void:
	bump_cooldown = max(bump_cooldown - delta, 0.0)
	for node: Node in get_tree().get_nodes_in_group("Player"):
		var other: PlayerClass3D = node as PlayerClass3D
		# Each pair is handled once, by the player with the lower instance id
		if not other or other == self or get_instance_id() > other.get_instance_id():
			continue
		var offset: Vector3 = other.global_position - global_position
		if abs(offset.y) > BODY_RADIUS * 3.0:
			continue
		offset.y = 0
		var dist: float = offset.length()
		if dist >= BODY_RADIUS * 2.0:
			continue
		var normal: Vector3 = offset / dist if dist > 0.001 else global_transform.basis.z

		# Push apart (move_and_collide so nobody gets shoved into a wall)
		var overlap: float = BODY_RADIUS * 2.0 - dist
		move_and_collide(-normal * overlap * 0.5)
		other.move_and_collide(normal * overlap * 0.5)

		if bump_cooldown > 0.0 or other.bump_cooldown > 0.0:
			continue
		bump_cooldown = BUMP_COOLDOWN
		other.bump_cooldown = BUMP_COOLDOWN
		var my_push: float = max(velocity.dot(normal), 0.0)
		var their_push: float = max(-other.velocity.dot(normal), 0.0)
		other.add_knockback(normal * (BUMP_BASE + my_push * BUMP_CLOSING_TRANSFER) + Vector3.UP * BUMP_POP)
		add_knockback(-normal * (BUMP_BASE + their_push * BUMP_CLOSING_TRANSFER) + Vector3.UP * BUMP_POP)


func _start_punch(is_left: bool) -> void:
	var swing_timer: float = swipe_timer_left if is_left else swipe_timer_right
	if swing_timer > 0.0 or not _use_stamina(PUNCH_STAMINA):
		return
	if is_left:
		swipe_timer_left = SWIPE_DURATION
		punching_left = true
		punch_hits_left.clear()
	else:
		swipe_timer_right = SWIPE_DURATION
		punching_right = true
		punch_hits_right.clear()


## While a fist is mid-swing, hit whatever it passes through (once each).
func _update_punches() -> void:
	if punching_left:
		punching_left = swipe_timer_left > 0.0
		if punching_left:
			_check_fist_hits(hand_left, punch_hits_left)
	if punching_right:
		punching_right = swipe_timer_right > 0.0
		if punching_right:
			_check_fist_hits(hand_right, punch_hits_right)


func _check_fist_hits(hand: Area3D, already_hit: Array[Node]) -> void:
	if not hand: return
	var sphere := SphereShape3D.new()
	sphere.radius = FIST_REACH
	var exclude: Array[RID] = [get_rid()]
	for weapon: Weapon3D in [held_weapon_left, held_weapon_right]:
		if weapon:
			exclude.append(weapon.get_rid())
	for body: Node3D in Combat.overlaps(get_world_3d(), sphere, Transform3D(Basis(), hand.global_position), exclude):
		if body in already_hit:
			continue
		already_hit.append(body)
		if Combat.strike(body, body.global_position - global_position, FIST_DAMAGE, FIST_KNOCKBACK, FIST_POP, FIST_OBJECT_IMPULSE):
			var recoil: Vector3 = global_position - body.global_position
			recoil.y = 0
			add_knockback(recoil.normalized() * FIST_RECOIL)


## Called by Combat.strike for every attack that lands on this player.
## `dir` is the direction the attack travels. Returns false if blocked.
func receive_hit(dir: Vector3, damage: float, knockback_velocity: Vector3) -> bool:
	if _is_blocking_from(dir):
		add_knockback(Vector3(knockback_velocity.x, 0, knockback_velocity.z) * BLOCK_KNOCKBACK_RATIO)
		return false
	if Entity:
		Entity.take_hit(damage, knockback_velocity)
	return true


func _is_blocking_from(attack_dir: Vector3) -> bool:
	for weapon: Weapon3D in [held_weapon_left, held_weapon_right]:
		if weapon is ShieldClass3D and weapon.is_blocking:
			# Blocked if the attack is coming at our front
			return global_transform.basis.z.dot(-attack_dir) > BLOCK_FACING_DOT
	return false


# ===== STAMINA =====

func _use_stamina(amount: float) -> bool:
	return Entity.use_stamina(amount) if Entity else true


func _update_sprint(direction: Vector3, delta: float) -> void:
	if not Entity:
		is_sprinting = Input_Handler.move_dodge
		return
	if sprint_exhausted and Entity.stamina >= Entity.stamina_max * SPRINT_RECOVER_RATIO:
		sprint_exhausted = false
	is_sprinting = Input_Handler.move_dodge and not direction.is_zero_approx() and not sprint_exhausted
	if is_sprinting:
		Entity.drain_stamina(SPRINT_STAMINA_PER_SEC * delta)
		if Entity.stamina <= 0.0:
			sprint_exhausted = true

func _handle_target() -> void:
	if not Input_Handler or not Entity: return
	## Handle target scrolling (cycle through targets)
	#if Entity.target and Input_Handler.target_scroll:
		#Input_Handler.target_scroll = false
		## Get nearest entity, excluding the current target if it's still valid
		#var exclude_target: Node3D = Entity.target if is_instance_valid(Entity.target) else null
		#var nearest := Global.get_nearest_3d(global_position, "Entity", INF, exclude_target)
		#if nearest.get("found", false):
			#Entity.target = nearest["inst"]
	#
	## Handle target toggle (target nearest or clear current)
	#if Input_Handler.target_toggle:
		#Input_Handler.target_toggle = false
		#if Entity.target and is_instance_valid(Entity.target):
			## Clear current target
			#Entity.target = null
		#else:
			## Find nearest entity
			#var nearest := Global.get_nearest_3d(global_position, "Entity", INF)
			#if nearest.get("found", false):
				#Entity.target = nearest["inst"]


func _handle_rotation(_delta: float) -> void:
	if not Entity: return
	## Rotate to face target if locked
	#if Entity.target and is_instance_valid(Entity.target):
		#var direction: Vector3 = (Entity.target.global_position - global_position)
		#var horizontal_dir: Vector3 = Vector3(direction.x, 0, direction.z).normalized()
		#if horizontal_dir.length() > 0.1:
			#var target_angle: float = atan2(horizontal_dir.x, horizontal_dir.z)
			#rotation.y = lerp_angle(rotation.y, target_angle, ROTATION_SPEED * delta)
	#elif Input_Handler and Input_Handler.look_dir.length() > 0.1:
		## Face look direction
		#var look_dir: Vector3 = Input_Handler.look_dir
		#var target_angle: float = atan2(look_dir.x, look_dir.z)
		#rotation.y = lerp_angle(rotation.y, target_angle, ROTATION_SPEED * delta)


func _update_hand_mesh_position() -> void:
	# Only weapons need this: they drift from the hand due to spring-follow
	# lag, so the hand mesh is pinned to follow. The ball is pinned to a
	# fixed offset from the hand directly, so the hand mesh can stay at its
	# natural rest position instead of jumping to the ball's center.
	_sync_hand_mesh(held_weapon_left, hand_left_mesh, hand_left_mesh_rest)
	_sync_hand_mesh(held_weapon_right, hand_right_mesh, hand_right_mesh_rest)


func _sync_hand_mesh(item: Node3D, mesh: MeshInstance3D, rest: Transform3D) -> void:
	if not mesh: return
	# When holding something (weapon or ball), set hand mesh to top_level and sync to its position
	if item:
		if not mesh.top_level:
			mesh.top_level = true
		mesh.global_position = item.global_position
	elif mesh.top_level:
		# When empty-handed, restore normal behavior. Turning top_level off
		# keeps the mesh's current global transform (re-expressed as a local
		# offset), which would leave the hand frozen wherever the weapon was
		# at release - e.g. out in the crossbow's aim pose. Snap it back to
		# its local rest pose so it follows the shoulder (and sway) again.
		mesh.top_level = false
		mesh.transform = rest


func _update_weapon_swipes(delta: float) -> void:
	# Rotating both shoulders the same way around Y swings one hand forward
	# and the other back, which is exactly the opposed walking arm swing.
	var sway_angle: float = sin(sway_phase * TAU) * sway_amount * SWAY_MAX_ANGLE
	swipe_timer_left = _update_shoulder_swipe(delta, shoulder_left, original_shoulder_rotation_left, swipe_timer_left, 1.0, windup_left, sway_angle * sway_weight_left)
	swipe_timer_right = _update_shoulder_swipe(delta, shoulder_right, original_shoulder_rotation_right, swipe_timer_right, -1.0, windup_right, sway_angle * sway_weight_right)


func _update_shoulder_swipe(delta: float, shoulder: Node3D, base_rotation: Vector3, timer: float, direction: float, windup: float, sway: float = 0.0) -> float:
	if not shoulder: return timer

	if timer > 0.0:
		timer -= delta
		var swipe_angle := deg_to_rad(100) * direction
		var t: float = clamp(1.0 - (timer / SWIPE_DURATION), 0.0, 1.0)

		# Rotate the shoulder out during the swipe, then back to original
		var target_rotation: float
		if t < 0.5:
			# First half: rotate out
			var progress: float = t * 2.0  # 0 to 1 over first half
			target_rotation = lerp(0.0, swipe_angle, progress)
		else:
			# Second half: rotate back
			var progress: float = (t - 0.5) * 2.0  # 0 to 1 over second half
			target_rotation = lerp(swipe_angle, 0.0, progress)

		shoulder.rotation.y = base_rotation.y - target_rotation
	else:
		# At rest (not mid-swipe): pull back opposite the swing-out direction,
		# proportional to how wound up this arm currently is.
		shoulder.rotation.y = base_rotation.y + direction * windup * WINDUP_MAX_ANGLE + sway

	return timer


## Advances the walk-sway cycle by distance travelled and eases the overall
## sway amount toward how fast we're moving (0 standing/airborne, 1 at walk
## speed, up to SWAY_RUN_AMPLITUDE_RATIO when running).
func _update_arm_sway(delta: float) -> void:
	var walk_speed: float = Entity.SPEED if Entity else 5.0
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	if not is_on_floor():
		horizontal_speed = 0.0

	sway_phase = fmod(sway_phase + horizontal_speed * SWAY_CYCLES_PER_METER * delta, 1.0)
	var target_amount: float = clamp(horizontal_speed / walk_speed, 0.0, SWAY_RUN_AMPLITUDE_RATIO)
	sway_amount = move_toward(sway_amount, target_amount, delta * SWAY_BLEND_SPEED)

	sway_weight_left = move_toward(sway_weight_left, _arm_sway_target(true), delta * SWAY_BLEND_SPEED)
	sway_weight_right = move_toward(sway_weight_right, _arm_sway_target(false), delta * SWAY_BLEND_SPEED)


## An arm holding a fixed pose (crossbow aimed forward, shield raised) doesn't
## sway, and a winding-up arm fades its sway out as it pulls back.
func _arm_sway_target(is_left: bool) -> float:
	var weapon: Weapon3D = held_weapon_left if is_left else held_weapon_right
	if weapon is CrossbowClass3D:
		return 0.0
	if weapon is ShieldClass3D and weapon.is_blocking:
		return 0.0
	var windup: float = windup_left if is_left else windup_right
	return 1.0 - windup


## Winds the arm back while its hand holds something throwable and the
## attack button is held, ramping up over WINDUP_RAMP_DURATION (matching the
## throw-charge window) and relaxing back to rest otherwise.
func _update_weapon_windups(delta: float) -> void:
	windup_left = _update_hand_windup(windup_left, delta, Input_Handler.action_left and attack_left_armed, attack_left_press_time, _is_hand_occupied(true))
	windup_right = _update_hand_windup(windup_right, delta, Input_Handler.action_right and attack_right_armed, attack_right_press_time, _is_hand_occupied(false))


func _update_hand_windup(current: float, delta: float, is_pressed: bool, press_time: float, has_throwable: bool) -> float:
	var target: float = 0.0
	if is_pressed and has_throwable:
		var hold_duration: float = (Time.get_ticks_msec() / 1000.0) - press_time
		target = clamp(hold_duration / WINDUP_RAMP_DURATION, 0.0, 1.0)
	return move_toward(current, target, delta * WINDUP_LERP_SPEED)
