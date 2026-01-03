extends Node

const GAME: String = "res://Game/game.tscn"
var Game3D: Game3D_Class
const MAIN: String = "res://Main Menu/Main Menu.tscn"
const ROOM: String = "res://Game/Room/room.tscn"

const PLAYER: PackedScene = preload("res://Entities/Player/player.tscn")
const BALL: PackedScene = preload("res://Entities/Ball/ball.tscn")
const BOSS: PackedScene = preload("res://Entities/Boss/boss.tscn")
const WEAPON: PackedScene = preload("res://Items/Weapons/weapon.tscn")
const DISPLAY_DAMAGE: PackedScene = preload("res://HUD/display_damage.tscn")
const DISPLAY_DAMAGE_3D: PackedScene = preload("res://3D/HUD/display_damage_3d.tscn")
var player_display_name: String

var resources_to_load: Array[Resource]
var rooms: Array[RoomClass]
var current_room: int = -1
var current_room_bounds: Rect2

var input_type: String = "Keyboard"

# Weapon persistence data
var player_held_weapons: Dictionary = {
	"left_hand": null,
	"right_hand": null
}

# Layer system for rendering order
enum Layers {
	# Environment (0-8)
	FLOOR = 0,
	WALLS = 1,
	BG_DECOR = 2,
	FG_DECOR = 3,
	GROUND_EFFECTS = 4,
	WEAPON_ON_GROUND = 7,
	WEAPON_IN_HAND = 8,
	# Characters/Entities (9-19)
	PLAYER_HANDS = 9,
	PROJECTILES = 10,
	PLAYER = 11,
	ENEMIES = 12,
	NPCS = 13,
	# Effects/Attacks (20-29)
	ATTACK_VISUALS = 23,
	# UI/Overlay (30-39)
	GAME_UI = 30,
	MENUS = 31,
	HUD = 32
}



func is_current_room(room: RoomClass, make_current: bool = false) -> bool:
	if current_room == rooms.find(room):
		return true
	elif make_current: set_current_room(room)
	return false

func set_current_room(room: RoomClass) -> void:
	current_room = rooms.find(room)
	var game: GameClass = get_tree().current_scene
	if game:
		# Calculate and store room bounds
		current_room_bounds = room.get_room_bounds()
		# Update game's camera bounds
		game.current_room_bounds = current_room_bounds
		game.update_camera_limits()
		# Keep camera_target for backward compatibility (may be removed later)
		game.camera_target = room.global_position


func get_nearest(from: Vector2, type: String, dist: float, ignore: Node2D = null, ignore_array: Array[Node2D] = []) -> Dictionary:
	var entities: Array[Node] = get_tree().get_nodes_in_group(type)
	var closest_entity: Node2D = null
	var min_distance := INF
	
	# Find the closest entity in a single pass
	for entity: Node2D in entities:
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

func save_player_weapons(player: PlayerClass) -> void:
	# Save the weapon resources from the player's hands
	if player.Hands.Left.held_weapon:
		player_held_weapons["left_hand"] = player.Hands.Left.held_weapon.Properties
	else:
		player_held_weapons["left_hand"] = null
		
	if player.Hands.Right.held_weapon:
		player_held_weapons["right_hand"] = player.Hands.Right.held_weapon.Properties
	else:
		player_held_weapons["right_hand"] = null

func restore_player_weapons(player: PlayerClass) -> void:
	# Note: This function uses call_deferred, so on_equip will be called next frame
	# Restore weapons to the player's hands
	if player_held_weapons["left_hand"]:
		var left_weapon: WeaponClass = WEAPON.instantiate()
		left_weapon.Properties = player_held_weapons["left_hand"]
		player.Hands.Left.held_weapon = left_weapon
		left_weapon.wielder = player
		# Add to scene tree first, then reparent
		var Entities := get_tree().get_first_node_in_group("Entities")
		Entities.add_child(left_weapon)
		left_weapon.call_deferred("reparent", player.Hands.Left.hand)
		# Zero out weapon position since parent will handle positioning
		left_weapon.call_deferred("set", "position", Vector2.ZERO)
		
		# Set up weapon state (can be done immediately)
		left_weapon.can_pickup = false
		left_weapon.is_thrown = false
		left_weapon.modulate = player.EB.Sprite.modulate
		left_weapon.Sprite.position = left_weapon.Properties.weapon_sprite_offset
		left_weapon.Collision.position = left_weapon.Properties.weapon_col_offset
		
		# Call on_equip() deferred to ensure reparenting is complete
		left_weapon.call_deferred("_restore_on_equip")
 		
	if player_held_weapons["right_hand"]:
		var right_weapon: WeaponClass = WEAPON.instantiate()
		right_weapon.Properties = player_held_weapons["right_hand"]
		player.Hands.Right.held_weapon = right_weapon
		right_weapon.wielder = player
		# Add to scene tree first, then reparent
		var Entities := get_tree().get_first_node_in_group("Entities")
		Entities.add_child(right_weapon)
		right_weapon.call_deferred("reparent", player.Hands.Right.hand)
		# Zero out weapon position since parent will handle positioning
		right_weapon.call_deferred("set", "position", Vector2.ZERO)
		
		# Set up weapon state (can be done immediately)
		right_weapon.can_pickup = false
		right_weapon.is_thrown = false
		right_weapon.modulate = player.EB.Sprite.modulate
		right_weapon.Sprite.position = right_weapon.Properties.weapon_sprite_offset
		right_weapon.Collision.position = right_weapon.Properties.weapon_col_offset
		
		# Call on_equip() deferred to ensure reparenting is complete
		right_weapon.call_deferred("_restore_on_equip")
 
func display_damage(damage: float, position: Vector2) -> void:
	# Spawn a damage display label at the given position
	var damage_label := DISPLAY_DAMAGE.instantiate()
	damage_label.text = str(damage)
	damage_label.global_position = position
	
	# Add to the current scene
	var current_scene := get_tree().current_scene
	if current_scene:
		current_scene.add_child(damage_label)
	else:
		print_debug("ERROR: No current scene to add damage label to!")

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
