class_name SmoothPanelContainer extends PanelContainer
## A PanelContainer whose panel (the theme's stone frame, or whatever its
## "panel" style is) grows and shrinks smoothly when its contents change
## size, instead of snapping. The contents are laid out at once as usual;
## only the frame drawn behind them eases to fit. Eases in screen space, so
## it also follows a parent moving or rescaling it (e.g. FitCenterContainer).

## How quickly the frame eases to its new size (higher is snappier; about
## 4 / ease_speed seconds to settle).
@export var ease_speed: float = 12.0

## The real panel style, drawn by _draw; the container itself gets an empty
## one with the same margins, so the contents sit where they would.
var _style: StyleBox
## Where the frame is drawn, on screen: [top-left, size].
var _drawn: Rect2
var _placed: bool = false


func _ready() -> void:
	_style = get_theme_stylebox(&"panel")
	var spacer := StyleBoxEmpty.new()
	for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		spacer.set_content_margin(side, _style.get_margin(side))
	add_theme_stylebox_override(&"panel", spacer)


func _process(delta: float) -> void:
	var target: Rect2 = _screen_rect()
	if not _placed:
		_drawn = target
		_placed = true
	elif _drawn.is_equal_approx(target):
		return
	var weight: float = 1.0 - exp(-ease_speed * delta)
	_drawn = Rect2(_drawn.position.lerp(target.position, weight), _drawn.size.lerp(target.size, weight))
	queue_redraw()


func _draw() -> void:
	var to_local: Transform2D = get_global_transform().affine_inverse()
	var top_left: Vector2 = to_local * _drawn.position
	var bottom_right: Vector2 = to_local * _drawn.end
	draw_style_box(_style, Rect2(top_left, bottom_right - top_left))


## This container's own rect, on screen.
func _screen_rect() -> Rect2:
	var xform: Transform2D = get_global_transform()
	return Rect2(xform.origin, size * xform.get_scale())
