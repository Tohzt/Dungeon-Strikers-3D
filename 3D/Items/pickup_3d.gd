@tool
class_name Pickup3D extends Area3D
## Something a player takes by running through it, which then vanishes for
## `respawn_time`. Each one is a spawn point: drop its scene anywhere in the
## arena and move it around. Its model (see _model()) bobs and spins.
## Online the server decides who got it, so two players can't both take it.
## Subclasses say who may take it (_can_take) and what it gives (_give).

## Seconds before it reappears after being taken.
@export var respawn_time: float = 4.0

const BOB_HEIGHT := 0.15
const BOB_SPEED := 2.5
const SPIN_SPEED := 1.5

## Seconds left before it's back; 0 = ready to take.
var respawn_left: float = 0.0
var _bob_time: float = 0.0
var _model_rest_y: float = 0.0
## Online: waiting to hear whether the server gave it to us.
var _requested: bool = false


func _ready() -> void:
	_bob_time = randf() * TAU
	_model_rest_y = _model().position.y


## The part that bobs, spins, and hides while it respawns.
func _model() -> Node3D:
	return null


## Whether `player` would get anything from it.
func _can_take(_player: PlayerClass3D) -> bool:
	return true


## `player` took it. Called on their own machine only.
func _give(_player: PlayerClass3D) -> void:
	pass


func _physics_process(delta: float) -> void:
	var model: Node3D = _model()
	_bob_time += delta
	model.position.y = _model_rest_y + sin(_bob_time * BOB_SPEED) * BOB_HEIGHT
	model.rotate_y(SPIN_SPEED * delta)
	if Engine.is_editor_hint():
		return
	if respawn_left > 0.0:
		respawn_left = max(respawn_left - delta, 0.0)
		model.visible = respawn_left == 0.0
		return
	if _requested:
		return
	for body: Node3D in get_overlapping_bodies():
		var player := body as PlayerClass3D
		if player and not player.is_remote and _can_take(player):
			_request_take(player)
			return


func is_ready() -> bool:
	return respawn_left <= 0.0


func _request_take(player: PlayerClass3D) -> void:
	if not Net.in_session():
		_taken(player.name)
	elif Net.is_server:
		_taken.rpc(player.name)  # A bot
	else:
		_requested = true
		_ask_server.rpc_id(Net.SERVER_ID)


@rpc("any_peer", "reliable")
func _ask_server() -> void:
	if not Net.is_server:
		return
	var player: PlayerClass3D = Global.Game3D.rpc_sender()
	if player and is_ready():
		_taken.rpc(player.name)
	else:
		_refused.rpc_id(multiplayer.get_remote_sender_id())


## Offline, or server -> everyone: `player_name` got it. Their own machine
## applies it (see _give).
@rpc("authority", "call_local", "reliable")
func _taken(player_name: String) -> void:
	_requested = false
	respawn_left = respawn_time
	_model().visible = false
	var player: PlayerClass3D = Global.Game3D.player_named(player_name)
	if player and not player.is_remote:
		_give(player)


## Server -> asker: someone beat you to it.
@rpc("authority", "reliable")
func _refused() -> void:
	_requested = false
