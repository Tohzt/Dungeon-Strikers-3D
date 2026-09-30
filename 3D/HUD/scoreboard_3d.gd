class_name Scoreboard3D extends CanvasLayer
## Team scores at the top-middle of the screen, each in its team's color.

@onready var row: HBoxContainer = $Row

var _labels: Dictionary[int, Label] = {}


## One score per team, in the order given, separated by dashes.
func setup(teams: Array[int]) -> void:
	for child: Node in row.get_children():
		child.queue_free()
	_labels.clear()
	for i in teams.size():
		if i > 0:
			row.add_child(_make_label("-", Color.WHITE))
		var team: int = teams[i]
		var color: Color = Players.TEAM_COLORS[team % Players.TEAM_COLORS.size()]
		_labels[team] = _make_label("0", color)
		row.add_child(_labels[team])


func set_score(team: int, score: int) -> void:
	if _labels.has(team):
		_labels[team].text = str(score)


func _make_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 10)
	return label
