class_name PlayerClass3D extends CharacterBody3D
@onready var Entity: EntityBehavior3D = $Entity
@onready var visual: PlayerVisual3D = $Visual
## Where the ball is carried.
@onready var hold_point: Node3D = $Hold

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
	# Rolling / staggered / boosting body, for PlayerVisual3D
	^":anim_pose", ^":body_tilt",
	^":armored",
]
## Online only; sends SYNCED_PROPERTIES from this player's owner.
var net_sync: MultiplayerSynchronizer = null
## Online: another machine controls this player (see set_remote()).
var is_remote: bool = false
## Online: [time, transform, arm_anim], written by the owner every physics
## tick and played back smoothly by remote copies.
var net_pose: Array = []:
	set(value):
		net_pose = value
		if is_remote and value.size() == 3:
			_net_motion.push(value[0], value[1], value[2])
var _net_motion: NetInterpolator = null

## What each arm is doing, for PlayerVisual3D to pick and pose its clip:
## [left ArmAction, left phase, right ArmAction, right phase, left clip,
## right clip, spin]. The clips are a combo beat's own (an index into
## PlayerVisual3D.CLIP_KEYS, -1 = the weapon's usual one); spin is how far
## round (radians) a spinning combo beat has turned the body. A swing's or
## throw's phase runs 0-1 winding up, 1-2 striking, 2-3 recovering (see
## PlayerVisual3D.CLIP_KEYS). Worked out each physics tick from the swing
## timers on the owner, and played back from net_pose by remote copies.
enum ArmAction { REST, SWING, THROW, HOLD }
const ARM_ANIM_SIZE := 7
var arm_anim := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, -1.0, -1.0, 0.0])

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
# Simple controls' Throw button (see PlayerInputHandler3D.throw_left/right):
# when each hand's press began, and whether it began while free to act.
var was_throw_left: bool = false
var was_throw_right: bool = false
var throw_left_press_time: float = 0.0
var throw_right_press_time: float = 0.0
var throw_left_armed: bool = false
var throw_right_armed: bool = false

# How long past HOLD_THRESHOLD you can charge a throw for max power, and the
# force multiplier range that charge maps to (0.0 charge = just past the
# threshold, 1.0 charge = held for THROW_CHARGE_MAX_DURATION or longer).
const THROW_CHARGE_MAX_DURATION := 1.0
const THROW_FORCE_MIN_RATIO := 0.5
const THROW_FORCE_MAX_RATIO := 1.5

# Swing timers for each arm. Fists and ball bonks take SWIPE_DURATION; a
# weapon swing takes its own swing_duration (see WeaponProperties3D), so each
# arm keeps the length of its current one. The first half is the strike, the
# second the recovery.
var swipe_timer_left: float = 0.0
var swipe_timer_right: float = 0.0
const SWIPE_DURATION := 0.25
var swipe_duration_left: float = SWIPE_DURATION
var swipe_duration_right: float = SWIPE_DURATION
## The arm_anim phase each arm's swing starts from: 1 (cocked) after a
## draw-back, else partway through the wind-up so the clip still shows some.
const QUICK_SWING_PHASE := 0.5
var swipe_from_left: float = QUICK_SWING_PHASE
var swipe_from_right: float = QUICK_SWING_PHASE
## A ranged shot plays its clip's strike and recovery over this long. It
## doesn't count as swinging (shots aren't committed, and aren't rate-limited
## by it), so it has its own timer.
const SHOT_ANIM_DURATION := 0.35
var shot_time_left: float = 0.0
var shot_time_right: float = 0.0
## After letting go of a throw, the arm follows through for this long.
const THROW_RELEASE_DURATION := 0.3
var release_time_left: float = 0.0
var release_time_right: float = 0.0

## A heavy weapon's swing draws back before it strikes (its swing_windup), so
## it can be seen coming. Once drawn it's committed: it can't be rolled out of.
class SwingDraw:
	var weapon: Weapon3D = null
	var time_left: float = 0.0
	var total: float = 0.0

	func is_active() -> bool:
		return time_left > 0.0

	## 0 at the start of the draw, 1 fully drawn back; quick at first, then
	## held, so the pose reads.
	func progress() -> float:
		var p: float = 1.0 - time_left / total
		return 1.0 - (1.0 - p) * (1.0 - p)

var draw_left := SwingDraw.new()
var draw_right := SwingDraw.new()
## A chop (a vertical_swing weapon like the axe) can only hit over this share
## of its swing: the downstroke, not the recovery.
const CHOP_DOWNSTROKE := 0.5
## A spinning combo beat takes this share of its time to get the arms out
## (and as long again to bring them back in at the end).
const SPIN_ARMS_OUT := 0.15

## A swing that connected: the arm holds still for a moment (hit-stop), then,
## if it hit something solid, springs back from where it stopped instead of
## carrying on through.
class SwingContact:
	var hitstop: float = 0.0
	var rebound: float = 0.0  # Time left springing back; 0 = following through
	var phase_from: float = 0.0  # arm_anim phase where it stopped

	## 1 where it stopped, easing to 0 back at rest (quick off the target).
	func rebound_weight() -> float:
		var r: float = rebound / REBOUND_DURATION
		return r * r

const REBOUND_DURATION := 0.18
var contact_left := SwingContact.new()
var contact_right := SwingContact.new()

## A dual-wield special (see WeaponCombo3D) under way: the beats still to
## come, the time to the next, and the weapons it's for (it stops if either
## leaves its hand).
var _combo_steps: Array[WeaponComboStep3D] = []
var _combo_wait: float = 0.0
var _combo_left: Weapon3D = null
var _combo_right: Weapon3D = null
## Which hand the combo's MAIN beats strike with (an alt attack with the
## weapon in the left hand), the other being OFF.
var _combo_main_left: bool = false
## Each arm's swing clip from a combo beat (empty = the weapon's own), and
## whether it's held out for a spin rather than swung through.
var _swing_clip_left: StringName = &""
var _swing_clip_right: StringName = &""
var _swing_spin_left: bool = false
var _swing_spin_right: bool = false
## A spinning beat (see WeaponComboStep3D.spin_turns): time left of it, out
## of _spin_total, turning the body _spin_turns times round.
var _spin_time: float = 0.0
var _spin_total: float = 0.0
var _spin_turns: float = 0.0
## Just got hit: frozen for a moment (see Combat.HITSTOP).
var hitstop: float = 0.0

# Wind-up: while a hand holding something throwable (weapon or ball) is
# pressed, the arm winds back for the throw progressively instead of sitting
# static (the wind-up of its throw clip). Ramps up over the same
# press-and-hold window that charges throw force, so a fully wound-up arm
# means a fully-charged throw is coming.
const WINDUP_RAMP_DURATION := HOLD_THRESHOLD + THROW_CHARGE_MAX_DURATION
const WINDUP_LERP_SPEED := 6.0
## Below this, a winding-down arm counts as back at rest.
const WINDUP_SHOWN := 0.02
var windup_left: float = 0.0
var windup_right: float = 0.0

const THROW_FORCE = 10.0
const UPWARD_FORCE = 3.0

const ROTATION_SPEED = 10.0

# Boost: a meter filled by running through boost orbs (BoostOrb3D) around
# the arena. Holding the boost button while moving burns it to accelerate
# up to BOOST_SPEED (well past a sprint), and letting go eases back down, so
# it carries some momentum. It costs no stamina, works carrying the ball,
# and the speed bowls over anyone you run into (see _bump_other_players).
# The meter is the owner's; it isn't synced (the lean it causes is).
signal boost_changed(new_boost: float, max_boost: float)
const BOOST_MAX := 100.0
## What a fresh (or respawned) player starts with.
const BOOST_START := 34.0
## Meter burned per second of boosting: a full one lasts 3 seconds.
const BOOST_DRAIN_PER_SEC := 33.0
## Top speed while boosting (walking is Entity.SPEED, sprinting twice that).
const BOOST_SPEED := 17.0
## Seconds to reach full boost speed, and to ease back off it.
const BOOST_RAMP_UP := 0.3
const BOOST_RAMP_DOWN := 0.6
## Leans forward into it.
const BOOST_LEAN := deg_to_rad(15)
var boost: float = BOOST_START:
	set(value):
		boost = clamp(value, 0.0, BOOST_MAX)
		boost_changed.emit(boost, BOOST_MAX)
var is_boosting: bool = false
## 0 = moving normally, 1 = at full boost speed.
var boost_blend: float = 0.0

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
## How close a loose weapon has to be to pick it up (interact).
const WEAPON_REACH := 2.0
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

# Fists: attacking with an empty hand swings it (same arm swing as a
# weapon) and punches whatever the fist passes through, once per swing.
const FIST_REACH := 0.4  # Radius around the hand that counts as a hit
const FIST_DAMAGE := 10.0  # Players have 250 HP; a sword hit is 40
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
const SWING_STAMINA := 1.05
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
const ROLL_SPEED := 13.2
const ROLL_END_SPEED_RATIO := 0.4  # Slows to this share of ROLL_SPEED by the end
const ROLL_IFRAMES := 0.25  # From the start of the roll
const BACKSTEP_DURATION := 0.25
const BACKSTEP_SPEED := 9.6
const BACKSTEP_IFRAMES := 0.15
const ROLL_STAMINA := 2.0  # Any stamina left is enough to start one
const ROLL_BUFFER_MSEC := 250
## Intermission: close enough to our altar to stop walking (see _walk_to_altar).
const ALTAR_STOP_DISTANCE := 2.5
## Standing at our altar for the intermission.
var at_altar: bool = false
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
## Hits on a staggered player do this much more damage, so breaking
## someone's poise is a real opening (like the boss's stagger).
const STAGGERED_DAMAGE_MULTIPLIER := 1.5
var stagger_time: float = 0.0

## What the body is doing, for PlayerVisual3D to pick a clip (synced online).
enum Pose { NONE, ROLL, BACKSTEP, STAGGER }
var anim_pose: int = Pose.NONE
## How far the body leans forward into a boost (synced online).
var body_tilt: float = 0.0

var punching_left: bool = false
var punching_right: bool = false
var punch_hits_left: Array[Node] = []
var punch_hits_right: Array[Node] = []

# Kills: the last opponent to hit us gets the kill if we die within
# KILL_CREDIT_TIME of it, even if something else (a boss stomp) finishes
# us off. Dying takes us out of play for Game3D.respawn_delay seconds.
const KILL_CREDIT_TIME := 4.0
## A bounty shield that soaks a killing blow leaves this share of max HP.
const SHIELD_SAVE_HP_RATIO := 0.25
var _last_attacker_name: String = ""
var _last_attacker_msec: int = -1
## Seconds left before respawning; 0 = alive.
var dead_time: float = 0.0
var _alive_collision_layer: int = 0
## Wearing armor from an ArmorPickup3D: takes less damage and shows the
## character's helmet/hat and cape, until they next die (synced online).
const ARMOR_DAMAGE_TAKEN := 0.7
var armored: bool = false:
	set(value):
		armored = value
		if visual:
			visual.set_armored(value)
## Floats over the head of anyone on the team leading in kills.
var _crown: MeshInstance3D = null


func _ready() -> void:
	# Properties is a sub-resource of player_3d.tscn, so every instance would
	# share it (and speed_mod is written every frame) - give each player its own.
	if Properties:
		Properties = Properties.duplicate()
		if slot:
			Properties.player_id = slot.index
			Properties.player_color = slot.color
	if visual:
		visual.setup(self)
	if Input_Handler:
		Input_Handler.slot = slot

	# Initialize spawn position
	if Entity:
		Entity.spawn_pos = global_position
		# Initialize Entity with Properties if available
		if Properties:
			Entity.reset(true)


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
	if is_remote or is_dead():
		return
	if hitstop > 0.0:
		hitstop -= delta
		return
	if not is_on_floor():
		velocity += get_gravity() * delta

	var direction: Vector3 = Vector3.ZERO
	if Input_Handler:
		direction = Input_Handler.move_dir
	# Walking to the altar or choosing a perk: our own buttons do nothing
	var perk_locked: bool = is_perk_locked()
	if perk_locked:
		direction = _walk_to_altar()
		Input_Handler.interact = false
		Input_Handler.swap_hands = false
		Input_Handler.dodge_request_msec = -1
	else:
		at_altar = false
	_update_boost(direction, delta)
	_update_sprint(direction, delta)
	_try_roll(direction)

	if Input_Handler.interact:
		Input_Handler.interact = false
		if not _grab_nearest_ball() and not _pick_up_nearest_weapon():
			_take_from_nearest_stand()
	if Input_Handler.swap_hands:
		Input_Handler.swap_hands = false
		swap_hands()

	if is_sprinting:
		Properties.speed_mod.x = 2.0
		Properties.speed_mod.z = 2.0
	else:
		Properties.speed_mod = Vector3.ONE

	# Walking velocity (speed_mod applies only to horizontal, not vertical)
	var speed: float = (Entity.SPEED if Entity else 6.5) * perk_stat(&"move_speed")
	if held_ball:
		speed *= BALL_CARRY_SPEED
	var walk: Vector3 = direction * speed
	if Properties:
		walk.x *= Properties.speed_mod.x
		walk.z *= Properties.speed_mod.z
	if boost_blend > 0.0:
		var boost_speed: float = BOOST_SPEED * perk_stat(&"boost_speed") * (BALL_CARRY_SPEED if held_ball else 1.0)
		walk = walk.lerp(direction * max(boost_speed, walk.length()), boost_blend)
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
	elif Input_Handler and !Input_Handler.look_dir.is_zero_approx() and not perk_locked:
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
	_update_body_pose()
	_bump_other_players(delta)

	_update_weapon_windups(delta)
	_update_swing_draws(delta)
	_update_combo(delta)
	_update_arm_swings(delta)
	_update_punches()
	_update_arm_anim()

	if held_ball:
		update_held_ball_position()
		held_ball.linear_velocity = Vector3.ZERO
		held_ball.angular_velocity = Vector3.ZERO

	if net_sync:
		net_pose = [NetInterpolator.now(), global_transform, arm_anim]


## A hand is occupied if it holds a weapon, or both hands carry the ball or
## a two-handed weapon.
func is_hand_occupied(is_left: bool) -> bool:
	if held_ball:
		return true
	if is_left and _holds_two_handed():
		return true
	return (held_weapon_left if is_left else held_weapon_right) != null


## Which hand the Attack button works (see PlayerInputHandler3D): the
## right, the main hand, unless it's empty and the left holds something to
## use. A shield counts only if `shield_too` (throwing it, or the advanced
## controls' tap-to-bash); otherwise Off-hand keeps it, to block. Off-hand
## works the other hand.
func main_hand_is_left(shield_too: bool = false) -> bool:
	if held_weapon_right != null or held_weapon_left == null or held_ball:
		return false
	return shield_too or not held_weapon_left is ShieldClass3D


## A one-handed weapon (not a shield) in each hand: the Off-hand button
## does a special with both (see WeaponCombo3D).
func can_combo() -> bool:
	var left: Weapon3D = held_weapon_left
	var right: Weapon3D = held_weapon_right
	return left != null and right != null and not held_ball \
		and not left is ShieldClass3D and not right is ShieldClass3D


## The right hand holds a two-handed weapon (so the left is on it too).
func _holds_two_handed() -> bool:
	return held_weapon_right != null and held_weapon_right.grip == Weapon3D.Grip.TWO_HANDED


## Whether a weapon held with `grip` may go in that hand (if it's free). The
## right hand is the main hand, the left the off hand (see Weapon3D.Grip).
static func grip_allows(grip: Weapon3D.Grip, is_left: bool) -> bool:
	match grip:
		Weapon3D.Grip.OFF_HAND:
			return is_left
		Weapon3D.Grip.MAIN_HAND, Weapon3D.Grip.EITHER_HAND:
			return true
	return not is_left


## Whether `weapon` could go in that hand right now.
func can_hold(weapon: Weapon3D, is_left: bool) -> bool:
	return can_hold_grip(weapon.grip, is_left)


func can_hold_grip(grip: Weapon3D.Grip, is_left: bool) -> bool:
	if not grip_allows(grip, is_left) or is_hand_occupied(is_left):
		return false
	return grip != Weapon3D.Grip.TWO_HANDED or not is_hand_occupied(true)


## Which hand a weapon held with `grip` would go in (true = left), or null
## if neither can take it now. Right hand first.
func free_hand_for(grip: Weapon3D.Grip) -> Variant:
	if can_hold_grip(grip, false):
		return false
	if can_hold_grip(grip, true):
		return true
	return null


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


## Whether `weapon` is lying loose and we have a free hand that can hold it
## (it still has to be within WEAPON_REACH to pick up).
func can_pick_up(weapon: Weapon3D) -> bool:
	return not weapon.wielder and not weapon.is_held and not weapon.is_thrown \
		and weapon.can_pickup and free_hand_for(weapon.grip) != null


## Interact: pick up the nearest loose weapon in reach. Returns whether we
## are (or, online, have asked to).
func _pick_up_nearest_weapon() -> bool:
	if not Global.Game3D:
		return false
	var nearest: Weapon3D = null
	var nearest_dist: float = WEAPON_REACH
	for weapon: Weapon3D in Global.Game3D.weapons():
		var to := weapon.global_position - global_position
		var dist: float = Vector2(to.x, to.z).length()  # It may be lying on the floor
		if dist <= nearest_dist and can_pick_up(weapon):
			nearest = weapon
			nearest_dist = dist
	if nearest:
		nearest.request_equip(self, free_hand_for(nearest.grip))
	return nearest != null


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
	weapon.equip(self, _hand_holding(weapon, is_left))


## The hand bone that carries `weapon` when it's that hand's weapon.
func _hand_holding(weapon: Weapon3D, is_left: bool) -> Node3D:
	return visual.hand(is_left or weapon.rides_left_hand)


## Move each hand's weapon to the other hand, if both arms are free and each
## weapon may go in the other hand (see Weapon3D.Grip).
func swap_hands() -> void:
	if held_ball or is_busy() or is_swinging() or not (held_weapon_left or held_weapon_right):
		return
	if (held_weapon_left and not grip_allows(held_weapon_left.grip, false)) \
			or (held_weapon_right and not grip_allows(held_weapon_right.grip, true)):
		return
	_swap_hands()
	if Net.match_synced:
		_net_swap_hands.rpc()


func _swap_hands() -> void:
	var left: Weapon3D = held_weapon_left
	held_weapon_left = held_weapon_right
	held_weapon_right = left
	for weapon: Weapon3D in [held_weapon_left, held_weapon_right]:
		if weapon is ShieldClass3D:
			weapon.stop_block()
	if held_weapon_left:
		held_weapon_left.equip(self, _hand_holding(held_weapon_left, true))
	if held_weapon_right:
		held_weapon_right.equip(self, _hand_holding(held_weapon_right, false))


@rpc("any_peer", "reliable")
func _net_swap_hands() -> void:
	if multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_swap_hands()


## Carries the ball out in front, at the hold point.
func update_held_ball_position() -> void:
	if not held_ball: return
	held_ball.global_position = hold_point.global_position


func _process(delta: float) -> void:
	if is_dead():
		_update_death(delta)
		return
	if is_remote:
		_process_remote(delta)
		return
	# Rolling or staggered: hands do nothing, and presses made meanwhile
	# don't count once it's over (like presses made while blocking)
	var busy: bool = is_busy() or is_perk_locked()
	if busy:
		_set_attack_armed(true, false)
		_set_attack_armed(false, false)
		throw_left_armed = false
		throw_right_armed = false

	# Heavy input takes priority: if the hand holds a shield, it raises to
	# block instead of following its usual tap-bump/hold-throw behavior.
	_handle_hand_block(Input_Handler.action_heavy_left and not busy, true)
	_handle_hand_block(Input_Handler.action_heavy_right and not busy, false)

	# Handle each hand independently: while carrying the ball either button
	# throws it on release (charged by hold duration); a hand holding a weapon
	# swings it on a quick tap or throws it on a hold-then-release past the threshold.
	var attack_left: bool = _attack_pressed(true)
	var attack_right: bool = _attack_pressed(false)
	var throw_left: bool = _throw_pressed(true)
	var throw_right: bool = _throw_pressed(false)
	if not busy:
		_handle_hand_input(attack_left, was_attack_left, true)
		_handle_hand_input(attack_right, was_attack_right, false)
		_handle_hand_throw(throw_left, was_throw_left, true)
		_handle_hand_throw(throw_right, was_throw_right, false)
	was_attack_left = attack_left
	was_attack_right = attack_right
	was_throw_left = throw_left
	was_throw_right = throw_right
	if Input_Handler.drop_weapon:
		Input_Handler.drop_weapon = false
		if not busy:
			_drop_main_weapon()


## Throw tapped on its own: let go of the main hand's weapon, or the off
## hand's if that's all we hold.
func _drop_main_weapon() -> void:
	var weapon: Weapon3D = held_weapon_right if held_weapon_right else held_weapon_left
	if weapon and not (weapon is ShieldClass3D and weapon.is_blocking):
		weapon.drop()


## That hand's attack button. With a two-handed weapon the right hand's
## swings it and the (empty) left's is its alt attack (see _handle_hand_attack).
func _attack_pressed(is_left: bool) -> bool:
	return Input_Handler.action_left if is_left else Input_Handler.action_right


## That hand's throw (simple controls), like _attack_pressed.
func _throw_pressed(is_left: bool) -> bool:
	if _holds_two_handed():
		return false if is_left else Input_Handler.throw_left or Input_Handler.throw_right
	return Input_Handler.throw_left if is_left else Input_Handler.throw_right


## Remote copy, every rendered frame: move to where the owner was a moment
## ago, then carry along the ball. Held weapons ride the hands (see
## PlayerVisual3D), which play the owner's arm_anim.
func _process_remote(delta: float) -> void:
	var sample: Array = _net_motion.sample(delta)
	if not sample.is_empty():
		global_transform = sample[0]
		if sample[1].size() == ARM_ANIM_SIZE:
			arm_anim = sample[1]
	update_held_ball_position()


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
	if Input_Handler.uses_simple_controls():
		# Bonk on press; the Throw button throws it
		if is_pressed and not was_pressed and not is_arm_swinging(is_left):
			_begin_arm_swing(is_left, SWIPE_DURATION)
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
		elif not is_arm_swinging(is_left):
			_begin_arm_swing(is_left, SWIPE_DURATION)


func _handle_hand_attack(weapon: Weapon3D, is_pressed: bool, was_pressed: bool, is_left: bool) -> void:
	if not weapon:
		if is_pressed and not was_pressed:
			# An empty hand's button is the off hand's: with a weapon in the
			# other hand that's its alt attack, otherwise a punch
			var other: Weapon3D = held_weapon_right if is_left else held_weapon_left
			if other and not other is ShieldClass3D:
				_start_alt(not is_left)
			else:
				_start_punch(is_left)
		return
	if Input_Handler.uses_simple_controls():
		# Throwing has its own button, so a swing goes off as soon as it's pressed
		if is_pressed and not was_pressed:
			_swing_or_combo(weapon, is_left)
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
			_swing_or_combo(weapon, is_left)


## The off hand's button with a weapon in each hand does a special (the left
## is the off hand then); otherwise it's a plain swing.
func _swing_or_combo(weapon: Weapon3D, is_left: bool) -> void:
	if is_left and can_combo():
		_start_combo()
	else:
		_swing_weapon(weapon, is_left)


## Swing (or fire) the weapon in that hand, if that arm is free and we have
## the stamina; false if it couldn't. A heavy weapon draws back first (see
## SwingDraw).
func _swing_weapon(weapon: Weapon3D, is_left: bool) -> bool:
	var swing_stamina: float = SWING_STAMINA * (weapon.Properties.swing_stamina_scale if weapon.Properties else 1.0)
	if is_arm_swinging(is_left) or not _use_stamina(swing_stamina):
		return false  # Mid-swing already, or too tired
	var draw_time: float = weapon.Properties.swing_windup if weapon.Properties else 0.0
	if draw_time > 0.0 and weapon.plays_swipe_animation:
		var draw: SwingDraw = draw_left if is_left else draw_right
		draw.weapon = weapon
		draw.time_left = draw_time
		draw.total = draw_time
	else:
		_strike(weapon, is_left)
	return true


## The weapon in that hand attacks now: a melee one swings (live for its
## swing_duration) with a step forward, a ranged one just fires. `step` is
## the combo beat it's part of, if any. Returns the swing's length.
func _strike(weapon: Weapon3D, is_left: bool, step: WeaponComboStep3D = null) -> float:
	var club: bool = step != null and step.melee  # A ranged weapon swung, not fired
	if not club:
		weapon.attack(_get_aim_direction())
	if not weapon.plays_swipe_animation and not club:
		if is_left:
			shot_time_left = SHOT_ANIM_DURATION
		else:
			shot_time_right = SHOT_ANIM_DURATION
		return SHOT_ANIM_DURATION
	var duration: float = weapon.Properties.swing_duration if weapon.Properties else SWIPE_DURATION
	var drawn: bool = step == null and weapon.Properties != null and weapon.Properties.swing_windup > 0.0
	var spin: bool = step != null and step.spin_turns != 0.0
	if step:
		duration *= step.duration_scale
	_begin_arm_swing(is_left, duration, 1.0 if drawn else QUICK_SWING_PHASE)
	if step:
		var clip: StringName = step.off_clip if is_left else step.main_clip
		if is_left:
			_swing_clip_left = clip
			_swing_spin_left = spin
		else:
			_swing_clip_right = clip
			_swing_spin_right = spin
	var window: float = duration * CHOP_DOWNSTROKE if _chops(is_left) and not spin else duration
	weapon.start_swing(window, step.damage_scale if step else 1.0)
	var lunge_scale: float = step.lunge_scale if step else 1.0
	if lunge_scale > 0.0:
		_lunge(SWING_LUNGE_SPEED * lunge_scale)
	return duration


# ===== DUAL-WIELD SPECIALS =====

## The Off-hand button with a weapon in each hand: their special (see
## WeaponCombo3D.find_for).
func _start_combo() -> bool:
	if not can_combo():
		return false
	return _start_special(WeaponCombo3D.find_for(held_weapon_left, held_weapon_right), false)


## The Off-hand button with nothing in the off hand: the weapon in the other
## hand's alt attack, or a plain swing if it has none.
func _start_alt(weapon_is_left: bool) -> bool:
	var weapon: Weapon3D = held_weapon_left if weapon_is_left else held_weapon_right
	if not weapon.alt_attack:
		return _swing_weapon(weapon, weapon_is_left)
	return _start_special(weapon.alt_attack, weapon_is_left)


## Start `combo`'s beats, its MAIN ones in the left hand if `main_is_left`,
## if both arms are free and we have the stamina.
func _start_special(combo: WeaponCombo3D, main_is_left: bool) -> bool:
	if not combo or combo.steps.is_empty() or is_swinging():
		return false
	_combo_main_left = main_is_left
	var cost: float = 0.0
	for step: WeaponComboStep3D in combo.steps:
		for is_left: bool in _step_hands(step):
			var weapon: Weapon3D = held_weapon_left if is_left else held_weapon_right
			cost += SWING_STAMINA * (weapon.Properties.swing_stamina_scale if weapon.Properties else 1.0)
	if not _use_stamina(cost * combo.stamina_scale):
		return false
	_combo_left = held_weapon_left
	_combo_right = held_weapon_right
	_combo_steps = combo.steps.duplicate()
	_combo_wait = _combo_steps[0].delay
	_update_combo(0.0)
	return true


## Which hands (true = left) strike on `step`: those of its hands that hold
## a weapon.
func _step_hands(step: WeaponComboStep3D) -> Array[bool]:
	var hands: Array[bool] = [true, false]
	match step.hand:
		WeaponComboStep3D.Hand.OFF:
			hands = [not _combo_main_left]
		WeaponComboStep3D.Hand.MAIN:
			hands = [_combo_main_left]
	var holding: Array[bool] = []
	for is_left: bool in hands:
		if (held_weapon_left if is_left else held_weapon_right) != null:
			holding.append(is_left)
	return holding


## Strikes each combo beat as it comes due, and turns the body through a
## spinning one. Drops the rest if either weapon has left its hand.
func _update_combo(delta: float) -> void:
	_spin_time = max(_spin_time - delta, 0.0)
	if _combo_steps.is_empty():
		return
	if held_weapon_left != _combo_left or held_weapon_right != _combo_right:
		_combo_steps.clear()
		return
	_combo_wait -= delta
	while not _combo_steps.is_empty() and _combo_wait <= 0.0:
		var step: WeaponComboStep3D = _combo_steps.pop_front()
		var longest: float = 0.0
		for is_left: bool in _step_hands(step):
			longest = maxf(longest, _strike(held_weapon_left if is_left else held_weapon_right, is_left, step))
		if step.spin_turns != 0.0:
			_spin_total = longest
			_spin_time = longest
			_spin_turns = step.spin_turns
		if not _combo_steps.is_empty():
			_combo_wait += _combo_steps[0].delay


## How far round (radians) a spinning beat has turned the body: quick to get
## going, easing off at the end.
func _spin_angle() -> float:
	if _spin_time <= 0.0 or _spin_total <= 0.0:
		return 0.0
	var t: float = 1.0 - _spin_time / _spin_total
	return _spin_turns * TAU * smoothstep(0.0, 1.0, t)


## Start that arm's swing, `duration` seconds long, its clip from arm_anim
## phase `from` (see QUICK_SWING_PHASE).
func _begin_arm_swing(is_left: bool, duration: float, from: float = QUICK_SWING_PHASE) -> void:
	if is_left:
		swipe_timer_left = duration
		swipe_duration_left = duration
		swipe_from_left = from
		_swing_clip_left = &""
		_swing_spin_left = false
	else:
		swipe_timer_right = duration
		swipe_duration_right = duration
		swipe_from_right = from
		_swing_clip_right = &""
		_swing_spin_right = false


## Draw-backs finish here and turn into the strike, if the same weapon is
## still in that hand (it may have been thrown, dropped or broken meanwhile).
func _update_swing_draws(delta: float) -> void:
	for is_left: bool in [true, false]:
		var draw: SwingDraw = draw_left if is_left else draw_right
		if not draw.is_active():
			continue
		draw.time_left = max(draw.time_left - delta, 0.0)
		if draw.is_active():
			continue
		var weapon: Weapon3D = draw.weapon
		draw.weapon = null
		var held: Weapon3D = held_weapon_left if is_left else held_weapon_right
		if is_instance_valid(weapon) and weapon == held:
			_strike(weapon, is_left)


## Simple controls' throw for one hand (Throw held + that hand's attack
## button): winds up while held (harder the longer, up to
## THROW_CHARGE_MAX_DURATION) and throws what
## that hand holds - the ball, or its weapon - on release. A quick tap is a
## light toss. A raised shield can't be thrown.
func _handle_hand_throw(is_pressed: bool, was_pressed: bool, is_left: bool) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if is_pressed and not was_pressed:
		if is_left:
			throw_left_press_time = now
			throw_left_armed = true
		else:
			throw_right_press_time = now
			throw_right_armed = true
		return
	if is_pressed or not was_pressed or not (throw_left_armed if is_left else throw_right_armed):
		return
	if is_left:
		throw_left_armed = false
	else:
		throw_right_armed = false
	var weapon: Weapon3D = held_weapon_left if is_left else held_weapon_right
	if not held_ball and (not weapon or (weapon is ShieldClass3D and weapon.is_blocking)):
		return
	var press_time: float = throw_left_press_time if is_left else throw_right_press_time
	var charge_ratio: float = clamp((now - press_time) / THROW_CHARGE_MAX_DURATION, 0.0, 1.0)
	if not _use_stamina(THROW_STAMINA):
		charge_ratio = 0.0
	if held_ball:
		throw_ball(lerp(THROW_FORCE_MIN_RATIO, THROW_FORCE_MAX_RATIO, charge_ratio))
	else:
		_throw_weapon(weapon, is_left, charge_ratio)


func _throw_weapon(weapon: Weapon3D, is_left: bool, charge_ratio: float = 1.0) -> void:
	var spin_direction: float = -1.0 if is_left else 1.0
	var force_multiplier: float = lerp(THROW_FORCE_MIN_RATIO, THROW_FORCE_MAX_RATIO, charge_ratio) * perk_stat(&"throw_power")
	weapon.throw(_get_aim_direction(), -1.0, spin_direction, force_multiplier)
	if is_left:
		held_weapon_left = null
	else:
		held_weapon_right = null
	_play_throw_release(is_left)


## The arm follows through after letting go of a throw.
func _play_throw_release(is_left: bool) -> void:
	if is_left:
		release_time_left = THROW_RELEASE_DURATION
	else:
		release_time_right = THROW_RELEASE_DURATION


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
	_play_throw_release(false)


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
		if not other or other == self or other.is_dead():
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
	if is_arm_swinging(is_left) or not _use_stamina(PUNCH_STAMINA):
		return
	_begin_arm_swing(is_left, SWIPE_DURATION)
	if is_left:
		punching_left = true
		punch_hits_left.clear()
	else:
		punching_right = true
		punch_hits_right.clear()
	_lunge(FIST_LUNGE_SPEED)


## While a fist is mid-swing, hit whatever it passes through (once each).
func _update_punches() -> void:
	if punching_left:
		punching_left = swipe_timer_left > 0.0
		if punching_left:
			_check_fist_hits(visual.hand(true), punch_hits_left, true)
	if punching_right:
		punching_right = swipe_timer_right > 0.0
		if punching_right:
			_check_fist_hits(visual.hand(false), punch_hits_right, false)


func _check_fist_hits(hand: Node3D, already_hit: Array[Node], is_left: bool) -> void:
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
## `attacker` is the player behind it, if any (they may get the kill).
## Online the hit is decided on this player's owner, so a remote copy just
## passes it on (and can't know yet whether it was blocked).
func receive_hit(dir: Vector3, damage: float, knockback_velocity: Vector3, attacker: Node3D = null) -> bool:
	if is_dead():
		return false
	if not _is_local():
		if Net.match_synced:
			var attacker_name: String = String(attacker.name) if attacker is PlayerClass3D else ""
			_net_receive_hit.rpc_id(get_multiplayer_authority(), dir, damage, knockback_velocity, attacker_name)
		return true
	if roll_iframes > 0.0:
		return false  # Rolled through it
	if attacker is PlayerClass3D and attacker != self:
		_last_attacker_name = attacker.name
		_last_attacker_msec = Time.get_ticks_msec()
	damage *= perk_stat(&"damage_taken")
	if armored:
		damage *= ARMOR_DAMAGE_TAKEN
	if stagger_time > 0.0:
		damage *= STAGGERED_DAMAGE_MULTIPLIER
	var knockback_taken: float = perk_stat(&"knockback_taken")
	knockback_velocity.x *= knockback_taken
	knockback_velocity.z *= knockback_taken
	var shield: ShieldClass3D = _blocking_shield(dir)
	if shield:
		_receive_blocked_hit(damage, knockback_velocity, shield)
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
			var strip: float = attacker.perk_stat(&"ball_strip") if attacker is PlayerClass3D else 1.0
			if held_ball and damage * strip >= BALL_FUMBLE_DAMAGE * perk_stat(&"ball_grip"):
				held_ball.request_throw(self, (dir + Vector3.UP * 0.5) * BALL_FUMBLE_IMPULSE)
		if Entity.hp <= 0:
			_on_lethal_hit()
	return true


## Out of HP (on the owner). A bounty shield saves us from a hit that would
## give an opponent the kill; otherwise we die and Game3D is told who, if
## anyone, gets the kill.
func _on_lethal_hit() -> void:
	var killer_name: String = _credited_killer()
	if killer_name != "" and Global.Game3D and Global.Game3D.try_use_shield(self):
		Entity.hp = Entity.hp_max * SHIELD_SAVE_HP_RATIO
		return
	die()
	if Global.Game3D:
		Global.Game3D.report_death(self, killer_name)


## Whoever last hit us, if it was recent enough to count as their kill.
func _credited_killer() -> String:
	if _last_attacker_msec < 0 or Time.get_ticks_msec() - _last_attacker_msec > KILL_CREDIT_TIME * 1000.0:
		return ""
	return _last_attacker_name


func is_dead() -> bool:
	return dead_time > 0.0


## Killed: gone from the arena until the respawn delay runs out. The owner
## calls this the moment it happens and every machine again when Game3D
## announces the death, so a second call does nothing.
func die() -> void:
	if is_dead():
		return
	armored = false  # Comes back without it
	var delay: float = Global.Game3D.respawn_delay if Global.Game3D else 0.0
	delay *= perk_stat(&"respawn_time")
	if _is_local():
		# Our weapons stay where we fell, for anyone to take
		for weapon: Weapon3D in [held_weapon_left, held_weapon_right]:
			if weapon:
				weapon.drop()
		respawn()  # Wait at the spawn point, so remote copies don't streak there later
	if delay <= 0.0:
		return
	dead_time = delay
	_last_attacker_name = ""
	_last_attacker_msec = -1
	_cancel_attacks()
	_set_attack_armed(true, false)
	_set_attack_armed(false, false)
	_alive_collision_layer = collision_layer
	collision_layer = 0
	visible = false


func _update_death(delta: float) -> void:
	dead_time = max(dead_time - delta, 0.0)
	if dead_time > 0.0:
		return
	collision_layer = _alive_collision_layer
	visible = true
	if visual:
		visual.play_spawn()
	if Entity:
		Entity.start_iframes()  # A moment of spawn protection


## Game3D says whether our team leads in kills: wear the crown if so.
func set_leader(leading: bool) -> void:
	if leading and not _crown:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.3
		mesh.bottom_radius = 0.22
		mesh.height = 0.25
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 0.8, 0.1)
		material.emission_enabled = true
		material.emission = Color(1.0, 0.7, 0.1)
		material.emission_energy_multiplier = 1.5
		mesh.material = material
		_crown = MeshInstance3D.new()
		_crown.name = "Crown"
		_crown.mesh = mesh
		_crown.position = Vector3(0, 1.4, 0)
		add_child(_crown)
	if _crown:
		_crown.visible = leading


## We got a kill (on every machine): the kill_heal perk stat heals us.
func on_kill() -> void:
	var heal: float = perk_stat(&"kill_heal") - 1.0
	if heal > 0.0 and Entity and _is_local() and not is_dead():
		Entity.hp = min(Entity.hp + Entity.hp_max * heal, Entity.hp_max)


## Back to where this player started, fully restored. Anything still held
## comes along; the ball is let go. Online only the owner calls this; the
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
	is_boosting = false
	boost_blend = 0.0
	boost = BOOST_START
	Entity.reset(true)  # Full stats, and moves us to Entity.spawn_pos
	for weapon: Weapon3D in [held_weapon_left, held_weapon_right]:
		if weapon:
			weapon.follow_hand()


## Burned (e.g. holding a burning ball): damage with no flinch, iframes or
## shove, so a tick of it doesn't stun-lock. Routed like receive_hit.
func receive_burn(damage: float, attacker: Node3D = null) -> void:
	if is_dead():
		return
	if not _is_local():
		if Net.match_synced:
			var attacker_name: String = String(attacker.name) if attacker is PlayerClass3D else ""
			_net_receive_burn.rpc_id(get_multiplayer_authority(), damage, attacker_name)
		return
	if not Entity:
		return
	if attacker is PlayerClass3D and attacker != self:
		_last_attacker_name = attacker.name
		_last_attacker_msec = Time.get_ticks_msec()
	Entity.hp -= damage * perk_stat(&"damage_taken") * (ARMOR_DAMAGE_TAKEN if armored else 1.0)
	if Entity.hp <= 0:
		_on_lethal_hit()


@rpc("any_peer", "reliable")
func _net_receive_burn(damage: float, attacker_name: String) -> void:
	if is_multiplayer_authority():
		var attacker: Node3D = null
		if attacker_name != "" and Global.Game3D:
			attacker = Global.Game3D.get_node_or_null(attacker_name) as PlayerClass3D
		receive_burn(damage, attacker)


## A shove with no damage (e.g. a fast ball), routed like receive_hit.
func shove(direction: Vector3, force: float) -> void:
	if not _is_local():
		if Net.match_synced:
			_net_shove.rpc_id(get_multiplayer_authority(), direction, force)
	elif Entity and roll_iframes <= 0.0 and not is_dead():
		var was_in_iframes: bool = Entity.is_in_iframes
		Entity.apply_knockback(direction, force * perk_stat(&"knockback_taken"))
		_share_iframes(was_in_iframes)


# ===== DODGE ROLL, SWING COMMITMENT & POISE =====

## Rolling or staggered: no attacking, boosting, turning or rolling again.
func is_busy() -> bool:
	return roll_time > 0.0 or stagger_time > 0.0


## The intermission (walking back to our altar and picking there), or
## choosing a perk mid-round: movement and hands are out of our control.
func is_perk_locked() -> bool:
	var game: Game3D_Class = Global.Game3D
	if not game:
		return false
	return game.phase == Game3D_Class.Phase.INTERMISSION or game.perks.is_picking(self)


## Where to walk while perk-locked: in the intermission, straight to our
## team's altar, then stand there and take the cards waiting (a bot picks
## its own; see BotInputHandler3D). Mid-round picks just stand still.
func _walk_to_altar() -> Vector3:
	var game: Game3D_Class = Global.Game3D
	var altar: Altar3D = game.altar_of_team(slot.team) if slot else null
	if game.phase != Game3D_Class.Phase.INTERMISSION or not altar:
		return Vector3.ZERO
	var to_altar: Vector3 = altar.global_position - global_position
	to_altar.y = 0.0
	at_altar = to_altar.length() < ALTAR_STOP_DISTANCE or altar.reach.overlaps_body(self)
	if not at_altar:
		return NavPath.direction(self, altar.global_position)
	if not slot.is_bot:
		game.perks.open_for(self)
	return Vector3.ZERO


## Either arm is mid-swing (weapon, fist or ball bonk), or drawing one back.
func is_swinging() -> bool:
	return is_arm_swinging(true) or is_arm_swinging(false) or not _combo_steps.is_empty()


## That arm is mid-swing or drawing one back.
func is_arm_swinging(is_left: bool) -> bool:
	if is_left:
		return swipe_timer_left > 0.0 or draw_left.is_active()
	return swipe_timer_right > 0.0 or draw_right.is_active()


## Drawing a heavy swing back, or in the strike half of any swing: committed,
## so no rolling out of it. The follow-through can be rolled out of.
func _is_committed() -> bool:
	return draw_left.is_active() or draw_right.is_active() \
		or swipe_timer_left > swipe_duration_left * 0.5 \
		or swipe_timer_right > swipe_duration_right * 0.5


## Roll if the dodge button was tapped recently and we're free to.
func _try_roll(direction: Vector3) -> void:
	var request: int = Input_Handler.dodge_request_msec if Input_Handler else -1
	if request < 0:
		return
	if Time.get_ticks_msec() - request > ROLL_BUFFER_MSEC:
		Input_Handler.dodge_request_msec = -1
		return
	if is_busy() or _is_committed() or not is_on_floor():
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


# ===== ARMOR =====

## Whether running through an armor pickup would give us anything.
func can_take_armor() -> bool:
	return not is_dead() and not armored


## Owner only (pickups call it on the machine that controls us).
func put_on_armor() -> void:
	if not is_dead():
		armored = true


# ===== BOOST & DASH =====

## Whether running through a boost orb would give us anything.
func can_take_boost() -> bool:
	return not is_dead() and boost < BOOST_MAX


## Owner only (orbs call it on the machine that controls us).
func add_boost(amount: float) -> void:
	boost += amount * perk_stat(&"boost_gain")


## Burn boost while the button is held, we're moving and free to; ease
## the speed up or back down.
func _update_boost(direction: Vector3, delta: float) -> void:
	var held: bool = Input_Handler != null and Input_Handler.boost_held
	is_boosting = held and boost > 0.0 and not direction.is_zero_approx() \
		and not is_busy() and not is_perk_locked()
	if is_boosting:
		boost -= BOOST_DRAIN_PER_SEC * delta
		boost_blend = move_toward(boost_blend, 1.0, delta / BOOST_RAMP_UP)
	else:
		boost_blend = move_toward(boost_blend, 0.0, delta / BOOST_RAMP_DOWN)
	if is_busy():
		boost_blend = 0.0


## Stop any punch or weapon swing from hitting anything more.
func _cancel_attacks() -> void:
	punching_left = false
	punching_right = false
	for draw: SwingDraw in [draw_left, draw_right]:
		draw.time_left = 0.0
		draw.weapon = null
	_combo_steps.clear()
	_spin_time = 0.0
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
func _receive_blocked_hit(damage: float, knockback_velocity: Vector3, shield: ShieldClass3D) -> void:
	add_knockback(Vector3(knockback_velocity.x, 0, knockback_velocity.z) * BLOCK_KNOCKBACK_RATIO)
	shield.wear()  # Each block is a use
	if not Entity or Entity.is_in_iframes:
		return
	Entity.hp -= damage * BLOCK_DAMAGE_RATIO
	Entity.drain_stamina(damage * BLOCK_STAMINA_PER_DAMAGE * perk_stat(&"block_stamina"))
	hitstop = Combat.HITSTOP
	if Entity.stamina <= 0.0:
		_stagger()
	if Entity.hp <= 0:
		_on_lethal_hit()


## Poise broken: stagger, cutting short any roll or swing.
func _stagger() -> void:
	stagger_time = STAGGER_DURATION
	roll_time = 0.0
	roll_iframes = 0.0
	_cancel_attacks()


func _update_poise(delta: float) -> void:
	stagger_time = max(stagger_time - delta, 0.0)


## Rolling, backstepping or staggered (each has its own clip), otherwise
## leaning into a boost.
func _update_body_pose() -> void:
	if roll_time > 0.0:
		anim_pose = Pose.BACKSTEP if is_backstep else Pose.ROLL
	elif stagger_time > 0.0:
		anim_pose = Pose.STAGGER
	else:
		anim_pose = Pose.NONE
	body_tilt = BOOST_LEAN * boost_blend if anim_pose == Pose.NONE else 0.0


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


## If that hit just started our iframes, flinch and show the fade on
## everyone's copy.
func _share_iframes(was_in_iframes: bool) -> void:
	if was_in_iframes or not Entity.is_in_iframes:
		return
	if visual:
		visual.play_hit()
	if Net.match_synced:
		_net_iframes.rpc()


@rpc("any_peer", "reliable")
func _net_receive_hit(dir: Vector3, damage: float, knockback_velocity: Vector3, attacker_name: String) -> void:
	if is_multiplayer_authority():
		var attacker: Node3D = null
		if attacker_name != "" and Global.Game3D:
			attacker = Global.Game3D.get_node_or_null(attacker_name) as PlayerClass3D
		receive_hit(dir, damage, knockback_velocity, attacker)


@rpc("any_peer", "reliable")
func _net_shove(direction: Vector3, force: float) -> void:
	if is_multiplayer_authority():
		shove(direction, force)


@rpc("any_peer", "unreliable")
func _net_iframes() -> void:
	if Entity and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		Entity.start_iframes()
		if visual:
			visual.play_hit()


## The raised shield that stops an attack travelling along `attack_dir`, if any.
func _blocking_shield(attack_dir: Vector3) -> ShieldClass3D:
	for weapon: Weapon3D in [held_weapon_left, held_weapon_right]:
		if weapon is ShieldClass3D and weapon.is_blocking:
			# Blocked if the attack is coming at our front
			return weapon if global_transform.basis.z.dot(-attack_dir) > BLOCK_FACING_DOT else null
	return null


# ===== STAMINA =====

func _use_stamina(amount: float) -> bool:
	return Entity.use_stamina(amount) if Entity else true


func _update_sprint(direction: Vector3, delta: float) -> void:
	if not Entity:
		is_sprinting = Input_Handler.move_dodge
		return
	if sprint_exhausted and Entity.stamina >= Entity.stamina_max * SPRINT_RECOVER_RATIO:
		sprint_exhausted = false
	is_sprinting = Input_Handler.move_dodge and not direction.is_zero_approx() and not sprint_exhausted and not is_boosting \
		and not held_ball and not is_busy() and not is_perk_locked()
	if is_sprinting:
		Entity.drain_stamina(SPRINT_STAMINA_PER_SEC * delta)
		if Entity.stamina <= 0.0:
			sprint_exhausted = true

func _update_arm_swings(delta: float) -> void:
	swipe_timer_left = _update_arm_swing(delta, swipe_timer_left, contact_left)
	swipe_timer_right = _update_arm_swing(delta, swipe_timer_right, contact_right)
	shot_time_left = max(shot_time_left - delta, 0.0)
	shot_time_right = max(shot_time_right - delta, 0.0)
	release_time_left = max(release_time_left - delta, 0.0)
	release_time_right = max(release_time_right - delta, 0.0)


## That hand holds a weapon that chops (see WeaponClass3D.vertical_swing).
func _chops(is_left: bool) -> bool:
	var weapon: Weapon3D = held_weapon_left if is_left else held_weapon_right
	return weapon is WeaponClass3D and weapon.vertical_swing


## A held weapon's swing connected (see Weapon3D._swing_contact).
func swing_contact(weapon: Weapon3D, solid: bool) -> void:
	_start_swing_contact(weapon == held_weapon_left, solid)


## Stop that arm where it is for a moment; off something solid, spring it
## back from there afterwards instead of finishing the swing.
func _start_swing_contact(is_left: bool, solid: bool) -> void:
	var contact: SwingContact = contact_left if is_left else contact_right
	if contact.hitstop > 0.0 or contact.rebound > 0.0:
		return  # Already stopped
	# A spin carries on round through whatever it hits
	if _swing_spin_left if is_left else _swing_spin_right:
		solid = false
	contact.hitstop = Combat.HITSTOP if solid else Combat.HITSTOP_LIGHT
	if not solid:
		return
	contact.rebound = REBOUND_DURATION
	contact.phase_from = _swing_phase(is_left)
	# A fist springing back off someone shouldn't punch anyone on the way
	if is_left:
		punching_left = false
	else:
		punching_right = false


## Counts down one arm's swing `timer`. It holds still during a hit-stop, and
## while springing back off something solid it runs on the rebound instead.
func _update_arm_swing(delta: float, timer: float, contact: SwingContact) -> float:
	if contact.hitstop > 0.0:
		contact.hitstop -= delta
		return timer  # Held where it connected
	if contact.rebound > 0.0:
		contact.rebound = max(contact.rebound - delta, 0.0)
		return contact.rebound  # Still mid-swing until it's back at rest
	return max(timer - delta, 0.0)


## Where that arm's swing is (see arm_anim): from where it started
## (swipe_from_*) through the strike over the first half of the swing, then
## recovering over the second.
func _swing_phase(is_left: bool) -> float:
	var timer: float = swipe_timer_left if is_left else swipe_timer_right
	var duration: float = swipe_duration_left if is_left else swipe_duration_right
	var from: float = swipe_from_left if is_left else swipe_from_right
	var t: float = clamp(1.0 - timer / duration, 0.0, 1.0)
	if _swing_spin_left if is_left else _swing_spin_right:
		# Arms out at the end of the strike for the spin, then recover
		if t < SPIN_ARMS_OUT:
			return lerp(from, 2.0, t / SPIN_ARMS_OUT)
		return 2.0 + maxf(t - (1.0 - SPIN_ARMS_OUT), 0.0) / SPIN_ARMS_OUT
	if t < 0.5:
		return lerp(from, 2.0, t * 2.0)
	return 2.0 + (t - 0.5) * 2.0


## Work out arm_anim from each arm's timers.
func _update_arm_anim() -> void:
	var left: Vector2 = _arm_action(true)
	var right: Vector2 = _arm_action(false)
	arm_anim = PackedFloat32Array([left.x, left.y, right.x, right.y,
			_arm_clip_index(true), _arm_clip_index(false), _spin_angle()])


## arm_anim's clip for that arm: a combo beat's, while it swings.
func _arm_clip_index(is_left: bool) -> float:
	var swinging: bool = (swipe_timer_left if is_left else swipe_timer_right) > 0.0 \
		or (contact_left if is_left else contact_right).rebound > 0.0
	if not swinging:
		return -1.0
	return PlayerVisual3D.clip_index(_swing_clip_left if is_left else _swing_clip_right)


## (ArmAction, phase) for one arm, busiest first.
func _arm_action(is_left: bool) -> Vector2:
	var contact: SwingContact = contact_left if is_left else contact_right
	if contact.rebound > 0.0:
		# Back the way it came, from where it hit to cocked
		return Vector2(ArmAction.SWING, lerp(1.0, contact.phase_from, contact.rebound_weight()))
	if (swipe_timer_left if is_left else swipe_timer_right) > 0.0:
		return Vector2(ArmAction.SWING, _swing_phase(is_left))
	var draw: SwingDraw = draw_left if is_left else draw_right
	if draw.is_active():
		return Vector2(ArmAction.SWING, draw.progress())
	var shot: float = shot_time_left if is_left else shot_time_right
	if shot > 0.0:
		return Vector2(ArmAction.SWING, 3.0 - 2.0 * shot / SHOT_ANIM_DURATION)
	var release: float = release_time_left if is_left else release_time_right
	if release > 0.0:
		return Vector2(ArmAction.THROW, 3.0 - 2.0 * release / THROW_RELEASE_DURATION)
	var windup: float = windup_left if is_left else windup_right
	if windup > WINDUP_SHOWN:
		return Vector2(ArmAction.THROW, windup)
	var weapon: Weapon3D = held_weapon_left if is_left else held_weapon_right
	if weapon and weapon.is_holding_pose() and not held_ball:
		return Vector2(ArmAction.HOLD, 0.0)
	return Vector2(ArmAction.REST, 0.0)


## Winds the arm back while its hand holds something throwable and the
## attack button is held, ramping up over WINDUP_RAMP_DURATION (matching the
## throw-charge window) and relaxing back to rest otherwise.
func _update_weapon_windups(delta: float) -> void:
	if Input_Handler.uses_simple_controls():
		windup_left = _update_hand_windup(windup_left, delta, _throw_pressed(true) and throw_left_armed, throw_left_press_time, is_hand_occupied(true), THROW_CHARGE_MAX_DURATION)
		windup_right = _update_hand_windup(windup_right, delta, _throw_pressed(false) and throw_right_armed, throw_right_press_time, is_hand_occupied(false), THROW_CHARGE_MAX_DURATION)
		return
	# A two-handed weapon's left button is its alt attack: no throw to wind up
	windup_left = _update_hand_windup(windup_left, delta, _attack_pressed(true) and attack_left_armed, attack_left_press_time, held_weapon_left != null or held_ball)
	windup_right = _update_hand_windup(windup_right, delta, _attack_pressed(false) and attack_right_armed, attack_right_press_time, is_hand_occupied(false))


func _update_hand_windup(current: float, delta: float, is_pressed: bool, press_time: float, has_throwable: bool, ramp: float = WINDUP_RAMP_DURATION) -> float:
	var target: float = 0.0
	if is_pressed and has_throwable:
		var hold_duration: float = (Time.get_ticks_msec() / 1000.0) - press_time
		target = clamp(hold_duration / ramp, 0.0, 1.0)
	return move_toward(current, target, delta * WINDUP_LERP_SPEED)
