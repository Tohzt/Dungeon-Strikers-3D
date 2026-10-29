extends Node

var Game3D: Game3D_Class

var input_type: String = "Keyboard"


func _ready() -> void:
	# Exports start fullscreen from project settings. Editor runs start windowed so the
	# Game tab can embed them; a run that isn't embedded goes fullscreen here instead.
	if OS.has_feature("editor") and not Engine.is_embedded_in_editor():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _input(event: InputEvent) -> void:
	##TODO: Update for Multiplayer/Server
	if event is InputEventFromWindow:
		input_type = "Keyboard"
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		input_type = "Controller"
