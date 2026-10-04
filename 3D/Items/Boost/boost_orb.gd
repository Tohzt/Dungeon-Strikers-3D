@tool
class_name BoostOrb3D extends Area3D
## A glowing blue orb that fills a player's boost (see PlayerClass3D.boost)
## when they run through it, then vanishes for `respawn_time`. Each one is a
## spawn point: drop boost_orb.tscn anywhere in the arena and move it around.
## A player with a full meter passes through without taking it.
## Online the server decides who got it, so two players can't both take it.

## Boost given (the meter holds PlayerClass3D.BOOST_MAX = 100).
@export_range(1.0, 100.0) var amount: float = 25.0:
	set(value):
		amount = value
		if is_node_ready():
			_update_look()
## Seconds before it reappears after being taken.
@export var respawn_time: float = 4.0

const BOB_HEIGHT := 0.15
const BOB_SPEED := 2.5
const SPIN_SPEED := 1.5
## Orb radius at amount 25 and at 100.
const SMALL_RADIUS := 0.35
const BIG_RADIUS := 0.7

@onready var orb: MeshInstance3D = $Orb
@onready var light: OmniLight3D = $Orb/Light

## Seconds left before it's back; 0 = ready to take.
var respawn_left: float = 0.0
var _bob_time: float = 0.0
var _orb_rest_y: float = 0.0
## Online: waiting to hear whether the server gave it to us.
var _requested: bool = false


func _ready() -> void:
	_bob_time = randf() * TAU
	_orb_rest_y = orb.position.y
	_update_look()


func _update_look() -> void:
	var t: float = clamp((amount - 25.0) / 75.0, 0.0, 1.0)
	var radius: float = lerp(SMALL_RADIUS, BIG_RADIUS, t)
	orb.scale = Vector3.ONE * (radius / SMALL_RADIUS)
	light.omni_range = 2.0 + 3.0 * t


func _physics_process(delta: float) -> void:
	_bob_time += delta
	orb.position.y = _orb_rest_y + sin(_bob_time * BOB_SPEED) * BOB_HEIGHT
	orb.rotate_y(SPIN_SPEED * delta)
	if Engine.is_editor_hint():
		return
	if respawn_left > 0.0:
		respawn_left = max(respawn_left - delta, 0.0)
		orb.visible = respawn_left == 0.0
		return
	if _requested:
		return
	for body: Node3D in get_overlapping_bodies():
		var player := body as PlayerClass3D
		if player and not player.is_remote and player.can_take_boost():
			_request_take(player)
			return


func is_ready() -> bool:
	return respawn_left <= 0.0


func _request_take(player: PlayerClass3D) -> void:
	if not Net.in_session():
		_taken(player.name)
	else:
		_requested = true
		_ask_server.rpc_id(Net.SERVER_ID)


@rpc("any_peer", "reliable")
func _ask_server() -> void:
	if not Net.is_server:
		return
	var player: PlayerClass3D = Global.Game3D.player_of_peer(multiplayer.get_remote_sender_id())
	if player and is_ready():
		_taken.rpc(player.name)
	else:
		_refused.rpc_id(multiplayer.get_remote_sender_id())


## Offline, or server -> everyone: `player_name` got it. Their own machine
## adds the boost (the meter is the owner's to keep).
@rpc("authority", "call_local", "reliable")
func _taken(player_name: String) -> void:
	_requested = false
	respawn_left = respawn_time
	orb.visible = false
	var player: PlayerClass3D = Global.Game3D.get_node_or_null(player_name) as PlayerClass3D
	if player and not player.is_remote:
		player.add_boost(amount)


## Server -> asker: someone beat you to it.
@rpc("authority", "reliable")
func _refused() -> void:
	_requested = false
