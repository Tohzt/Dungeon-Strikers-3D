extends Node2D

@export var indicator: Node2D
var cast_duration: float = 0.0
var current_time: float = 0.0

func initialize(duration: float) -> void:
	cast_duration = duration
	current_time = 0.0
	indicator.scale = Vector2.ZERO
	z_index = Global.Layers.GROUND_EFFECTS
	
func _process(delta: float) -> void:
	if current_time < cast_duration:
		current_time += delta
		var progress: float = current_time / cast_duration
		indicator.scale = Vector2.ONE * progress
