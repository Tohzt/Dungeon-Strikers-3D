class_name FitCenterContainer extends Container
## Centers its children like a CenterContainer, but scales any child that's
## bigger than this rect down until it fits, so a tall or wide menu shrinks
## instead of running off the edges of the screen. Never scales up.

## Space kept clear between the content and the edges.
@export var margin: float = 16.0
## Where the content sits vertically; it's always centered horizontally.
@export_enum("Top", "Center", "Bottom") var vertical: int = 1


func _get_minimum_size() -> Vector2:
	# Unlike CenterContainer, don't take the children's size: that would grow
	# this past the screen, which is exactly what it's here to stop.
	return Vector2.ZERO


func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN:
		return
	var room: Vector2 = (size - Vector2.ONE * margin * 2.0).max(Vector2.ONE)
	for node in get_children():
		var child := node as Control
		if child == null or not child.visible or child.top_level:
			continue
		var need: Vector2 = child.get_combined_minimum_size().max(Vector2.ONE)
		var fit: float = minf(1.0, minf(room.x / need.x, room.y / need.y))
		var spare: Vector2 = size - need * fit
		var y: float = [margin, spare.y / 2.0, spare.y - margin][vertical]
		fit_child_in_rect(child, Rect2(Vector2(spare.x / 2.0, y).floor(), need))
		child.pivot_offset = Vector2.ZERO
		child.scale = Vector2.ONE * fit  # After the fit, which resets scale
