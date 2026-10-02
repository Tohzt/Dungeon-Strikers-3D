class_name TorchClass3D extends WeaponClass3D
## Torch: a light, quick melee weapon that lights up the dungeon around
## whoever carries it. The flame and its light flicker while it's out.

@export var flicker_speed: float = 14.0
@export var flicker_amount: float = 0.25

@onready var flame_light: OmniLight3D = $FlameLight
@onready var flame: MeshInstance3D = $Flame

var _base_energy: float = 1.0
var _flicker_seed: float = 0.0


func _ready() -> void:
	super()
	_base_energy = flame_light.light_energy
	_flicker_seed = randf() * 100.0


func _process(delta: float) -> void:
	super(delta)
	var t: float = Time.get_ticks_msec() / 1000.0 * flicker_speed + _flicker_seed
	var flicker: float = (sin(t) + sin(t * 2.3 + 1.7) * 0.5) / 1.5
	flame_light.light_energy = _base_energy * (1.0 + flicker * flicker_amount)
	flame.scale = Vector3(1.0, 1.0 + flicker * flicker_amount, 1.0)
