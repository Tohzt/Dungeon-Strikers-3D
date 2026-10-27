class_name FlyingCoin3D extends Node3D
## One coin flying into a player, Ready Player One style: it hops up off
## the ground, then curves into their chest, spinning, and speeds up as it
## goes. Back to back, a pile's coins stream in like a ribbon. Looks only:
## the coin was counted (PlayerClass3D.add_coins) when it set off, and the
## HUD leaves it out until it lands (PlayerClass3D.coins_in_flight).

## Seconds from leaving the ground to landing.
const FLIGHT_TIME := 0.42
## How high the hop goes, and how far off to the side, before it curves in.
const HOP_HEIGHT := Vector2(1.4, 2.6)
const HOP_SIDEWAYS := 1.1
## Where on the player it lands, above their feet.
const CHEST_HEIGHT := 1.2
const SPIN_SPEED := 22.0
const RADIUS := 0.2
const THICKNESS := 0.045
const GOLD := Color(1.0, 0.78, 0.22)

var _player: PlayerClass3D
var _start: Vector3
var _hop: Vector3
var _delay: float = 0.0
var _time: float = 0.0
var _spin: Node3D

static var _mesh: CylinderMesh


## Fly a coin from `from` into `player`, after `delay` seconds, under
## `parent` (the game, so it outlives the pile it came from).
static func launch(parent: Node, from: Vector3, player: PlayerClass3D, delay: float = 0.0) -> FlyingCoin3D:
	var coin := FlyingCoin3D.new()
	coin._player = player
	coin._start = from
	coin._delay = delay
	player.coins_in_flight += 1
	parent.add_child(coin)
	coin.global_position = from
	return coin


## A coin lying flat, for piles (shared looks with the flying ones).
static func make_mesh() -> MeshInstance3D:
	if not _mesh:
		_mesh = CylinderMesh.new()
		_mesh.top_radius = RADIUS
		_mesh.bottom_radius = RADIUS
		_mesh.height = THICKNESS
		_mesh.radial_segments = 16
		_mesh.rings = 1
		var material := StandardMaterial3D.new()
		material.albedo_color = GOLD
		material.metallic = 0.9
		material.roughness = 0.25
		material.emission_enabled = true
		material.emission = GOLD
		material.emission_energy_multiplier = 0.6
		_mesh.material = material
	var coin := MeshInstance3D.new()
	coin.mesh = _mesh
	coin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return coin


func _ready() -> void:
	# Stood on its edge, spinning like a flipped coin
	_spin = Node3D.new()
	add_child(_spin)
	var coin: MeshInstance3D = make_mesh()
	coin.rotation.x = PI / 2.0
	_spin.add_child(coin)
	var side: Vector3 = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() * HOP_SIDEWAYS
	_hop = _start + side + Vector3.UP * randf_range(HOP_HEIGHT.x, HOP_HEIGHT.y)
	visible = _delay <= 0.0


func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		queue_free()
		return
	if _delay > 0.0:
		_delay -= delta
		visible = _delay <= 0.0
		return
	_time += delta
	var t: float = minf(_time / FLIGHT_TIME, 1.0)
	# Slow off the ground, fast into the chest; the end follows the player
	var eased: float = t * t
	var target: Vector3 = _player.global_position + Vector3.UP * CHEST_HEIGHT
	var a: Vector3 = _start.lerp(_hop, eased)
	var b: Vector3 = _hop.lerp(target, eased)
	global_position = a.lerp(b, eased)
	_spin.rotate_y(SPIN_SPEED * delta)
	scale = Vector3.ONE * lerpf(1.0, 0.6, eased)
	if t >= 1.0:
		_land()


func _land() -> void:
	Sfx.play(&"coin", global_position, _player.coin_landed())
	queue_free()
