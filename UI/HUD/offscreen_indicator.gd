class_name OffscreenIndicator3D extends CanvasLayer
## Points at every boss drop in play (Game3D.balls: the ball, skulls...)
## that's off screen: an arrow pinned to the screen edge in its direction,
## ringed in the colour of the team that last played it. A bomb's marker
## also shows its fuse countdown.

## Gap between the arrows and the screen edges, in pixels.
const EDGE_MARGIN := 48.0
## Counts as off screen once this close to an edge, so the arrow shows
## before the drop is fully gone.
const ONSCREEN_INSET := 12.0
const RADIUS := 14.0
const ARROW_LENGTH := 14.0
const ARROW_WIDTH := 12.0
const BALL_COLOR := Color(1.0, 1.0, 1.0)
const SKULL_COLOR := Color(0.93, 0.87, 0.7)
const NO_TEAM_COLOR := Color(0.1, 0.1, 0.1)
## The bomb's countdown inside its marker.
const FUSE_FONT_SIZE := 18
const FUSE_OUTLINE := 5
const FUSE_URGENT_COLOR := Color(1.0, 0.25, 0.2)

var _canvas: Control


func _ready() -> void:
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_indicators)
	add_child(_canvas)


func _process(_delta: float) -> void:
	_canvas.queue_redraw()


func _draw_indicators() -> void:
	var game: Game3D_Class = Global.Game3D
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not game or not camera:
		return
	var screen: Rect2 = _canvas.get_rect()
	var onscreen: Rect2 = screen.grow(-ONSCREEN_INSET)
	var center: Vector2 = screen.get_center()
	var half: Vector2 = screen.size * 0.5 - Vector2(EDGE_MARGIN, EDGE_MARGIN)
	# Slow pulse, so the arrows catch the eye without flickering
	var pulse: float = 1.0 + 0.12 * sin(Time.get_ticks_msec() * 0.008)
	for ball: Ball3D in game.balls:
		if not is_instance_valid(ball) or not ball.is_inside_tree():
			continue
		var behind: bool = camera.is_position_behind(ball.global_position)
		var pos: Vector2 = camera.unproject_position(ball.global_position)
		if not behind and onscreen.has_point(pos):
			continue
		var dir: Vector2 = pos - center
		if behind:
			dir = -dir
		if dir.length_squared() < 0.001:
			dir = Vector2.DOWN
		# Out from the middle along dir until it meets the margin rect
		var scale_x: float = half.x / absf(dir.x) if absf(dir.x) > 0.001 else INF
		var scale_y: float = half.y / absf(dir.y) if absf(dir.y) > 0.001 else INF
		var at: Vector2 = center + dir * minf(scale_x, scale_y)
		_draw_arrow(at, dir.normalized(), ball, pulse)


func _draw_arrow(at: Vector2, dir: Vector2, ball: Ball3D, pulse: float) -> void:
	var fill: Color = SKULL_COLOR if ball is Skull3D else (ball.color() if ball is Bomb3D else BALL_COLOR)
	var team: int = ball.holder.slot.team if ball.holder and ball.holder.slot else ball.last_team
	var ring: Color = Players.TEAM_COLORS[team % Players.TEAM_COLORS.size()] if team >= 0 else NO_TEAM_COLOR
	var r: float = RADIUS * pulse
	var side: Vector2 = dir.orthogonal()
	var tip: Vector2 = at + dir * (r + ARROW_LENGTH)
	var base: Vector2 = at + dir * (r - 2.0)
	var arrow := PackedVector2Array([tip, base + side * ARROW_WIDTH, base - side * ARROW_WIDTH])
	_canvas.draw_colored_polygon(arrow, ring)
	_canvas.draw_circle(at, r + 3.0, ring)
	_canvas.draw_circle(at, r, fill)
	if ball is Skull3D:
		# Two eye sockets, so a skull reads differently from the ball
		var eye: Vector2 = Vector2(r * 0.35, -r * 0.1)
		_canvas.draw_circle(at + eye, r * 0.22, NO_TEAM_COLOR)
		_canvas.draw_circle(at + Vector2(-eye.x, eye.y), r * 0.22, NO_TEAM_COLOR)
	elif ball is Bomb3D:
		_draw_fuse(at, ball as Bomb3D)


## The bomb's seconds left, written in the middle of its marker; red once urgent.
func _draw_fuse(at: Vector2, bomb: Bomb3D) -> void:
	var font: Font = ThemeDB.fallback_font
	var text: String = str(ceili(bomb.fuse_left))
	var color: Color = FUSE_URGENT_COLOR if bomb.fuse_left <= Bomb3D.URGENT_TIME else Color.WHITE
	var width: float = RADIUS * 4.0
	# draw_string positions the baseline, so drop it by half the glyph height to centre
	var baseline: Vector2 = at + Vector2(-width * 0.5, (font.get_ascent(FUSE_FONT_SIZE) - font.get_descent(FUSE_FONT_SIZE)) * 0.5)
	_canvas.draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, width, FUSE_FONT_SIZE, FUSE_OUTLINE, NO_TEAM_COLOR)
	_canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, width, FUSE_FONT_SIZE, color)
