extends Label3D

var move_speed: float = 50.0
var fade_speed: float = 1.0
var lifetime: float = 2.0
var elapsed_time: float = 0.0

func _ready() -> void:
	# Offset position upward
	position.y += randf_range(0.5, 1.0)
	# Make it billboard so it always faces camera
	billboard = BaseMaterial3D.BILLBOARD_ENABLED


func _process(delta: float) -> void:
	elapsed_time += delta
	position.y += move_speed * delta * 0.01  # Scale down for 3D
	_fade_out()
	

func _fade_out() -> void:
	var alpha := 1.0 - (elapsed_time / lifetime)
	modulate.a = alpha
	if elapsed_time >= lifetime or alpha <= 0:
		queue_free()
