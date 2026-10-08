class_name PlayerClass3D extends CharacterBody3D
## A player in the arena. Each arm's state (what it holds, its buttons, its
## swing) lives in a PlayerArm3D, and both arms run the same code; a
## dual-wield special or alt attack plays out in a PlayerCombo3D.

@onready var Entity: EntityBehavior3D = $Entity
@onready var visual: PlayerVisual3D = $Visual

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
			_motion.push(value[0], value[1], value[2])
var _motion := NetMotion.new()

## What each arm is doing, for PlayerVisual3D to pick and pose its clip:
## [left ArmAction, left phase, right ArmAction, right phase, left clip,
## right clip, spin]. The clips are a combo beat's own (an index into
## PlayerVisual3D.CLIP_KEYS, -1 = the weapon's usual one); spin is how far
## round (radians) a spinning combo beat has turned the body. Phases run as
## described in PlayerArm3D. Worked out each physics tick from the arms on
## the owner, and played back from net_pose by remote copies.
enum ArmAction { REST, SWING, THROW, HOLD }
const ARM_ANIM_SIZE := 7
var arm_anim := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, -1.0, -1.0, 0.0])

# ===== ARMS =====

var left_arm := PlayerArm3D.new(true)
var right_arm := PlayerArm3D.new(false)
## Both arms, left first.
var arms: Array[PlayerArm3D] = [left_arm, right_arm]
## Each hand's weapon (shortcuts to the arms', which other scripts use).
var held_weapon_left: Weapon3D:
	get: return left_arm.weapon
	set(value): left_arm.weapon = value
var held_weapon_right: Weapon3D:
	get: return right_arm.weapon
	set(value): right_arm.weapon = value
## The dual-wield special or alt attack under way, if any.
var _combo := PlayerCombo3D.new(self)
## Just got hit: frozen for a moment (see Combat.HITSTOP).
var hitstop: float = 0.0

# Advanced controls: tap to swing, hold to throw (see _tap_or_hold).
const HOLD_THRESHOLD := 0.35
# How long past HOLD_THRESHOLD you can charge a throw for max power, and the
# force multiplier range that charge maps to (0.0 charge = just past the
# threshold, 1.0 charge = held for THROW_CHARGE_MAX_DURATION or longer).
const THROW_CHARGE_MAX_DURATION := 1.0
const THROW_FORCE_MIN_RATIO := 0.5
const THROW_FORCE_MAX_RATIO := 1.5
## Wind-up: while a hand holding a weapon is pressed, the arm winds back for the throw progressively instead of
## sitting static. Ramps up over the same press-and-hold window that charges
## throw force, so a fully wound-up arm means a fully-charged throw is coming.
const WINDUP_RAMP_DURATION := HOLD_THRESHOLD + THROW_CHARGE_MAX_DURATION
## Releases of the Advanced controls' tap-or-hold buttons.
enum Release { NONE, TAP, HOLD }

const ROTATION_SPEED = 10.0

## A chop (a vertical_swing weapon like the axe) can only hit over this share
## of its swing: the downstroke, not the recovery.
const CHOP_DOWNSTROKE := 0.5

# Boost: a meter filled by running through boost orbs (BoostOrb3D) around
# the arena. Holding the boost button while moving burns it to accelerate
# up to BOOST_SPEED (well past a sprint), and letting go eases back down, so
# it carries some momentum. It costs no stamina, and the speed bowls over anyone you run into (see _bump_other_players).
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
## How close a loose weapon has to be to pick it up (interact).
const WEAPON_REACH := 2.0
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
var _fist_shape := SphereShape3D.new()

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
## Sprinting walks this many times faster.
const SPRINT_SPEED_MULTIPLIER := 2.0
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

# Kills: the last opponent to hit us gets the kill if we die within
# KILL_CREDIT_TIME of it, even if something else (a boss stomp) finishes
# us off. Dying takes us out of play for a while (Game3D.revive_delay): we
# respawn at our team's spawn, or with Game3D.knockouts, lie where we fell
# and get back up there.
const KILL_CREDIT_TIME := 4.0
var _last_attacker_name: String = ""
var _last_attacker_msec: int = -1
## Seconds left before respawning; 0 = alive.
var dead_time: float = 0.0
## How many times we've died this match (knockouts take longer each time).
var deaths: int = 0
## Knocked out rather than gone: still in the level, lying where we fell.
var is_knocked_out: bool = false
var _alive_collision_layer: int = 0
## Wearing armor from an ArmorPickup3D: takes less damage and shows the
## character's helmet/hat and cape, until they next die (synced online).
const ARMOR_DAMAGE_TAKEN := 0.7
var armored: bool = false:
	set(value):
		armored = value
		if visual:  # Not yet found before _ready
			visual.set_armored(value)
## Floats over the head of anyone on the team leading in kills.
var _crown: MeshInstance3D = null


func _ready() -> void:
	# All part of player_3d.tscn (a bot swaps the Input node's script, it
	# doesn't remove it), so the rest of this script uses them unchecked.
	assert(Entity and visual and Input_Handler and Properties,
		"player_3d.tscn needs its Entity, Visual and Input nodes and its Properties")
	# Properties is a sub-resource of player_3d.tscn, so every instance would
	# share it - give each player its own, in its team's color.
	Properties = Properties.duplicate()
	if slot:
		Properties.player_color = slot.color
	visual.setup(self)
	Input_Handler.slot = slot
	_fist_shape.radius = FIST_REACH

	Entity.spawn_pos = global_position
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
	Input_Handler.set_process(false)
	Input_Handler.set_process_input(false)


func _physics_process(delta: float) -> void:
	if is_remote:
		return
	if is_dead():
		if is_knocked_out:
			_fall_while_down(delta)
		return
	if hitstop > 0.0:
		hitstop -= delta
		return
	if not is_on_floor():
		velocity += get_gravity() * delta

	var direction: Vector3 = Input_Handler.move_dir
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
		if not _pick_up_nearest_weapon():
			_take_from_nearest_stand()
	if Input_Handler.swap_hands:
		Input_Handler.swap_hands = false
		swap_hands()

	# Walking velocity (sprinting speeds up only the horizontal part)
	var speed: float = Entity.SPEED * perk_stat(&"move_speed")
	var walk: Vector3 = direction * speed
	if is_sprinting:
		walk.x *= SPRINT_SPEED_MULTIPLIER
		walk.z *= SPRINT_SPEED_MULTIPLIER
	if boost_blend > 0.0:
		var boost_speed: float = BOOST_SPEED * perk_stat(&"boost_speed")
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
	elif !Input_Handler.look_dir.is_zero_approx() and not perk_locked:
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
	_combo.update(delta)
	for arm: PlayerArm3D in arms:
		arm.tick(delta)
	_update_punches()
	_update_arm_anim()

	if net_sync:
		net_pose = [NetInterpolator.now(), global_transform, arm_anim]


func _process(delta: float) -> void:
	if is_dead():
		_update_death(delta)
		if is_remote and is_knocked_out:
			_process_remote(delta)  # Lying where we fell, but still falling there
		return
	if is_remote:
		_process_remote(delta)
		return
	# Rolling or staggered: hands do nothing, and presses made meanwhile
	# don't count once it's over (like presses made while blocking)
	var busy: bool = is_busy() or is_perk_locked()
	if busy:
		for arm: PlayerArm3D in arms:
			arm.attack.armed = false
			arm.throw.armed = false

	# A shield raises to block while its guard is held, instead of following
	# its hand's usual swing/throw behavior.
	for arm: PlayerArm3D in arms:
		_handle_guard(arm, _guard_pressed(arm) and not busy)

	# Each hand on its own: a hand holding a weapon swings or throws it, an
	# empty one punches (see _handle_weapon_arm). Every button is read before any acts, since
	# acting (e.g. throwing a two-handed weapon) changes what they mean.
	for arm: PlayerArm3D in arms:
		arm.attack.held = _attack_pressed(arm)
		arm.throw.held = _throw_pressed(arm)
	if not busy:
		for arm: PlayerArm3D in arms:
			_handle_attack_button(arm)
		for arm: PlayerArm3D in arms:
			_handle_throw_button(arm)
	for arm: PlayerArm3D in arms:
		arm.attack.was_held = arm.attack.held
		arm.throw.was_held = arm.throw.held
	if Input_Handler.drop_weapon:
		Input_Handler.drop_weapon = false
		if not busy:
			_drop_main_weapon()


## Remote copy, every rendered frame: move to where the owner was a moment
## ago. Held weapons ride the hands (see
## PlayerVisual3D), which play the owner's arm_anim.
func _process_remote(delta: float) -> void:
	var extras: PackedFloat32Array = _motion.play(self, delta)
	if extras.size() == ARM_ANIM_SIZE:
		arm_anim = extras


# ===== HANDS & HOLDING =====

func arm_of(is_left: bool) -> PlayerArm3D:
	return left_arm if is_left else right_arm


func _other_arm(arm: PlayerArm3D) -> PlayerArm3D:
	return right_arm if arm == left_arm else left_arm


## A hand is occupied if it holds a weapon, or both hands hold a two-handed
## one.
func is_hand_occupied(is_left: bool) -> bool:
	if is_left and _holds_two_handed():
		return true
	return arm_of(is_left).weapon != null


## Which hand the Attack button works (see PlayerInputHandler3D): the
## right, the main hand, unless it's empty and the left holds something to
## use. A shield counts only if `shield_too` (throwing it, or the advanced
## controls' tap-to-bash); otherwise Off-hand keeps it, to block. Off-hand
## works the other hand.
func main_hand_is_left(shield_too: bool = false) -> bool:
	if held_weapon_right != null or held_weapon_left == null:
		return false
	return shield_too or not held_weapon_left is ShieldClass3D


## A one-handed weapon (not a shield) in each hand: the Off-hand button
## does a special with both (see WeaponCombo3D).
func can_combo() -> bool:
	var left: Weapon3D = held_weapon_left
	var right: Weapon3D = held_weapon_right
	return left != null and right != null \
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
	arm_of(is_left).weapon = weapon
	weapon.equip(self, _hand_holding(weapon, is_left))
	Sfx.play(weapon.equip_sound(), global_position)


## The hand bone that carries `weapon` when it's that hand's weapon.
func _hand_holding(weapon: Weapon3D, is_left: bool) -> Node3D:
	return visual.hand(is_left or weapon.rides_left_hand)


## Move each hand's weapon to the other hand, if both arms are free and each
## weapon may go in the other hand (see Weapon3D.Grip).
func swap_hands() -> void:
	if is_busy() or is_swinging() or not (held_weapon_left or held_weapon_right):
		return
	if (held_weapon_left and not grip_allows(held_weapon_left.grip, false)) \
			or (held_weapon_right and not grip_allows(held_weapon_right.grip, true)):
		return
	_swap_hands()
	if Net.match_synced:
		_net_swap_hands.rpc()


func _swap_hands() -> void:
	var left: Weapon3D = left_arm.weapon
	left_arm.weapon = right_arm.weapon
	right_arm.weapon = left
	for arm: PlayerArm3D in arms:
		if arm.weapon is ShieldClass3D:
			arm.weapon.stop_block()
	for arm: PlayerArm3D in arms:
		if arm.weapon:
			arm.weapon.equip(self, _hand_holding(arm.weapon, arm.is_left))


@rpc("any_peer", "reliable")
func _net_swap_hands() -> void:
	if multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_swap_hands()


# ===== BUTTONS =====
# Simple controls: Attack and Off-hand act on press, a shield blocks while
# its button is held, and Throw + a hand's button throws (see
# _handle_throw_button). Advanced: a tap swings and a hold throws (see
# _tap_or_hold), with separate guard buttons. See PlayerInputHandler3D.

## That arm's attack button. With a two-handed weapon the right hand's
## swings it and the (empty) left's is its alt attack (see _handle_weapon_arm).
func _attack_pressed(arm: PlayerArm3D) -> bool:
	return Input_Handler.action_left if arm.is_left else Input_Handler.action_right


func _guard_pressed(arm: PlayerArm3D) -> bool:
	return Input_Handler.action_heavy_left if arm.is_left else Input_Handler.action_heavy_right


## That arm's throw (simple controls), like _attack_pressed.
func _throw_pressed(arm: PlayerArm3D) -> bool:
	if _holds_two_handed():
		return false if arm.is_left else Input_Handler.throw_left or Input_Handler.throw_right
	return Input_Handler.throw_left if arm.is_left else Input_Handler.throw_right


func _handle_guard(arm: PlayerArm3D, guarding: bool) -> void:
	if arm.weapon is ShieldClass3D:
		if guarding:
			arm.weapon.start_block()
		else:
			arm.weapon.stop_block()


func _handle_attack_button(arm: PlayerArm3D) -> void:
	var button: PlayerArm3D.Press = arm.attack
	if arm.weapon is ShieldClass3D and arm.weapon.is_blocking:
		button.armed = false
		return  # Raised to block - ignore tap/hold-throw for this hand.

	if button.just_pressed():
		button.armed = true
	elif button.just_released():
		if not button.armed:
			return  # Pressed while blocking - nothing to release
		button.armed = false

	_handle_weapon_arm(arm)


## An empty hand's button is the off hand's: with a weapon in the other hand
## that's its alt attack, otherwise a punch. A hand with a weapon swings it
## (or does the dual-wield special, see _swing_or_combo), and with advanced
## controls throws it on a hold.
func _handle_weapon_arm(arm: PlayerArm3D) -> void:
	if not arm.weapon:
		if arm.attack.just_pressed():
			var other: PlayerArm3D = _other_arm(arm)
			if other.weapon and not other.weapon is ShieldClass3D:
				_start_alt(other)
			else:
				_start_punch(arm)
		return
	if Input_Handler.uses_simple_controls():
		# Throwing has its own button, so a swing goes off as soon as it's pressed
		if arm.attack.just_pressed():
			_swing_or_combo(arm)
		return
	match _tap_or_hold(arm.attack):
		Release.HOLD:
			_throw_weapon(arm, _pay_throw_charge(arm.attack.held_for() - HOLD_THRESHOLD))
		Release.TAP:
			_swing_or_combo(arm)


## Advanced controls: a press only notes when it began; whether it swings
## or throws is decided on release, by how long it was held.
func _tap_or_hold(button: PlayerArm3D.Press) -> Release:
	if button.just_pressed():
		button.press_time = PlayerArm3D.now()
	elif button.just_released():
		return Release.HOLD if button.held_for() >= HOLD_THRESHOLD else Release.TAP
	return Release.NONE


## Simple controls' throw for one hand (Throw held + that hand's attack
## button): winds up while held (harder the longer, up to
## THROW_CHARGE_MAX_DURATION) and throws that hand's weapon on release. A
## quick tap is a light toss. A raised shield
## can't be thrown.
func _handle_throw_button(arm: PlayerArm3D) -> void:
	var button: PlayerArm3D.Press = arm.throw
	if button.just_pressed():
		button.press_time = PlayerArm3D.now()
		button.armed = true
		return
	if not button.just_released() or not button.armed:
		return
	button.armed = false
	var weapon: Weapon3D = arm.weapon
	if not weapon or (weapon is ShieldClass3D and weapon.is_blocking):
		return
	_throw_weapon(arm, _pay_throw_charge(button.held_for()))


## Throw tapped on its own: let go of the main hand's weapon, or the off
## hand's if that's all we hold.
func _drop_main_weapon() -> void:
	var weapon: Weapon3D = held_weapon_right if held_weapon_right else held_weapon_left
	if weapon and not (weapon is ShieldClass3D and weapon.is_blocking):
		weapon.drop()


# ===== SWINGS =====

## The off hand's button with a weapon in each hand does a special (the left
## is the off hand then); otherwise it's a plain swing.
func _swing_or_combo(arm: PlayerArm3D) -> void:
	if arm.is_left and can_combo():
		_start_combo()
	else:
		_swing_weapon(arm)


## Stamina a swing of `weapon` costs.
func _swing_stamina(weapon: Weapon3D) -> float:
	return SWING_STAMINA * (weapon.Properties.swing_stamina_scale if weapon.Properties else 1.0)


## Swing (or fire) the arm's weapon, if that arm is free and we have the
## stamina; false if it couldn't. A heavy weapon draws back first (see
## PlayerArm3D.begin_draw).
func _swing_weapon(arm: PlayerArm3D) -> bool:
	var weapon: Weapon3D = arm.weapon
	if arm.is_swinging() or not _use_stamina(_swing_stamina(weapon)):
		return false  # Mid-swing already, or too tired
	var draw_time: float = weapon.Properties.swing_windup if weapon.Properties else 0.0
	if draw_time > 0.0 and weapon.plays_swipe_animation:
		arm.begin_draw(weapon, draw_time)
	else:
		strike(arm)
	return true


## The arm's weapon attacks now: a melee one swings (live for its
## swing_duration) with a step forward, a ranged one just fires. `step` is
## the combo beat it's part of, if any. Returns the swing's length.
func strike(arm: PlayerArm3D, step: WeaponComboStep3D = null) -> float:
	var weapon: Weapon3D = arm.weapon
	var club: bool = step != null and step.melee  # A ranged weapon swung, not fired
	if not club:
		weapon.attack(_get_aim_direction())
	if not weapon.plays_swipe_animation and not club:
		arm.shot_time = PlayerArm3D.SHOT_ANIM_DURATION
		return PlayerArm3D.SHOT_ANIM_DURATION
	var duration: float = weapon.Properties.swing_duration if weapon.Properties else PlayerArm3D.SWIPE_DURATION
	var drawn: bool = step == null and weapon.Properties != null and weapon.Properties.swing_windup > 0.0
	var spin: bool = step != null and step.spin_turns != 0.0
	if step:
		duration *= step.duration_scale
	arm.begin_swing(duration, 1.0 if drawn else PlayerArm3D.QUICK_SWING_PHASE)
	if step:
		arm.swing_clip = step.off_clip if arm.is_left else step.main_clip
		arm.swing_spin = spin
	var window: float = duration * CHOP_DOWNSTROKE if _chops(arm) and not spin else duration
	weapon.start_swing(window, step.damage_scale if step else 1.0)
	var lunge_scale: float = step.lunge_scale if step else 1.0
	if lunge_scale > 0.0:
		_lunge(SWING_LUNGE_SPEED * lunge_scale)
	return duration


## Draw-backs finish here and turn into the strike, if the same weapon is
## still in that hand (it may have been thrown, dropped or broken meanwhile).
func _update_swing_draws(delta: float) -> void:
	for arm: PlayerArm3D in arms:
		var drawn: Weapon3D = arm.tick_draw(delta)
		if is_instance_valid(drawn) and drawn == arm.weapon:
			strike(arm)


## That arm holds a weapon that chops (see WeaponClass3D.vertical_swing).
func _chops(arm: PlayerArm3D) -> bool:
	return arm.weapon is WeaponClass3D and arm.weapon.vertical_swing


## A held weapon's swing connected (see Weapon3D._swing_contact).
func swing_contact(weapon: Weapon3D, solid: bool) -> void:
	arm_of(weapon == held_weapon_left).start_contact(solid)


## Either arm is mid-swing (weapon or fist), drawing one back, or
## playing out a special.
func is_swinging() -> bool:
	return left_arm.is_swinging() or right_arm.is_swinging() or _combo.is_running()


## That arm is mid-swing or drawing one back.
func is_arm_swinging(is_left: bool) -> bool:
	return arm_of(is_left).is_swinging()


## Drawing a heavy swing back, or in the strike half of any swing: committed,
## so no rolling out of it. The follow-through can be rolled out of.
func _is_committed() -> bool:
	return left_arm.is_committed() or right_arm.is_committed()


## Stop any punch or weapon swing from hitting anything more.
func _cancel_attacks() -> void:
	_combo.cancel()
	for arm: PlayerArm3D in arms:
		arm.cancel()


## Step toward the lock-on target (or the aim) at `speed`, stopping short of
## the target instead of running into it.
func _lunge(speed: float) -> void:
	var dir: Vector3 = _get_aim_direction()
	dir.y = 0.0
	if dir.is_zero_approx():
		return
	var target: Node3D = Entity.target
	if target and is_instance_valid(target):
		var target_radius: float = Boss3D.RADIUS if target is Boss3D else BODY_RADIUS
		var to_target := Vector3(target.global_position.x - global_position.x, 0.0, target.global_position.z - global_position.z)
		var gap: float = max(to_target.length() - BODY_RADIUS - target_radius - LUNGE_STOP_GAP, 0.0)
		# A lunge slides speed^2 / (2 * friction) before it stops
		speed = min(speed, sqrt(2.0 * LUNGE_FRICTION * gap))
	lunge = dir.normalized() * speed


# ===== DUAL-WIELD SPECIALS =====

## The Off-hand button with a weapon in each hand: their special (see
## WeaponCombo3D.find_for).
func _start_combo() -> bool:
	if not can_combo():
		return false
	return _start_special(WeaponCombo3D.find_for(held_weapon_left, held_weapon_right), false)


## The Off-hand button with nothing in the off hand: the weapon in `arm`'s
## alt attack, or a plain swing if it has none.
func _start_alt(arm: PlayerArm3D) -> bool:
	if not arm.weapon.alt_attack:
		return _swing_weapon(arm)
	return _start_special(arm.weapon.alt_attack, arm.is_left)


## Start `combo`'s beats (see PlayerCombo3D), its MAIN ones in the left hand
## if `main_is_left`, if both arms are free and we have the stamina for
## every beat.
func _start_special(combo: WeaponCombo3D, main_is_left: bool) -> bool:
	if not combo or combo.steps.is_empty() or is_swinging():
		return false
	var cost: float = 0.0
	for step: WeaponComboStep3D in combo.steps:
		for arm: PlayerArm3D in _combo.arms_for(step, main_is_left):
			cost += _swing_stamina(arm.weapon)
	if not _use_stamina(cost * combo.stamina_scale):
		return false
	_combo.start(combo, main_is_left)
	return true


# ===== THROWING =====

## A throw charged for `seconds` (0-1, full at THROW_CHARGE_MAX_DURATION),
## paid for in stamina. Too tired to pay = the weakest possible throw.
func _pay_throw_charge(seconds: float) -> float:
	var charge: float = clamp(seconds / THROW_CHARGE_MAX_DURATION, 0.0, 1.0)
	return charge if _use_stamina(THROW_STAMINA) else 0.0


## The force multiplier a throw `charge` (0-1) gives.
func _throw_force_ratio(charge: float) -> float:
	return lerp(THROW_FORCE_MIN_RATIO, THROW_FORCE_MAX_RATIO, charge)


func _throw_weapon(arm: PlayerArm3D, charge: float = 1.0) -> void:
	var spin_direction: float = -1.0 if arm.is_left else 1.0
	var force_multiplier: float = _throw_force_ratio(charge) * perk_stat(&"throw_power")
	arm.weapon.throw(_get_aim_direction(), -1.0, spin_direction, force_multiplier)
	arm.weapon = null
	arm.play_throw_release()


func _get_aim_direction() -> Vector3:
	if Entity.target and is_instance_valid(Entity.target):
		return (Entity.target.global_position - global_position).normalized()
	if not Input_Handler.look_dir.is_zero_approx():
		return Input_Handler.look_dir
	return Vector3(sin(rotation.y), 0, cos(rotation.y))


## Winds each arm back while its throw is being charged: Throw + its button
## with simple controls, its button held with advanced ones (a two-handed
## weapon's left button is its alt attack, so that has no throw to wind up).
func _update_weapon_windups(delta: float) -> void:
	var simple: bool = Input_Handler.uses_simple_controls()
	for arm: PlayerArm3D in arms:
		var button: PlayerArm3D.Press = arm.throw if simple else arm.attack
		var pressed: bool = (_throw_pressed(arm) if simple else _attack_pressed(arm)) and button.armed
		var ramp: float = THROW_CHARGE_MAX_DURATION if simple else WINDUP_RAMP_DURATION
		arm.update_windup(delta, pressed, button.press_time, arm.weapon != null, ramp)


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


func _start_punch(arm: PlayerArm3D) -> void:
	if arm.is_swinging() or not _use_stamina(PUNCH_STAMINA):
		return
	arm.begin_swing(PlayerArm3D.SWIPE_DURATION)
	arm.punching = true
	arm.punch_hits.clear()
	_lunge(FIST_LUNGE_SPEED)


## While a fist is mid-swing, hit whatever it passes through (once each).
func _update_punches() -> void:
	for arm: PlayerArm3D in arms:
		if arm.punching:
			arm.punching = arm.swing_time > 0.0
			if arm.punching:
				_check_fist_hits(arm)


func _check_fist_hits(arm: PlayerArm3D) -> void:
	var hand: Node3D = visual.hand(arm.is_left)
	if not hand: return
	var exclude: Array[RID] = [get_rid()]
	for held: PlayerArm3D in arms:
		if held.weapon:
			exclude.append(held.weapon.get_rid())
	var contact: bool = false
	var solid: bool = false
	for body: Node3D in Combat.overlaps(get_world_3d(), _fist_shape, Transform3D(Basis(), hand.global_position), exclude):
		if body in arm.punch_hits:
			continue
		arm.punch_hits.append(body)
		contact = true
		solid = solid or Combat.is_solid(body)
		if Combat.strike(body, body.global_position - global_position, FIST_DAMAGE, FIST_KNOCKBACK, FIST_POP, FIST_OBJECT_IMPULSE, self):
			var recoil: Vector3 = global_position - body.global_position
			recoil.y = 0
			add_knockback(recoil.normalized() * FIST_RECOIL)
	if contact:
		arm.start_contact(solid)


# ===== HITS & DEATH =====

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
	var was_in_iframes: bool = Entity.is_in_iframes
	var exhausted: bool = Entity.stamina <= 0.0
	Entity.take_hit(damage, knockback_velocity)
	_share_iframes(was_in_iframes)
	if not was_in_iframes:
		hitstop = Combat.HITSTOP
		if exhausted:
			_stagger()
	if Entity.hp <= 0:
		_on_lethal_hit()
	return true


## Out of HP (on the owner): we die and Game3D is told who, if anyone,
## gets the kill.
func _on_lethal_hit() -> void:
	var killer_name: String = _credited_killer()
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
	deaths += 1
	var delay: float = Global.Game3D.revive_delay(self, deaths) if Global.Game3D else 0.0
	if Global.Game3D and Global.Game3D.knockouts and delay > 0.0:
		_knock_out(delay)
		return
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
	for arm: PlayerArm3D in arms:
		arm.attack.armed = false
	_alive_collision_layer = collision_layer
	collision_layer = 0
	visible = false


func _update_death(delta: float) -> void:
	dead_time = max(dead_time - delta, 0.0)
	if dead_time > 0.0:
		return
	collision_layer = _alive_collision_layer
	visible = true
	if is_knocked_out:
		is_knocked_out = false
		if _is_local():
			_revive_in_place()
	visual.play_spawn()
	Entity.start_iframes()  # A moment of spawn protection


## Knocked out for `delay` seconds: we drop where we stand and stay there,
## weapons still in hand, where enemies can't hit us and others walk
## through us. Like die(), on every machine.
func _knock_out(delay: float) -> void:
	is_knocked_out = true
	dead_time = delay
	_last_attacker_name = ""
	_last_attacker_msec = -1
	_cancel_attacks()
	for arm: PlayerArm3D in arms:
		arm.attack.armed = false
	knockback = Vector3.ZERO
	lunge = Vector3.ZERO
	roll_time = 0.0
	roll_iframes = 0.0
	stagger_time = 0.0
	is_boosting = false
	boost_blend = 0.0
	_alive_collision_layer = collision_layer
	collision_layer = 0
	visual.play_down()


## Owner, while knocked out: just fall to the floor (a stomp may have
## knocked us into the air) and keep everyone else posted.
func _fall_while_down(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()
	if net_sync:
		net_pose = [NetInterpolator.now(), global_transform, arm_anim]


## Owner: back up after a knockout, fully restored, right where we lay.
func _revive_in_place() -> void:
	var lying_at: Vector3 = global_position
	velocity = Vector3.ZERO
	boost = BOOST_START
	Entity.reset(true)  # Full stats (it also moves us to Entity.spawn_pos...)
	global_position = lying_at  # ...so put us back


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
	if heal > 0.0 and _is_local() and not is_dead():
		Entity.hp = min(Entity.hp + Entity.hp_max * heal, Entity.hp_max)


## Back to where this player started, fully restored. Anything still held
## comes along. Online only the owner calls this; the
## new position and HP reach everyone through the usual sync.
func respawn() -> void:
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


## A shove with no damage (e.g. a fast ball), routed like receive_hit.
func shove(direction: Vector3, force: float) -> void:
	if not _is_local():
		if Net.match_synced:
			_net_shove.rpc_id(get_multiplayer_authority(), direction, force)
	elif roll_iframes <= 0.0 and not is_dead():
		var was_in_iframes: bool = Entity.is_in_iframes
		Entity.apply_knockback(direction, force * perk_stat(&"knockback_taken"))
		_share_iframes(was_in_iframes)


# ===== DODGE ROLL & POISE =====

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


## Roll if the dodge button was tapped recently and we're free to.
func _try_roll(direction: Vector3) -> void:
	var request: int = Input_Handler.dodge_request_msec
	if request < 0:
		return
	if Time.get_ticks_msec() - request > ROLL_BUFFER_MSEC:
		Input_Handler.dodge_request_msec = -1
		return
	if is_busy() or _is_committed() or not is_on_floor():
		return  # Keep it buffered
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


## A hit landed on our raised shield: a little damage and shove, paid for
## in stamina. Emptying the bar breaks the guard. Unlike an open hit it
## leaves no iframes, so a flurry keeps draining the guard.
func _receive_blocked_hit(damage: float, knockback_velocity: Vector3, shield: ShieldClass3D) -> void:
	add_knockback(Vector3(knockback_velocity.x, 0, knockback_velocity.z) * BLOCK_KNOCKBACK_RATIO)
	Sfx.play_everywhere(&"block", shield.global_position)
	shield.wear()  # Each block is a use
	if Entity.is_in_iframes:
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


## Work out arm_anim from each arm's timers.
func _update_arm_anim() -> void:
	var left: Vector2 = left_arm.action()
	var right: Vector2 = right_arm.action()
	arm_anim = PackedFloat32Array([left.x, left.y, right.x, right.y,
			left_arm.clip_index(), right_arm.clip_index(), _combo.spin_angle()])


# ===== ARMOR =====

## Whether running through an armor pickup would give us anything.
func can_take_armor() -> bool:
	return not is_dead() and not armored


## Owner only (pickups call it on the machine that controls us).
func put_on_armor() -> void:
	if not is_dead():
		armored = true


# ===== BOOST & SPRINT =====

## Whether running through a boost orb would give us anything.
func can_take_boost() -> bool:
	return not is_dead() and boost < BOOST_MAX


## Owner only (orbs call it on the machine that controls us).
func add_boost(amount: float) -> void:
	boost += amount * perk_stat(&"boost_gain")


## Burn boost while the button is held, we're moving and free to; ease
## the speed up or back down.
func _update_boost(direction: Vector3, delta: float) -> void:
	is_boosting = Input_Handler.boost_held and boost > 0.0 and not direction.is_zero_approx() \
		and not is_busy() and not is_perk_locked()
	if is_boosting:
		boost -= BOOST_DRAIN_PER_SEC * delta
		boost_blend = move_toward(boost_blend, 1.0, delta / BOOST_RAMP_UP)
	else:
		boost_blend = move_toward(boost_blend, 0.0, delta / BOOST_RAMP_DOWN)
	if is_busy():
		boost_blend = 0.0


func _update_sprint(direction: Vector3, delta: float) -> void:
	if sprint_exhausted and Entity.stamina >= Entity.stamina_max * SPRINT_RECOVER_RATIO:
		sprint_exhausted = false
	is_sprinting = Input_Handler.move_dodge and not direction.is_zero_approx() and not sprint_exhausted and not is_boosting \
		and not is_busy() and not is_perk_locked()
	if is_sprinting:
		Entity.drain_stamina(SPRINT_STAMINA_PER_SEC * delta)
		if Entity.stamina <= 0.0:
			sprint_exhausted = true


func _use_stamina(amount: float) -> bool:
	return Entity.use_stamina(amount)


# ===== CONTROL SCHEME =====

## Souls-like controls follow `cam` (camera-relative movement, lock-on);
## null returns to the usual top-down controls. Local players only.
func set_souls_camera(cam: SoulsCamera3D) -> void:
	Input_Handler.souls_camera = cam
	if not cam:
		Entity.target = null


# ===== PERKS =====

## This player's multiplier for a perk stat (see PerkSet.STATS).
func perk_stat(stat_name: StringName) -> float:
	return perks.stat(stat_name)


## Take a perk. Max HP/stamina grow at once, keeping how full they were.
## Call on every machine.
func add_perk(perk: Perk) -> void:
	perks.add(perk)
	Entity.refresh_max_stats()


# ===== NETWORK =====

## Whether this machine controls this player (always, offline).
func _is_local() -> bool:
	return not Net.in_session() or is_multiplayer_authority()


## If that hit just started our iframes, flinch and show the fade on
## everyone's copy.
func _share_iframes(was_in_iframes: bool) -> void:
	if was_in_iframes or not Entity.is_in_iframes:
		return
	visual.play_hit()
	Sfx.play(&"hit_player", global_position)
	if Net.match_synced:
		_net_iframes.rpc()


@rpc("any_peer", "reliable")
func _net_receive_hit(dir: Vector3, damage: float, knockback_velocity: Vector3, attacker_name: String) -> void:
	if is_multiplayer_authority():
		var attacker: PlayerClass3D = Global.Game3D.player_named(attacker_name) if Global.Game3D else null
		receive_hit(dir, damage, knockback_velocity, attacker)


@rpc("any_peer", "reliable")
func _net_shove(direction: Vector3, force: float) -> void:
	if is_multiplayer_authority():
		shove(direction, force)


@rpc("any_peer", "unreliable")
func _net_iframes() -> void:
	if multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		Entity.start_iframes()
		visual.play_hit()
		Sfx.play(&"hit_player", global_position)


## The raised shield that stops an attack travelling along `attack_dir`, if any.
func _blocking_shield(attack_dir: Vector3) -> ShieldClass3D:
	for weapon: Weapon3D in [held_weapon_left, held_weapon_right]:
		if weapon is ShieldClass3D and weapon.is_blocking:
			# Blocked if the attack is coming at our front
			return weapon if global_transform.basis.z.dot(-attack_dir) > BLOCK_FACING_DOT else null
	return null
