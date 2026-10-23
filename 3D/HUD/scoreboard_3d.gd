class_name Scoreboard3D extends CanvasLayer
## Team scores (kills, or goals in modes won by goals) on a wooden banner
## hanging from the top-middle of the screen, each in its team's color,
## with what's needed to win below. Kills, goals and other happenings go
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

@onready var row: HBoxContainer = $Banner/Column/Row
@onready var _caption: Label = $Banner/Column/Caption
@onready var _log: VBoxContainer = $Log

var _score_labels: Dictionary[int, Label] = {}
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
	_winner = _make_label("", Color.WHITE, 96)
	_winner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_winner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_winner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_winner.hide()
	add_child(_winner)


## One score per team, in the order given, separated by dashes, with
## `caption` (e.g. "First to 5 kills") below.
func setup(teams: Array[int], caption: String) -> void:
	for child: Node in row.get_children():
		child.queue_free()
	_score_labels.clear()
	for i in teams.size():
		if i > 0:
			row.add_child(_make_label("-", Color.WHITE, 40))
		var team: int = teams[i]
		var color: Color = Players.TEAM_COLORS[team % Players.TEAM_COLORS.size()]
		_score_labels[team] = _make_label("0", color, 40)
		row.add_child(_score_labels[team])
	_caption.text = caption


## Replace the line under the scores.
func set_caption(text: String) -> void:
	_caption.text = text


func set_score(team: int, value: int) -> void:
	if _score_labels.has(team):
		_score_labels[team].text = str(value)


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
	_winner.show()


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
