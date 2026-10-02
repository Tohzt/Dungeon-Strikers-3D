class_name Weapon3D extends RigidBody3D
## Online, one machine simulates each weapon and streams its pose to the
## rest, which just follow along. Loose weapons start with the server; the
## server hands a weapon to whoever it lets pick it up, and that player's
## machine keeps simulating it (held, thrown, lying where it landed) until
## someone else picks it up. Only the simulating machine checks its hits.

@export var Properties: WeaponProperties3D
@export var Behavior: WeaponBehavior3D
@onready var Collision := $CollisionShape3D

## Whether a quick tap plays the shoulder-swipe swing animation. Melee
## weapons want the swing; a weapon that just fires in place (like the
## crossbow) turns this off.
@export var plays_swipe_animation: bool = true

var wielder: Node3D = null
var held_hand: Area3D = null
var is_held: bool = false
var is_thrown: bool = false

var can_pickup: bool = true
var can_pickup_cd: float = 0.0
var can_pickup_dur_in_sec: float = 1.0

var throw_spin_direction: float = 1.0

# Durability: each use (a swing or throw that hits a player, boss or
# minion, a block, a shot) wears it by one; at 0 it breaks. How many uses it gets
# depends on its rarity. Worn down to WORN_RATIO it pulses red. Online the
# machine simulating it wears it and tells everyone the new value.
const WORN_RATIO := 0.25
const WORN_COLOR := Color(1.0, 0.1, 0.05, 0.5)
const WORN_PULSE_SPEED := 8.0
const BREAK_TIME := 0.15
## Dropped on death: tossed this hard, up and away.
const DROP_IMPULSE := 3.0
var rarity: int = WeaponRarity.Tier.COMMON
var max_durability: int = 1
var durability: int = 1
var is_broken: bool = false
var _worn_this_action: bool = false
var _glow: StandardMaterial3D = null
var _worn_glow: StandardMaterial3D = null

# Hitting things: a swing is live for a short window after a tap-attack, a
# throw while the weapon is still flying fast. Each target is hit once per
# swing/throw. Damage and shove come from Behavior (base_damage/knockback_force).
const HIT_POP := 3.0
const THROWN_DAMAGE_MULTIPLIER := 1.25
const THROWN_HIT_MIN_SPEED := 4.0
const THROWN_SLOWDOWN_ON_HIT := 0.3  # Keeps this much speed after hitting a player
var swing_time_left: float = 0.0
var thrower: Node3D = null  # Who threw it, so it can't hit them mid-flight
var _hit_this_action: Array[Node] = []

# A swing knocks things the way the blade is moving (not just away from the
# wielder), harder the faster it's going: SWING_REFERENCE_SPEED hits for the
# weapon's usual knockback, scaled within SWING_POWER_MIN..MAX. That's for a
# REFERENCE_SWING_DURATION swing; a slower weapon's blade is expected to move
# slower, so a full-speed greataxe swing isn't weaker for being slow.
const SWING_REFERENCE_SPEED := 18.0
const REFERENCE_SWING_DURATION := 0.25
const SWING_POWER_MIN := 0.6
const SWING_POWER_MAX := 1.0
const SOLID_BOUNCE := 0.25
var _blade_velocity: Vector3 = Vector3.ZERO
var _blade_prev_pos: Vector3
var _blade_tracked: bool = false
## Clang off a wall only when the blade swings into it, not when a sword
## resting against it starts a swing already inside.
var _blade_in_wall: bool = false
var _swing_reference_speed: float = SWING_REFERENCE_SPEED

const THROWN_SETTLE_SPEED: float = 0.4
const DEFAULT_THROW_FORCE: float = 15.0
const DEFAULT_THROW_UPWARD_RATIO: float = 0.15
const DEFAULT_THROW_SPIN_SPEED: float = 8.0

## Client: don't ask the server again every frame we're touching the weapon.
const REQUEST_RETRY_MSEC := 250
var _next_request_msec: int = 0
var _last_sent_transform: Transform3D
var _last_sent_frame: int = -1
var _last_sent_msec: int = 0
## Replicas: the owner's recent poses, played back smoothly. While held they
## are relative to the wielder, so the weapon moves rigidly with the
## (also smoothed) body holding it.
var _net_motion: NetInterpolator = null
var _net_motion_is_local: bool = false
var _net_motion_sender: int = 0


func _ready() -> void:
	_set_props()
	set_rarity(rarity)


func _process(delta: float) -> void:
	_update_worn_glow()
	_handle_pickup_cooldown(delta)
	_send_pose()
	# A held replica is posed by its wielder, right after the wielder moves
	if not wielder:
		follow_net_pose(delta)


func _physics_process(delta: float) -> void:
	if not simulates():
		return
	_handle_thrown_settle()
	_update_hits(delta)
	if is_thrown:
		var spin_speed: float = Properties.throw_spin_speed if Properties else DEFAULT_THROW_SPIN_SPEED
		# Spin around the weapon's own local Z axis (perpendicular to its
		# length, which runs along local Y for a capsule-shaped weapon), so
		# it tumbles end-over-end like a flicked frisbee no matter which way
		# it happened to be pointing at the moment it was released.
		rotate_object_local(Vector3.FORWARD, spin_speed * throw_spin_direction * delta)


func _set_props() -> void:
	if !Properties:
		print("No Propertied found")
		queue_free()
		return

	# Set name from properties
	if Properties.weapon_name.is_empty():
		Properties.weapon_name = "Weapon3D"
	self.name = Properties.weapon_name

	# Setup collision if available
	if Collision:
		# Collision shape should be set up in the scene
		pass

	_update_collisions("on-ground")


func _handle_pickup_cooldown(delta: float) -> void:
	if wielder:
		return  # Don't update cooldown if held

	can_pickup_cd = max(can_pickup_cd - delta, 0.0)
	if can_pickup_cd == 0.0:
		can_pickup = true
	else:
		can_pickup = false


func _handle_thrown_settle() -> void:
	if is_thrown and linear_velocity.length() < THROWN_SETTLE_SPEED:
		is_thrown = false
		thrower = null
		_update_collisions("on-ground")


## Makes the next `duration` seconds of this held weapon's swing able to hit.
func start_swing(duration: float) -> void:
	swing_time_left = duration
	_swing_reference_speed = SWING_REFERENCE_SPEED * REFERENCE_SWING_DURATION / max(duration, 0.01)
	_hit_this_action.clear()
	_worn_this_action = false
	_blade_tracked = false
	_blade_in_wall = Combat.touches_wall(get_world_3d(), Collision.shape, Collision.global_transform)


## The wielder rolled away or got staggered: this swing hits nothing more.
func cancel_swing() -> void:
	swing_time_left = 0.0


func _update_hits(delta: float) -> void:
	if swing_time_left > 0.0:
		swing_time_left -= delta
		if is_held and wielder:
			_track_blade(delta)
			_hit_overlapping(wielder, 1.0, false)
			var was_in_wall: bool = _blade_in_wall
			_blade_in_wall = Combat.touches_wall(get_world_3d(), Collision.shape, Collision.global_transform)
			if swing_time_left > 0.0 and _blade_in_wall and not was_in_wall:
				_swing_contact(true)
	elif is_thrown and linear_velocity.length() > THROWN_HIT_MIN_SPEED:
		_hit_overlapping(thrower, THROWN_DAMAGE_MULTIPLIER, true)


## How fast the blade itself is moving mid-swing. The swing mostly turns the
## weapon rather than pushing it, so its linear_velocity misses most of it.
func _track_blade(delta: float) -> void:
	var pos: Vector3 = Collision.global_position
	_blade_velocity = (pos - _blade_prev_pos) / delta if _blade_tracked else Vector3.ZERO
	_blade_prev_pos = pos
	_blade_tracked = true


## The swing met something: tell the wielder's arm to stop for a moment
## (and spring back off anything solid), and stop hitting on the way back.
func _swing_contact(solid: bool) -> void:
	if solid:
		swing_time_left = 0.0
		# Stop dead instead of sliding on through it, with a little kick back
		linear_velocity *= -SOLID_BOUNCE
	else:
		swing_time_left += Combat.HITSTOP_LIGHT  # The arm pauses; keep the window open as long
	if wielder is PlayerClass3D:
		wielder.swing_contact(self, solid)


func _hit_overlapping(attacker: Node3D, damage_multiplier: float, thrown: bool) -> void:
	if not Collision or not Collision.shape: return
	var exclude: Array[RID] = [get_rid()]
	if attacker is CollisionObject3D:
		exclude.append(attacker.get_rid())
	var contact: bool = false
	var solid: bool = false
	var landed: bool = false
	for body: Node3D in Combat.overlaps(get_world_3d(), Collision.shape, Collision.global_transform, exclude):
		# Never hit our own side's gear (e.g. the wielder's other-hand weapon)
		if body in _hit_this_action or (body is Weapon3D and attacker and body.wielder == attacker):
			continue
		_hit_this_action.append(body)
		var dir: Vector3 = linear_velocity if thrown else body.global_position - attacker.global_position
		var damage: float = (Behavior.get_damage() if Behavior else 10.0) * damage_multiplier
		var knockback: float = Behavior.knockback_force if Behavior else 8.0
		if not thrown:
			dir = _swing_hit_direction(dir)
			knockback *= clamp(_blade_velocity.length() / _swing_reference_speed, SWING_POWER_MIN, SWING_POWER_MAX)
			contact = true
			solid = solid or Combat.is_solid(body)
		if Combat.strike(body, dir, damage, knockback, HIT_POP, -1.0, attacker) and thrown:
			linear_velocity *= THROWN_SLOWDOWN_ON_HIT
		landed = landed or body is PlayerClass3D or body is Boss3D or body is SlimeMinion3D
	if contact:
		_swing_contact(solid)
	# One use per swing or throw, however many it hits
	if landed and not _worn_this_action:
		_worn_this_action = true
		wear()


## Half away from the wielder, half along the blade's travel, so a slash
## sends things off to the side it was swung toward.
func _swing_hit_direction(away: Vector3) -> Vector3:
	var travel := Vector3(_blade_velocity.x, 0.0, _blade_velocity.z)
	away.y = 0.0
	if travel.length() < 0.5 or away.length() < 0.01:
		return away
	return away.normalized() + travel.normalized()


## High-level API: called when a quick tap resolves to an attack rather than a
## hold-to-throw. Base weapons rely on the shoulder-swipe animation alone;
## ranged weapons (like the crossbow) override this to fire a projectile.
func attack(_aim_direction: Vector3) -> void:
	pass


## High-level API: called by player/enemy when picking up this weapon.
## `hand` is the Area3D of the hand it's being equipped into, used by
## weapon behaviors (like the spring-follow sword) to know what to track.
func equip(new_wielder: Node3D, hand: Area3D = null) -> void:
	wielder = new_wielder
	held_hand = hand
	is_held = true
	is_thrown = false
	can_pickup = false
	can_pickup_cd = can_pickup_dur_in_sec
	_update_collisions("in-hand")

	# Layer/mask alone still leaves a window where the wielder's own physics
	# body can shove or be shoved by this weapon (e.g. mid-transition, or
	# while it's still moving to its held pose). A hard collision exception
	# between this specific pair rules that out entirely, regardless of
	# layer/mask state or timing. It has to be added on BOTH sides: Godot's
	# move_and_slide() consults the calling body's own exception list, so
	# only exempting the weapon leaves the wielder's own move_and_slide still
	# treating it as a solid obstacle.
	if new_wielder is PhysicsBody3D:
		add_collision_exception_with(new_wielder)
		new_wielder.add_collision_exception_with(self)

	# Snap straight to the hand instead of leaving the weapon at its pickup
	# spot for the hand-follow spring to violently close the gap. A large,
	# fast RigidBody3D lurching up off the ground right under the wielder's
	# feet gets picked up by move_and_slide() as if standing on a launching
	# platform, flinging the wielder into the air.
	if hand:
		global_position = hand.global_position
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO

	if Behavior:
		Behavior.equip(new_wielder)


## Jump straight to the holding hand, e.g. after the wielder teleports, so
## the hand-follow spring doesn't fling it across the map to catch up.
func snap_to_hand() -> void:
	if not held_hand:
		return
	global_position = held_hand.global_position
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


## High-level API: called when the weapon is dropped/unequipped.
func unequip() -> void:
	if Behavior:
		Behavior.unequip()

	if wielder is PhysicsBody3D:
		remove_collision_exception_with(wielder)
		wielder.remove_collision_exception_with(self)

	_clear_from_wielder()
	wielder = null
	held_hand = null
	is_held = false
	_update_collisions("on-ground")


## High-level API: called to throw the weapon in a given (horizontal) direction.
## `spin_direction` lets the thrower flip which way it tumbles (e.g. mirrored
## for a left-hand vs right-hand throw) - pass -1.0 to reverse it.
## `force_multiplier` scales the resolved base throw force (e.g. for a
## charge-up-by-holding-the-button throw).
func throw(direction: Vector3, force: float = -1.0, spin_direction: float = 1.0, force_multiplier: float = 1.0) -> void:
	if !wielder: return
	_let_go_thrown(spin_direction)
	if Net.match_synced:
		_net_thrown.rpc(spin_direction)

	var throw_force: float = force if force > 0.0 else DEFAULT_THROW_FORCE
	var upward_ratio: float = DEFAULT_THROW_UPWARD_RATIO
	if Properties:
		if Properties.throw_force > 0.0 and force <= 0.0:
			throw_force = Properties.throw_force
		upward_ratio = Properties.throw_upward_ratio
	throw_force *= force_multiplier

	var horizontal_dir: Vector3 = direction.normalized()
	var launch_dir: Vector3 = (horizontal_dir + Vector3.UP * upward_ratio).normalized()
	linear_velocity = launch_dir * throw_force
	angular_velocity = Vector3.ZERO


## The part of a throw every machine does: out of the wielder's hand and
## into the air. Only the simulating machine launches it.
func _let_go_thrown(spin_direction: float) -> void:
	throw_spin_direction = spin_direction
	thrower = wielder
	swing_time_left = 0.0
	_hit_this_action.clear()
	_worn_this_action = false

	if Behavior:
		Behavior.unequip()

	if wielder is PhysicsBody3D:
		remove_collision_exception_with(wielder)
		wielder.remove_collision_exception_with(self)

	_clear_from_wielder()
	wielder = null
	held_hand = null
	is_held = false
	is_thrown = true
	can_pickup = false
	can_pickup_cd = can_pickup_dur_in_sec
	_update_collisions("projectile")


## Empty whichever of the wielder's hands was holding this.
func _clear_from_wielder() -> void:
	if not is_instance_valid(wielder) or not wielder is PlayerClass3D:
		return
	if wielder.held_weapon_left == self:
		wielder.held_weapon_left = null
	if wielder.held_weapon_right == self:
		wielder.held_weapon_right = null


# ===== RARITY & DURABILITY =====

## Make this a `tier` weapon, at full durability. Call on every machine.
func set_rarity(tier: int) -> void:
	rarity = clampi(tier, 0, WeaponRarity.Tier.size() - 1)
	var durability_scale: float = Properties.durability_scale if Properties else 1.0
	max_durability = maxi(roundi(WeaponRarity.DURABILITY[rarity] * durability_scale), 1)
	durability = max_durability
	_glow = WeaponRarity.apply_glow(self, rarity)
	_worn_glow = null


## One use's worth of wear, on the machine simulating the weapon. Breaks it
## (everywhere) at 0.
func wear(amount: int = 1) -> void:
	if is_broken or not simulates():
		return
	var left: int = maxi(durability - amount, 0)
	if Net.match_synced:
		_net_durability.rpc(left)
	else:
		_net_durability(left)


@rpc("any_peer", "call_local", "reliable")
func _net_durability(value: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return
	durability = value
	if durability <= 0:
		_break()


func is_worn() -> bool:
	return durability <= maxi(ceili(max_durability * WORN_RATIO), 1)


## Nearly broken: pulse red over (in place of) its rarity glow.
func _update_worn_glow() -> void:
	if is_broken or not is_worn():
		return
	if not _worn_glow:
		_worn_glow = StandardMaterial3D.new()
		_worn_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_worn_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_worn_glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		for mesh: Node in find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).material_overlay = _worn_glow
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * WORN_PULSE_SPEED)
	_worn_glow.albedo_color = Color(WORN_COLOR, WORN_COLOR.a * pulse)


## Out of durability, on every machine: out of the wielder's hand, out of
## the physics world, a quick shrink, gone.
func _break() -> void:
	if is_broken:
		return
	is_broken = true
	if wielder:
		unequip()
	swing_time_left = 0.0
	is_thrown = false
	process_mode = Node.PROCESS_MODE_DISABLED  # Leaves the physics world at once
	# Not bound to this node: a disabled node's own tweens don't run
	var tween: Tween = get_tree().create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, BREAK_TIME)
	tween.tween_callback(queue_free)


## The wielder died (on their machine): let go, tossed up and out a little,
## where anyone can pick it up once the pickup cooldown is over.
func drop() -> void:
	if not wielder:
		return
	var away: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	unequip()
	if Net.match_synced:
		_net_dropped.rpc()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	apply_central_impulse((away + Vector3.UP * 1.5).normalized() * DROP_IMPULSE * mass)


@rpc("any_peer", "reliable")
func _net_dropped() -> void:
	if _is_from_owner() and wielder:
		unequip()


# ===== NETWORK =====

## Online, on every machine: the server simulates loose weapons to begin
## with. Call before the match starts syncing.
func setup_network() -> void:
	_set_net_owner(Net.SERVER_ID)


## Whether this machine runs the weapon's physics (and checks its hits).
func simulates() -> bool:
	return not Net.in_session() or is_multiplayer_authority()


func _set_net_owner(peer_id: int) -> void:
	set_multiplayer_authority(peer_id)
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = not is_multiplayer_authority()
	_last_sent_transform = Transform3D()
	if not _net_motion:
		_net_motion = NetInterpolator.new(0.0 if Net.is_server else NetInterpolator.DELAY)
	_net_motion.clear()


## Whoever simulated this weapon left: the server takes it back, out of
## their hand if they were holding it.
func forget_departed_owner() -> void:
	var peer_id: int = get_multiplayer_authority()
	if peer_id == Net.SERVER_ID or Net.peers.has(peer_id):
		return
	if wielder:
		unequip()
	thrower = null
	is_thrown = false
	_set_net_owner(Net.SERVER_ID)


## Once per physics tick at most, and only when it moved. Held weapons
## send their pose relative to the wielder.
func _send_pose() -> void:
	if not Net.match_synced or not is_multiplayer_authority():
		return
	var frame: int = Engine.get_physics_frames()
	var is_local: bool = wielder != null
	var xform: Transform3D = wielder.global_transform.affine_inverse() * global_transform if is_local else global_transform
	var now_msec: int = Time.get_ticks_msec()
	if frame == _last_sent_frame or (xform.is_equal_approx(_last_sent_transform) \
			and now_msec - _last_sent_msec < NetInterpolator.RESEND_IDLE_MSEC):
		return
	_last_sent_frame = frame
	_last_sent_transform = xform
	_last_sent_msec = now_msec
	_net_pose.rpc(NetInterpolator.now(), xform, is_local)


func _is_from_owner() -> bool:
	return multiplayer.get_remote_sender_id() == get_multiplayer_authority()


@rpc("any_peer", "unreliable_ordered")
func _net_pose(time: float, xform: Transform3D, is_local: bool) -> void:
	if not _is_from_owner() or not _net_motion:
		return
	# Snapshots in the other space, or stamped by another machine's clock,
	# can't be blended with these
	var sender: int = multiplayer.get_remote_sender_id()
	if is_local != _net_motion_is_local or sender != _net_motion_sender:
		_net_motion.clear()
		_net_motion_is_local = is_local
		_net_motion_sender = sender
	_net_motion.push(time, xform)


## Replicas, once per rendered frame: move to where the owner had this a
## moment ago.
func follow_net_pose(delta: float) -> void:
	if simulates() or not _net_motion:
		return
	if _net_motion_is_local != (wielder != null):
		return  # e.g. just thrown here, world-space poses not in yet
	var sample: Array = _net_motion.sample(delta)
	if not sample.is_empty():
		global_transform = wielder.global_transform * sample[0] if wielder else sample[0]


@rpc("any_peer", "reliable")
func _net_thrown(spin_direction: float) -> void:
	if _is_from_owner() and wielder:
		_let_go_thrown(spin_direction)


## Hit or shoved by something (see Combat.push).
func receive_impulse(impulse: Vector3) -> void:
	if simulates():
		apply_central_impulse(impulse)
	else:
		_request_push.rpc_id(get_multiplayer_authority(), impulse)


@rpc("any_peer", "reliable")
func _request_push(impulse: Vector3) -> void:
	if is_multiplayer_authority():
		apply_central_impulse(impulse)


## `player` touched this with a free hand. Online the server decides, so two
## players can't pick up the same weapon.
func request_equip(player: PlayerClass3D, is_left: bool) -> void:
	if not Net.in_session():
		player.equip_weapon(self, is_left)
	elif Time.get_ticks_msec() >= _next_request_msec:
		_next_request_msec = Time.get_ticks_msec() + REQUEST_RETRY_MSEC
		_request_equip.rpc_id(Net.SERVER_ID, is_left)


@rpc("any_peer", "reliable")
func _request_equip(is_left: bool) -> void:
	if not Net.is_server or wielder or not can_pickup:
		return
	var player: PlayerClass3D = Global.Game3D.player_of_peer(multiplayer.get_remote_sender_id())
	if player and not player.is_hand_occupied(is_left):
		_equipped.rpc(player.name, is_left)


## Server -> everyone. Not "authority" mode: the weapon's authority is
## whoever last held it, not the server.
@rpc("any_peer", "call_local", "reliable")
func _equipped(player_name: String, is_left: bool) -> void:
	if multiplayer.get_remote_sender_id() != Net.SERVER_ID:
		return
	var player: PlayerClass3D = Global.Game3D.get_node_or_null(player_name) as PlayerClass3D
	if player:
		hand_to(player, is_left)


## Put this in `player`'s hand. Online, every machine does this once the
## server has decided, and that player's machine simulates it from then on.
func hand_to(player: PlayerClass3D, is_left: bool) -> void:
	if wielder:
		unequip()
	if Net.in_session():
		_set_net_owner(player.get_multiplayer_authority())
	player.equip_weapon(self, is_left)


func _update_collisions(state: String) -> void:
	match state:
		"on-ground":
			set_collision_layer_value(2, false)
			set_collision_layer_value(4, true)
			set_collision_mask_value(1, true)  # World
			set_collision_mask_value(2, true)  # Player
			set_collision_mask_value(3, true)  # Enemy
			set_collision_mask_value(4, true)  # Weapon

		"in-hand":
			set_collision_layer_value(2, true)
			set_collision_layer_value(4, false)
			set_collision_mask_value(1, false)  # World
			set_collision_mask_value(2, false)  # Player
			set_collision_mask_value(3, true)   # Enemy
			set_collision_mask_value(4, true)   # Weapon

		"projectile":
			set_collision_layer_value(2, false)
			set_collision_layer_value(4, true)
			set_collision_mask_value(1, true)   # World
			set_collision_mask_value(2, false)  # Player
			set_collision_mask_value(3, true)   # Enemy
			set_collision_mask_value(4, true)   # Weapon
