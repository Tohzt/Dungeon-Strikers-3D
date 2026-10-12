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
	^"Entity:hp",
	# Lets each owner work out how hard someone else bumped into them
	^":velocity",
	# Rolling / sliding / staggered body, for PlayerVisual3D
	^":anim_pose",
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
## This character's signature kit (see Roster and the KIT section below),
## main hand first. Made by make_kit().
var kit: Array[Weapon3D] = []
## Kit weapons made so far, so a new character's kit doesn't take the old
## one's names (the same on every machine).
var _kits_made: int = 0
## Who a person playing here picked to come back as while down (see
## HUD3D), taken on as they get up. -1 = stay as we are.
var next_character: int = -1
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

# ===== CARRYING THE BALL =====
# Interact picks up a ball in reach. Carrying it drains the carry meter
# (shown on the HUD); Throw charges and throws it where we aim, Shoot (E /
# LT) charges and shoots it at the goal we attack (a skull: at our altar),
# and an empty meter tosses it forward on its own. Locked on (teammates
# can be locked on to while carrying), Shoot passes to a teammate or
# attacks an enemy with the ball instead. The meter refills while we don't carry.
signal carry_changed(new_carry: float, max_carry: float)
const CARRY_MAX := 100.0
## A full meter lasts this many seconds of carrying.
const CARRY_DRAIN_PER_SEC := 100.0 / 3.0
## Refills from empty in this many seconds.
const CARRY_REGEN_PER_SEC := 100.0 / 4.0
## Need this much to pick the ball up.
const CARRY_MIN_TO_GRAB := 25.0
const BALL_REACH := 2.0
## Walking speed while carrying, times normal (sprinting still works).
const CARRY_SPEED := 0.85
## Throw speed (scaled by the throw charge), and how much it rises.
const BALL_THROW_SPEED := 14.0
const BALL_THROW_LIFT := 0.15
## Shot speed (scaled by the charge like a throw: half to 1.5x), and how
## much it rises.
const BALL_SHOT_SPEED := 16.0
const BALL_SHOT_LIFT := 0.12
## A pass flies at least this fast, keeping low so it reaches them.
const BALL_PASS_MIN_SPEED := 10.0
const BALL_PASS_LIFT := 0.05
## A ball attack's damage, from no charge to full.
const BALL_ATTACK_DAMAGE_MIN := 8.0
const BALL_ATTACK_DAMAGE_MAX := 20.0
## Meter ran dry: tossed forward this fast.
const BALL_TOSS_SPEED := 6.0
var carry: float = CARRY_MAX:
	set(value):
		carry = clampf(value, 0.0, CARRY_MAX)
		carry_changed.emit(carry, CARRY_MAX)
## The ball we carry (every machine), if any.
var held_ball: Ball3D = null
## Asked to throw (online, until the server lets go).
var _ball_thrown: bool = false
## The Throw press under way began while carrying: it's for the ball, so
## letting go without it (stripped mid-charge) throws nothing.
var _throw_for_ball: bool = false
## Hit while carrying: the ball pops loose along the hit this fast.
const BALL_FUMBLE_SPEED := 5.0

## Walking speed while charging a heavy (see WeaponMove3D), times normal.
const CHARGE_MOVE_SPEED := 0.6
# How long you can charge a throw (holding Throw) for max power,
# and the force multiplier range that charge maps to.
const THROW_CHARGE_MAX_DURATION := 1.0
const THROW_FORCE_MIN_RATIO := 0.5
const THROW_FORCE_MAX_RATIO := 1.5
## A dash (see WeaponMove3D.Action.DASH): time left, and its velocity.
var _dash_time: float = 0.0
var _dash_velocity: Vector3 = Vector3.ZERO

const ROTATION_SPEED = 10.0

## A chop (a vertical_swing weapon like the axe) can only hit over this share
## of its swing: the downstroke, not the recovery.
const CHOP_DOWNSTROKE := 0.5

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


## Sprinting walks this many times faster.
const SPRINT_SPEED_MULTIPLIER := 2.0
var is_sprinting: bool = false

# Dodge roll (tap the dodge button): a dive along the walking direction that
# tucks into a forward roll (see PlayerVisual3D), untouchable for the first
# part of it. Rolls are on a cooldown (ROLL_COOLDOWN) so they have to be
# timed rather than spammed. Standing still, it's
# a short backstep instead; sprinting, a slide tackle (see SLIDE_DURATION). Can't roll in the
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
const ROLL_BUFFER_MSEC := 250
## Seconds from the start of a roll, backstep or slide until the next can go.
const ROLL_COOLDOWN := 1.0
## Intermission: close enough to our altar to stop walking (see _walk_to_altar).
const ALTAR_STOP_DISTANCE := 2.5
## Standing at our altar for the intermission.
var at_altar: bool = false
var roll_time: float = 0.0  # Time left in the current roll or backstep
var roll_duration: float = 0.0
var roll_iframes: float = 0.0
var roll_dir: Vector3 = Vector3.ZERO
var is_backstep: bool = false
var _roll_cooldown: float = 0.0

# Slide tackle: dodging while sprinting (or just after letting go of a
# controller's dodge button, since holding it is the sprint) slides in feet first instead of rolling. It has no iframes,
# but anyone it sweeps is knocked down (see _knock_down) unless their raised
# shield takes it or they roll through it; anything else gets kicked.
const SLIDE_DURATION := 0.6
const SLIDE_SPEED := 15.0
const SLIDE_END_SPEED_RATIO := 0.25  # Slows to this share of SLIDE_SPEED by the end
## A dodge this soon (seconds) after sprinting still slides.
const SLIDE_SPRINT_GRACE := 0.4
## The sweep: a ball this big just ahead of our feet.
const SLIDE_REACH := 0.7
const SLIDE_DAMAGE := 5.0
const SLIDE_KNOCKBACK := 6.0
const SLIDE_POP := 2.5
const SLIDE_OBJECT_IMPULSE := 9.0  # Kicks the ball hard
var is_slide: bool = false
## Seconds since we last sprinted.
var _since_sprint: float = 99.0
## Who this slide has already swept.
var _slide_hits: Array[Node3D] = []
var _slide_shape := SphereShape3D.new()

# Knocked down (slide-tackled): flat on our back seeing stars for
# KNOCKDOWN_DURATION, then GETUP_DURATION getting back up. No moving,
# turning, attacking or rolling meanwhile, like a stagger. Just back up,
# we can't be knocked down again for KNOCKDOWN_IMMUNITY.
const KNOCKDOWN_DURATION := 2.0
const GETUP_DURATION := 0.6
const KNOCKDOWN_IMMUNITY := 1.5
## Seconds left lying there and getting up; 0 = on our feet.
var knockdown_time: float = 0.0
var _knockdown_immunity: float = 0.0

# A swing (or punch) hops you forward a little toward the aim. You keep
# full steering and turning while swinging, and a roll cancels any swing.
const SWING_LUNGE_SPEED := 5.0
const FIST_LUNGE_SPEED := 3.5
const LUNGE_FRICTION := 20.0
var lunge: Vector3 = Vector3.ZERO

# Poise (hidden, owner only): the damage we take adds up, and once it
# reaches POISE_MAX we're staggered: no moving, turning, attacking, blocking
# or rolling for a moment, and whatever we were swinging is cut short. It
# comes back POISE_RESET_TIME after the last hit, so it takes a quick
# flurry (a sword hits for 40) or a big hit to break.
const POISE_MAX := 100.0
const POISE_RESET_TIME := 2.0
var _poise_damage: float = 0.0
var _poise_reset: float = 0.0
const STAGGER_DURATION := 0.7
## Hits on a staggered player do this much more damage, so breaking
## someone's poise is a real opening (like the boss's stagger).
const STAGGERED_DAMAGE_MULTIPLIER := 1.5
var stagger_time: float = 0.0

## What the body is doing, for PlayerVisual3D to pick a clip (synced online).
enum Pose { NONE, ROLL, BACKSTEP, STAGGER, SLIDE, KNOCKDOWN, GETUP, FROZEN, ASLEEP }
var anim_pose: int = Pose.NONE

# Kills: the last opponent to hit us gets the kill if we die within
# KILL_CREDIT_TIME of it, even if something else (a boss stomp) finishes
# us off. Dying takes us out of play for a while (Game3D.revive_delay): we
# lie where we fell, then respawn at our team's spawn, or with
# Game3D.knockouts, get back up there.
const KILL_CREDIT_TIME := 4.0
## Killed (not knocked out): how long before getting up we vanish from the
## floor, to move to the spawn point unseen.
const RESPAWN_HIDE_TIME := 0.3
var _last_attacker_name: String = ""
var _last_attacker_msec: int = -1
## Seconds left before respawning; 0 = alive.
var dead_time: float = 0.0
## Wild items' effects still running: perk -> seconds left (see add_timed_perk).
var timed_perks: Dictionary[Perk, float] = {}
## Frozen, burning, asleep, and the wild items' status buffs' looks.
var status: PlayerStatus3D = null
## A hit this hard (after perks and armor) gets the bigger hit effect.
const HARD_HIT_DAMAGE := 25.0
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
	_slide_shape.radius = SLIDE_REACH
	status = PlayerStatus3D.new(self)
	add_child(status)

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
		Input_Handler.dodge_request_msec = -1
	else:
		at_altar = false
	_update_sprint(direction, delta)
	_try_roll(direction)

	if Input_Handler.interact:
		Input_Handler.interact = false
		if not _grab_nearest_ball() and not _pick_up_nearest_weapon():
			_take_from_nearest_stand()
	_update_carry(delta)

	# Walking velocity (sprinting speeds up only the horizontal part)
	var speed: float = Entity.SPEED * perk_stat(&"move_speed")
	var walk: Vector3 = direction * speed
	if is_sprinting:
		walk.x *= SPRINT_SPEED_MULTIPLIER
		walk.z *= SPRINT_SPEED_MULTIPLIER
	if carries_ball():
		walk *= CARRY_SPEED
	# Being shoved takes some control away until the shove dies down
	var control: float = clamp(1.0 - knockback.length() / KNOCKBACK_CONTROL_LOSS, KNOCKBACK_MIN_CONTROL, 1.0)
	if stagger_time > 0.0 or knockdown_time > 0.0 or status.held():
		control = 0.0
	if left_arm.charging or right_arm.charging:
		walk *= CHARGE_MOVE_SPEED
	var move: Vector3 = _roll_velocity() if roll_time > 0.0 else walk * control
	if _dash_time > 0.0:
		_dash_time -= delta
		move = _dash_velocity
	velocity.x = move.x + knockback.x + lunge.x
	velocity.z = move.z + knockback.z + lunge.z

	# Face the aim direction if aiming (works while standing still too),
	# otherwise face the direction we're trying to walk (not the shove).
	# Rolling and staggered players can't turn.
	if is_busy():
		pass
	elif !Input_Handler.look_dir.is_zero_approx() and not perk_locked:
		var look_dir: Vector3 = Input_Handler.look_dir
		var target_angle: float = atan2(look_dir.x, look_dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, ROTATION_SPEED * delta)
	elif !direction.is_zero_approx():
		var target_angle: float = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_angle, ROTATION_SPEED * delta)

	move_and_slide()
	_update_knockback(delta)
	lunge = lunge.move_toward(Vector3.ZERO, LUNGE_FRICTION * delta)
	if is_slide and roll_time > 0.0:
		_check_slide_hits()
	_update_roll(delta)
	_update_poise(delta)
	_update_knockdown(delta)
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
	_update_timed_perks(delta)  # Every machine, alive or not, so they all agree
	if is_dead():
		_update_death(delta)
		if is_remote:
			_process_remote(delta)  # Lying where we fell, but still falling there
		return
	if is_remote:
		_process_remote(delta)
		return
	# Rolling, staggered or picking a perk: the buttons do nothing
	_handle_buttons(is_busy() or is_perk_locked())

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
## one. Our kit doesn't count: anything else we take puts it away.
func is_hand_occupied(is_left: bool) -> bool:
	if is_left and _holds_two_handed() and held_weapon_right.kit_owner != self:
		return true
	var weapon: Weapon3D = arm_of(is_left).weapon
	return weapon != null and weapon.kit_owner != self


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


## Whether `weapon` may go in that hand. Whatever's in the way there is let
## go (see _make_room_for).
func can_hold(weapon: Weapon3D, is_left: bool) -> bool:
	return grip_allows(weapon.grip, is_left)


func can_hold_grip(grip: Weapon3D.Grip, is_left: bool) -> bool:
	return grip_allows(grip, is_left)


## Which hand a weapon held with `grip` goes in (true = left) when we don't
## know what it is yet (an altar's or stand's reward, an item box's): the off
## hand for a shield, else the main hand, in place of what's there.
func free_hand_for(grip: Weapon3D.Grip) -> Variant:
	return grip == Weapon3D.Grip.OFF_HAND


## Which hand a loose `weapon` goes in (true = left): beside a compatible
## weapon we found (see Weapon3D.is_compatible_with), if the other hand's
## free, else in place of what we hold.
func hand_for(weapon: Weapon3D) -> bool:
	if weapon.grip == Weapon3D.Grip.OFF_HAND:
		return true
	if weapon.grip == Weapon3D.Grip.TWO_HANDED:
		return false
	var right: Weapon3D = _found_in(false)
	return right != null and _found_in(true) == null and right.is_compatible_with(weapon)


## The weapon we found (not our kit) in that hand, if any.
func _found_in(is_left: bool) -> Weapon3D:
	var weapon: Weapon3D = arm_of(is_left).weapon
	return weapon if weapon and weapon.kit_owner != self else null


## Whether `weapon` is lying loose for us to take (it still has to be within
## WEAPON_REACH). Anything we hold that doesn't go with it gets let go.
func can_pick_up(weapon: Weapon3D) -> bool:
	return not weapon.wielder and not weapon.is_held and not weapon.is_thrown and not weapon.kit_owner \
		and weapon.can_pickup


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
		nearest.request_equip(self, hand_for(nearest))
	return nearest != null


## Returns whether a stand in reach is giving us its weapon.
func _take_from_nearest_stand() -> bool:
	var nearest: WeaponStand3D = null
	for stand: WeaponStand3D in get_tree().get_nodes_in_group("WeaponStand"):
		if stand.can_give_to(self) and (not nearest \
				or global_position.distance_to(stand.global_position) < global_position.distance_to(nearest.global_position)):
			nearest = stand
	return nearest != null and nearest.request_take(self)


## Put `weapon` in a hand (online, once the server has said we got it), on
## every machine. Anything but our own kit puts the kit away first, and lets
## go of what we found that's in its way.
func equip_weapon(weapon: Weapon3D, is_left: bool) -> void:
	if weapon.kit_owner != self:
		_make_room_for(weapon, is_left)
		_holster_kit()
	arm_of(is_left).weapon = weapon
	weapon.equip(self, _hand_holding(weapon, is_left))
	Sfx.play(weapon.equip_sound(), global_position)


## The hand bone that carries `weapon` when it's that hand's weapon.
func _hand_holding(weapon: Weapon3D, is_left: bool) -> Node3D:
	return visual.hand(is_left or weapon.rides_left_hand)


## Let go of what we found (not our kit) that's in `weapon`'s way going in
## that hand: what's in the same hand, everything for a two-handed weapon,
## and a weapon in the other hand that doesn't go with it. On every machine;
## the one simulating it tosses it aside.
func _make_room_for(weapon: Weapon3D, is_left: bool) -> void:
	for arm: PlayerArm3D in arms:
		var held: Weapon3D = arm.weapon
		if not held or held == weapon or held.kit_owner == self:
			continue
		if arm.is_left == is_left or weapon.grip == Weapon3D.Grip.TWO_HANDED \
				or held.grip == Weapon3D.Grip.TWO_HANDED or not weapon.is_compatible_with(held):
			held.unequip()
			if held.simulates():
				held.linear_velocity = (global_basis.x * (-1.0 if arm.is_left else 1.0) + Vector3.UP) * Weapon3D.DROP_IMPULSE


# ===== KIT =====
# Every character has a signature kit (Roster.kit_of) that's theirs alone and
# never breaks. Picking up anything else puts the whole kit away; once
# nothing else is left in our hands (it broke, was thrown or dropped), the
# kit comes back out. All of it happens on every machine, following the
# weapon events that already reach everyone.

## Every machine, once the player is in the tree: make our kit and take it
## in hand. Named after us, so it lines up online.
func make_kit() -> void:
	var scenes: Array = Roster.kit_of(slot.character if slot else 0)
	for i in scenes.size():
		var scene: PackedScene = scenes[i]
		if not scene:
			continue
		var weapon: Weapon3D = scene.instantiate()
		var weapon_name: String = "%s_Kit%d" % [name, _kits_made]
		_kits_made += 1
		weapon.name = weapon_name
		weapon.kit_owner = self
		Global.Game3D.add_weapon(weapon)
		weapon.name = weapon_name  # Its _ready renames it after its Properties
		weapon.global_position = global_position + Vector3.UP
		if Net.in_session():
			weapon.setup_network()
		kit.append(weapon)
		if holds_found_weapon():
			weapon.holster()  # Out once what we found is gone (see draw_kit)
		else:
			equip_weapon(weapon, _kit_hand_is_left(weapon, i))


## Every machine: become `character` (if our team can play it), with its
## body and its kit; the old kit goes.
func set_character(character: int) -> void:
	if not slot or character == slot.character or not Roster.fits_team(character, slot.team):
		return
	slot.character = character
	for weapon: Weapon3D in kit:
		if not is_instance_valid(weapon):
			continue
		if weapon.wielder == self:
			weapon.unequip()
		weapon.queue_free()
	kit.clear()
	visual.show_character(character)
	make_kit()


## Owner, getting up: take on the character picked while down, everywhere.
func _take_next_character() -> void:
	var character: int = next_character
	next_character = -1
	if character < 0 or not slot or character == slot.character:
		return
	if Net.match_synced:
		_net_set_character.rpc(character)
	set_character(character)


@rpc("any_peer", "reliable")
func _net_set_character(character: int) -> void:
	if multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		set_character(character)


## Whether we hold anything that isn't our kit.
func holds_found_weapon() -> bool:
	for weapon: Weapon3D in [held_weapon_left, held_weapon_right]:
		if weapon and weapon.kit_owner != self:
			return true
	return false


## Which hand kit weapon `index` (0 = main, 1 = off) goes in.
func _kit_hand_is_left(weapon: Weapon3D, index: int) -> bool:
	if weapon.grip == Weapon3D.Grip.TWO_HANDED:
		return false
	return weapon.grip == Weapon3D.Grip.OFF_HAND or index == 1


## Put every kit weapon we hold away, cutting short whatever it was doing.
func _holster_kit() -> void:
	var held: Array[Weapon3D] = []
	for weapon: Weapon3D in [held_weapon_left, held_weapon_right]:
		if weapon and weapon.kit_owner == self:
			held.append(weapon)
	if held.is_empty():
		return
	_cancel_attacks()
	for weapon: Weapon3D in held:
		if weapon is ShieldClass3D:
			weapon.stop_block()
		weapon.holster()


## Our hands hold nothing but the kit: take out whatever of it is put away.
## A kit weapon that's still flying comes back by itself (take_back_kit).
func draw_kit() -> void:
	if not is_inside_tree() or holds_found_weapon():
		return
	for i in kit.size():
		var weapon: Weapon3D = kit[i]
		if not is_instance_valid(weapon) or not weapon.holstered:
			continue
		var is_left: bool = _kit_hand_is_left(weapon, i)
		if arm_of(is_left).weapon or (weapon.grip == Weapon3D.Grip.TWO_HANDED and held_weapon_left):
			continue
		weapon.unholster()
		equip_weapon(weapon, is_left)


## A kit weapon we threw or dropped is back (every machine): into its holster,
## and out again if our hands are free for it.
func take_back_kit(weapon: Weapon3D) -> void:
	weapon.holster()
	draw_kit()


func _exit_tree() -> void:
	for weapon: Weapon3D in kit:
		if is_instance_valid(weapon):
			weapon.queue_free()


# ===== BUTTONS =====
# Light (left click / RB) attacks on press. Heavy (right click / LB)
# charges while held: let go once it's fully charged (the weapon glows) and
# it goes off; any sooner and nothing happens. Throw (Q / Y) charges while
# held and throws the weapon in hand on release. A compatible pair (see
# Weapon3D.is_compatible_with) take turns on light attacks and share a
# heavy. A shield doesn't attack: holding one cuts the damage we take.
# See PlayerInputHandler3D.

var _light := PlayerArm3D.Press.new()
var _heavy := PlayerArm3D.Press.new()
var _throw := PlayerArm3D.Press.new()
## Shoot only does anything while carrying the ball (see shoot_ball).
var _shoot := PlayerArm3D.Press.new()
## Which hand the last light attack used, so a pair take turns.
var _last_light_left: bool = true
## The sparks gathering on a charging heavy's weapon (see _show_charging),
## while they're shown.
var _charge_fx: Node3D = null
## _charge_fx is a held orb (see _show_charging), not the sparks.
var _charge_fx_held: bool = false
## A legendary heavy's blast (see _emit_move) lands this far ahead (m).
const LEGENDARY_BLAST_AHEAD := 1.8
## A held orb let go of, about to fly off as its heavy strikes (see _emit_move).
var _launching_orb: Node3D = null
## How long it waits for that strike before fizzling.
const LAUNCH_WAIT := 0.5
## The sparks start this big (times the blade's length) and grow to full
## over the charge.
const CHARGE_FX_START := 0.35
## Their size, times the blade's length.
const CHARGE_FX_SIZE := 0.6
## Their color on a common weapon (rarer ones take their rarity's).
const CHARGE_FX_COLOR := Color(1.0, 0.85, 0.5)


## Read the buttons and act on them. While `busy` they do nothing, and
## presses made meanwhile don't count once it's over.
func _handle_buttons(busy: bool) -> void:
	_light.held = Input_Handler.light_held
	_heavy.held = Input_Handler.heavy_held
	_throw.held = Input_Handler.throw_held
	_shoot.held = Input_Handler.shoot_held
	for button: PlayerArm3D.Press in [_light, _heavy, _throw, _shoot]:
		if busy:
			button.armed = false
		elif button.just_pressed():
			button.armed = true
			button.press_time = PlayerArm3D.now()
			if button == _throw:
				_throw_for_ball = carries_ball()
	if busy:
		for arm: PlayerArm3D in arms:
			_end_charge(arm)
	else:
		if _light.just_pressed():
			_light_attack()
		_handle_heavy_button()
		_handle_throw_button()
		_handle_shoot_button()
	for button: PlayerArm3D.Press in [_light, _heavy, _throw, _shoot]:
		if button.just_released():
			button.armed = false
		button.was_held = button.held


## Whether that hand holds something to attack with right now.
func _attacks_with(arm: PlayerArm3D) -> bool:
	return arm.weapon != null and not arm.weapon is ShieldClass3D and not arm.weapon.away


## The hand a light attack uses: whichever holds something to attack with
## (a pair take turns, skipping one that's still mid-swing), or an empty one
## to punch with.
func _light_arm() -> PlayerArm3D:
	var ready: Array[PlayerArm3D] = []
	for arm: PlayerArm3D in arms:
		if _attacks_with(arm):
			ready.append(arm)
	if ready.is_empty():
		if not held_weapon_right:
			return right_arm
		return left_arm if not held_weapon_left else null
	if ready.size() == 1:
		return ready[0]
	var next: PlayerArm3D = arm_of(not _last_light_left)
	if next.is_swinging() and not _other_arm(next).is_swinging():
		next = _other_arm(next)
	return next


func _light_attack() -> void:
	var arm: PlayerArm3D = _light_arm()
	if not arm:
		return
	if not arm.weapon:
		_start_punch(arm)
	elif arm.weapon.light_move:
		_start_move(arm, arm.weapon.light_move, false)
	else:
		_swing_weapon(arm)
	_last_light_left = arm.is_left


## A pair's own heavy (see Weapon3D.pair_heavy_move), if that hand's weapon
## has one with what's in the other hand.
func _pair_heavy_of(arm: PlayerArm3D) -> WeaponMove3D:
	var other: Weapon3D = _other_arm(arm).weapon
	if other and arm.weapon.pair_heavy_move and arm.weapon.pairs_with_weapon(other):
		return arm.weapon.pair_heavy_move
	return null


## The heavy that hand's weapon does: its pair's, or its own.
func _heavy_move_of(arm: PlayerArm3D) -> WeaponMove3D:
	if not arm.weapon:
		return null
	var pair: WeaponMove3D = _pair_heavy_of(arm)
	return pair if pair else arm.weapon.heavy_move


## The hand a heavy uses: one with a pair's own heavy, else the main hand
## first.
func _heavy_arm() -> PlayerArm3D:
	var best: PlayerArm3D = null
	for arm: PlayerArm3D in [right_arm, left_arm]:
		if not _attacks_with(arm) or not _heavy_move_of(arm):
			continue
		if _pair_heavy_of(arm):
			return arm
		if not best:
			best = arm
	return best


## The heavy the heavy button would do now, if any (bots read it to know
## how long to hold).
func heavy_move() -> WeaponMove3D:
	var arm: PlayerArm3D = _heavy_arm()
	return _heavy_move_of(arm) if arm else null


func _charging_arm() -> PlayerArm3D:
	for arm: PlayerArm3D in arms:
		if arm.charging:
			return arm
	return null


func _handle_heavy_button() -> void:
	if _heavy.held and _heavy.armed:
		var arm: PlayerArm3D = _charging_arm()
		if not arm:
			arm = _heavy_arm()
		if arm:
			_update_charge(arm, _heavy_move_of(arm))
	elif _heavy.just_released() and _heavy.armed:
		var arm: PlayerArm3D = _charging_arm()
		if not arm:
			return
		var full: bool = arm.charged
		_end_charge(arm)
		if full and _attacks_with(arm):
			_start_move(arm, _heavy_move_of(arm), true)


## Wind back for the heavy once the arm's free, fully charged after its
## charge_time. Its weapon going (thrown, broken) stops it.
func _update_charge(arm: PlayerArm3D, heavy: WeaponMove3D) -> void:
	if not heavy or not _attacks_with(arm):
		_end_charge(arm)
		return
	if not arm.charging:
		if arm.is_swinging() or _combo.is_running():
			return  # Starts once the arm's free
		var fallback: StringName = arm.weapon.offhand_swing_clip if arm.is_left else arm.weapon.swing_clip
		arm.begin_charge(heavy.charge_clip(fallback))
		_show_charging(true, arm.is_left)
		if Net.match_synced:
			_net_charging.rpc(true, arm.is_left)
	arm.charge = clampf((PlayerArm3D.now() - arm.charge_start) / maxf(heavy.charge_time, 0.01), 0.0, 1.0)
	if arm.charge >= 1.0 and not arm.charged:
		arm.charged = true
		_show_charged(arm.is_left, true)
		if Net.match_synced:
			_net_charged.rpc(arm.is_left, true)


## Stop charging (let go, or interrupted). `cut_short`: a held orb fizzles
## even if it was ready to fly.
func _end_charge(arm: PlayerArm3D, cut_short: bool = false) -> void:
	if not arm.charging:
		return
	if arm.charged:
		_show_charged(arm.is_left, false)
		if Net.match_synced:
			_net_charged.rpc(arm.is_left, false)
	# Let go early: the swirl stops (once charged it finishes its burst). A
	# held orb always goes: it's flying off as its wave, or fizzling.
	var cut: bool = cut_short or not arm.charged
	_show_charging(false, arm.is_left, cut)
	if Net.match_synced:
		_net_charging.rpc(false, arm.is_left, cut)
	arm.end_charge()


## On every machine: that arm's weapon glows while its heavy is ready.
func _show_charged(is_left: bool, on: bool) -> void:
	var weapon: Weapon3D = arm_of(is_left).weapon
	if not weapon:
		return
	weapon.set_charged(on)
	if on:
		Sfx.play(&"altar_tier", weapon.global_position)


@rpc("any_peer", "reliable")
func _net_charged(is_left: bool, on: bool) -> void:
	if multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_show_charged(is_left, on)


## On every machine: sparks gather on that hand's weapon while its heavy
## charges, growing till it's ready (see Weapon3D.charge_anchor); or, for a
## heavy that holds its orb (see AttackWaveSpec3D.held_while_charging), the
## orb grows in front of us instead, to fly off as it strikes. Stopping
## lets the sparks fade out; a held orb not `cut` waits to be launched.
func _show_charging(on: bool, is_left: bool, cut: bool = true) -> void:
	if is_instance_valid(_charge_fx) and _charge_fx_held and not on and not cut:
		_launching_orb = _charge_fx
		var orb: Node3D = _charge_fx
		var holder: int = get_instance_id()
		orb.create_tween().tween_callback(func() -> void:
			if orb.get_parent() and orb.get_parent().get_instance_id() == holder:
				orb.queue_free()).set_delay(LAUNCH_WAIT)
	elif is_instance_valid(_charge_fx) and _charge_fx_held:
		_charge_fx.queue_free()
	elif is_instance_valid(_charge_fx):
		Vfx.release(_charge_fx)
	_charge_fx = null
	_charge_fx_held = false
	if not on:
		return
	var heavy: WeaponMove3D = _heavy_move_of(arm_of(is_left))
	if not heavy:
		return
	var weapon: Weapon3D = arm_of(is_left).weapon
	var held: AttackWaveSpec3D = heavy.held_wave()
	if held:
		_charge_fx = AttackWave3D.hold_orb(held, self, heavy.charge_time, weapon.tint(held.color))
		_charge_fx_held = true
	else:
		var tint: Color = WeaponRarity.effect_color(weapon.rarity)
		var size: float = weapon.blade_length() * CHARGE_FX_SIZE
		_charge_fx = Vfx.attach(&"charging", weapon.charge_anchor(), Vector3.ZERO, 0.0, size,
			tint if tint.a > 0.0 else CHARGE_FX_COLOR)
		if _charge_fx:
			var full: Vector3 = _charge_fx.scale
			_charge_fx.scale = full * CHARGE_FX_START
			_charge_fx.create_tween().tween_property(_charge_fx, ^"scale", full, heavy.charge_time)


@rpc("any_peer", "reliable")
func _net_charging(on: bool, is_left: bool, cut: bool = true) -> void:
	if multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_show_charging(on, is_left, cut)


## Let go of Throw: throw the weapon in hand, harder the longer it was held
## (up to THROW_CHARGE_MAX_DURATION).
func _handle_throw_button() -> void:
	if not _throw.just_released() or not _throw.armed:
		return
	if carries_ball():
		throw_ball(_pay_throw_charge(_throw.held_for()))
		return
	if _throw_for_ball:
		return
	var arm: PlayerArm3D = _throw_arm()
	if arm:
		_throw_weapon(arm, _pay_throw_charge(_throw.held_for()))


## Let go of Shoot while carrying: shoot the ball at the goal, further the
## longer it was held. Pressed without the ball it does nothing.
func _handle_shoot_button() -> void:
	if _shoot.just_released() and _shoot.armed and carries_ball():
		shoot_ball(_pay_throw_charge(_shoot.held_for()))


## The hand Throw throws from: the main hand first. A weapon off flying
## (see WeaponPhantom3D) can't be thrown.
func _throw_arm() -> PlayerArm3D:
	for arm: PlayerArm3D in [right_arm, left_arm]:
		if arm.weapon and not arm.weapon.away:
			return arm
	return null


# ===== CARRYING =====

## Whether we have the ball in hand (and haven't let it go yet).
func carries_ball() -> bool:
	return is_instance_valid(held_ball) and held_ball.holder == self and not _ball_thrown


## Where a carried ball rides: out in front of the chest.
func carry_point() -> Vector3:
	return global_position + global_basis.z * 0.8 + Vector3.UP * 0.4


## Whether we could pick `ball` up now.
func can_grab_ball(ball: Ball3D, reach: float = BALL_REACH) -> bool:
	return not ball.holder and not is_dead() and not is_busy() and not is_instance_valid(held_ball) \
		and carry >= CARRY_MIN_TO_GRAB and global_position.distance_to(ball.global_position) <= reach


## Interact: pick up the nearest ball in reach. Returns whether we are (or,
## online, have asked to).
func _grab_nearest_ball() -> bool:
	if not Global.Game3D:
		return false
	var nearest: Ball3D = null
	for ball: Ball3D in Global.Game3D.balls:
		if is_instance_valid(ball) and ball.is_inside_tree() and can_grab_ball(ball) and (not nearest \
				or global_position.distance_to(ball.global_position) < global_position.distance_to(nearest.global_position)):
			nearest = ball
	if nearest:
		nearest.request_grab(self)
	return nearest != null


## Every machine (see Ball3D.grab).
func on_ball_grabbed(ball: Ball3D) -> void:
	held_ball = ball
	_ball_thrown = false


## Every machine (see Ball3D.release).
func on_ball_released(ball: Ball3D) -> void:
	if held_ball == ball:
		held_ball = null
	_ball_thrown = false


## Throw the ball along our aim, harder with more `charge` (0-1).
func throw_ball(charge: float) -> void:
	if not carries_ball():
		return
	var dir: Vector3 = _get_aim_direction()
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else global_basis.z
	var speed: float = BALL_THROW_SPEED * _throw_force_ratio(charge) * perk_stat(&"throw_power")
	_launch_ball((dir + Vector3.UP * BALL_THROW_LIFT).normalized() * speed)
	right_arm.play_throw_release()


## Shoot the ball, further with more `charge` (0-1): at what we're locked
## on to (a pass to a teammate, an attack on anyone else), or else at the
## goal we attack (a skull: at our altar), or else along our aim.
func shoot_ball(charge: float) -> void:
	if not carries_ball():
		return
	var speed: float = BALL_SHOT_SPEED * _throw_force_ratio(charge) * perk_stat(&"throw_power")
	var lift: float = BALL_SHOT_LIFT
	var shot: Ball3D.Shot = Ball3D.Shot.NONE
	var damage: float = 0.0
	var lock: Node3D = Input_Handler.lock_target
	var target: Node3D = null
	if is_instance_valid(lock):
		target = lock
		if Combat.are_teammates(lock, self):
			shot = Ball3D.Shot.PASS
			speed = max(speed, BALL_PASS_MIN_SPEED)
			lift = BALL_PASS_LIFT
		else:
			shot = Ball3D.Shot.ATTACK
			damage = lerp(BALL_ATTACK_DAMAGE_MIN, BALL_ATTACK_DAMAGE_MAX, charge)
	elif Global.Game3D:
		target = Global.Game3D.shot_target(self, held_ball)
	var dir: Vector3 = _get_aim_direction()
	if target:
		dir = target.global_position - global_position
		if shot != Ball3D.Shot.NONE and target is CharacterBody3D:
			dir += (target as CharacterBody3D).velocity * dir.length() / speed  # Lead them
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else global_basis.z
	_launch_ball((dir + Vector3.UP * lift).normalized() * speed, shot, damage)
	right_arm.play_throw_release()


func _launch_ball(launch: Vector3, shot: Ball3D.Shot = Ball3D.Shot.NONE, damage: float = 0.0) -> void:
	held_ball.touched_by(self)
	held_ball.request_throw(self, launch, shot, damage)
	_ball_thrown = true


## Owner: a hit knocks the ball loose, along `dir`.
func _fumble_ball(dir: Vector3) -> void:
	if not carries_ball():
		return
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else global_basis.z
	_launch_ball(dir * BALL_FUMBLE_SPEED + Vector3.UP * 3.0)


## Owner: drain the meter while carrying (tossing the ball forward once it's
## empty, or when we're knocked about), refill it otherwise.
func _update_carry(delta: float) -> void:
	if not is_instance_valid(held_ball):
		held_ball = null
	if carries_ball():
		carry -= CARRY_DRAIN_PER_SEC * delta
		if carry <= 0.0 or is_busy():
			_launch_ball(global_basis.z * BALL_TOSS_SPEED + Vector3.UP * 2.0)
	elif not held_ball:
		carry += CARRY_REGEN_PER_SEC * delta


# ===== SWINGS =====

## Swing (or fire) the arm's weapon, if that arm is free; false if it
## couldn't. A heavy weapon draws back first (see
## PlayerArm3D.begin_draw).
func _swing_weapon(arm: PlayerArm3D) -> bool:
	var weapon: Weapon3D = arm.weapon
	if arm.is_swinging() or weapon.away:
		return false  # Mid-swing already, or off flying
	arm.move = null
	var draw_time: float = weapon.Properties.swing_windup if weapon.Properties else 0.0
	if draw_time > 0.0 and weapon.plays_swipe_animation:
		arm.begin_draw(weapon, draw_time)
	else:
		strike(arm)
	return true


## The arm's weapon attacks now: a melee one swings (live for its
## swing_duration) with a step forward, a ranged one just fires. `step` is
## the combo beat it's part of, if any. Returns the swing's length.
## Part of a light or heavy attack (the arm's move, see WeaponMove3D), it
## also sends out the move's waves and does its action.
func strike(arm: PlayerArm3D, step: WeaponComboStep3D = null) -> float:
	var weapon: Weapon3D = arm.weapon
	var move: WeaponMove3D = arm.move
	var club: bool = step != null and step.melee  # A ranged weapon swung, not fired
	var swings: bool = move == null or move.swings
	if not club and swings:
		weapon.attack(_get_aim_direction())
	if not weapon.plays_swipe_animation and not club:
		arm.shot_time = PlayerArm3D.SHOT_ANIM_DURATION
		if move:
			_strike_move(arm, move)
		return PlayerArm3D.SHOT_ANIM_DURATION
	var duration: float = weapon.Properties.swing_duration if weapon.Properties else PlayerArm3D.SWIPE_DURATION
	# Already wound back: by a draw-back, or a heavy's charge
	var drawn: bool = (step == null and weapon.Properties != null and weapon.Properties.swing_windup > 0.0) \
		or (move != null and arm.move_heavy)
	var spin: bool = step != null and step.spin_turns != 0.0
	if step:
		duration *= step.duration_scale
	if move:
		duration *= move.duration_scale
	arm.begin_swing(duration, 1.0 if drawn else PlayerArm3D.QUICK_SWING_PHASE)
	if step:
		arm.swing_clip = step.off_clip if arm.is_left else step.main_clip
		arm.swing_spin = spin
	elif move and move.clip != &"":
		arm.swing_clip = move.clip
	var window: float = duration * CHOP_DOWNSTROKE if _chops(arm) and not spin else duration
	if swings:
		weapon.start_swing(window, step.damage_scale if step else 1.0)
	var lunge_scale: float = (step.lunge_scale if step else 1.0) * (move.lunge_scale if move else 1.0)
	if lunge_scale > 0.0:
		_lunge(SWING_LUNGE_SPEED * lunge_scale)
	if move:
		_strike_move(arm, move)
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
	_shake_view(CameraShake.LIGHT if solid else CameraShake.TINY)


## Either arm is mid-swing (weapon or fist), drawing one back, or
## playing out a special.
func is_swinging() -> bool:
	return left_arm.is_swinging() or right_arm.is_swinging() or _combo.is_running()


## That arm is mid-swing or drawing one back.
func is_arm_swinging(is_left: bool) -> bool:
	return arm_of(is_left).is_swinging()


## Stop any punch or weapon swing from hitting anything more.
func _cancel_attacks() -> void:
	_combo.cancel()
	_dash_time = 0.0
	for arm: PlayerArm3D in arms:
		arm.cancel()


## Hop toward the aim at `speed`.
func _lunge(speed: float) -> void:
	var dir: Vector3 = _get_aim_direction()
	dir.y = 0.0
	if dir.is_zero_approx():
		return
	lunge = dir.normalized() * speed


# ===== LIGHT & HEAVY ATTACKS =====
# See WeaponMove3D. A move swings like any attack (or plays its combo's
# beats), and each strike sends out its waves (AttackWave3D) and does its
# action. The waves and the action are real on this machine and shown on
# everyone else's (see _net_strike_move).

## Start `move` (a light attack, or a fully charged heavy if `heavy`) with
## `arm`'s weapon, if the arm's free. A light attack
## draws back first like a plain swing (see _swing_weapon); a heavy's charge
## already has.
func _start_move(arm: PlayerArm3D, move: WeaponMove3D, heavy: bool) -> bool:
	var weapon: Weapon3D = arm.weapon
	if arm.is_swinging() or _combo.is_running() or weapon.away:
		return false
	weapon.begin_action()
	arm.move = move
	arm.move_heavy = heavy
	if move.combo and not move.combo.steps.is_empty():
		_other_arm(arm).move = null
		_combo.start(move.combo, arm.is_left)
		return true
	var draw_time: float = weapon.Properties.swing_windup if weapon.Properties else 0.0
	if not heavy and draw_time > 0.0 and weapon.plays_swipe_animation:
		arm.begin_draw(weapon, draw_time)
	else:
		strike(arm)
	return true


## A move's strike: its waves and action, for real here and for show on
## everyone else's machine.
func _strike_move(arm: PlayerArm3D, move: WeaponMove3D) -> void:
	var dir: Vector3 = _get_aim_direction()
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else global_basis.z
	_emit_move(arm.weapon, move, dir, true, arm.move_heavy)
	if Net.match_synced:
		_net_strike_move.rpc(arm.is_left, arm.move_heavy, dir)


@rpc("any_peer", "reliable")
func _net_strike_move(is_left: bool, heavy: bool, dir: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	var weapon: Weapon3D = arm_of(is_left).weapon
	var move: WeaponMove3D = (_heavy_move_of(arm_of(is_left)) if heavy else weapon.light_move) if weapon else null
	if move:
		_emit_move(weapon, move, dir, false, heavy)


## `move`'s waves and action from `weapon` along `dir`: `real` ones hit
## things, the rest are for show. A rarer weapon's effects take its
## rarity's color, and a legendary's `heavy` lands with a blast of fire.
func _emit_move(weapon: Weapon3D, move: WeaponMove3D, dir: Vector3, real: bool, heavy: bool) -> void:
	var hits: Array[Node] = weapon.hits_this_action()
	var held: Node3D = null
	if is_instance_valid(_launching_orb) and _launching_orb.get_parent() == self:
		held = _launching_orb
	_launching_orb = null
	for spec: AttackWaveSpec3D in move.waves:
		AttackWave3D.emit(spec, self, weapon, dir, real, hits, 1.0, held if spec.held_while_charging else null)
	if move.sound != &"":
		Sfx.play(move.sound, global_position)
	if move.shake > 0.0:
		CameraShake.add(move.shake, global_position)
	var tint: Color = WeaponRarity.effect_color(weapon.rarity)
	if move.vfx != &"":
		Vfx.play(move.vfx, global_position, dir, weapon == held_weapon_left, 1.0, tint)
	if heavy and weapon.rarity >= WeaponRarity.Tier.LEGENDARY:
		var ahead: Vector3 = global_position + dir * LEGENDARY_BLAST_AHEAD
		Vfx.play(&"impact", ahead + Vector3.DOWN * 0.9, dir, false, 1.2, tint)
		Vfx.play(&"fire_cast", global_position, dir, false, 1.0, tint)
	match move.action:
		WeaponMove3D.Action.BOOMERANG:
			WeaponPhantom3D.launch(move, weapon, self, dir, real)
		WeaponMove3D.Action.ORBIT:
			WeaponPhantom3D.launch(move, weapon, self, dir, real, 1.0)
			# A pair of them go round opposite ways
			var other: Weapon3D = held_weapon_left if weapon == held_weapon_right else held_weapon_right
			if other and not other.away and other.heavy_move \
					and other.heavy_move.action == WeaponMove3D.Action.ORBIT:
				other.begin_action()
				WeaponPhantom3D.launch(other.heavy_move, other, self, dir, real, -1.0)
		WeaponMove3D.Action.DASH:
			if real:
				_dash_velocity = dir * move.dash_speed
				_dash_time = move.dash_time
		WeaponMove3D.Action.SHOT:
			if real and weapon is CrossbowClass3D:
				(weapon as CrossbowClass3D).fire_heavy(dir, move)


# ===== THROWING =====

## A throw charged for `seconds` (0-1, full at THROW_CHARGE_MAX_DURATION).
func _pay_throw_charge(seconds: float) -> float:
	return clamp(seconds / THROW_CHARGE_MAX_DURATION, 0.0, 1.0)


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
	if not Input_Handler.look_dir.is_zero_approx():
		return Input_Handler.look_dir
	return Vector3(sin(rotation.y), 0, cos(rotation.y))


## Winds the throwing arm back while Throw (or Shoot, with the ball) is held.
func _update_weapon_windups(delta: float) -> void:
	var throwing: PlayerArm3D = null
	var press: PlayerArm3D.Press = _throw
	if _throw.held and _throw.armed:
		throwing = right_arm if carries_ball() else _throw_arm()
	elif _shoot.held and _shoot.armed and carries_ball():
		throwing = right_arm
		press = _shoot
	for arm: PlayerArm3D in arms:
		arm.update_windup(delta, arm == throwing, press.press_time, arm.weapon != null or arm == throwing, THROW_CHARGE_MAX_DURATION)


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
	if arm.is_swinging():
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
		_shake_view(CameraShake.LIGHT if solid else CameraShake.TINY)


# ===== HITS & DEATH =====

## Called by Combat.strike for every attack that lands on this player.
## `dir` is the direction the attack travels. Returns false if blocked.
## `attacker` is the player behind it, if any (they may get the kill).
## `knock_down` (a slide tackle) also knocks us down if it gets through.
## Online the hit is decided on this player's owner, so a remote copy just
## passes it on (and can't know yet whether it was blocked).
func receive_hit(dir: Vector3, damage: float, knockback_velocity: Vector3, attacker: Node3D = null, knock_down: bool = false) -> bool:
	if is_dead():
		return false
	if not _is_local():
		if Net.match_synced:
			var attacker_name: String = String(attacker.name) if attacker is PlayerClass3D else ""
			_net_receive_hit.rpc_id(get_multiplayer_authority(), dir, damage, knockback_velocity, attacker_name, knock_down)
		return true
	if roll_iframes > 0.0:
		return false  # Rolled through it
	if attacker is PlayerClass3D and attacker != self:
		blame(attacker)
	damage *= perk_stat(&"damage_taken")
	if armored:
		damage *= ARMOR_DAMAGE_TAKEN
	if stagger_time > 0.0:
		damage *= STAGGERED_DAMAGE_MULTIPLIER
	var knockback_taken: float = perk_stat(&"knockback_taken")
	knockback_velocity.x *= knockback_taken
	knockback_velocity.z *= knockback_taken
	var shield: ShieldClass3D = _held_shield()
	if shield:
		damage *= shield.damage_taken
		knockback_velocity.x *= shield.knockback_taken
		knockback_velocity.z *= shield.knockback_taken
	var was_in_iframes: bool = Entity.is_in_iframes
	if shield and not was_in_iframes:
		Sfx.play_everywhere(&"block", shield.global_position)
		shield.wear()  # Each hit it softens is a use
	Entity.take_hit(damage, knockback_velocity)
	_share_iframes(was_in_iframes)
	if not was_in_iframes:
		var look: StringName = &"block" if shield else (&"hit_hard" if damage >= HARD_HIT_DAMAGE else &"hit")
		Vfx.play_everywhere(look, global_position, dir)
		status.on_hit()
		if attacker is PlayerClass3D and attacker != self:
			if attacker.status.has_buff(&"frost_touch"):
				status.apply(PlayerStatus3D.Kind.FROZEN, PlayerStatus3D.FREEZE_TIME, attacker)
			if attacker.status.has_buff(&"ablaze"):
				status.apply(PlayerStatus3D.Kind.BURNING, PlayerStatus3D.BURN_TIME, attacker)
		_fumble_ball(dir)
		hitstop = Combat.HITSTOP
		_shake_view(CameraShake.MEDIUM)
		_wear_poise(damage)
	if Entity.hp <= 0:
		_on_lethal_hit()
	elif knock_down:
		_knock_down()
	return true


## Owner: `attacker` gets the kill if we die soon (see KILL_CREDIT_TIME).
func blame(attacker: PlayerClass3D) -> void:
	_last_attacker_name = attacker.name
	_last_attacker_msec = Time.get_ticks_msec()


## Owner: lose `amount` HP to a status (burning): no shove, no flinch.
func hurt(amount: float) -> void:
	if is_dead():
		return
	Entity.hp -= amount * perk_stat(&"damage_taken")
	if Entity.hp <= 0:
		_on_lethal_hit()


## Owner: gain `amount` HP, up to max.
func heal(amount: float) -> void:
	if not is_dead():
		Entity.hp = minf(Entity.hp + amount, Entity.hp_max)


## Owner: frozen or put to sleep, so whatever we were doing stops.
func stop_in_place() -> void:
	roll_time = 0.0
	roll_iframes = 0.0
	lunge = Vector3.ZERO
	_dash_time = 0.0
	_cancel_attacks()


## Owner: woken up, so we get up off the floor.
func get_up() -> void:
	knockdown_time = GETUP_DURATION


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


## Killed: we collapse where we stand and lie there until the revive delay
## runs out, then get up at our team's spawn (or, with Game3D.knockouts,
## right where we lay). The owner calls this the moment it happens and
## every machine again when Game3D announces the death, so a second call
## does nothing.
func die() -> void:
	if is_dead():
		return
	armored = false  # Comes back without it
	deaths += 1
	_shake_view(CameraShake.HEAVY)
	var delay: float = Global.Game3D.revive_delay(self, deaths) if Global.Game3D else 0.0
	var knocked_out: bool = Global.Game3D and Global.Game3D.knockouts and delay > 0.0
	if _is_local() and not knocked_out:
		# Our weapons stay where we fell, for anyone to take (not our kit)
		for weapon: Weapon3D in [held_weapon_left, held_weapon_right]:
			if weapon and weapon.kit_owner != self:
				weapon.drop()
	if delay <= 0.0:
		if _is_local():
			respawn()
		return
	_go_down(delay, knocked_out)


func _update_death(delta: float) -> void:
	dead_time = max(dead_time - delta, 0.0)
	if not is_knocked_out and visible and dead_time <= RESPAWN_HIDE_TIME:
		# Vanish just before getting up, so the move to the spawn point
		# (snapped to on remote copies too) happens out of sight
		visible = false
		if _is_local():
			_take_next_character()
			respawn()
	if dead_time > 0.0:
		return
	collision_layer = _alive_collision_layer
	visible = true
	if is_knocked_out:
		is_knocked_out = false
		if _is_local():
			_take_next_character()
			_revive_in_place()
	visual.play_spawn()
	Entity.start_iframes()  # A moment of spawn protection


## Down for `delay` seconds: we drop where we stand and stay there, where
## enemies can't hit us and others walk through us. Knocked out, we keep
## our weapons and get back up on this spot. Like die(), on every machine.
func _go_down(delay: float, knocked_out: bool) -> void:
	is_knocked_out = knocked_out
	dead_time = delay
	_last_attacker_name = ""
	_last_attacker_msec = -1
	# A heavy being charged goes with its glow and sparks (here, and on remote
	# copies whether or not the owner's word has reached them yet)
	for arm: PlayerArm3D in arms:
		_end_charge(arm, true)
		if arm.weapon:
			arm.weapon.set_charged(false)
	_show_charging(false, false)
	_cancel_attacks()
	# Arms at rest (not frozen mid-charge or mid-swing), so the body lies flat
	arm_anim = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, -1.0, -1.0, 0.0])
	for button: PlayerArm3D.Press in [_light, _heavy, _throw, _shoot]:
		button.armed = false
	knockback = Vector3.ZERO
	lunge = Vector3.ZERO
	_dash_time = 0.0
	roll_time = 0.0
	roll_iframes = 0.0
	_roll_cooldown = 0.0
	stagger_time = 0.0
	_poise_damage = 0.0
	knockdown_time = 0.0
	_alive_collision_layer = collision_layer
	collision_layer = 0
	visual.play_down()


## Owner, while down: just fall to the floor (a stomp may have
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
		# On the visual (whose origin is at our feet), so it grows and
		# shrinks with the body (see the "size" perk stat)
		_crown.position = Vector3(0, 2.4, 0)
		visual.add_child(_crown)
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
	_dash_time = 0.0
	roll_time = 0.0
	roll_iframes = 0.0
	_roll_cooldown = 0.0
	stagger_time = 0.0
	_poise_damage = 0.0
	knockdown_time = 0.0
	Entity.reset(true)  # Full stats, and moves us to Entity.spawn_pos
	carry = CARRY_MAX
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

## Rolling, sliding, staggered or knocked down: no attacking, turning or
## rolling again.
func is_busy() -> bool:
	return roll_time > 0.0 or stagger_time > 0.0 or knockdown_time > 0.0 or status.held()


## The intermission (walking back to our altar and picking there), a
## draft, or choosing a perk mid-round: movement and hands are out of our
## control.
func is_perk_locked() -> bool:
	var game: Game3D_Class = Global.Game3D
	if not game:
		return false
	return game.phase == Game3D_Class.Phase.INTERMISSION or game.perks.in_draft or game.perks.is_picking(self)


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


## Roll (or slide, fresh from a sprint) if the dodge button was tapped
## recently and we're free to.
func _try_roll(direction: Vector3) -> void:
	var request: int = Input_Handler.dodge_request_msec
	if request < 0:
		return
	if Time.get_ticks_msec() - request > ROLL_BUFFER_MSEC:
		Input_Handler.dodge_request_msec = -1
		return
	if is_busy() or not is_on_floor() or _roll_cooldown > 0.0:
		return  # Keep it buffered
	_roll_cooldown = ROLL_COOLDOWN
	is_slide = not direction.is_zero_approx() and _since_sprint <= SLIDE_SPRINT_GRACE
	is_backstep = direction.is_zero_approx()
	Input_Handler.dodge_request_msec = -1
	_cancel_attacks()
	lunge = Vector3.ZERO
	_dash_time = 0.0
	if is_slide:
		roll_dir = direction
		roll_duration = SLIDE_DURATION
		roll_iframes = 0.0
		rotation.y = atan2(direction.x, direction.z)
		_slide_hits.clear()
	elif is_backstep:
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
	if is_slide:
		return roll_dir * SLIDE_SPEED * lerp(1.0, SLIDE_END_SPEED_RATIO, t) * perk_stat(&"move_speed")
	var speed: float = ROLL_SPEED * lerp(1.0, ROLL_END_SPEED_RATIO, t * t) * perk_stat(&"move_speed")
	return roll_dir * speed


func _update_roll(delta: float) -> void:
	roll_time = max(roll_time - delta, 0.0)
	roll_iframes = max(roll_iframes - delta, 0.0)
	_roll_cooldown = max(_roll_cooldown - delta, 0.0)


## Mid-slide: sweep whatever's just ahead of our feet, once each. Players
## (not teammates) are knocked down; anything else is kicked.
func _check_slide_hits() -> void:
	var exclude: Array[RID] = [get_rid()]
	for arm: PlayerArm3D in arms:
		if arm.weapon:
			exclude.append(arm.weapon.get_rid())
	# Our origin is about 1m up, so this is around the shins
	var at: Vector3 = global_position + roll_dir * SLIDE_REACH + Vector3.DOWN * 0.5
	for body: Node3D in Combat.overlaps(get_world_3d(), _slide_shape, Transform3D(Basis(), at), exclude):
		if body in _slide_hits:
			continue
		_slide_hits.append(body)
		if Combat.strike(body, roll_dir, SLIDE_DAMAGE, SLIDE_KNOCKBACK, SLIDE_POP, SLIDE_OBJECT_IMPULSE, self, true):
			_shake_view(CameraShake.LIGHT)


## Slide-tackled (owner only, see receive_hit): down we go, unless we're
## already down or only just got back up.
func _knock_down() -> void:
	if knockdown_time > 0.0 or _knockdown_immunity > 0.0 or is_dead():
		return
	knockdown_time = KNOCKDOWN_DURATION + GETUP_DURATION
	roll_time = 0.0
	roll_iframes = 0.0
	stagger_time = 0.0
	lunge = Vector3.ZERO
	_dash_time = 0.0
	_cancel_attacks()
	_shake_view(CameraShake.MEDIUM)


func _update_knockdown(delta: float) -> void:
	if knockdown_time > 0.0:
		knockdown_time = max(knockdown_time - delta, 0.0)
		if knockdown_time <= 0.0:
			_knockdown_immunity = KNOCKDOWN_IMMUNITY
	else:
		_knockdown_immunity = max(_knockdown_immunity - delta, 0.0)


## A hit got through for `damage`: wear down poise, staggering us once
## it's broken. Hits on someone already reeling don't count toward the next.
func _wear_poise(damage: float) -> void:
	if stagger_time > 0.0:
		return
	_poise_damage += damage
	_poise_reset = POISE_RESET_TIME
	if _poise_damage >= POISE_MAX:
		_poise_damage = 0.0
		_stagger()


## Poise broken: stagger, cutting short any roll or swing.
func _stagger() -> void:
	stagger_time = STAGGER_DURATION
	roll_time = 0.0
	roll_iframes = 0.0
	_cancel_attacks()


func _update_poise(delta: float) -> void:
	stagger_time = max(stagger_time - delta, 0.0)
	if _poise_reset > 0.0:
		_poise_reset -= delta
		if _poise_reset <= 0.0:
			_poise_damage = 0.0


## Rolling, backstepping, sliding, knocked down or staggered (each has its
## own clip).
func _update_body_pose() -> void:
	if roll_time > 0.0:
		if is_slide:
			anim_pose = Pose.SLIDE
		else:
			anim_pose = Pose.BACKSTEP if is_backstep else Pose.ROLL
	elif knockdown_time > 0.0:
		anim_pose = Pose.GETUP if knockdown_time <= GETUP_DURATION else Pose.KNOCKDOWN
	elif status.is_frozen():
		anim_pose = Pose.FROZEN
	elif status.is_asleep():
		anim_pose = Pose.ASLEEP
	elif stagger_time > 0.0:
		anim_pose = Pose.STAGGER
	else:
		anim_pose = Pose.NONE


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


# ===== SPRINT =====

func _update_sprint(direction: Vector3, delta: float) -> void:
	is_sprinting = Input_Handler.move_dodge and not direction.is_zero_approx() \
		and not is_busy() and not is_perk_locked()
	_since_sprint = 0.0 if is_sprinting else _since_sprint + delta


# ===== PERKS =====

## This player's multiplier for a perk stat (see PerkSet.STATS).
func perk_stat(stat_name: StringName) -> float:
	return perks.stat(stat_name)


## Take a perk. Max HP grows at once, keeping how full they were.
## Call on every machine.
func add_perk(perk: Perk) -> void:
	perks.add(perk)
	_on_perks_changed()


## A wild item's effect (see WildItem): `perk` for `seconds`, on every
## machine. Getting the same one again while it lasts starts its clock over.
func add_timed_perk(perk: Perk, seconds: float) -> void:
	if not timed_perks.has(perk):
		perks.add(perk)
		_on_perks_changed()
	timed_perks[perk] = seconds


func _update_timed_perks(delta: float) -> void:
	if timed_perks.is_empty():
		return
	for perk: Perk in timed_perks.keys():
		timed_perks[perk] -= delta
		if timed_perks[perk] <= 0.0:
			timed_perks.erase(perk)
			perks.remove(perk)
			_on_perks_changed()


func _on_perks_changed() -> void:
	Entity.refresh_max_stats()
	var size: float = perk_stat(&"size")
	var tween: Tween = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(visual, ^"scale", Vector3.ONE * size, 0.6)


# ===== NETWORK =====

## Whether this machine controls this player (always, offline).
func _is_local() -> bool:
	return not Net.in_session() or is_multiplayer_authority()


## A person playing on this machine (not a bot, not someone online).
func is_local_person() -> bool:
	return _is_local() and not (slot and slot.is_bot)


## Shake the camera (see CameraShake) for something that happened to us,
## if we're a person playing on this machine (bots don't shake the view).
func _shake_view(amount: float) -> void:
	if is_local_person():
		CameraShake.add(amount)


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
func _net_receive_hit(dir: Vector3, damage: float, knockback_velocity: Vector3, attacker_name: String, knock_down: bool) -> void:
	if is_multiplayer_authority():
		var attacker: PlayerClass3D = Global.Game3D.player_named(attacker_name) if Global.Game3D else null
		receive_hit(dir, damage, knockback_velocity, attacker, knock_down)


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


## A shield we're holding (see ShieldClass3D.damage_taken), if any.
func _held_shield() -> ShieldClass3D:
	for weapon: Weapon3D in [held_weapon_left, held_weapon_right]:
		if weapon is ShieldClass3D:
			return weapon
	return null
