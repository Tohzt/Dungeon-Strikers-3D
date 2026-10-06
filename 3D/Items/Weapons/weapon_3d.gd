class_name Weapon3D extends RigidBody3D
## Online, one machine simulates each weapon and streams its pose to the
## rest, which just follow along. Loose weapons start with the server; the
## server hands a weapon to whoever it lets pick it up, and that player's
## machine keeps simulating it (held, thrown, lying where it landed) until
## someone else picks it up. Only the simulating machine checks its hits.

@export var Properties: WeaponProperties3D
@export var Behavior: WeaponBehavior3D
@onready var Collision := $CollisionShape3D

## Whether a quick tap swings it (a melee weapon). A weapon that just fires
## in place (like the bow) turns this off.
@export var plays_swipe_animation: bool = true

## Which hand can hold it. The right hand is the main hand: the KayKit
## one-handed clips all swing with it. The left is the off hand, and swings
## with the left arm of the dual-wield clips. A one-handed weapon in each
## hand turns the Off-hand button into a special (see WeaponCombo3D).
enum Grip {
	MAIN_HAND,  ## One-handed: the right hand first, the left if that's taken
	OFF_HAND,  ## Left hand only (shield)
	EITHER_HAND,  ## Light enough to swing from either hand
	TWO_HANDED,  ## Right hand, and the left hand has to be free too
}
@export var grip: Grip = Grip.MAIN_HAND
## A two-handed weapon that sits in the left hand rather than the right, like
## a bow (drawn with the right). It still counts as the right hand's weapon.
@export var rides_left_hand: bool = false

@export_group("Animation")
## Clip (library/name, see PlayerVisual3D.CLIP_KEYS) the arm plays when this
## swings or fires from the right hand, or both hands if two-handed.
@export var swing_clip: StringName = &"CombatMelee/Melee_1H_Attack_Slice_Horizontal"
## The same, swung from the left hand.
@export var offhand_swing_clip: StringName = &"CombatMelee/Melee_Dualwield_Attack_Slice"
## Pose the arm holds while is_holding_pose() (aiming, blocking). Empty = none.
## The torso turns into it too (see PlayerVisual3D.TORSO_BONES).
@export var hold_clip: StringName = &""
## Thrown point first, like a spear: it flies straight along its throw
## instead of tumbling end over end.
@export var throw_point_first: bool = false
## Where it sits on the hand's handslot bone. The grip is the weapon's
## origin and the blade runs along its +Y, like the KayKit props, so most
## weapons need none.
@export var hold_offset: Transform3D = Transform3D.IDENTITY
@export_group("Specials")
## Weapons of the same family (e.g. "blade" for sword and scimitar) pair up
## like two of the same weapon. Empty = it only pairs with itself.
@export var combo_family: StringName = &""
## The special (Off-hand button) with a compatible weapon in the other hand
## (see WeaponCombo3D.find_for). Empty = both swing at once.
@export var pair_combo: WeaponCombo3D
## The Off-hand button's attack while the other hand is empty (or this is
## two-handed). Empty = the same as the Attack button.
@export var alt_attack: WeaponCombo3D
@export_group("")

var wielder: Node3D = null
## The wielder's hand bone (see PlayerVisual3D.hand()), which this rides
## rigidly while held.
var held_hand: Node3D = null
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
# Breaking is a payoff, not a fizzle: the use that breaks a weapon (its last
# swing or throw to land, last shot, last block) hits FINAL_* harder, and
# then the weapon shatters in a burst (see WeaponProperties3D) that hurts and
# shoves everyone nearby but its wielder's team. On that last use it pulses
# white-hot, so both sides can see the big hit coming.
const FINAL_DAMAGE_MULTIPLIER := 2.0
const FINAL_KNOCKBACK_MULTIPLIER := 1.5
const LAST_USE_COLOR := Color(1.0, 0.8, 0.35, 0.8)
const LAST_USE_PULSE_SPEED := 16.0
const SHATTER_COLOR := Color(0.75, 0.75, 0.8)
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
## Times the damage of the current swing (a combo beat may hit harder).
var _swing_damage_scale: float = 1.0
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
## Loose and in the air (thrown or dropped) until it first touches the
## world. It stops tumbling then, and lands lying flat if that was the
## ground. Set from contacts in _integrate_forces, acted on in _physics_process.
var _landed: bool = true
var _touched_world: bool = false
var _touched_floor: bool = false
## A thrown weapon that's down but somehow still sliding counts as settled
## after this long, so it can't stay a projectile forever.
const LANDED_SETTLE_TIME := 1.5
var _landed_time: float = 0.0
const DEFAULT_THROW_FORCE: float = 15.0
const DEFAULT_THROW_UPWARD_RATIO: float = 0.15
const DEFAULT_THROW_SPIN_SPEED: float = 8.0

## Client: don't ask the server again every frame we're touching the weapon.
const REQUEST_RETRY_MSEC := 250
var _next_request_msec: int = 0
## Online: whoever simulates it sends where it is, the rest play it back.
## Not while held: every machine poses a held weapon from its wielder's hand.
var _motion := NetMotion.new()


func _ready() -> void:
	# Thrown weapons are fast and thin: without this they can pass through
	# walls and floors in a single physics step.
	continuous_cd = true
	# Frozen while held, and on machines that don't simulate it
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	# To notice landing (see _integrate_forces)
	contact_monitor = true
	max_contacts_reported = 4
	# Spawned loose (e.g. a chest's loot): settle flat when it lands
	_landed = false
	_set_props()
	set_rarity(rarity)


func _process(delta: float) -> void:
	_update_worn_glow()
	_handle_pickup_cooldown(delta)
	_send_pose()
	follow_net_pose(delta)


func _physics_process(delta: float) -> void:
	if not simulates():
		return
	# The wielder may have moved since the hand's last pose
	follow_hand()
	_update_landing(delta)
	_handle_thrown_settle()
	_update_hits(delta)
	if is_thrown and not _landed:
		if throw_point_first:
			_point_along(linear_velocity)
		else:
			var spin_speed: float = Properties.throw_spin_speed if Properties else DEFAULT_THROW_SPIN_SPEED
			# Spin around the weapon's own local Z axis (perpendicular to its
			# length, which runs along local Y), so it tumbles end over end
			# whichever way it was pointing when it was let go.
			rotate_object_local(Vector3.FORWARD, spin_speed * throw_spin_direction * delta)


## Notes when a loose weapon in the air first touches the world, and
## whether that was the ground (a contact pushing it up).
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _landed or is_held:
		return
	for i in state.get_contact_count():
		var other: Object = state.get_contact_collider_object(i)
		var layer: Variant = other.get("collision_layer") if other else null
		if layer == null or (int(layer) & Combat.WORLD_MASK) == 0:
			continue  # A player, the ball, another weapon...
		_touched_world = true
		if state.get_contact_local_normal(i).y > 0.6:
			_touched_floor = true


## Down: no more tumbling. Off the floor it lies flat, so it rests still
## instead of balancing on an end.
func _update_landing(delta: float) -> void:
	if is_held:
		return
	if _landed:
		if is_thrown:
			_landed_time += delta
			if _landed_time > LANDED_SETTLE_TIME:
				linear_velocity = Vector3.ZERO
		return
	if not _touched_world:
		return
	if not _touched_floor:
		return  # Off a wall: keep falling (and tumbling) until it's down
	_landed = true
	_landed_time = 0.0
	global_basis = _lying_flat_basis()


## Its thinnest side up, keeping the way its length points.
func _lying_flat_basis() -> Basis:
	var box := Collision.shape as BoxShape3D if Collision else null
	var size: Vector3 = box.size if box else Vector3(0.3, 1.0, 0.15)
	var thin: int = size.min_axis_index()
	var long: int = size.max_axis_index()
	var current: Basis = global_basis.orthonormalized()
	var along: Vector3 = current[long]
	along.y = 0.0
	along = along.normalized() if along.length() > 0.01 else Vector3.FORWARD
	var flat := Basis()
	flat[thin] = Vector3.UP
	flat[long] = along
	var other: int = 3 - thin - long
	flat[other] = flat[(other + 1) % 3].cross(flat[(other + 2) % 3])
	return flat


## Point its blade (local +Y) along `direction`.
func _point_along(direction: Vector3) -> void:
	if direction.length() < 0.5:
		return
	var y: Vector3 = direction.normalized()
	var x: Vector3 = y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	global_basis = Basis(x, y, x.cross(y))


func _set_props() -> void:
	if !Properties:
		push_error("%s has no WeaponProperties3D; removing it." % scene_file_path)
		queue_free()
		return

	# Set name from properties
	if Properties.weapon_name.is_empty():
		Properties.weapon_name = "Weapon3D"
	self.name = Properties.weapon_name

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


## Makes the next `duration` seconds of this held weapon's swing able to
## hit, for `damage_scale` times its usual damage.
func start_swing(duration: float, damage_scale: float = 1.0) -> void:
	swing_time_left = duration
	_swing_damage_scale = damage_scale
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
			_hit_overlapping(wielder, _swing_damage_scale, false)
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
	var final_use: bool = is_last_use()
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
		if body is Ball3D and Behavior:
			# Each weapon plays the ball its own way (see WeaponBehavior3D.hit_ball)
			var travel := Vector3.ZERO if thrown else Vector3(_blade_velocity.x, 0.0, _blade_velocity.z)
			Behavior.hit_ball(body, dir, travel, knockback, attacker)
			continue
		if final_use:
			damage *= FINAL_DAMAGE_MULTIPLIER
			knockback *= FINAL_KNOCKBACK_MULTIPLIER
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


## Whether this and `other` pair up for a special (see WeaponCombo3D): the
## same weapon, or the same combo_family.
func is_compatible_with(other: Weapon3D) -> bool:
	if combo_family != &"" and combo_family == other.combo_family:
		return true
	if not scene_file_path.is_empty():
		return scene_file_path == other.scene_file_path
	return Properties != null and other.Properties != null \
		and Properties.weapon_name == other.Properties.weapon_name


## High-level API: called when a quick tap resolves to an attack rather than a
## hold-to-throw. Base weapons rely on the swing alone; ranged weapons (like
## the bow) override this to fire a projectile.
func attack(_aim_direction: Vector3) -> void:
	pass


## High-level API: called by player/enemy when picking up this weapon.
## `hand` is the hand bone it rides from now on.
func equip(new_wielder: Node3D, hand: Node3D = null) -> void:
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

	# Held, it's posed by the hand (on every machine), not by physics, and
	# steps after the wielder so its swing checks see where the wielder is now
	freeze = true
	process_physics_priority = new_wielder.process_physics_priority + 1
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	follow_hand()

	if Behavior:
		Behavior.equip(new_wielder)


## Held: sit in the hand, wherever its bone is now. The wielder calls this
## each time its skeleton is posed; the weapon's own physics step calls it
## too, in case the wielder moved since.
func follow_hand() -> void:
	if not is_held or not held_hand:
		return
	# Without the body's scale: physics bodies mustn't be scaled
	var hand := Transform3D(held_hand.global_basis.orthonormalized(), held_hand.global_position)
	if _mirrors_in_left_hand():
		hand = hand * LEFT_HAND_TURN
	global_transform = hand * hold_offset


## The left handslot is the right one mirrored on every axis but X (a turn
## can't mirror all three), so a weapon made for the right hand would sit
## in the left with its edge (and a katana's curve) on the wrong side.
## Turning it half round its blade puts that right. Off-hand-only weapons
## (shields) and ones made to ride the left hand (bows) are set up for it.
const LEFT_HAND_TURN := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)


func _mirrors_in_left_hand() -> bool:
	if grip == Grip.OFF_HAND or rides_left_hand or not wielder:
		return false
	return "held_weapon_left" in wielder and wielder.held_weapon_left == self


## Its wielder's skeleton was just posed (once per rendered frame).
func on_hand_posed() -> void:
	follow_hand()


## Whether the arm holding this should hold `hold_clip`'s pose right now.
func is_holding_pose() -> bool:
	return hold_clip != &""


## Off the hand: back to its own physics, if this machine simulates it,
## falling until it lands (see _update_landing).
func _release_from_hand() -> void:
	freeze = not simulates()
	process_physics_priority = 0
	_landed = false
	_touched_world = false
	_touched_floor = false


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
	_release_from_hand()
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
	if throw_point_first:
		_point_along(launch_dir)


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
	_release_from_hand()
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


## The next use breaks it.
func is_last_use() -> bool:
	return not is_broken and durability <= 1


func is_worn() -> bool:
	return durability <= maxi(ceili(max_durability * WORN_RATIO), 1)


## Nearly broken: pulse red over (in place of) its rarity glow; white-hot,
## and faster, on its last use.
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
	var last: bool = is_last_use()
	var color: Color = LAST_USE_COLOR if last else WORN_COLOR
	var speed: float = LAST_USE_PULSE_SPEED if last else WORN_PULSE_SPEED
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * speed)
	_worn_glow.albedo_color = Color(color, color.a * pulse)


## Out of durability, on every machine: out of the wielder's hand, out of
## the physics world, a quick shrink, gone - in a burst of shards. The
## machine simulating it decides who the burst hits.
func _break() -> void:
	if is_broken:
		return
	is_broken = true
	var breaker: Node3D = wielder if wielder else thrower
	var radius: float = Properties.break_burst_radius if Properties else 2.5
	if simulates():
		_shatter_burst(breaker, radius)
	var shard_color: Color = WeaponRarity.COLORS[rarity] if rarity != WeaponRarity.Tier.COMMON else SHATTER_COLOR
	WeaponShatter3D.spawn(get_parent(), global_position, Color(shard_color, 1.0), radius)
	if wielder:
		unequip()
	swing_time_left = 0.0
	is_thrown = false
	process_mode = Node.PROCESS_MODE_DISABLED  # Leaves the physics world at once
	# Not bound to this node: a disabled node's own tweens don't run
	var tween: Tween = get_tree().create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, BREAK_TIME)
	tween.tween_callback(queue_free)


## Hurt and shove everything in the break burst but `breaker` (whoever held
## or threw it) and their team, who get the credit.
func _shatter_burst(breaker: Node3D, radius: float) -> void:
	if not is_inside_tree() or not Properties:
		return
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var exclude: Array[RID] = [get_rid()]
	if breaker is CollisionObject3D:
		exclude.append(breaker.get_rid())
	var origin: Vector3 = global_position
	for body: Node3D in Combat.overlaps(get_world_3d(), sphere, Transform3D(Basis(), origin), exclude):
		if _on_team_of(body, breaker) or (body is Weapon3D and breaker and body.wielder == breaker):
			continue
		Combat.strike(body, body.global_position - origin, Properties.break_burst_damage,
			Properties.break_burst_knockback, HIT_POP, -1.0, breaker)


static func _on_team_of(body: Node3D, breaker: Node3D) -> bool:
	return body is PlayerClass3D and breaker is PlayerClass3D and body.slot and breaker.slot \
		and body.slot.team == breaker.slot.team


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
	_motion.send_next()
	_motion.clear()


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


## Not while held (see _motion).
func _send_pose() -> void:
	if Net.match_synced and is_multiplayer_authority() and not wielder and _motion.should_send(global_transform):
		_net_pose.rpc(NetInterpolator.now(), global_transform)


func _is_from_owner() -> bool:
	return multiplayer.get_remote_sender_id() == get_multiplayer_authority()


@rpc("any_peer", "unreliable_ordered")
func _net_pose(time: float, xform: Transform3D) -> void:
	if _is_from_owner():
		_motion.push(time, xform, PackedFloat32Array(), multiplayer.get_remote_sender_id())


## Replicas, once per rendered frame: move to where the owner had this a
## moment ago.
func follow_net_pose(delta: float) -> void:
	if simulates():
		return
	if wielder:
		# Poses from before it was picked up are stale by the time it's dropped
		_motion.clear()
		return
	_motion.play(self, delta)


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
	var player: PlayerClass3D = Global.Game3D.rpc_sender()
	if player and player.can_hold(self, is_left):
		_equipped.rpc(player.name, is_left)


## Server -> everyone. Not "authority" mode: the weapon's authority is
## whoever last held it, not the server.
@rpc("any_peer", "call_local", "reliable")
func _equipped(player_name: String, is_left: bool) -> void:
	if multiplayer.get_remote_sender_id() != Net.SERVER_ID:
		return
	var player: PlayerClass3D = Global.Game3D.player_named(player_name)
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
			set_collision_mask_value(2, false)  # Player: walked over, picked up with interact
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
