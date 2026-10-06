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
## How rare (see WeaponRarity) the weapons it hands out are.
@export var rarity: WeaponRarity.Tier = WeaponRarity.Tier.COMMON

@onready var display_anchor: Marker3D = $WeaponDisplay
@onready var reach: Area3D = $Reach

var cooldown_left: float = 0.0
## A copy of the weapon for looks only: never processed, not in the physics world.
var _display: Node3D = null
## Names the weapons this stand gives out, the same on every machine.
var _given_count: int = 0
## Rarity of the weapon _take_stock() last handed out.
var _given_rarity: int = WeaponRarity.Tier.COMMON


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
	_display = _make_display_copy(weapon_scene, rarity)
	_display.visible = cooldown_left <= 0.0
	display_anchor.add_child(_display)


## A copy of `scene` for looks only: never processed, not in the physics
## world. Glows in `tier`'s rarity color.
func _make_display_copy(scene: PackedScene, tier: int) -> Node3D:
	var copy: Node3D = scene.instantiate()
	copy.process_mode = Node.PROCESS_MODE_DISABLED
	if copy is RigidBody3D:
		copy.freeze = true
	if not Engine.is_editor_hint():
		WeaponRarity.apply_glow(copy, tier)
	return copy


## Whether `player` could take this stand's weapon right now.
func can_give_to(player: PlayerClass3D) -> bool:
	return has_weapon_for(player) and reach.overlaps_body(player)


## Whether `player` could take a weapon here once in reach (bots use this to
## pick a stand to walk to): one they have a free hand for.
func has_weapon_for(player: PlayerClass3D) -> bool:
	return _is_stocked() and _may_take(player) and player.free_hand_for(_stock_grip()) != null


## Which hand(s) the weapon handed out here goes in.
func _stock_grip() -> Weapon3D.Grip:
	var weapon := _display as Weapon3D
	return weapon.grip if weapon else Weapon3D.Grip.EITHER_HAND


## Whether there's a weapon here ready to hand out.
func _is_stocked() -> bool:
	return weapon_scene != null and cooldown_left <= 0.0


## Whether `player` is allowed this stand's weapons at all. Anyone, here;
## altars limit it to their team.
func _may_take(_player: PlayerClass3D) -> bool:
	return true


## `player` pressed interact here. Returns whether they're getting (or, online,
## have asked for) the weapon. Right hand first, like picking one up.
func request_take(player: PlayerClass3D) -> bool:
	if not can_give_to(player):
		return false
	var is_left: bool = player.free_hand_for(_stock_grip())
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
	if not Net.is_server or not _is_stocked():
		return
	var player: PlayerClass3D = Global.Game3D.rpc_sender()
	if player and _may_take(player) and player.can_hold_grip(_stock_grip(), is_left):
		_given.rpc(player.name, is_left, _next_weapon_name())


## Offline, or server -> everyone: make the weapon, put it in the player's
## hand and start the cooldown.
@rpc("authority", "call_local", "reliable")
func _given(player_name: String, is_left: bool, weapon_name: String) -> void:
	var scene: PackedScene = _take_stock()
	var player: PlayerClass3D = Global.Game3D.player_named(player_name)
	if player and scene:
		_hand_weapon(scene, _given_rarity, player, is_left, weapon_name, display_anchor.global_transform)
	_after_given()


## Every machine: make a `scene` weapon named `weapon_name`, of rarity
## `tier`, at `from`, and put it in `player`'s hand.
func _hand_weapon(scene: PackedScene, tier: int, player: PlayerClass3D, is_left: bool, weapon_name: String, from: Transform3D) -> void:
	var weapon: Weapon3D = scene.instantiate()
	weapon.name = weapon_name
	Global.Game3D.add_weapon(weapon)
	weapon.name = weapon_name  # Its _ready renames it after its Properties
	weapon.set_rarity(tier)
	weapon.global_transform = from
	weapon.hand_to(player, is_left)


## The weapon on display is being handed out: empty the stand for the
## cooldown and return what to make.
func _take_stock() -> PackedScene:
	cooldown_left = _cooldown_after_take()
	if _display:
		_display.visible = false
	_given_rarity = rarity
	return weapon_scene


## Seconds the stand stays empty after its weapon is taken.
func _cooldown_after_take() -> float:
	return cooldown


## Runs on every machine once a weapon has been handed out.
func _after_given() -> void:
	pass
