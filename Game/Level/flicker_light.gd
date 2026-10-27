class_name FlickerLight3D extends OmniLight3D
## A torch-like light: its brightness wobbles a little around where it was set.

## How far the energy strays from its starting value (0.2 = up to 20%).
@export_range(0.0, 1.0) var flicker_amount: float = 0.2
@export var flicker_speed: float = 9.0

@onready var _base_energy: float = light_energy
var _time: float = randf() * 100.0


func _process(delta: float) -> void:
	_time += delta * flicker_speed
	var wobble: float = sin(_time) * 0.5 + sin(_time * 2.3 + 1.7) * 0.3 + sin(_time * 5.1) * 0.2
	light_energy = _base_energy * (1.0 + wobble * flicker_amount)
