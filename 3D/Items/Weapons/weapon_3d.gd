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

const THROWN_SETTLE_SPEED: float = 0.4
const DEFAULT_THROW_FORCE: float = 15.0
const DEFAULT_THROW_UPWARD_RATIO: float = 0.15
const DEFAULT_THROW_SPIN_SPEED: float = 8.0

## Client: don't ask the server again every frame we're touching the weapon.
const REQUEST_RETRY_MSEC := 250
var _next_request_msec: int = 0
var _last_sent_transform: Transform3D
var _last_sent_frame: int = -1


func _ready() -> void:
	_set_props()


func _process(delta: float) -> void:
	_handle_pickup_cooldown(delta)
	_send_pose()


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
	_hit_this_action.clear()


func _update_hits(delta: float) -> void:
	if swing_time_left > 0.0:
		swing_time_left -= delta
		if is_held and wielder:
			_hit_overlapping(wielder, 1.0, false)
	elif is_thrown and linear_velocity.length() > THROWN_HIT_MIN_SPEED:
		_hit_overlapping(thrower, THROWN_DAMAGE_MULTIPLIER, true)


func _hit_overlapping(attacker: Node3D, damage_multiplier: float, thrown: bool) -> void:
	if not Collision or not Collision.shape: return
	var exclude: Array[RID] = [get_rid()]
	if attacker is CollisionObject3D:
		exclude.append(attacker.get_rid())
	for body: Node3D in Combat.overlaps(get_world_3d(), Collision.shape, Collision.global_transform, exclude):
		# Never hit our own side's gear (e.g. the wielder's other-hand weapon)
		if body in _hit_this_action or (body is Weapon3D and attacker and body.wielder == attacker):
			continue
		_hit_this_action.append(body)
		var dir: Vector3 = linear_velocity if thrown else body.global_position - attacker.global_position
		var damage: float = (Behavior.get_damage() if Behavior else 10.0) * damage_multiplier
		var knockback: float = Behavior.knockback_force if Behavior else 8.0
		if Combat.strike(body, dir, damage, knockback, HIT_POP) and thrown:
			linear_velocity *= THROWN_SLOWDOWN_ON_HIT


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


## Once per physics tick at most, and only when it moved.
func _send_pose() -> void:
	if not Net.match_synced or not is_multiplayer_authority():
		return
	var frame: int = Engine.get_physics_frames()
	if frame == _last_sent_frame or global_transform.is_equal_approx(_last_sent_transform):
		return
	_last_sent_frame = frame
	_last_sent_transform = global_transform
	_net_pose.rpc(global_transform)


func _is_from_owner() -> bool:
	return multiplayer.get_remote_sender_id() == get_multiplayer_authority()


@rpc("any_peer", "unreliable_ordered")
func _net_pose(xform: Transform3D) -> void:
	if _is_from_owner():
		global_transform = xform


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
	if not player:
		return
	if wielder:
		unequip()
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
