extends StateClass

##HACK: Temp display crosshair
signal target_position_changed(new_position: Vector2)

var target_position: Vector2
var direction_timer: float = 0.0
const DIRECTION_CHANGE_TIME: float = 2.0
const WANDER_RADIUS: float = 200.0
const DETECT_RANGE: int = 200

func enter_state() -> void:
	super.enter_state()
	_pick_new_target()


func update(delta: float) -> void:
	_is_on_target()
	_update_direction(delta)
	_detect_enemy()
	
	if Master.target_locked:
		exit_to("target_state")

func _detect_enemy() -> void:
	var entity: Dictionary = Global.get_nearest(Master.global_position, "Entity", INF)
	if entity:
		if entity["dist"] <= DETECT_RANGE:
			Master.target = entity["inst"]

func _is_on_target() -> void:
	if Master.global_position.distance_to(target_position) < 10:
		direction_timer = DIRECTION_CHANGE_TIME

func _update_direction(delta: float) -> void:
	direction_timer += delta
	if direction_timer >= DIRECTION_CHANGE_TIME:
		_pick_new_target()
		direction_timer = 0

func _pick_new_target() -> void:
	var random_angle: float = randf_range(0, TAU)
	var tar_pos := Master.global_position + Vector2(
		cos(random_angle) * WANDER_RADIUS,
		sin(random_angle) * WANDER_RADIUS
	)
	
	if Master.current_room:
		var padding := 10.0
		var room_area: Area2D = Master.current_room.area
		var room_shape: CollisionShape2D = room_area.get_node("CollisionShape2D")
		var room_rect := Rect2(
			room_area.global_position,
			room_shape.shape.size
		)
		
		if !room_rect.grow(-padding).has_point(tar_pos):
			_pick_new_target()
			return
	target_position = tar_pos
	Master.target = Master._Target
	Master.target.global_position = target_position
	
	##HACK: Temp display crosshair
	emit_signal("target_position_changed", target_position)
