class_name Ball3D extends RigidBody3D
## Online the server simulates the ball and streams where it is; players ask
## the server to grab, throw or push it. Every machine pins a held ball to
## its holder's hands itself, so holding looks smooth for everyone.

var max_ball_speed: float = 600.0 
var knockback_strength: float = 5.5
var min_velocity_for_knockback: float = 150.0

# Color settings
var color_slow: Color = Color.GREEN
var color_medium: Color = Color.YELLOW
var color_fast: Color = Color.ORANGE
var color_max: Color = Color.RED
var color_cur: Color = Color.RED
## Colors the mesh by speed (and the burn glow). Off for drops with their
## own look, like the skull.
var tint_by_speed: bool = true
var speed_medium_threshold: float = max_ball_speed * 0.3
var speed_fast_threshold: float = max_ball_speed * 0.6

@onready var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D")

## Who has the ball in hand, if anyone. Set on every machine.
var holder: PlayerClass3D = null
## Team (PlayerSlot.team) of the last player to play the ball, -1 = nobody
## yet. Kept by whoever simulates it; four-team goals credit this team.
var last_team: int = -1
var _free_collision_layer: int = 0
var _free_collision_mask: int = 0

## Server: after a throw nobody can grab the ball for a moment, so the
## thrower's grab request (sent before they saw the throw) doesn't catch it.
const GRAB_COOLDOWN := 0.3
var _grab_cooldown: float = 0.0
## Server: extra reach allowed on a client's grab, since it saw the ball
## (and the server saw the player) a little in the past.
const GRAB_REACH_SLACK := 1.0
var _last_sent_transform: Transform3D
var _last_sent_msec: int = 0
## Clients: the server's recent updates, played back smoothly.
var _net_motion: NetInterpolator = null

# Weapon effects (see WeaponBehavior3D.hit_ball). Online the server applies
# them, like every push.
## Curve: a sideways pull after an axe hook, fading out over CURVE_TIME.
const CURVE_TIME := 0.8
var _curve: Vector3 = Vector3.ZERO
var _curve_left: float = 0.0
## Burning (lit by a torch): whoever holds it takes BURN_HOLD_DPS, and a fast
## burning ball hurts whoever it hits. Known on every machine, for the flames.
const BURN_HOLD_DPS := 10.0
const BURN_TICK := 0.5
const BURN_HIT_DAMAGE := 15.0
const BURN_HIT_KNOCKBACK := 4.0
const BURN_HIT_MIN_SPEED := 4.0
const BURN_HIT_COOLDOWN_MSEC := 500
const BURN_COLOR := Color(1.0, 0.45, 0.05)
var burn_left: float = 0.0
var _igniter_name: String = ""
var _burn_tick: float = 0.0
var _burned_msec: Dictionary[String, int] = {}
var _burn_light: OmniLight3D = null
## A raised shield catches it: dropped just in front of the shield.
const CATCH_SPEED := 1.5
const CATCH_POP := 1.0

func _ready() -> void:
	# Find mesh instance if not directly named
	if not mesh_instance:
		mesh_instance = get_node_or_null("MeshInstance3D")
		if not mesh_instance:
			# Try to find any MeshInstance3D child
			for child in get_children():
				if child is MeshInstance3D:
					mesh_instance = child
					break
	
	# Update collision mask to detect weapons and entities
	set_collision_mask_value(1, true)  # World
	set_collision_mask_value(2, true)  # Player
	set_collision_mask_value(3, true)  # Enemy
	set_collision_mask_value(4, true)  # Weapon
	
	# Connect body entered signal
	body_entered.connect(_on_body_entered)
	_update_ball_color(0)
	_burn_light = OmniLight3D.new()
	_burn_light.light_color = BURN_COLOR
	_burn_light.omni_range = 5.0
	_burn_light.visible = false
	add_child(_burn_light)


func _process(delta: float) -> void:
	if _net_motion and not holder:
		var sample: Array = _net_motion.sample(delta)
		if not sample.is_empty():
			global_transform = sample[0]
	if mesh_instance and tint_by_speed:
		var material: StandardMaterial3D = mesh_instance.get_surface_override_material(0)
		if not material:
			material = StandardMaterial3D.new()
			mesh_instance.set_surface_override_material(0, material)
		material.albedo_color = color_cur
		_update_burn_visual(material)
	else:
		_burn_light.visible = burn_left > 0.0
	burn_left = max(burn_left - delta, 0.0)


func _physics_process(delta: float) -> void:
	if not _simulates():
		return  # The server's updates move and color it
	_grab_cooldown = max(_grab_cooldown - delta, 0.0)
	_update_curve(delta)
	_update_burn_damage(delta)
	if linear_velocity.length() > max_ball_speed:
		linear_velocity = linear_velocity.normalized() * max_ball_speed
	_update_ball_color(linear_velocity.length())
	_send_state()


# ===== NETWORK =====

## Online, on every machine: only the server's ball simulates physics; the
## others follow its updates. Call before the match starts syncing.
func setup_network() -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = not Net.is_server
	if not Net.is_server:
		_net_motion = NetInterpolator.new()


## Whether this machine runs the ball's physics.
func _simulates() -> bool:
	return not Net.in_session() or Net.is_server


func _send_state() -> void:
	if not Net.is_server or not Net.match_synced or holder:
		return
	var now_msec: int = Time.get_ticks_msec()
	if global_transform.is_equal_approx(_last_sent_transform) \
			and now_msec - _last_sent_msec < NetInterpolator.RESEND_IDLE_MSEC:
		return  # Resting - nothing new to tell anyone
	_last_sent_transform = global_transform
	_last_sent_msec = now_msec
	_net_state.rpc(NetInterpolator.now(), global_transform, color_cur)


@rpc("authority", "unreliable_ordered")
func _net_state(time: float, xform: Transform3D, color: Color) -> void:
	if holder:
		return  # Pinned to the holder's hand locally
	_net_motion.push(time, xform)
	color_cur = color


## Hit or shoved by something (see Combat.push).
func receive_impulse(impulse: Vector3) -> void:
	if holder:
		return
	if _simulates():
		apply_central_impulse(impulse)
	else:
		_request_push.rpc_id(Net.SERVER_ID, impulse)


@rpc("any_peer", "reliable")
func _request_push(impulse: Vector3) -> void:
	if Net.is_server and not holder:
		apply_central_impulse(impulse)


## `player` played the ball (shoved, shot or bumped it), so a goal now
## counts for their team. Passed on to whoever simulates the ball.
func touched_by(player: Node3D) -> void:
	if not player is PlayerClass3D:
		return
	if _simulates():
		_set_last_team(String(player.name))
	elif Net.match_synced:
		_request_touch.rpc_id(Net.SERVER_ID, String(player.name))


@rpc("any_peer", "reliable")
func _request_touch(player_name: String) -> void:
	if Net.is_server:
		_set_last_team(player_name)


func _set_last_team(player_name: String) -> void:
	var player: PlayerClass3D = Global.Game3D.get_node_or_null(player_name) as PlayerClass3D if Global.Game3D else null
	if player and player.slot:
		last_team = player.slot.team


# ===== HOLDING =====

## `player` pressed interact near the ball with both hands free. Online the
## server decides, so two players can't grab it at once.
func request_grab(player: PlayerClass3D) -> void:
	if holder:
		return
	if not Net.in_session():
		grab(player)
	else:
		_request_grab.rpc_id(Net.SERVER_ID)


## `player` (the holder) lets go with this impulse.
func request_throw(player: PlayerClass3D, impulse: Vector3) -> void:
	if holder != player:
		return
	if not Net.in_session():
		release(impulse)
	else:
		_request_throw.rpc_id(Net.SERVER_ID, impulse)


func grab(player: PlayerClass3D) -> void:
	if holder:
		release(Vector3.ZERO)
	holder = player
	if player.slot:
		last_team = player.slot.team
	if _net_motion:
		_net_motion.clear()  # Play back from the release, not before the grab
	player.held_ball = self
	_curve_left = 0.0
	# Freeze the ball's physics and disable collision while it's carried
	_free_collision_layer = collision_layer
	_free_collision_mask = collision_mask
	freeze = true
	collision_layer = 0
	collision_mask = 0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	player.update_held_ball_position()


## Drop the ball from the holder's hand, launching it with `impulse`.
func release(impulse: Vector3) -> void:
	if not holder:
		return
	if is_instance_valid(holder) and holder.held_ball == self:
		holder.held_ball = null
	holder = null
	collision_layer = _free_collision_layer
	collision_mask = _free_collision_mask
	freeze = not _simulates()
	if _simulates():
		apply_impulse(impulse)
	_grab_cooldown = GRAB_COOLDOWN
	_last_sent_transform = Transform3D()


@rpc("any_peer", "reliable")
func _request_grab() -> void:
	if not Net.is_server or holder or _grab_cooldown > 0.0:
		return
	var player: PlayerClass3D = Global.Game3D.player_of_peer(multiplayer.get_remote_sender_id())
	if player and player.can_grab_ball(self, PlayerClass3D.BALL_REACH + GRAB_REACH_SLACK):
		_grabbed.rpc(player.name)


@rpc("any_peer", "reliable")
func _request_throw(impulse: Vector3) -> void:
	if Net.is_server and holder and holder.get_multiplayer_authority() == multiplayer.get_remote_sender_id():
		_released.rpc(impulse)


@rpc("authority", "call_local", "reliable")
func _grabbed(player_name: String) -> void:
	var player: PlayerClass3D = Global.Game3D.get_node_or_null(player_name) as PlayerClass3D
	if player:
		grab(player)


@rpc("authority", "call_local", "reliable")
func _released(impulse: Vector3) -> void:
	release(impulse)


func _update_ball_color(speed: float) -> void:
	var new_color: Color
	if speed < speed_medium_threshold:
		var t: float = speed / speed_medium_threshold
		new_color = color_slow.lerp(color_medium, t)
	elif speed < speed_fast_threshold:
		var t: float = (speed - speed_medium_threshold) / (speed_fast_threshold - speed_medium_threshold)
		new_color = color_medium.lerp(color_fast, t)
	else:
		var t: float = (speed - speed_fast_threshold) / (max_ball_speed - speed_fast_threshold)
		t = min(t, 1.0)  
		new_color = color_fast.lerp(color_max, t)
	
	color_cur = new_color


func _on_body_entered(body: Node) -> void:
	if not _simulates():
		return
	if body is ShieldClass3D and body.is_blocking and body.wielder:
		_catch_on(body)
		_set_last_team(String(body.wielder.name))
		return
	if body is PlayerClass3D and burn_left > 0.0:
		_burn_on_hit(body)
	if body is PlayerClass3D:
		var player: PlayerClass3D = body as PlayerClass3D
		_set_last_team(String(player.name))
		# Check if it has EB (EntityBehavior3D)
		if player.Entity:
			var ball_speed: float = linear_velocity.length()
			var ball_to_player: Vector3 = (player.global_position - global_position).normalized()
			
			var effective_min_velocity: float = min_velocity_for_knockback
			
			if ball_speed > effective_min_velocity:
				var knockback_force: float = ball_speed * knockback_strength
				# Apply knockback
				player.shove(ball_to_player, knockback_force)
	# Swung and thrown weapons play the ball through WeaponBehavior3D.hit_ball,
	# so touching one here does nothing extra.


# ===== WEAPON EFFECTS =====

## A weapon hit the ball (see WeaponBehavior3D.hit_ball): `velocity` is
## added to its own, or replaces it if `exact`; `curve` pulls it sideways for
## a moment; above 0, `ignite_time` sets it burning.
func receive_weapon_hit(velocity: Vector3, exact: bool, curve: Vector3, ignite_time: float, attacker: Node3D) -> void:
	if holder:
		return
	if _simulates():
		_apply_weapon_hit(velocity, exact, curve, ignite_time, _player_name(attacker))
	else:
		_request_weapon_hit.rpc_id(Net.SERVER_ID, velocity, exact, curve, ignite_time, _player_name(attacker))


@rpc("any_peer", "reliable")
func _request_weapon_hit(velocity: Vector3, exact: bool, curve: Vector3, ignite_time: float, attacker_name: String) -> void:
	if Net.is_server and not holder:
		_apply_weapon_hit(velocity, exact, curve, ignite_time, attacker_name)


func _apply_weapon_hit(velocity: Vector3, exact: bool, curve: Vector3, ignite_time: float, attacker_name: String) -> void:
	_set_last_team(attacker_name)
	linear_velocity = velocity if exact else linear_velocity + velocity
	_curve = curve
	_curve_left = CURVE_TIME if not curve.is_zero_approx() else 0.0
	if ignite_time > 0.0:
		_ignite(ignite_time, attacker_name)


## Turn it to fly along `dir` (flattened), at its current speed or at least
## `min_speed`, keeping how it's rising or falling (the staff's bolt).
func redirect(dir: Vector3, min_speed: float) -> void:
	if holder:
		return
	if _simulates():
		_apply_redirect(dir, min_speed)
	else:
		_request_redirect.rpc_id(Net.SERVER_ID, dir, min_speed)


@rpc("any_peer", "reliable")
func _request_redirect(dir: Vector3, min_speed: float) -> void:
	if Net.is_server and not holder:
		_apply_redirect(dir, min_speed)


func _apply_redirect(dir: Vector3, min_speed: float) -> void:
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	var flat_speed: float = Vector2(linear_velocity.x, linear_velocity.z).length()
	var vertical: float = linear_velocity.y
	linear_velocity = dir.normalized() * max(flat_speed, min_speed) + Vector3.UP * vertical
	_curve_left = 0.0


## Server: a raised shield took the ball: it drops dead in front of it.
func _catch_on(shield: ShieldClass3D) -> void:
	var facing: Vector3 = shield.wielder.global_transform.basis.z
	facing.y = 0.0
	linear_velocity = facing.normalized() * CATCH_SPEED + Vector3.UP * CATCH_POP
	angular_velocity = Vector3.ZERO
	_curve_left = 0.0


func _update_curve(delta: float) -> void:
	if _curve_left <= 0.0 or holder:
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
	burn_left = duration


## Server/offline: burn whoever holds it, a tick at a time.
func _update_burn_damage(delta: float) -> void:
	if burn_left <= 0.0 or not holder:
		_burn_tick = 0.0
		return
	_burn_tick -= delta
	if _burn_tick <= 0.0:
		_burn_tick = BURN_TICK
		holder.receive_burn(BURN_HOLD_DPS * BURN_TICK, _igniter())


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
	if _igniter_name == "" or not Global.Game3D:
		return null
	return Global.Game3D.get_node_or_null(_igniter_name) as PlayerClass3D


func _player_name(node: Node3D) -> String:
	return String(node.name) if node is PlayerClass3D else ""


## Every machine: glow and flicker while it burns.
func _update_burn_visual(material: StandardMaterial3D) -> void:
	var burning: bool = burn_left > 0.0
	_burn_light.visible = burning
	material.emission_enabled = burning
	if not burning:
		return
	var flicker: float = 0.75 + 0.25 * sin(Time.get_ticks_msec() / 1000.0 * 18.0)
	material.albedo_color = color_cur.lerp(BURN_COLOR, 0.7)
	material.emission = BURN_COLOR
	material.emission_energy_multiplier = 2.0 * flicker
	_burn_light.light_energy = 1.5 * flicker
