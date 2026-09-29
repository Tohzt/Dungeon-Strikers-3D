extends Node

var Game3D: Game3D_Class

const DISPLAY_DAMAGE_3D: PackedScene = preload("res://3D/HUD/display_damage_3d.tscn")

var input_type: String = "Keyboard"


func _input(event: InputEvent) -> void:
	##TODO: Update for Multiplayer/Server
	if event is InputEventFromWindow:
		input_type = "Keyboard"
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		input_type = "Controller"

func display_damage_3d(damage: float, position: Vector3) -> void:
	# Spawn a 3D damage display label at the given position
	var damage_label := DISPLAY_DAMAGE_3D.instantiate()
	damage_label.text = str(damage)
	damage_label.global_position = position
	
	# Add to the current scene
	var current_scene := get_tree().current_scene
	if current_scene:
		current_scene.add_child(damage_label)
	else:
		print_debug("ERROR: No current scene to add damage label to!")
