class_name Ball3D extends RigidBody3D
## Online the server simulates the ball and streams where it is; players'
## hits and pushes are passed on to the server.

## Team (PlayerSlot.team) of the last player to play the ball, -1 = nobody
## yet. Kept by whoever simulates it; four-team goals credit this team.
var last_team: int = -1
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
const CATCH_SPEED := 1.5
const CATCH_POP := 1.0

func _ready() -> void:
	# Update collision mask to detect weapons and entities
	set_collision_mask_value(1, true)  # World
	set_collision_mask_value(2, true)  # Player
	set_collision_mask_value(3, true)  # Enemy
	set_collision_mask_value(4, true)  # Weapon
	
	# Connect body entered signal
	body_entered.connect(_on_body_entered)
	_burn_light = OmniLight3D.new()
	_burn_light.light_color = BURN_COLOR
	_burn_light.omni_range = 5.0
	_burn_light.visible = false
	add_child(_burn_light)


func _process(delta: float) -> void:
	if not Net.decides():
		_motion.play(self, delta)
	_update_burn_light()
	burn_left = max(burn_left - delta, 0.0)
	_update_burn_sound()


func _physics_process(delta: float) -> void:
	if not Net.decides():
		return  # The server's updates move it
	_update_curve(delta)
	_send_state()


# ===== NETWORK =====

## Online, on every machine: only the server's ball simulates physics; the
## others follow its updates. Call before the match starts syncing.
func setup_network() -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = not Net.is_server


func _send_state() -> void:
	if Net.is_server and Net.match_synced and _motion.should_send(global_transform):
		_net_state.rpc(NetInterpolator.now(), global_transform)


@rpc("authority", "unreliable_ordered")
func _net_state(time: float, xform: Transform3D) -> void:
	_motion.push(time, xform)


## Hit or shoved by something (see Combat.push).
func receive_impulse(impulse: Vector3) -> void:
	if Net.decides():
		apply_central_impulse(impulse)
	else:
		_request_push.rpc_id(Net.SERVER_ID, impulse)


@rpc("any_peer", "reliable")
func _request_push(impulse: Vector3) -> void:
	if Net.is_server:
		apply_central_impulse(impulse)


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


func _on_body_entered(body: Node) -> void:
	if not Net.decides():
		return
	if body is ShieldClass3D and body.is_blocking and body.wielder:
		_catch_on(body)
		_set_last_team(String(body.wielder.name))
		return
	if body is PlayerClass3D and burn_left > 0.0:
		_burn_on_hit(body)
	if body is PlayerClass3D:
		_set_last_team(String(body.name))
	# Swung and thrown weapons play the ball through WeaponBehavior3D.hit_ball,
	# so touching one here does nothing extra.


# ===== WEAPON EFFECTS =====

## A weapon hit the ball (see WeaponBehavior3D.hit_ball): `velocity` is
## added to its own, or replaces it if `exact`; `curve` pulls it sideways for
## a moment; above 0, `ignite_time` sets it burning.
func receive_weapon_hit(velocity: Vector3, exact: bool, curve: Vector3, ignite_time: float, attacker: Node3D) -> void:
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
	linear_velocity = velocity if exact else linear_velocity + velocity
	_curve = curve
	_curve_left = CURVE_TIME if not curve.is_zero_approx() else 0.0
	if ignite_time > 0.0:
		_ignite(ignite_time, attacker_name)


## Turn it to fly along `dir` (flattened), at its current speed or at least
## `min_speed`, keeping how it's rising or falling (the staff's bolt).
func redirect(dir: Vector3, min_speed: float) -> void:
	if Net.decides():
		_apply_redirect(dir, min_speed)
	else:
		_request_redirect.rpc_id(Net.SERVER_ID, dir, min_speed)


@rpc("any_peer", "reliable")
func _request_redirect(dir: Vector3, min_speed: float) -> void:
	if Net.is_server:
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
