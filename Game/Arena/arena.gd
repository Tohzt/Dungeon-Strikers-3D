class_name RoomClass extends Node2D
@export var current_room: bool = false
@export var area: Area2D 

func _ready() -> void:
	z_index = Global.Layers.FLOOR

func _on_body_entered(body: Node2D) -> void:
	##TODO: Rewrite so mult.get_ yadda yada can be called from Server
	if !Server.OFFLINE and multiplayer.get_unique_id() != int(body.name): return
	Global.is_current_room(self, true)

func get_room_bounds() -> Rect2:
	## Returns the global bounds of the room based on its Area2D CollisionShape2D
	## Accounts for node scaling
	if !area:
		return Rect2()
	
	var collision_shape: CollisionShape2D = area.get_child(0) as CollisionShape2D
	if !collision_shape:
		return Rect2()
	
	var shape: RectangleShape2D = collision_shape.shape as RectangleShape2D
	if !shape:
		return Rect2()
	
	# Get the scale of the Area2D
	# Note: scale affects the shape size but not child node positions
	var area_scale: Vector2 = area.scale
	
	# Calculate the actual size in world space (shape size * scale)
	var world_size: Vector2 = shape.size * area_scale
	
	# Calculate the center of the shape in global coordinates
	# collision_shape.position is in local coordinates (not affected by scale)
	var shape_center: Vector2 = area.global_position + collision_shape.position
	
	# Return Rect2 with top-left position and scaled size
	return Rect2(shape_center - (world_size / 2), world_size)
