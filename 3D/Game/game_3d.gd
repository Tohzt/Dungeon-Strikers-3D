class_name Game3D_Class extends Node3D

signal set_camera_active(TorF: bool)

@export var player_scene: PackedScene
## How many players to seat automatically when no menu has joined anyone
## (controllers first, then keyboard/mouse). Set to 1 for single-player.
@export_range(1, 4) var default_player_count: int = 2
## Indexed by player slot; ordered to match the HUD corners (P1 left,
## P2 right, P3/P4 nearer the camera, i.e. the bottom of the screen).
@export var spawn_points: Array[Vector3] = [
	Vector3(-8, 1, 0), Vector3(8, 1, 0), Vector3(-8, 1, 6), Vector3(8, 1, 6),
]

@onready var ball: RigidBody3D = $Ball_3D
@onready var HUD: HUD3D = $HUD

var players: Array[PlayerClass3D] = []
## First player, kept for code that only knows about one.
var Player: PlayerClass3D:
	get: return players[0] if not players.is_empty() else null

func _enter_tree() -> void: Global.Game3D = self

func _ready() -> void:
	if Players.slots.is_empty():
		Players.join_default_devices(default_player_count)
	for slot: PlayerSlot in Players.slots:
		_spawn_player(slot)

	await get_tree().create_timer(3.0).timeout
	set_camera_active.emit(true)


func _spawn_player(slot: PlayerSlot) -> void:
	var player: PlayerClass3D = player_scene.instantiate()
	player.slot = slot
	player.name = "Player%d" % (slot.index + 1)
	player.position = spawn_points[slot.index % spawn_points.size()]
	add_child(player)
	players.append(player)

	# The scene's HUD serves the first player; the rest get copies.
	var hud: HUD3D = HUD if players.size() == 1 else HUD.duplicate()
	if hud != HUD:
		add_child(hud)
	hud.setup(player, slot)


func _process(_delta: float) -> void: pass


## Put the ball back at its starting spot, taking it from whoever holds it.
func reset_ball() -> void:
	if not ball: return
	for player: PlayerClass3D in players:
		if player.held_ball == ball:
			player.drop_ball()
	ball.global_position = ball.starting_position
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
