class_name FitCenterContainer extends Container
## Centers its children like a CenterContainer, but scales any child that's
## bigger than this rect down until it fits, so a tall or wide menu shrinks
## instead of running off the edges of the screen. Never scales up.
##
## With ease_speed set, a child whose size changes glides to its new place
## and scale instead of jumping there (pair it with a SmoothPanelContainer
## so the frame's edges glide too).

## Space kept clear between the content and the edges.
@export var margin: float = 16.0
## Where the content sits vertically; it's always centered horizontally.
@export_enum("Top", "Center", "Bottom") var vertical: int = 1
## How quickly children ease to a new place and scale (higher is snappier;
## about 4 / ease_speed seconds to settle). 0 = jump straight there.
@export var ease_speed: float = 0.0

## Per eased child: [position, scale] it's heading for.
var _targets: Dictionary[Control, Array] = {}


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
		var was_placed: bool = _targets.has(child)
		var from_position: Vector2 = child.position
		var from_scale: Vector2 = child.scale
		fit_child_in_rect(child, Rect2(Vector2(spare.x / 2.0, y).floor(), need))
		child.pivot_offset = Vector2.ZERO
		child.scale = Vector2.ONE * fit  # After the fit, which resets scale
		if ease_speed <= 0.0:
			continue
		_targets[child] = [child.position, child.scale]
		# The size has to change at once (it can't be under the child's
		# minimum), but where it sits and how big it's drawn can ease over
		if was_placed:
			child.position = from_position
			child.scale = from_scale


func _process(delta: float) -> void:
	if _targets.is_empty():
		return
	var weight: float = 1.0 - exp(-ease_speed * delta)
	for child: Control in _targets.keys():
		if not is_instance_valid(child) or child.get_parent() != self:
			_targets.erase(child)
			continue
		var target: Array = _targets[child]
		child.position = child.position.lerp(target[0], weight)
		child.scale = child.scale.lerp(target[1], weight)
