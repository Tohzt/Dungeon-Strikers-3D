@tool
class_name BoostOrb3D extends Pickup3D
## A glowing blue orb that fills a player's boost (see PlayerClass3D.boost)
## when they run through it. A player with a full meter passes through
## without taking it.

## Boost given (the meter holds PlayerClass3D.BOOST_MAX = 100).
@export_range(1.0, 100.0) var amount: float = 25.0:
	set(value):
		amount = value
		if is_node_ready():
			_update_look()

## Orb radius at amount 25 and at 100.
const SMALL_RADIUS := 0.35
const BIG_RADIUS := 0.7

@onready var orb: MeshInstance3D = $Orb
@onready var light: OmniLight3D = $Orb/Light


func _ready() -> void:
	super._ready()
	_update_look()


func _update_look() -> void:
	var t: float = clamp((amount - 25.0) / 75.0, 0.0, 1.0)
	var radius: float = lerp(SMALL_RADIUS, BIG_RADIUS, t)
	orb.scale = Vector3.ONE * (radius / SMALL_RADIUS)
	light.omni_range = 2.0 + 3.0 * t


func _model() -> Node3D:
	return orb


func _can_take(player: PlayerClass3D) -> bool:
	return player.can_take_boost()


## The meter is the owner's to keep.
func _give(player: PlayerClass3D) -> void:
	player.add_boost(amount)
