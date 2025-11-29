extends Node3D
@onready var ball: Node3D = $Ball_3D


func _ready() -> void: pass
func _process(_delta: float) -> void: pass


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		ball.global_position = ball.starting_position
