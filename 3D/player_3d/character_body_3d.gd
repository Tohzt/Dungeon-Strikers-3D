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

## Rogue-lite perks taken at the altar. The same on every machine.
var perks := PerkSet.new()

## Online: what the owning machine sends everyone else about this player.
const SYNCED_PROPERTIES: Array[NodePath] = [
	^":net_pose",
	^"Entity:hp", ^"Entity:stamina",
	# Lets each owner work out how hard someone else bumped into them
	^":velocity",
	# Rolling / staggered body pose
	^":body_tilt",
]
## Online only; sends SYNCED_PROPERTIES from this player's owner.
var net_sync: MultiplayerSynchronizer = null
## Online: another machine controls this player (see set_remote()).
var is_remote: bool = false
## Online: [time, transform, left shoulder yaw, right shoulder yaw], written
## by the owner every physics tick and played back smoothly by remote copies.
var net_pose: Array = []:
	set(value):
		net_pose = value
		if is_remote and value.size() == 4:
			_net_motion.push(value[0], value[1], PackedFloat32Array([value[2], value[3]]))
var _net_motion: NetInterpolator = null

var held_weapon_left: Weapon3D = null
var held_weapon_right: Weapon3D = null
## Carried in both hands, so it can only be picked up with nothing else held.
var held_ball: Ball3D = null
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
# Wrist: during a swing the blade first cocks back behind the arm, then whips
# through ahead of it, so the slash isn't all shoulder.
const WRIST_COCK_ANGLE := deg_to_rad(35)
const WRIST_SNAP_ANGLE := deg_to_rad(60)

## A swing that connected: the arm holds still for a moment (hit-stop), then,
## if it hit something solid, springs back from where it stopped instead of
## carrying on through.
class SwingContact:
	var hitstop: float = 0.0
	var rebound: float = 0.0  # Time left springing back; 0 = following through
	var shoulder_from: float = 0.0  # Shoulder yaw offset from rest where it stopped
	var wrist_from: float = 0.0

	## 1 where it stopped, easing to 0 back at rest (quick off the target).
	func rebound_weight() -> float:
		var r: float = rebound / REBOUND_DURATION
		return r * r

const REBOUND_DURATION := 0.18
var contact_left := SwingContact.new()
var contact_right := SwingContact.new()
## Just got hit: frozen for a moment (see Combat.HITSTOP).
var hitstop: float = 0.0

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
## How far from the player's center the ball can be to pick it up.
const BALL_REACH := 2.0
## Carrying the ball costs something: no sprinting, and a slower walk.
const BALL_CARRY_SPEED := 0.8
## A hit dealing at least this much damage knocks the ball loose (a punch
## is 10). The ball_grip perk stat raises it.
const BALL_FUMBLE_DAMAGE := 8.0
## How hard a fumbled ball pops out, along the hit.
const BALL_FUMBLE_IMPULSE := 4.0
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
# blocked - only a fraction of the damage and shove gets through, but
# blocking costs stamina (the block_stamina perk stat scales it). A block
# that empties the stamina bar breaks the guard (see Poise).
const BLOCK_FACING_DOT := 0.3
const BLOCK_KNOCKBACK_RATIO := 0.35
const BLOCK_DAMAGE_RATIO := 0.2
const BLOCK_STAMINA_PER_DAMAGE := 0.08  # A blocked sword hit (40) costs 3.2

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

# Dodge roll (tap the dodge button): a burst along the walking direction,
# untouchable for the first part of it so it has to be timed rather than
# spammed. Standing still, it's a short backstep instead. Can't roll in the
# air, while staggered, or during the strike of a swing (the follow-through
# can be rolled out of). A tap made while a roll isn't allowed is kept for
# ROLL_BUFFER_MSEC, so it still goes off as soon as it can.
const ROLL_DURATION := 0.4
const ROLL_SPEED := 11.0
const ROLL_END_SPEED_RATIO := 0.4  # Slows to this share of ROLL_SPEED by the end
const ROLL_IFRAMES := 0.25  # From the start of the roll
const BACKSTEP_DURATION := 0.25
const BACKSTEP_SPEED := 8.0
const BACKSTEP_IFRAMES := 0.15
const BACKSTEP_LEAN := deg_to_rad(-20)
const ROLL_STAMINA := 2.0  # Any stamina left is enough to start one
const ROLL_BUFFER_MSEC := 250
var roll_time: float = 0.0  # Time left in the current roll or backstep
var roll_duration: float = 0.0
var roll_iframes: float = 0.0
var roll_dir: Vector3 = Vector3.ZERO
var is_backstep: bool = false

# Swing commitment: a swing (or punch) steps you forward a little, toward
# the lock-on target or aim, and while it's out you turn slowly and only
# partly steer, so a whiff can be punished.
const SWING_LUNGE_SPEED := 5.0
const FIST_LUNGE_SPEED := 3.5
const LUNGE_FRICTION := 20.0
const LUNGE_STOP_GAP := 0.3  # A lunge stops short of the lock-on target by this much
const SWING_TURN_SPEED := 2.5
const SWING_MOVE_CONTROL := 0.5
var lunge: Vector3 = Vector3.ZERO

# Poise is stamina: getting hit with none left, or blocking a hit that
# empties it, staggers you: no moving, turning, attacking, blocking or
# rolling for a moment, and whatever you were swinging is cut short. So
# sprinting, swinging and rolling yourself dry leaves you open.
const STAGGER_DURATION := 0.7
const STAGGER_TILT := deg_to_rad(-25)  # Rocked back on the heels
var stagger_time: float = 0.0

## The body mesh's pitch, for rolling and staggering (synced online).
var body_tilt: float = 0.0
var body_mesh_rest: Transform3D

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
	if mesh_instance_3d[0]:
		body_mesh_rest = mesh_instance_3d[0].transform


## Online: hand this player to the peer that controls it. Call before it
## enters the tree. Syncing stays off until start_network_sync().
func setup_network(peer_id: int) -> void:
	var config := SceneReplicationConfig.new()
	for path: NodePath in SYNCED_PROPERTIES:
		config.add_property(path)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	net_sync = MultiplayerSynchronizer.new()
	net_sync.name = "NetSync"
	net_sync.replication_config = config
	net_sync.public_visibility = false
	add_child(net_sync)
	set_multiplayer_authority(peer_id)


## Online, once every machine has spawned its copy: the owner starts sending.
## Every copy turns visibility on, not just the owner's, because Godot also
## uses a node's synchronizer visibility to decide who it may send RPCs to
## (hits sent to this player's owner would be refused otherwise).
func start_network_sync() -> void:
	if net_sync:
		net_sync.public_visibility = true


## Online: another machine controls this player, so stop simulating it here
## and play back its owner's updates instead (see _process_remote).
func set_remote() -> void:
	is_remote = true
	_net_motion = NetInterpolator.new(0.0 if Net.is_server else NetInterpolator.DELAY)
	if Input_Handler:
		Input_Handler.set_process(false)
		Input_Handler.set_process_input(false)


func _physics_process(delta: float) -> void:
	if is_remote:
		return
	if hitstop > 0.0:
		hitstop -= delta
		return
	if not is_on_floor():
		velocity += get_gravity() * delta

	var direction: Vector3 = Vector3.ZERO
	if Input_Handler:
		direction = Input_Handler.move_dir
	_update_sprint(direction, delta)
	_try_roll(direction)

	# Interact shares the controller's A button with jump, so picking up the
	# ball or taking a weapon off a stand doesn't also hop
	if Input_Handler.interact:
		Input_Handler.interact = false
		if _grab_nearest_ball() or _take_from_nearest_stand():
			Input_Handler.move_jump = false

	# Apply jump velocity multiplier only when jump is initiated, not every frame
	if Input_Handler.move_jump and is_on_floor() and not is_busy():
		var jump_multiplier: float = 1.0
		if is_sprinting:
			jump_multiplier = 1.5  # Sprint jump multiplier
		velocity.y = JUMP_VELOCITY * jump_multiplier * perk_stat(&"jump")

	if is_sprinting:
		Properties.speed_mod.x = 2.0
		Properties.speed_mod.z = 2.0
	else:
		Properties.speed_mod = Vector3.ONE

	# Walking velocity (speed_mod applies only to horizontal, not vertical)
	var speed: float = (Entity.SPEED if Entity else 5.0) * perk_stat(&"move_speed")
	if held_ball:
		speed *= BALL_CARRY_SPEED
	var walk: Vector3 = direction * speed
	if Properties:
		walk.x *= Properties.speed_mod.x
		walk.z *= Properties.speed_mod.z
	# Being shoved takes some control away until the shove dies down
	var control: float = clamp(1.0 - knockback.length() / KNOCKBACK_CONTROL_LOSS, KNOCKBACK_MIN_CONTROL, 1.0)
	if stagger_time > 0.0:
		control = 0.0
	elif is_swinging():
		control *= SWING_MOVE_CONTROL
	var move: Vector3 = _roll_velocity() if roll_time > 0.0 else walk * control
	velocity.x = move.x + knockback.x + lunge.x
	velocity.z = move.z + knockback.z + lunge.z

	# Face the aim direction if aiming (works while standing still too),
	# otherwise face the direction we're trying to walk (not the shove).
	# Rolling and staggered players can't turn; mid-swing they turn slowly.
	var turn_speed: float = SWING_TURN_SPEED if is_swinging() else ROTATION_SPEED
	if is_busy():
		pass
	elif Input_Handler and !Input_Handler.look_dir.is_zero_approx():
		var look_dir: Vector3 = Input_Handler.look_dir
		var target_angle: float = atan2(look_dir.x, look_dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, turn_speed * delta)
	elif !direction.is_zero_approx():
		var target_angle: float = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_angle, turn_speed * delta)

	move_and_slide()
	_update_knockback(delta)
	lunge = lunge.move_toward(Vector3.ZERO, LUNGE_FRICTION * delta)
	_update_roll(delta)
	_update_poise(delta)
	_update_body_tilt()
	_bump_other_players(delta)

	_update_weapon_windups(delta)
	_update_arm_sway(delta)
	_update_weapon_swipes(delta)
	_update_punches()
	_update_hand_mesh_position()

	if held_ball:
		update_held_ball_position()
		held_ball.linear_velocity = Vector3.ZERO
		held_ball.angular_velocity = Vector3.ZERO

	if net_sync:
		net_pose = [NetInterpolator.now(), global_transform, shoulder_left.rotation.y, shoulder_right.rotation.y]

	for i in range(get_slide_collision_count()):
		var collision: KinematicCollision3D = get_slide_collision(i)
		var collider: Node3D = collision.get_collider()
		if not collider:
			continue

		if collider.is_in_group("Weapon") and collider is Weapon3D and collider.can_pickup:
			_pickup_weapon(collider)


## A hand is occupied if it holds a weapon, or both hands carry the ball.
func is_hand_occupied(is_left: bool) -> bool:
	if held_ball:
		return true
	return (held_weapon_left if is_left else held_weapon_right) != null


## Whether this player could pick up `ball` right now: both hands empty and
## the ball within `reach`.
func can_grab_ball(ball: Ball3D, reach: float = BALL_REACH) -> bool:
	return not ball.holder and not is_hand_occupied(false) and not is_hand_occupied(true) \
		and global_position.distance_to(ball.global_position) <= reach


## Returns whether we're picking up (or, online, have asked for) a ball.
func _grab_nearest_ball() -> bool:
	if not Global.Game3D:
		return false
	var nearest: Ball3D = null
	for ball: Ball3D in Global.Game3D.balls:
		if ball.is_inside_tree() and can_grab_ball(ball) and (not nearest \
				or global_position.distance_to(ball.global_position) < global_position.distance_to(nearest.global_position)):
			nearest = ball
	if nearest:
		nearest.request_grab(self)
	return nearest != null


func _pickup_weapon(weapon: Weapon3D) -> void:
	if not is_hand_occupied(false):
		weapon.request_equip(self, false)
	elif not is_hand_occupied(true):
		weapon.request_equip(self, true)
	# else both hands are full - leave it on the ground


## Returns whether a stand in reach is giving us its weapon.
func _take_from_nearest_stand() -> bool:
	var nearest: WeaponStand3D = null
	for stand: WeaponStand3D in get_tree().get_nodes_in_group("WeaponStand"):
		if stand.can_give_to(self) and (not nearest \
				or global_position.distance_to(stand.global_position) < global_position.distance_to(nearest.global_position)):
			nearest = stand
	return nearest != null and nearest.request_take(self)


## Put `weapon` in a hand (online, once the server has said we got it).
func equip_weapon(weapon: Weapon3D, is_left: bool) -> void:
	if is_left:
		held_weapon_left = weapon
	else:
		held_weapon_right = weapon
	weapon.equip(self, hand_left if is_left else hand_right)


## Holds the ball between both hands, pushed out in front by its own radius
## so its surface rests against them instead of its center.
func update_held_ball_position() -> void:
	if not held_ball: return
	var between_hands: Vector3 = (hand_left.global_position + hand_right.global_position) * 0.5
	var outward_dir: Vector3 = between_hands - global_position
	outward_dir.y = 0
	if outward_dir.length() < 0.01:
		outward_dir = global_transform.basis.z
	held_ball.global_position = between_hands + outward_dir.normalized() * _get_ball_radius(held_ball)


func _get_ball_radius(ball: RigidBody3D) -> float:
	var collision: CollisionShape3D = ball.get_node_or_null("CollisionShape3D")
	if collision and collision.shape is SphereShape3D:
		return (collision.shape as SphereShape3D).radius
	return 0.5


func _process(delta: float) -> void:
	if is_remote:
		_process_remote(delta)
		return
	# Rolling or staggered: hands do nothing, and presses made meanwhile
	# don't count once it's over (like presses made while blocking)
	var busy: bool = is_busy()
	if busy:
		_set_attack_armed(true, false)
		_set_attack_armed(false, false)

	# Heavy input takes priority: if the hand holds a shield, it raises to
	# block instead of following its usual tap-bump/hold-throw behavior.
	_handle_hand_block(Input_Handler.action_heavy_left and not busy, true)
	_handle_hand_block(Input_Handler.action_heavy_right and not busy, false)

	# Handle each hand independently: while carrying the ball either button
	# throws it on release (charged by hold duration); a hand holding a weapon
	# swings it on a quick tap or throws it on a hold-then-release past the threshold.
	if not busy:
		_handle_hand_input(Input_Handler.action_left, was_attack_left, true)
		_handle_hand_input(Input_Handler.action_right, was_attack_right, false)
	was_attack_left = Input_Handler.action_left
	was_attack_right = Input_Handler.action_right


## Remote copy, every rendered frame: move to where the owner was a moment
## ago, then carry along what's in hand. Held weapons are posed from here
## (relative to this body) rather than on their own, so they can't lag a
## frame behind the hand holding them.
func _process_remote(delta: float) -> void:
	var sample: Array = _net_motion.sample(delta)
	if not sample.is_empty():
		global_transform = sample[0]
		shoulder_left.rotation.y = sample[1][0]
		shoulder_right.rotation.y = sample[1][1]
	for weapon: Weapon3D in [held_weapon_left, held_weapon_right]:
		if weapon:
			weapon.follow_net_pose(delta)
	_update_hand_mesh_position()
	update_held_ball_position()
	_apply_body_tilt()


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

	if held_ball:
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
				_lunge(SWING_LUNGE_SPEED)


func _throw_weapon(weapon: Weapon3D, is_left: bool, charge_ratio: float = 1.0) -> void:
	var spin_direction: float = -1.0 if is_left else 1.0
	var force_multiplier: float = lerp(THROW_FORCE_MIN_RATIO, THROW_FORCE_MAX_RATIO, charge_ratio) * perk_stat(&"throw_power")
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

	# Calculate forward direction based on player's rotation
	var forward_direction: Vector3 = Vector3(
		sin(rotation.y),
		0,
		cos(rotation.y)
	).normalized()

	var throw_direction: Vector3 = (forward_direction + Vector3.UP * (UPWARD_FORCE / THROW_FORCE)).normalized()
	# Online the ball stays in hand until the server lets it go
	held_ball.request_throw(self, throw_direction * THROW_FORCE * force_multiplier * perk_stat(&"throw_power"))


## Let go of the ball without throwing it (e.g. when the ball is reset).
func drop_ball() -> void:
	if held_ball:
		held_ball.release(Vector3.ZERO)


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
## Online each owner only moves its own player (using the other's synced
## velocity), and the other side's owner does the same from their end.
func _bump_other_players(delta: float) -> void:
	bump_cooldown = max(bump_cooldown - delta, 0.0)
	var online: bool = Net.in_session()
	for node: Node in get_tree().get_nodes_in_group("Player"):
		var other: PlayerClass3D = node as PlayerClass3D
		if not other or other == self:
			continue
		# Offline each pair is handled once, by the player with the lower instance id
		if not online and get_instance_id() > other.get_instance_id():
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
		if not online:
			other.move_and_collide(normal * overlap * 0.5)

		if bump_cooldown > 0.0 or (not online and other.bump_cooldown > 0.0):
			continue
		bump_cooldown = BUMP_COOLDOWN
		var their_push: float = max(-other.velocity.dot(normal), 0.0)
		add_knockback(-normal * (BUMP_BASE + their_push * BUMP_CLOSING_TRANSFER) + Vector3.UP * BUMP_POP)
		if not online:
			other.bump_cooldown = BUMP_COOLDOWN
			var my_push: float = max(velocity.dot(normal), 0.0)
			other.add_knockback(normal * (BUMP_BASE + my_push * BUMP_CLOSING_TRANSFER) + Vector3.UP * BUMP_POP)


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
	_lunge(FIST_LUNGE_SPEED)


## While a fist is mid-swing, hit whatever it passes through (once each).
func _update_punches() -> void:
	if punching_left:
		punching_left = swipe_timer_left > 0.0
		if punching_left:
			_check_fist_hits(hand_left, punch_hits_left, true)
	if punching_right:
		punching_right = swipe_timer_right > 0.0
		if punching_right:
			_check_fist_hits(hand_right, punch_hits_right, false)


func _check_fist_hits(hand: Area3D, already_hit: Array[Node], is_left: bool) -> void:
	if not hand: return
	var sphere := SphereShape3D.new()
	sphere.radius = FIST_REACH
	var exclude: Array[RID] = [get_rid()]
	for weapon: Weapon3D in [held_weapon_left, held_weapon_right]:
		if weapon:
			exclude.append(weapon.get_rid())
	var contact: bool = false
	var solid: bool = false
	for body: Node3D in Combat.overlaps(get_world_3d(), sphere, Transform3D(Basis(), hand.global_position), exclude):
		if body in already_hit:
			continue
		already_hit.append(body)
		contact = true
		solid = solid or Combat.is_solid(body)
		if Combat.strike(body, body.global_position - global_position, FIST_DAMAGE, FIST_KNOCKBACK, FIST_POP, FIST_OBJECT_IMPULSE, self):
			var recoil: Vector3 = global_position - body.global_position
			recoil.y = 0
			add_knockback(recoil.normalized() * FIST_RECOIL)
	if contact:
		_start_swing_contact(is_left, solid)


## Called by Combat.strike for every attack that lands on this player.
## `dir` is the direction the attack travels. Returns false if blocked.
## Online the hit is decided on this player's owner, so a remote copy just
## passes it on (and can't know yet whether it was blocked).
func receive_hit(dir: Vector3, damage: float, knockback_velocity: Vector3) -> bool:
	if not _is_local():
		if Net.match_synced:
			_net_receive_hit.rpc_id(get_multiplayer_authority(), dir, damage, knockback_velocity)
		return true
	if roll_iframes > 0.0:
		return false  # Rolled through it
	damage *= perk_stat(&"damage_taken")
	var knockback_taken: float = perk_stat(&"knockback_taken")
	knockback_velocity.x *= knockback_taken
	knockback_velocity.z *= knockback_taken
	if _is_blocking_from(dir):
		_receive_blocked_hit(damage, knockback_velocity)
		return false
	if Entity:
		var was_in_iframes: bool = Entity.is_in_iframes
		var exhausted: bool = Entity.stamina <= 0.0
		Entity.take_hit(damage, knockback_velocity)
		_share_iframes(was_in_iframes)
		if not was_in_iframes:
			hitstop = Combat.HITSTOP
			if exhausted:
				_stagger()
			if held_ball and damage >= BALL_FUMBLE_DAMAGE * perk_stat(&"ball_grip"):
				held_ball.request_throw(self, (dir + Vector3.UP * 0.5) * BALL_FUMBLE_IMPULSE)
		if Entity.hp <= 0:
			respawn()
	return true


## Out of HP: back to where this player started, fully restored. Weapons
## stay in hand; the ball is let go. Online only the owner calls this; the
## new position and HP reach everyone through the usual sync.
func respawn() -> void:
	if held_ball:
		held_ball.request_throw(self, Vector3.ZERO)
	knockback = Vector3.ZERO
	velocity = Vector3.ZERO
	lunge = Vector3.ZERO
	roll_time = 0.0
	roll_iframes = 0.0
	stagger_time = 0.0
	Entity.reset(true)  # Full stats, and moves us to Entity.spawn_pos
	for weapon: Weapon3D in [held_weapon_left, held_weapon_right]:
		if weapon:
			weapon.snap_to_hand()


## A shove with no damage (e.g. a fast ball), routed like receive_hit.
func shove(direction: Vector3, force: float) -> void:
	if not _is_local():
		if Net.match_synced:
			_net_shove.rpc_id(get_multiplayer_authority(), direction, force)
	elif Entity and roll_iframes <= 0.0:
		var was_in_iframes: bool = Entity.is_in_iframes
		Entity.apply_knockback(direction, force * perk_stat(&"knockback_taken"))
		_share_iframes(was_in_iframes)


# ===== DODGE ROLL, SWING COMMITMENT & POISE =====

## Rolling or staggered: no attacking, jumping, turning or rolling again.
func is_busy() -> bool:
	return roll_time > 0.0 or stagger_time > 0.0


## Either arm is mid-swing (weapon, fist or ball bonk).
func is_swinging() -> bool:
	return swipe_timer_left > 0.0 or swipe_timer_right > 0.0


## Roll if the dodge button was tapped recently and we're free to.
func _try_roll(direction: Vector3) -> void:
	var request: int = Input_Handler.dodge_request_msec if Input_Handler else -1
	if request < 0:
		return
	if Time.get_ticks_msec() - request > ROLL_BUFFER_MSEC:
		Input_Handler.dodge_request_msec = -1
		return
	# The strike half of a swing is committed; its follow-through isn't
	var striking: bool = swipe_timer_left > SWIPE_DURATION * 0.5 or swipe_timer_right > SWIPE_DURATION * 0.5
	if is_busy() or striking or not is_on_floor():
		return  # Keep it buffered
	if Entity:
		if Entity.stamina <= 0.0:
			return
		Entity.drain_stamina(ROLL_STAMINA)
	Input_Handler.dodge_request_msec = -1
	_cancel_attacks()
	lunge = Vector3.ZERO
	is_backstep = direction.is_zero_approx()
	if is_backstep:
		roll_dir = -global_transform.basis.z
		roll_duration = BACKSTEP_DURATION
		roll_iframes = BACKSTEP_IFRAMES
	else:
		roll_dir = direction
		roll_duration = ROLL_DURATION
		roll_iframes = ROLL_IFRAMES
		rotation.y = atan2(direction.x, direction.z)
	roll_time = roll_duration


func _roll_velocity() -> Vector3:
	var t: float = 1.0 - roll_time / roll_duration
	if is_backstep:
		return roll_dir * BACKSTEP_SPEED * (1.0 - t)
	var speed: float = ROLL_SPEED * lerp(1.0, ROLL_END_SPEED_RATIO, t * t) * perk_stat(&"move_speed")
	return roll_dir * speed


func _update_roll(delta: float) -> void:
	roll_time = max(roll_time - delta, 0.0)
	roll_iframes = max(roll_iframes - delta, 0.0)


## Stop any punch or weapon swing from hitting anything more.
func _cancel_attacks() -> void:
	punching_left = false
	punching_right = false
	for weapon: Weapon3D in [held_weapon_left, held_weapon_right]:
		if weapon:
			weapon.cancel_swing()


## Step toward the lock-on target (or the aim) at `speed`, stopping short of
## the target instead of running into it.
func _lunge(speed: float) -> void:
	var dir: Vector3 = _get_aim_direction()
	dir.y = 0.0
	if dir.is_zero_approx():
		return
	var target: Node3D = Entity.target if Entity else null
	if target and is_instance_valid(target):
		var target_radius: float = Boss3D.RADIUS if target is Boss3D else BODY_RADIUS
		var to_target := Vector3(target.global_position.x - global_position.x, 0.0, target.global_position.z - global_position.z)
		var gap: float = max(to_target.length() - BODY_RADIUS - target_radius - LUNGE_STOP_GAP, 0.0)
		# A lunge slides speed^2 / (2 * friction) before it stops
		speed = min(speed, sqrt(2.0 * LUNGE_FRICTION * gap))
	lunge = dir.normalized() * speed


## A hit landed on our raised shield: a little damage and shove, paid for
## in stamina. Emptying the bar breaks the guard. Unlike an open hit it
## leaves no iframes, so a flurry keeps draining the guard.
func _receive_blocked_hit(damage: float, knockback_velocity: Vector3) -> void:
	add_knockback(Vector3(knockback_velocity.x, 0, knockback_velocity.z) * BLOCK_KNOCKBACK_RATIO)
	if not Entity or Entity.is_in_iframes:
		return
	Entity.hp -= damage * BLOCK_DAMAGE_RATIO
	Entity.drain_stamina(damage * BLOCK_STAMINA_PER_DAMAGE * perk_stat(&"block_stamina"))
	hitstop = Combat.HITSTOP
	if Entity.stamina <= 0.0:
		_stagger()
	if Entity.hp <= 0:
		respawn()


## Poise broken: stagger, cutting short any roll or swing.
func _stagger() -> void:
	stagger_time = STAGGER_DURATION
	roll_time = 0.0
	roll_iframes = 0.0
	_cancel_attacks()


func _update_poise(delta: float) -> void:
	stagger_time = max(stagger_time - delta, 0.0)


## Tumble forward through a roll, lean back on a backstep, rock back while
## staggered.
func _update_body_tilt() -> void:
	if roll_time > 0.0:
		var t: float = 1.0 - roll_time / roll_duration
		body_tilt = BACKSTEP_LEAN * sin(PI * t) if is_backstep else TAU * t
	elif stagger_time > 0.0:
		body_tilt = STAGGER_TILT * min(stagger_time / STAGGER_DURATION * 2.0, 1.0)
	else:
		body_tilt = 0.0
	_apply_body_tilt()


func _apply_body_tilt() -> void:
	var mesh: MeshInstance3D = mesh_instance_3d[0]
	if mesh:
		mesh.transform = Transform3D(Basis(Vector3.RIGHT, body_tilt), Vector3.ZERO) * body_mesh_rest


# ===== CONTROL SCHEME =====

## Souls-like controls follow `cam` (camera-relative movement, lock-on);
## null returns to the usual top-down controls. Local players only.
func set_souls_camera(cam: SoulsCamera3D) -> void:
	if Input_Handler:
		Input_Handler.souls_camera = cam
	if not cam and Entity:
		Entity.target = null


# ===== PERKS =====

## This player's multiplier for a perk stat (see PerkSet.STATS).
func perk_stat(stat_name: StringName) -> float:
	return perks.stat(stat_name)


## Take a perk. Max HP/stamina grow at once, keeping how full they were.
## Call on every machine.
func add_perk(perk: Perk) -> void:
	perks.add(perk)
	if Entity:
		Entity.refresh_max_stats()


## Whether this machine controls this player (always, offline).
func _is_local() -> bool:
	return not Net.in_session() or is_multiplayer_authority()


## If that hit just started our iframes, show the fade on everyone's copy.
func _share_iframes(was_in_iframes: bool) -> void:
	if Net.match_synced and not was_in_iframes and Entity.is_in_iframes:
		_net_iframes.rpc()


@rpc("any_peer", "reliable")
func _net_receive_hit(dir: Vector3, damage: float, knockback_velocity: Vector3) -> void:
	if is_multiplayer_authority():
		receive_hit(dir, damage, knockback_velocity)


@rpc("any_peer", "reliable")
func _net_shove(direction: Vector3, force: float) -> void:
	if is_multiplayer_authority():
		shove(direction, force)


@rpc("any_peer", "unreliable")
func _net_iframes() -> void:
	if Entity and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		Entity.start_iframes()


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
	is_sprinting = Input_Handler.move_dodge and not direction.is_zero_approx() and not sprint_exhausted \
		and not held_ball and not is_busy()
	if is_sprinting:
		Entity.drain_stamina(SPRINT_STAMINA_PER_SEC * delta)
		if Entity.stamina <= 0.0:
			sprint_exhausted = true

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
	swipe_timer_left = _update_shoulder_swipe(delta, shoulder_left, original_shoulder_rotation_left, swipe_timer_left, 1.0, windup_left, contact_left, sway_angle * sway_weight_left)
	swipe_timer_right = _update_shoulder_swipe(delta, shoulder_right, original_shoulder_rotation_right, swipe_timer_right, -1.0, windup_right, contact_right, sway_angle * sway_weight_right)
	# The wrist turns the same way the shoulder swings (see _update_shoulder_swipe)
	if held_weapon_left is WeaponClass3D:
		held_weapon_left.wrist_yaw = -_wrist_angle(swipe_timer_left, contact_left)
	if held_weapon_right is WeaponClass3D:
		held_weapon_right.wrist_yaw = _wrist_angle(swipe_timer_right, contact_right)


## A held weapon's swing connected (see Weapon3D._swing_contact).
func swing_contact(weapon: Weapon3D, solid: bool) -> void:
	_start_swing_contact(weapon == held_weapon_left, solid)


## Stop that arm where it is for a moment; off something solid, spring it
## back from there afterwards instead of finishing the swing.
func _start_swing_contact(is_left: bool, solid: bool) -> void:
	var contact: SwingContact = contact_left if is_left else contact_right
	if contact.hitstop > 0.0 or contact.rebound > 0.0:
		return  # Already stopped
	contact.hitstop = Combat.HITSTOP if solid else Combat.HITSTOP_LIGHT
	if not solid:
		return
	var shoulder: Node3D = shoulder_left if is_left else shoulder_right
	var base: Vector3 = original_shoulder_rotation_left if is_left else original_shoulder_rotation_right
	contact.rebound = REBOUND_DURATION
	contact.shoulder_from = shoulder.rotation.y - base.y
	contact.wrist_from = _swing_wrist_angle(swipe_timer_left if is_left else swipe_timer_right)
	# A fist springing back off someone shouldn't punch anyone on the way
	if is_left:
		punching_left = false
	else:
		punching_right = false


func _wrist_angle(timer: float, contact: SwingContact) -> float:
	if contact.rebound > 0.0:
		return contact.wrist_from * contact.rebound_weight()
	return _swing_wrist_angle(timer)


## How far the wrist has turned the blade along the swing: dips back (cocked)
## early on, then accelerates past the arm to WRIST_SNAP_ANGLE as the arm
## reaches full swing, and relaxes with the arm on the way back.
func _swing_wrist_angle(timer: float) -> float:
	if timer <= 0.0:
		return 0.0
	var t: float = clamp(1.0 - (timer / SWIPE_DURATION), 0.0, 1.0)
	if t < 0.5:
		var p: float = t * 2.0
		return WRIST_SNAP_ANGLE * p * p - WRIST_COCK_ANGLE * sin(PI * p)
	return lerp(WRIST_SNAP_ANGLE, 0.0, (t - 0.5) * 2.0)


func _update_shoulder_swipe(delta: float, shoulder: Node3D, base_rotation: Vector3, timer: float, direction: float, windup: float, contact: SwingContact, sway: float = 0.0) -> float:
	if not shoulder: return timer

	if contact.hitstop > 0.0:
		contact.hitstop -= delta
		return timer  # Held where it connected
	if contact.rebound > 0.0:
		contact.rebound = max(contact.rebound - delta, 0.0)
		shoulder.rotation.y = base_rotation.y + contact.shoulder_from * contact.rebound_weight()
		return contact.rebound  # Still mid-swing until it's back at rest

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
	windup_left = _update_hand_windup(windup_left, delta, Input_Handler.action_left and attack_left_armed, attack_left_press_time, is_hand_occupied(true))
	windup_right = _update_hand_windup(windup_right, delta, Input_Handler.action_right and attack_right_armed, attack_right_press_time, is_hand_occupied(false))


func _update_hand_windup(current: float, delta: float, is_pressed: bool, press_time: float, has_throwable: bool) -> float:
	var target: float = 0.0
	if is_pressed and has_throwable:
		var hold_duration: float = (Time.get_ticks_msec() / 1000.0) - press_time
		target = clamp(hold_duration / WINDUP_RAMP_DURATION, 0.0, 1.0)
	return move_toward(current, target, delta * WINDUP_LERP_SPEED)
