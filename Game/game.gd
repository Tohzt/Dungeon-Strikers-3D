class_name GameClass extends Node2D

@onready var Entities: Node2D = $Entities
@onready var Player: PlayerClass
@onready var Spawn_Points: Node = $"Spawn Points"
@onready var Loading: CanvasLayer = $Loading
@onready var Camera: Camera2D = $Camera2D
@onready var HOST_UI: CanvasLayer = $"Host UI"
@onready var HUD: CanvasLayer = $Camera2D/Hud
var camera_target: Vector2

# Camera bounds system
var current_room_bounds: Rect2
const CAMERA_DEADZONE: float = 200.0
const CAMERA_PEEK_OFFSET: float = 0.0

# Camera zoom system
var camera_zoom: float = 1.0
var target_zoom: float = 0.7  # Start zoomed out
const ZOOM_MIN: float = 0.5
const ZOOM_MAX: float = 2.0
const ZOOM_SPEED: float = 0.1
const ZOOM_LERP_SPEED: float = 8.0

func _ready() -> void:
	if !Player:
		var _player := Global.PLAYER.instantiate()
		Entities.add_child(_player)
		# Get spawn position - ensure Player_One is available
		var spawn_point: Marker2D = Spawn_Points.get_node("P1 Spawn") as Marker2D
		if spawn_point:
			# Set spawn_pos before calling reset() so reset() uses the correct position
			_player.EB.spawn_pos = spawn_point.global_position
		else:
			print_debug("ERROR: Could not find P1 Spawn point!")
		var _res := Global.resources_to_load[0]
		
		# Create a new PlayerResource instance and copy all properties automatically
		var new_properties := PlayerResource.new()
		var properties := _res.get_property_list()
		for property in properties:
			# Skip built-in properties and only copy our custom ones
			if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
				var property_name: String = property["name"]
				if _res.get(property_name) != null:  # Only copy if source has a value
					new_properties.set(property_name, _res.get(property_name))
		
		# Assign the new resource to the player
		_player.Properties = new_properties
		
		Player = _player
	
	Global.restore_player_weapons(Player)
	
	# Activate the player and initialize stats
	# reset() will set the position to spawn_pos, which we set above
	Player.EB.reset()
 	
	for room: RoomClass in $Rooms.get_children():
		if !Global.rooms.has(room):
			Global.rooms.append(room)
		# Initialize camera bounds from first room (Arena)
		if current_room_bounds == Rect2():
			current_room_bounds = room.get_room_bounds()
			update_camera_limits()
	
	# Initialize camera zoom
	Camera.zoom = Vector2(camera_zoom, camera_zoom)
	if multiplayer.is_server():
		HUD.hide()
		set_loading(false)
	if Server.OFFLINE: 
		HUD.show()
		HOST_UI.hide()


func _process(delta: float) -> void:
	_overwrite_camera(delta)
	_handle_zoom(delta)
	
	if Input.is_action_just_pressed("ui_cancel"):
		#TODO: Disconnect Client
		get_tree().change_scene_to_file(Global.MAIN)


func update_camera_limits() -> void:
	## Updates Camera2D limits based on current room bounds with peek offset
	if current_room_bounds == Rect2():
		return
	
	var expanded_bounds: Rect2 = Rect2(
		current_room_bounds.position - Vector2(CAMERA_PEEK_OFFSET, CAMERA_PEEK_OFFSET),
		current_room_bounds.size + Vector2(CAMERA_PEEK_OFFSET * 2, CAMERA_PEEK_OFFSET * 2)
	)
	
	Camera.limit_left = int(expanded_bounds.position.x)
	Camera.limit_top = int(expanded_bounds.position.y)
	Camera.limit_right = int(expanded_bounds.position.x + expanded_bounds.size.x)
	Camera.limit_bottom = int(expanded_bounds.position.y + expanded_bounds.size.y)
	Camera.limit_smoothed = true

func _handle_zoom(delta: float) -> void:
	## Smoothly lerps camera zoom to target zoom
	if abs(camera_zoom - target_zoom) > 0.01:
		camera_zoom = lerp(camera_zoom, target_zoom, delta * ZOOM_LERP_SPEED)
		Camera.zoom = Vector2(camera_zoom, camera_zoom)

func _input(event: InputEvent) -> void:
	## Handle zoom input when not target locked
	if !Player:
		return
	
	# Only allow zoom when not target locked
	var is_target_locked: bool = Player.EB.target != null and is_instance_valid(Player.EB.target)
	if is_target_locked:
		return
	
	# Handle mouse wheel zoom
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_zoom = clamp(target_zoom + ZOOM_SPEED, ZOOM_MIN, ZOOM_MAX)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_zoom = clamp(target_zoom - ZOOM_SPEED, ZOOM_MIN, ZOOM_MAX)

func _overwrite_camera(delta: float) -> void:
	if current_room_bounds == Rect2() or !Player:
		return
	
	var expanded_bounds: Rect2 = Rect2(
		current_room_bounds.position - Vector2(CAMERA_PEEK_OFFSET, CAMERA_PEEK_OFFSET),
		current_room_bounds.size + Vector2(CAMERA_PEEK_OFFSET * 2, CAMERA_PEEK_OFFSET * 2)
	)
	
	var camera_center: Vector2 = Camera.global_position
	var player_pos: Vector2 = Player.global_position
	
	# Manual panning (prioritize if active)
	var direction: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if !direction.is_zero_approx():
		var pan_speed: float = 100.0
		var new_pos: Vector2 = Camera.global_position + direction * delta * pan_speed
		# Clamp manual pan to bounds
		new_pos.x = clamp(new_pos.x, expanded_bounds.position.x, expanded_bounds.position.x + expanded_bounds.size.x)
		new_pos.y = clamp(new_pos.y, expanded_bounds.position.y, expanded_bounds.position.y + expanded_bounds.size.y)
		Camera.global_position = new_pos
	else:
		# Player following with deadzone (only when not manually panning)
		var distance_to_player: float = camera_center.distance_to(player_pos)
		if distance_to_player > CAMERA_DEADZONE:
			var direction_to_player: Vector2 = (player_pos - camera_center).normalized()
			# Target position keeps player at deadzone edge
			var target_pos: Vector2 = player_pos - direction_to_player * CAMERA_DEADZONE
			# Clamp target position to bounds
			target_pos.x = clamp(target_pos.x, expanded_bounds.position.x, expanded_bounds.position.x + expanded_bounds.size.x)
			target_pos.y = clamp(target_pos.y, expanded_bounds.position.y, expanded_bounds.position.y + expanded_bounds.size.y)
			# Lerp camera toward target
			Camera.global_position = camera_center.lerp(target_pos, delta * 5.0)
	
	# Legacy camera_target support for multiplayer (non-host clients)
	if !Server.OFFLINE and multiplayer.get_unique_id() != 1:
		if !Camera.global_position.is_equal_approx(camera_target):
			var lerped_pos: Vector2 = Camera.global_position.lerp(camera_target, delta * 10)
			# Clamp lerped position to bounds
			lerped_pos.x = clamp(lerped_pos.x, expanded_bounds.position.x, expanded_bounds.position.x + expanded_bounds.size.x)
			lerped_pos.y = clamp(lerped_pos.y, expanded_bounds.position.y, expanded_bounds.position.y + expanded_bounds.size.y)
			Camera.global_position = lerped_pos


@rpc("any_peer", "call_remote", "reliable")
func set_loading(TorF: bool) -> void: 
	match TorF:
		true: Loading.show()
		false: Loading.hide()
