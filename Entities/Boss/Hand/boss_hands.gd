extends Node2D
@onready var Master: BossClass = get_parent()
@onready var Left: BossHandClass = $"Left Hand"
@onready var Right: BossHandClass = $"Right Hand"

var angle: float = deg_to_rad(10)
var angle_low: float = angle
var angle_high: float = deg_to_rad(30)
var freq: float = 1.0
var freq_low: float = freq
var freq_high: float = 30.0

var time_elapsed: float = 0.0
var sin_value: float = 0.0
var cos_value: float = 0.0

func _process(delta: float) -> void:
	if !multiplayer.is_server(): return
	_wave_calculator(delta * freq_low)
	_update_wave(delta)
	_update_sway()

func _update_wave(delta: float) -> void:
	if Master.velocity.length() > 200:
		freq = lerp(freq, freq_high, delta)
		angle = lerp(angle, angle_high, delta)
	else:
		freq = lerp(freq, freq_low, delta*10)
		angle = lerp(angle, angle_low, delta)

func _update_sway() -> void:
	if !Left.is_attacking:
		Left.rotation = angle * sin_value
	if !Right.is_attacking:
		Right.rotation = angle * sin_value

func _wave_calculator(delta: float) -> void:
	time_elapsed += delta * freq
	sin_value = sin(time_elapsed)
	cos_value = cos(time_elapsed)
