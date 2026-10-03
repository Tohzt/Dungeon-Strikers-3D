class_name Scoreboard3D extends CanvasLayer
## Team kill counts at the top-middle of the screen, each in its team's
## color, with any banked bounty shields under them and the kills needed to
## win below. Also announces kills, goals and the winner.

## How long an announcement stays up before fading.
const ANNOUNCE_TIME := 2.5
const ANNOUNCE_FADE := 0.4

@onready var row: HBoxContainer = $Row

var _kill_labels: Dictionary[int, Label] = {}
var _shield_labels: Dictionary[int, Label] = {}
var _caption: Label
var _announcement: Label
var _winner: Label
var _announce_tween: Tween


func _ready() -> void:
	_caption = _make_label("", Color(1, 1, 1, 0.8), 18)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_caption.position.y = 112
	_caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_caption)
	_announcement = _make_label("", Color.WHITE, 28)
	_announcement.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_announcement.position.y = 142
	_announcement.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_announcement.modulate.a = 0.0
	add_child(_announcement)
	_winner = _make_label("", Color.WHITE, 96)
	_winner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_winner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_winner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_winner.hide()
	add_child(_winner)


## One kill count per team, in the order given, separated by dashes.
func setup(teams: Array[int], kills_to_win: int) -> void:
	for child: Node in row.get_children():
		child.queue_free()
	_kill_labels.clear()
	_shield_labels.clear()
	for i in teams.size():
		if i > 0:
			row.add_child(_make_label("-", Color.WHITE, 48))
		var team: int = teams[i]
		var color: Color = Players.TEAM_COLORS[team % Players.TEAM_COLORS.size()]
		var column := VBoxContainer.new()
		column.alignment = BoxContainer.ALIGNMENT_BEGIN
		_kill_labels[team] = _make_label("0", color, 48)
		_shield_labels[team] = _make_label("", color, 16)
		column.add_child(_kill_labels[team])
		column.add_child(_shield_labels[team])
		row.add_child(column)
	_caption.text = "First to %d kills" % kills_to_win


func set_kills(team: int, kills: int) -> void:
	if _kill_labels.has(team):
		_kill_labels[team].text = str(kills)


func set_shields(team: int, shields: int) -> void:
	if _shield_labels.has(team):
		_shield_labels[team].text = "SHIELD" if shields == 1 else ("SHIELD x%d" % shields if shields > 1 else "")


## Show `text` under the scores for a moment (replacing any earlier one).
func announce(text: String, color: Color) -> void:
	_announcement.text = text
	_announcement.add_theme_color_override("font_color", color)
	if _announce_tween:
		_announce_tween.kill()
	_announcement.modulate.a = 1.0
	_announce_tween = create_tween()
	_announce_tween.tween_interval(ANNOUNCE_TIME)
	_announce_tween.tween_property(_announcement, "modulate:a", 0.0, ANNOUNCE_FADE)


func show_winner(text: String, color: Color) -> void:
	_winner.text = text
	_winner.add_theme_color_override("font_color", color)
	_winner.show()


func _make_label(text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", maxi(roundi(size / 5.0), 4))
	return label
