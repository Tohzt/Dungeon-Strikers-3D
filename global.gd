extends Node

var Game3D: Game3D_Class

const DISPLAY_DAMAGE_3D: PackedScene = preload("res://3D/HUD/display_damage_3d.tscn")

var input_type: String = "Keyboard"


func get_nearest_3d(from: Vector3, type: String, dist: float, ignore: Node3D = null, ignore_array: Array[Node3D] = []) -> Dictionary:
	var entities: Array[Node] = get_tree().get_nodes_in_group(type)
	var closest_entity: Node3D = null
	var min_distance := INF
	
	# Find the closest entity in a single pass
	for entity: Node3D in entities:
		# Skip if entity is in ignore list
		if entity == ignore or entity in ignore_array:
			continue
		if entity.global_position.is_equal_approx(from):
			continue
			
		var distance := from.distance_to(entity.global_position)
		if distance < min_distance:
			min_distance = distance
			closest_entity = entity
	
	# Return result
	if !closest_entity or min_distance > dist:
		return {"found": false}
	else:
		return {
			"inst": closest_entity,
			"dist": min_distance,
			"found": true
		}


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
