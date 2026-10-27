extends Node

var Game3D: Game3D_Class

var input_type: String = "Keyboard"


func _input(event: InputEvent) -> void:
	##TODO: Update for Multiplayer/Server
	if event is InputEventFromWindow:
		input_type = "Keyboard"
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		input_type = "Controller"
