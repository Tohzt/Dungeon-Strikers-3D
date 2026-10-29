class_name Ball3D extends RigidBody3D
## Online the server simulates the ball and streams where it is; players'
## hits and pushes are passed on to the server, and so are grabs and throws.
## Every machine pins a held ball to its holder itself, so carrying looks
## smooth for everyone.

## Who carries the ball, if anyone (see PlayerClass3D.carry). Set on every
## machine.
var holder: PlayerClass3D = null
var _free_collision_layer: int = 0
var _free_collision_mask: int = 0
## Server: after a throw nobody can grab the ball for a moment, so the
## thrower's own grab doesn't catch it straight back.
const GRAB_COOLDOWN := 0.4
var _grab_cooldown: float = 0.0
## Server: extra reach allowed on a client's grab, since it saw the ball
## (and the server saw the player) a little in the past.
const GRAB_REACH_SLACK := 1.0

## What a launch (see PlayerClass3D.shoot_ball) was meant as: a pass, which
## the first of the passer's teammates it reaches catches, or an attack,
## which hurts the first enemy it hits. Server/offline, until it's caught,
## hits something or SHOT_TIME runs out.
enum Shot { NONE, PASS, ATTACK }
const SHOT_TIME := 1.5
const ATTACK_KNOCKBACK := 6.0
const ATTACK_POP := 2.0
var _shot: Shot = Shot.NONE
var _shot_by_name: String = ""
var _shot_damage: float = 0.0
var _shot_left: float = 0.0

## Team (PlayerSlot.team) of the last player to play the ball, -1 = nobody
## yet. Kept by whoever simulates it; four-team goals credit this team.
var last_team: int = -1
## Name of the last player to play the ball ("" = nobody yet), who gets
## the goal in the match stats (see MatchStats). Kept like last_team.
var last_player: String = ""
## Online: the server sends where it is; clients play it back.
var _motion := NetMotion.new()

# Weapon effects (see WeaponBehavior3D.hit_ball). Online the server applies
# them, like every push.
## Curve: a sideways pull after an axe hook, fading out over CURVE_TIME.
const CURVE_TIME := 0.8
var _curve: Vector3 = Vector3.ZERO
var _curve_left: float = 0.0
## Burning (lit by a torch): a fast burning ball hurts whoever it hits.
## Known on every machine, for the flames.
const BURN_HIT_DAMAGE := 15.0
const BURN_HIT_KNOCKBACK := 4.0
const BURN_HIT_MIN_SPEED := 4.0
const BURN_HIT_COOLDOWN_MSEC := 500
const BURN_COLOR := Color(1.0, 0.45, 0.05)
var burn_left: float = 0.0
var _igniter_name: String = ""
var _burned_msec: Dictionary[String, int] = {}
var _burn_light: OmniLight3D = null
## The crackle while it burns (see _update_burn_sound).
var _burn_sound: AudioStreamPlayer3D = null
## A raised shield catches it: dropped just in front of the shield.
## Below this it has escaped the level (squeezed through a wall).
const OUT_OF_BOUNDS_Y := -10.0
const CATCH_SPEED := 1.5
const CATCH_POP := 1.0
## Walls are springy: coming off one, the ball keeps this much of the speed
## it hit it with (the floor keeps its own, duller bounce).
const WALL_BOUNCE := 0.85
## Its velocity the step before, to see how hard it hit a wall.
var _last_velocity: Vector3 = Vector3.ZERO
## Fast enough, it can cross a thin floor, wall or roof between two physics
## steps (continuous collision misses it), e.g. a high shot coming back down
## off the roof. Each step it checks the line it just travelled against
## these layers (World, Roof) and is put back on the near side, bounced.
const TUNNEL_MASK := 1 | 64
## Moving further than its speed allows in a step means it was put
## somewhere (reset, released from hands), not that it tunnelled.
const TELEPORT_SLACK := 1.0
## Bounce kept coming back off a surface it would have tunnelled through.
const TUNNEL_BOUNCE := 0.6
var _last_position: Vector3 = Vector3.INF  # None yet: the first step is skipped

func _ready() -> void:
	# Update collision mask to detect weapons and entities
	set_collision_mask_value(1, true)  # World
	set_collision_mask_value(2, true)  # Player
	set_collision_mask_value(3, true)  # Enemy
	set_collision_mask_value(4, true)  # Weapon
	set_collision_mask_value(7, true)  # Roof (keeps it in bounds)
	
	# Connect body entered signal
	body_entered.connect(_on_body_entered)
	# Weapons already in hands pass through it (see Weapon3D._update_ball_contact)
	for weapon: Node in get_tree().get_nodes_in_group(Weapon3D.HELD_GROUP):
		add_collision_exception_with(weapon)
		(weapon as Weapon3D).add_collision_exception_with(self)
	_burn_light = OmniLight3D.new()
	_burn_light.light_color = BURN_COLOR
	_burn_light.omni_range = 5.0
	_burn_light.visible = false
	add_child(_burn_light)


func _process(delta: float) -> void:
	if holder:
		_follow_holder()
	elif not Net.decides():
		_motion.play(self, delta)
	_update_burn_light()
	burn_left = max(burn_left - delta, 0.0)
	_update_burn_sound()
	ElementReactions.ball_at(self)


func _physics_process(delta: float) -> void:
	if not Net.decides():
		return  # The server's updates move it
	_grab_cooldown = max(_grab_cooldown - delta, 0.0)
	if holder:
		if not is_instance_valid(holder) or holder.is_dead():
			_released_everywhere(Vector3.ZERO)
		_last_position = global_position
		return
	_shot_left = max(_shot_left - delta, 0.0)
	if _shot_left <= 0.0:
		_shot = Shot.NONE
	_stop_tunnelling(delta)
	if global_position.y < OUT_OF_BOUNDS_Y and Global.Game3D:
		Global.Game3D.ball_fell(self)
	_update_curve(delta)
	_send_state()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if Net.decides() and not holder:
		_bounce_off_walls(state)
	_last_velocity = state.linear_velocity


## Server/offline: if the last physics step carried it through a floor,
## wall or roof, put it back in front of that surface and bounce it off.
func _stop_tunnelling(delta: float) -> void:
	var from: Vector3 = _last_position
	_last_position = global_position
	var travelled: float = from.distance_to(global_position)
	if travelled < 0.01 or travelled > linear_velocity.length() * delta * 2.0 + TELEPORT_SLACK:
		return
	var query := PhysicsRayQueryParameters3D.create(from, global_position, TUNNEL_MASK, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var normal: Vector3 = hit.normal
	# Should be rare: say what sent it through, to find and fix the cause
	push_warning("%s crossed %s at %.0f m/s (from %s to %s), touching %s; put back" % [name, hit.collider.name,
		linear_velocity.length(), from.snapped(Vector3.ONE * 0.01), global_position.snapped(Vector3.ONE * 0.01),
		get_colliding_bodies().map(func(body: Node) -> String: return String(body.name))])
	global_position = hit.position + normal * (_radius() + 0.01)
	_last_position = global_position
	var into: float = linear_velocity.dot(normal)
	if into < 0.0:
		linear_velocity -= normal * into * (1.0 + TUNNEL_BOUNCE)


func _radius() -> float:
	for child: Node in get_children():
		if child is CollisionShape3D and child.shape is SphereShape3D:
			return child.shape.radius
	return 0.5


## A wall it just ran into sends it back out at WALL_BOUNCE of the speed it
## came in at, whatever the physics engine made of the hit.
func _bounce_off_walls(state: PhysicsDirectBodyState3D) -> void:
	for i in state.get_contact_count():
		var collider: Object = state.get_contact_collider_object(i)
		if not (collider is StaticBody3D or collider is GridMap):
			continue
		# Out of the wall: from where it touches to the ball's middle
		var normal: Vector3 = (state.transform.origin - state.get_contact_local_position(i)).normalized()
		if absf(normal.y) > 0.7:
			continue  # Floor, ramp or ceiling
		normal.y = 0.0
		normal = normal.normalized()
		var into: float = _last_velocity.dot(normal)
		if into >= -0.5:
			continue  # Already leaving it, or barely touching
		var velocity: Vector3 = state.linear_velocity
		velocity -= normal * velocity.dot(normal)
		state.linear_velocity = velocity - normal * into * WALL_BOUNCE
		return


# ===== NETWORK =====

## Online, on every machine: only the server's ball simulates physics; the
## others follow its updates. Call before the match starts syncing.
func setup_network() -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = not Net.is_server


func _send_state() -> void:
	if Net.is_server and Net.match_synced and not holder and _motion.should_send(global_transform):
		_net_state.rpc(NetInterpolator.now(), global_transform)


@rpc("authority", "unreliable_ordered")
func _net_state(time: float, xform: Transform3D) -> void:
	if holder:
		return  # Pinned to the holder locally
	_motion.push(time, xform)


## Hit or shoved by something (see Combat.push).
func receive_impulse(impulse: Vector3) -> void:
	if holder:
		return
	if Net.decides():
		_kick(impulse / mass)
	else:
		_request_push.rpc_id(Net.SERVER_ID, impulse)


@rpc("any_peer", "reliable")
func _request_push(impulse: Vector3) -> void:
	if Net.is_server:
		_kick(impulse / mass)


## Server/offline: a hit or shove sends it off at `velocity`, without
## stacking on speed it already has that way. Otherwise a player running into
## it (whose body already carries it along at their speed) and then hitting it
## would send it off at both speeds added up. Speed it has the other way, or
## sideways, is still met by the hit as before.
func _kick(velocity: Vector3) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var current: Vector3 = linear_velocity
	var result := Vector3(current.x, 0.0, current.z)
	if flat.length() > 0.01:
		var dir: Vector3 = flat.normalized()
		var along: float = result.dot(dir)
		result += dir * (max(along, flat.length()) - along) if along > 0.0 else flat
	result.y = max(current.y, velocity.y) if current.y > 0.0 and velocity.y > 0.0 else current.y + velocity.y
	linear_velocity = result


## `player` played the ball (shoved, shot or bumped it), so a goal now
## counts for their team. Passed on to whoever simulates the ball.
func touched_by(player: Node3D) -> void:
	if not player is PlayerClass3D:
		return
	if Net.decides():
		_set_last_team(String(player.name))
	elif Net.match_synced:
		_request_touch.rpc_id(Net.SERVER_ID, String(player.name))


@rpc("any_peer", "reliable")
func _request_touch(player_name: String) -> void:
	if Net.is_server:
		_set_last_team(player_name)


func _set_last_team(player_name: String) -> void:
	var player: PlayerClass3D = Global.Game3D.player_named(player_name) if Global.Game3D else null
	if player and player.slot:
		last_team = player.slot.team
		last_player = player_name
	# An Ablaze player's touch lights it (see PlayerStatus3D)
	if player and player.status and player.status.has_buff(&"ablaze"):
		_ignite(PlayerStatus3D.ABLAZE_BALL_BURN, player_name)


# ===== CARRYING =====

## `player` wants to pick the ball up. Online the server decides, so two
## players can't grab it at once.
func request_grab(player: PlayerClass3D) -> void:
	if holder:
		return
	if not Net.in_session():
		if _grab_cooldown <= 0.0:
			grab(player)
	elif Net.is_server:
		_decide_grab(player)  # A bot
	else:
		_request_grab.rpc_id(Net.SERVER_ID)


## `player` (the holder) lets go with this velocity, as a plain throw, a
## pass or an attack doing `damage` (see Shot).
func request_throw(player: PlayerClass3D, launch: Vector3, shot: Shot = Shot.NONE, damage: float = 0.0) -> void:
	if holder != player:
		return
	if not Net.in_session():
		release(launch)
		_start_shot(shot, String(player.name), damage)
	elif Net.is_server:
		_decide_throw(launch, shot, damage)  # A bot
	else:
		_request_throw.rpc_id(Net.SERVER_ID, launch, shot, damage)


func grab(player: PlayerClass3D) -> void:
	if holder:
		release(Vector3.ZERO)
	holder = player
	_shot = Shot.NONE
	if player.slot:
		last_team = player.slot.team
		last_player = String(player.name)
	_motion.clear()  # Play back from the release, not before the grab
	player.on_ball_grabbed(self)
	_curve_left = 0.0
	_free_collision_layer = collision_layer
	_free_collision_mask = collision_mask
	freeze = true
	collision_layer = 0
	collision_mask = 0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_follow_holder()


## Let go of the ball, flying off at `launch`.
func release(launch: Vector3) -> void:
	if not holder:
		return
	if is_instance_valid(holder):
		holder.on_ball_released(self)
	holder = null
	collision_layer = _free_collision_layer
	collision_mask = _free_collision_mask
	freeze = Net.in_session() and not Net.is_server
	if Net.decides():
		linear_velocity = launch
	_grab_cooldown = GRAB_COOLDOWN
	_motion.send_next()


## Carried out in front of the holder's chest.
func _follow_holder() -> void:
	if is_instance_valid(holder):
		global_position = holder.carry_point()


## Server/offline: let go everywhere (the holder died, or the ball's reset).
func _released_everywhere(launch: Vector3) -> void:
	if Net.match_synced:
		_released.rpc(launch)
	else:
		release(launch)


@rpc("any_peer", "reliable")
func _request_grab() -> void:
	if Net.is_server:
		_decide_grab(Global.Game3D.rpc_sender())


## Server: hand the ball to `player` if it's still free and in reach.
func _decide_grab(player: PlayerClass3D) -> void:
	if holder or _grab_cooldown > 0.0:
		return
	if player and player.can_grab_ball(self, PlayerClass3D.BALL_REACH + GRAB_REACH_SLACK):
		_grabbed.rpc(player.name)


@rpc("any_peer", "reliable")
func _request_throw(launch: Vector3, shot: Shot, damage: float) -> void:
	if Net.is_server and holder and holder.get_multiplayer_authority() == multiplayer.get_remote_sender_id():
		_decide_throw(launch, shot, damage)


## Server: the holder lets go, everywhere.
func _decide_throw(launch: Vector3, shot: Shot, damage: float) -> void:
	var by_name := String(holder.name)
	_released.rpc(launch)
	_start_shot(shot, by_name, damage)


@rpc("authority", "call_local", "reliable")
func _grabbed(player_name: String) -> void:
	var player: PlayerClass3D = Global.Game3D.player_named(player_name)
	if player:
		grab(player)


@rpc("authority", "call_local", "reliable")
func _released(launch: Vector3) -> void:
	release(launch)


func _on_body_entered(body: Node) -> void:
	if not Net.decides():
		return
	if body is ShieldClass3D and body.is_blocking and body.wielder:
		_shot = Shot.NONE
		_catch_on(body)
		_set_last_team(String(body.wielder.name))
		return
	if _shot != Shot.NONE and _shot_reached(body):
		return
	if body is PlayerClass3D and burn_left > 0.0:
		_burn_on_hit(body)
	if body is PlayerClass3D:
		_set_last_team(String(body.name))
	# Swung and thrown weapons play the ball through WeaponBehavior3D.hit_ball,
	# so touching one here does nothing extra.


# ===== PASSES & BALL ATTACKS =====

## Server/offline: the ball just left `by_name`'s hands as `shot`.
func _start_shot(shot: Shot, by_name: String, damage: float) -> void:
	_shot = shot
	_shot_by_name = by_name
	_shot_damage = damage
	_shot_left = SHOT_TIME if shot != Shot.NONE else 0.0


## Server/offline: a pass or attack ran into `body`. Returns whether it was
## caught (nothing else happens then).
func _shot_reached(body: Node) -> bool:
	var by: PlayerClass3D = Global.Game3D.player_named(_shot_by_name) if Global.Game3D else null
	if not by or body == by:
		return false
	if _shot == Shot.PASS:
		if body is PlayerClass3D and Combat.are_teammates(body, by) and body.can_grab_ball(self, INF):
			_shot = Shot.NONE
			_caught_by.call_deferred(body)  # Not mid-collision: grabbing freezes the body
			return true
	elif (body is PlayerClass3D or body is Boss3D or body is SlimeMinion3D or body is SkeletonEnemy3D or body is Tower3D) \
			and not Combat.are_teammates(body, by):
		_shot = Shot.NONE
		Combat.strike(body, linear_velocity, _shot_damage, ATTACK_KNOCKBACK, ATTACK_POP, -1.0, by)
	return false


func _caught_by(player: PlayerClass3D) -> void:
	if holder or not is_instance_valid(player) or not player.can_grab_ball(self, INF):
		return
	if Net.match_synced:
		_grabbed.rpc(player.name)
	else:
		grab(player)


# ===== WEAPON EFFECTS =====

## A weapon hit the ball (see WeaponBehavior3D.hit_ball): `velocity` is
## added to its own (see _kick), or replaces it if `exact`; `curve` pulls it sideways for
## a moment; above 0, `ignite_time` sets it burning.
func receive_weapon_hit(velocity: Vector3, exact: bool, curve: Vector3, ignite_time: float, attacker: Node3D) -> void:
	if holder:
		return
	if Net.decides():
		_apply_weapon_hit(velocity, exact, curve, ignite_time, _player_name(attacker))
	else:
		_request_weapon_hit.rpc_id(Net.SERVER_ID, velocity, exact, curve, ignite_time, _player_name(attacker))


@rpc("any_peer", "reliable")
func _request_weapon_hit(velocity: Vector3, exact: bool, curve: Vector3, ignite_time: float, attacker_name: String) -> void:
	if Net.is_server:
		_apply_weapon_hit(velocity, exact, curve, ignite_time, attacker_name)


func _apply_weapon_hit(velocity: Vector3, exact: bool, curve: Vector3, ignite_time: float, attacker_name: String) -> void:
	_set_last_team(attacker_name)
	if exact:
		linear_velocity = velocity
	else:
		_kick(velocity)
	_curve = curve
	_curve_left = CURVE_TIME if not curve.is_zero_approx() else 0.0
	if ignite_time > 0.0:
		_ignite(ignite_time, attacker_name)


## Turn it to fly along `dir` (flattened), at its current speed plus
## `boost`, or at least `min_speed`, rising at least `lift` (a magic bolt).
func redirect(dir: Vector3, min_speed: float, boost: float = 0.0, lift: float = 0.0) -> void:
	if holder:
		return
	if Net.decides():
		_apply_redirect(dir, min_speed, boost, lift)
	else:
		_request_redirect.rpc_id(Net.SERVER_ID, dir, min_speed, boost, lift)


@rpc("any_peer", "reliable")
func _request_redirect(dir: Vector3, min_speed: float, boost: float, lift: float) -> void:
	if Net.is_server:
		_apply_redirect(dir, min_speed, boost, lift)


func _apply_redirect(dir: Vector3, min_speed: float, boost: float, lift: float) -> void:
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	var flat_speed: float = Vector2(linear_velocity.x, linear_velocity.z).length()
	var vertical: float = max(linear_velocity.y, lift)
	linear_velocity = dir.normalized() * max(flat_speed + boost, min_speed) + Vector3.UP * vertical
	_curve_left = 0.0


## Server: a raised shield took the ball: it drops dead in front of it.
func _catch_on(shield: ShieldClass3D) -> void:
	var facing: Vector3 = shield.wielder.global_transform.basis.z
	facing.y = 0.0
	linear_velocity = facing.normalized() * CATCH_SPEED + Vector3.UP * CATCH_POP
	angular_velocity = Vector3.ZERO
	_curve_left = 0.0


func _update_curve(delta: float) -> void:
	if _curve_left <= 0.0:
		return
	linear_velocity += _curve * (_curve_left / CURVE_TIME) * delta
	_curve_left = max(_curve_left - delta, 0.0)


## Server/offline: set it burning for `duration` (or keep it burning, if
## longer), credited to `igniter_name`.
func _ignite(duration: float, igniter_name: String) -> void:
	_igniter_name = igniter_name
	var new_burn: float = max(burn_left, duration)
	if Net.match_synced:
		_net_burn.rpc(new_burn)
	else:
		_net_burn(new_burn)


@rpc("authority", "call_local", "reliable")
func _net_burn(duration: float) -> void:
	if burn_left <= 0.0 and duration > 0.0:
		Sfx.play(&"ignite", global_position)
	burn_left = duration


## Server/offline: a burning ball flying into someone hurts them (once in a
## while each, not every contact while it rolls against them).
func _burn_on_hit(player: PlayerClass3D) -> void:
	if linear_velocity.length() < BURN_HIT_MIN_SPEED:
		return
	var now: int = Time.get_ticks_msec()
	if now - _burned_msec.get(String(player.name), -BURN_HIT_COOLDOWN_MSEC) < BURN_HIT_COOLDOWN_MSEC:
		return
	_burned_msec[String(player.name)] = now
	Combat.strike(player, linear_velocity, BURN_HIT_DAMAGE, BURN_HIT_KNOCKBACK, 1.0, 0.0, _igniter())


func _igniter() -> PlayerClass3D:
	return Global.Game3D.player_named(_igniter_name) if Global.Game3D else null


func _player_name(node: Node3D) -> String:
	return String(node.name) if node is PlayerClass3D else ""


## Every machine: crackle while it burns.
func _update_burn_sound() -> void:
	if burn_left > 0.0 and not _burn_sound:
		_burn_sound = Sfx.play_loop(&"fire_loop", self)
	elif burn_left <= 0.0 and _burn_sound:
		_burn_sound.queue_free()
		_burn_sound = null


## Every machine: a flickering glow while it burns.
func _update_burn_light() -> void:
	_burn_light.visible = burn_left > 0.0
	if _burn_light.visible:
		_burn_light.light_energy = 1.5 * (0.75 + 0.25 * sin(Time.get_ticks_msec() / 1000.0 * 18.0))
