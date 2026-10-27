@tool
class_name PotionPickup3D extends Pickup3D
## A small potion lying about, popped out of a chest or an item box (see
## pop): whoever runs through it first drinks it on the spot (see
## Potion.drink). Good for one drink; it goes after LIFETIME if nobody does.
##
## Every machine makes it, named the same, from what the deciding machine
## said popped out; taking it goes through the server like any Pickup3D.

## Seconds the pop takes, from where it came out to the floor.
const POP_TIME := 0.55
const POP_HEIGHT := 2.2
## Seconds it lies there before it's gone.
const LIFETIME := 45.0
const REACH := 0.9

## Which small potion (Potion.SMALL).
var kind: int = 0
var _flask: Node3D
var _landed: bool = false
var _age: float = 0.0


## Every machine: potion `kind_` pops out of `from` and lands at `to`.
static func pop(parent: Node, pickup_name: String, kind_: int, from: Vector3, to: Vector3) -> PotionPickup3D:
	var pickup := PotionPickup3D.new()
	pickup.name = pickup_name
	pickup.kind = kind_
	parent.add_child(pickup)
	pickup._fly(from, GroundPatch3D._floor_under(pickup, to))
	return pickup


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # Players
	monitorable = false
	var reach := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = REACH
	reach.shape = sphere
	reach.position.y = 0.5
	add_child(reach)
	var potion: Dictionary = Potion.small(kind)
	_flask = Node3D.new()
	_flask.position.y = 0.25
	_flask.add_child(Potion.model(potion.shape, potion.color, Potion.SMALL_HEIGHT))
	var glow := OmniLight3D.new()
	glow.light_color = potion.color
	glow.light_energy = 0.6
	glow.omni_range = 2.0
	glow.position.y = 0.3
	_flask.add_child(glow)
	add_child(_flask)
	super._ready()


func _fly(from: Vector3, to: Vector3) -> void:
	global_position = from
	var tween: Tween = create_tween().set_parallel()
	tween.tween_method(func(t: float) -> void:
		global_position = from.lerp(to, t) + Vector3.UP * POP_HEIGHT * 4.0 * t * (1.0 - t), 0.0, 1.0, POP_TIME)
	tween.chain().tween_callback(func() -> void: _landed = true)


func _model() -> Node3D:
	return _flask


func _can_take(_player: PlayerClass3D) -> bool:
	return _landed


func _on_taken(player: PlayerClass3D) -> void:
	if player:
		Potion.drink(player, kind)
		if Global.Game3D and player.is_local_person():
			Global.Game3D.scoreboard.announce(Potion.small(kind).title, Potion.small(kind).color)
	queue_free()


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
	elif _age >= LIFETIME - 3.0:
		_flask.visible = fmod(_age * 8.0, 1.0) < 0.6  # Blinks out
