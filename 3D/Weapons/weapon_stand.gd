@tool
class_name WeaponStand3D extends Node3D
## Shows off a weapon. A player in reach presses interact to take a fresh
## copy of it; the one on display then vanishes until the cooldown is over.
## Online the server decides who gets it, so two players can't both take it.

## Which weapon this stand hands out, e.g. sword_3d.tscn.
@export var weapon_scene: PackedScene:
	set(value):
		weapon_scene = value
		if is_node_ready():
			_build_display()
## Seconds before the stand can be used again after someone takes its weapon.
@export var cooldown: float = 5.0
## How fast the displayed weapon turns, in radians/sec.
@export var display_spin_speed: float = 1.0

@onready var display_anchor: Marker3D = $WeaponDisplay
@onready var reach: Area3D = $Reach

var cooldown_left: float = 0.0
## A copy of the weapon for looks only: never processed, not in the physics world.
var _display: Node3D = null
## Names the weapons this stand gives out, the same on every machine.
var _given_count: int = 0


func _ready() -> void:
	_build_display()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	display_anchor.rotate_y(display_spin_speed * delta)
	if cooldown_left > 0.0:
		cooldown_left = max(cooldown_left - delta, 0.0)
		if cooldown_left == 0.0 and _display:
			_display.visible = true


func _build_display() -> void:
	if _display:
		_display.queue_free()
		_display = null
	if not weapon_scene:
		return
	_display = weapon_scene.instantiate()
	_display.process_mode = Node.PROCESS_MODE_DISABLED
	if _display is RigidBody3D:
		_display.freeze = true
	_display.visible = cooldown_left <= 0.0
	display_anchor.add_child(_display)


## Whether `player` could take this stand's weapon right now.
func can_give_to(player: PlayerClass3D) -> bool:
	return weapon_scene != null and cooldown_left <= 0.0 and reach.overlaps_body(player) \
		and (not player.is_hand_occupied(false) or not player.is_hand_occupied(true))


## `player` pressed interact here. Returns whether they're getting (or, online,
## have asked for) the weapon. Right hand first, like picking one up.
func request_take(player: PlayerClass3D) -> bool:
	if not can_give_to(player):
		return false
	var is_left: bool = player.is_hand_occupied(false)
	if not Net.in_session():
		_given(player.name, is_left, _next_weapon_name())
	else:
		_request_take.rpc_id(Net.SERVER_ID, is_left)
	return true


func _next_weapon_name() -> String:
	_given_count += 1
	return "%s_Weapon%d" % [name, _given_count]


@rpc("any_peer", "reliable")
func _request_take(is_left: bool) -> void:
	if not Net.is_server or not weapon_scene or cooldown_left > 0.0:
		return
	var player: PlayerClass3D = Global.Game3D.player_of_peer(multiplayer.get_remote_sender_id())
	if player and not player.is_hand_occupied(is_left):
		_given.rpc(player.name, is_left, _next_weapon_name())


## Offline, or server -> everyone: make the weapon, put it in the player's
## hand and start the cooldown.
@rpc("authority", "call_local", "reliable")
func _given(player_name: String, is_left: bool, weapon_name: String) -> void:
	cooldown_left = cooldown
	if _display:
		_display.visible = false
	var player: PlayerClass3D = Global.Game3D.get_node_or_null(player_name) as PlayerClass3D
	if not player:
		return
	var weapon: Weapon3D = weapon_scene.instantiate()
	weapon.name = weapon_name
	Global.Game3D.add_weapon(weapon)
	weapon.name = weapon_name  # Its _ready renames it after its Properties
	weapon.global_transform = display_anchor.global_transform
	weapon.hand_to(player, is_left)
