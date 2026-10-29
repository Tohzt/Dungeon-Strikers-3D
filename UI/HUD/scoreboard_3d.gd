class_name Scoreboard3D extends CanvasLayer
## Team scores (kills, or goals in modes won by goals; or each base's
## health, see setup_health) on a thin stone banner hanging from the
## top-middle of the screen, each in its team's color. Kills, goals and other happenings go
## to a quiet feed in the bottom-right corner; the winner is shown big.

## How long a feed line stays up before fading, and the most shown at once
## (the oldest drops off first).
const LOG_TIME := 6.0
const LOG_FADE := 0.6
const LOG_MAX := 5
const LOG_FONT_SIZE := 16
const LOG_BACKGROUND := Color(0.0, 0.0, 0.0, 0.35)
const LOG_LIGHTEN := 0.4

## How long a call-out (countdowns) stays up in the middle before fading.
const CALL_OUT_TIME := 0.8
const CALL_OUT_FADE := 0.2

## A base's health bar (see setup_health), how long a hit takes to drain
## it, and the flash it gives.
const HEALTH_BAR_SIZE := Vector2(200, 26)
const HEALTH_BAR_BACK := Color(0.07, 0.07, 0.09, 0.85)
const HEALTH_DRAIN_TIME := 0.5
const HEALTH_HIT_FLASH := Color(1.0, 0.35, 0.35)

## The winner's line: this big, unless it has to shrink to fit the screen
## (keeping this much space at each side).
const WINNER_FONT_SIZE := 96
const WINNER_MIN_FONT_SIZE := 32
const WINNER_SIDE_MARGIN := 40.0

@onready var row: HBoxContainer = $Banner/Row
@onready var _log: VBoxContainer = $Log

var _score_labels: Dictionary[int, Label] = {}
var _health_bars: Dictionary[int, ProgressBar] = {}
var _max_health: int = 0
var _log_style: StyleBoxFlat
var _call_out: Label
var _winner: Label
var _call_out_tween: Tween


func _ready() -> void:
	_log_style = StyleBoxFlat.new()
	_log_style.bg_color = LOG_BACKGROUND
	_log_style.set_corner_radius_all(4)
	_log_style.content_margin_left = 8
	_log_style.content_margin_right = 8
	_log_style.content_margin_top = 1
	_log_style.content_margin_bottom = 1
	_call_out = _make_label("", Color.WHITE, 64)
	_call_out.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_call_out.position.y = 140
	_call_out.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_call_out.modulate.a = 0.0
	add_child(_call_out)
	_winner = _make_label("", Color.WHITE, WINNER_FONT_SIZE)
	_winner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_winner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_winner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_winner.hide()
	add_child(_winner)


## One score per team, in the order given, separated by dashes.
func setup(teams: Array[int]) -> void:
	_clear()
	for i in teams.size():
		if i > 0:
			row.add_child(_make_label("-", Color.WHITE, 40))
		var team: int = teams[i]
		var color: Color = Players.TEAM_COLORS[team % Players.TEAM_COLORS.size()]
		_score_labels[team] = _make_label("0", color, 40)
		row.add_child(_score_labels[team])


## Like setup, but each team gets its base's health instead: a bar in its
## color, full at `max_health`, with the HP on it.
func setup_health(teams: Array[int], max_health: int) -> void:
	_clear()
	_max_health = max_health
	for i in teams.size():
		if i > 0:
			row.add_child(_make_label("vs", Color.WHITE, 24))
		var team: int = teams[i]
		var color: Color = Players.TEAM_COLORS[team % Players.TEAM_COLORS.size()]
		var bar := ProgressBar.new()
		bar.custom_minimum_size = HEALTH_BAR_SIZE
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.show_percentage = false
		bar.max_value = max_health
		bar.value = max_health
		bar.add_theme_stylebox_override("background", _bar_style(HEALTH_BAR_BACK))
		bar.add_theme_stylebox_override("fill", _bar_style(color))
		var hp: Label = _make_label(str(max_health), Color.WHITE, 18)
		hp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bar.add_child(hp)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		_health_bars[team] = bar
		_score_labels[team] = hp


func _clear() -> void:
	for child: Node in row.get_children():
		child.queue_free()
	_score_labels.clear()
	_health_bars.clear()


func _bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	style.border_color = Color.BLACK
	style.set_border_width_all(2)
	return style


## A team's score, or its base's health (see setup_health): the bar drains
## to it with a red flash when it drops.
func set_score(team: int, value: int) -> void:
	if _score_labels.has(team):
		_score_labels[team].text = str(value)
	var bar: ProgressBar = _health_bars.get(team)
	if not bar:
		return
	if value < bar.value:
		bar.modulate = HEALTH_HIT_FLASH
	var tween: Tween = bar.create_tween().set_parallel()
	tween.tween_property(bar, "value", float(value), HEALTH_DRAIN_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(bar, "modulate", Color.WHITE, HEALTH_DRAIN_TIME)


## Add `text` to the bottom of the feed in the corner, where it fades after
## a few seconds.
func announce(text: String, color: Color) -> void:
	var line := PanelContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.size_flags_horizontal = Control.SIZE_SHRINK_END
	line.add_theme_stylebox_override("panel", _log_style)
	# Lightened so dark team colors still read on the dim strip
	var label: Label = _make_label(text, color.lerp(Color.WHITE, LOG_LIGHTEN), LOG_FONT_SIZE)
	label.add_theme_constant_override("outline_size", 3)
	line.add_child(label)
	_log.add_child(line)
	while _log.get_child_count() > LOG_MAX:
		var oldest: Node = _log.get_child(0)
		_log.remove_child(oldest)
		oldest.queue_free()
	var tween: Tween = line.create_tween()
	tween.tween_interval(LOG_TIME)
	tween.tween_property(line, "modulate:a", 0.0, LOG_FADE)
	tween.tween_callback(line.queue_free)


## Flash `text` big in the middle for a moment (replacing any earlier one).
## Only for things that have to be seen right now, like a countdown.
func call_out(text: String, color: Color) -> void:
	_call_out.text = text
	_call_out.add_theme_color_override("font_color", color)
	if _call_out_tween:
		_call_out_tween.kill()
	_call_out.modulate.a = 1.0
	_call_out_tween = create_tween()
	_call_out_tween.tween_interval(CALL_OUT_TIME)
	_call_out_tween.tween_property(_call_out, "modulate:a", 0.0, CALL_OUT_FADE)


func show_winner(text: String, color: Color) -> void:
	_winner.text = text
	_winner.add_theme_color_override("font_color", color)
	var size: int = _fitting_size(text, WINNER_FONT_SIZE, _winner.get_viewport_rect().size.x - 2.0 * WINNER_SIDE_MARGIN)
	_winner.add_theme_font_size_override("font_size", size)
	_winner.add_theme_constant_override("outline_size", maxi(roundi(size / 5.0), 4))
	_winner.reset_size()  # Shrink back round the new text, still centered
	_winner.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_winner.show()


## The biggest font size up to `size` at which every line of `text` fits
## in `width` (outline included).
func _fitting_size(text: String, size: int, width: float) -> int:
	var font: Font = _winner.get_theme_font(&"font")
	var widest: float = 0.0
	for line: String in text.split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	widest += size / 5.0 * 2.0
	if widest <= width:
		return size
	return maxi(floori(size * width / widest), WINNER_MIN_FONT_SIZE)


func hide_winner() -> void:
	_winner.hide()


func _make_label(text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", maxi(roundi(size / 5.0), 4))
	return label
