extends Label

var move_speed: float = 50.0
var fade_speed: float = 1.0
var lifetime: float = 2.0
var elapsed_time: float = 0.0

func _ready() -> void:
	z_index = Global.Layers.HUD
	position.y -= randi_range(20,40)


func _process(delta: float) -> void:
	elapsed_time += delta
	position.y -= move_speed * delta
	_fade_out()
	

func _fade_out() -> void:
	var alpha := 1.0 - (elapsed_time / lifetime)
	modulate.a = alpha
	if elapsed_time >= lifetime or alpha <= 0:
		queue_free()
