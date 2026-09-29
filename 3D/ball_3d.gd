class_name Ball3D extends RigidBody3D
## Online the server simulates the ball and streams where it is; players ask
## the server to grab, throw or push it. Every machine pins a held ball to
## its holder's hand itself, so holding looks smooth for everyone.
@onready var starting_position: Vector3 = self.global_position

var max_ball_speed: float = 600.0 
var knockback_strength: float = 5.5
var min_velocity_for_knockback: float = 150.0

# Color settings
var color_slow: Color = Color.GREEN
var color_medium: Color = Color.YELLOW
var color_fast: Color = Color.ORANGE
var color_max: Color = Color.RED
var color_cur: Color = Color.RED
var speed_medium_threshold: float = max_ball_speed * 0.3
var speed_fast_threshold: float = max_ball_speed * 0.6

@onready var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D")

## Whether players can pick the ball up. Off for now; meant to be switched
## on during the phases of a session that use it.
@export var can_be_picked_up: bool = false

## Who has the ball in hand, if anyone. Set on every machine.
var holder: PlayerClass3D = null
var holder_hand_is_left: bool = false
var _free_collision_layer: int = 0
var _free_collision_mask: int = 0

## Server: after a throw nobody can grab the ball for a moment, so the
## thrower's grab request (sent before they saw the throw) doesn't catch it.
const GRAB_COOLDOWN := 0.3
var _grab_cooldown: float = 0.0
## Client: don't ask the server again every frame we're touching the ball.
const REQUEST_RETRY_MSEC := 250
var _next_request_msec: int = 0
var _last_sent_transform: Transform3D
var _last_sent_msec: int = 0
## Clients: the server's recent updates, played back smoothly.
var _net_motion: NetInterpolator = null

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


func _process(delta: float) -> void:
	if _net_motion and not holder:
		var sample: Array = _net_motion.sample(delta)
		if not sample.is_empty():
			global_transform = sample[0]
	if mesh_instance:
		var material: StandardMaterial3D = mesh_instance.get_surface_override_material(0)
		if not material:
			material = StandardMaterial3D.new()
			mesh_instance.set_surface_override_material(0, material)
		material.albedo_color = color_cur


func _physics_process(delta: float) -> void:
	if not _simulates():
		return  # The server's updates move and color it
	_grab_cooldown = max(_grab_cooldown - delta, 0.0)
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


# ===== HOLDING =====

## `player` touched the ball with a free hand. Online the server decides, so
## two players can't grab it at once.
func request_grab(player: PlayerClass3D, is_left: bool) -> void:
	if holder or not can_be_picked_up:
		return
	if not Net.in_session():
		grab(player, is_left)
	elif Time.get_ticks_msec() >= _next_request_msec:
		_next_request_msec = Time.get_ticks_msec() + REQUEST_RETRY_MSEC
		_request_grab.rpc_id(Net.SERVER_ID, is_left)


## `player` (the holder) lets go with this impulse.
func request_throw(player: PlayerClass3D, impulse: Vector3) -> void:
	if holder != player:
		return
	if not Net.in_session():
		release(impulse)
	else:
		_request_throw.rpc_id(Net.SERVER_ID, impulse)


func grab(player: PlayerClass3D, is_left: bool) -> void:
	if holder:
		release(Vector3.ZERO)
	holder = player
	holder_hand_is_left = is_left
	if _net_motion:
		_net_motion.clear()  # Play back from the release, not before the grab
	player.held_ball = self
	player.held_ball_hand_is_left = is_left
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
func _request_grab(is_left: bool) -> void:
	if not Net.is_server or holder or not can_be_picked_up or _grab_cooldown > 0.0:
		return
	var player: PlayerClass3D = Global.Game3D.player_of_peer(multiplayer.get_remote_sender_id())
	if player and not player.is_hand_occupied(is_left):
		_grabbed.rpc(player.name, is_left)


@rpc("any_peer", "reliable")
func _request_throw(impulse: Vector3) -> void:
	if Net.is_server and holder and holder.get_multiplayer_authority() == multiplayer.get_remote_sender_id():
		_released.rpc(impulse)


@rpc("authority", "call_local", "reliable")
func _grabbed(player_name: String, is_left: bool) -> void:
	var player: PlayerClass3D = Global.Game3D.get_node_or_null(player_name) as PlayerClass3D
	if player:
		grab(player, is_left)


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
	if body is PlayerClass3D:
		var player: PlayerClass3D = body as PlayerClass3D
		# Check if it has EB (EntityBehavior3D)
		if player.Entity:
			var ball_speed: float = linear_velocity.length()
			var ball_to_player: Vector3 = (player.global_position - global_position).normalized()
			
			var effective_min_velocity: float = min_velocity_for_knockback
			
			if ball_speed > effective_min_velocity:
				var knockback_force: float = ball_speed * knockback_strength
				# Apply knockback
				player.shove(ball_to_player, knockback_force)
	
	# Handle weapon/projectile collisions to move the ball
	if body.is_in_group("Weapon") and body is Weapon3D:
		var weapon: Weapon3D = body
		if weapon.Properties:
			var weapon_damage: float = weapon.Properties.weapon_damage
			var weapon_velocity: Vector3 = weapon.linear_velocity
			
			# For melee attacks (held weapons with no velocity), calculate knockback differently
			var impact_force: Vector3
			if weapon_velocity.length() < 10.0:  # Very low velocity = held weapon
				# Calculate direction from weapon to ball
				var knockback_direction: Vector3 = (global_position - weapon.global_position).normalized()
				# Use damage-based knockback force for melee
				impact_force = knockback_direction * weapon_damage * 50.0
			else:
				# For projectiles, use velocity-based knockback
				impact_force = weapon_velocity * weapon_damage
			
			apply_central_impulse(impact_force)
