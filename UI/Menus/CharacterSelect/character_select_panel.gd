class_name CharacterSelectPanel extends PanelContainer
## One player's character select: a header (who's choosing), a tab per
## team, the team's lineup in 3D (CharacterStage3D) with the current pick
## stepped forward, and its name and kit underneath. Built in code, so the
## menus just make one per player.
##
## It only shows choices and reports clicks: the menu decides what a click
## (or a button press on a player's own device) changes, then calls
## show_choice(). Mouse input is only taken while `interactive`, so in the
## local lobby only the keyboard & mouse player's panel answers the mouse.
##
## Over the lineup is the player's name (show_name), in the font it has
## over their head in a match: click it to type a new one, or reroll a
## random one. The name field takes clicks on every panel, so whoever is at
## the keyboard can name players on controllers too.

## A team tab was clicked.
signal team_picked(team: int)
## A figure in the lineup was clicked.
signal character_picked(character: int)
## One of the arrows beside the name was clicked (-1 or 1).
signal character_stepped(step: int)
## A name was typed in (sent as it's typed, and again when it's done).
signal name_typed(text: String)
## The reroll button was clicked: wants a new random name.
signal name_rerolled

const TAB_HEIGHT := 32
const NAME_FONT_SIZE := 22
const SMALL_FONT_SIZE := 15
const PLAYER_NAME_FONT_SIZE := 24
## The smallest a long character name shrinks to before it's cut short.
const MIN_NAME_FONT_SIZE := 14

var interactive: bool = true:
	set(value):
		interactive = value
		for button: Button in _tabs + [_prev, _next, _reroll]:
			button.mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
## Whether its buttons take keyboard/controller focus (single player and
## online: the menus' own navigation reaches them). Off in the local lobby,
## where each player steers their own panel from their own device.
var focusable: bool = true:
	set(value):
		focusable = value
		for button: Button in _tabs + [_prev, _next, _reroll]:
			button.focus_mode = Control.FOCUS_ALL if value else Control.FOCUS_NONE

## Whether the team tabs show (off when the team can't change, e.g. mid-match).
var teams_shown: bool = true:
	set(value):
		teams_shown = value
		if _tabs_row:
			_tabs_row.visible = value and not _empty.visible

## Whether the name field shows (off where the name can't change, e.g.
## mid-match).
var names_shown: bool = true:
	set(value):
		names_shown = value
		if _player_name_row:
			_player_name_row.visible = value and not _empty.visible

var team: int = -1
var character: int = -1

var _stage_size: Vector2
var _style: StyleBoxFlat
var _header: Label
var _player_name_row: HBoxContainer
var _player_name: LineEdit
var _reroll: Button
var _tabs_row: HBoxContainer
var _tabs: Array[Button] = []
var _stage_box: ScreenResViewport
var _viewport: SubViewport
var _stage: CharacterStage3D
var _name_row: HBoxContainer
var _name: Label
var _prev: Button
var _next: Button
var _kit: Label
## Shown instead of the lineup while the seat is empty.
var _empty: Label


func _init(stage_size: Vector2 = Vector2(300, 240)) -> void:
	_stage_size = stage_size
	_style = StyleBoxFlat.new()
	_style.set_corner_radius_all(6)
	_style.set_border_width_all(3)
	_style.set_content_margin_all(8)
	_style.bg_color = Color(0.08, 0.08, 0.1, 0.85)
	_style.border_color = Color(0.2, 0.2, 0.24)
	add_theme_stylebox_override("panel", _style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	_header = _label(SMALL_FONT_SIZE)
	column.add_child(_header)

	_player_name_row = HBoxContainer.new()
	_player_name_row.add_theme_constant_override("separation", 6)
	column.add_child(_player_name_row)
	_player_name = LineEdit.new()
	_player_name.max_length = PlayerNames.MAX_LENGTH
	_player_name.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_name.placeholder_text = "Your name"
	_player_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Only by clicking: menu navigation (and each seat's own device in the
	# local lobby) steers the rest of the panel
	_player_name.focus_mode = Control.FOCUS_CLICK
	_player_name.add_theme_font_override("font", NameTag.font())
	_player_name.add_theme_font_size_override("font_size", PLAYER_NAME_FONT_SIZE)
	_player_name.text_changed.connect(func(text: String) -> void: name_typed.emit(text))
	_player_name.text_submitted.connect(func(_text: String) -> void: _player_name.release_focus())
	# Done typing: the menu may have tidied the name up meanwhile
	_player_name.focus_exited.connect(func() -> void: name_typed.emit(_player_name.text))
	_player_name_row.add_child(_player_name)
	_reroll = Button.new()
	_reroll.text = "Reroll"
	_reroll.tooltip_text = "Random name (Y on a controller)"
	_reroll.pressed.connect(func() -> void: name_rerolled.emit())
	_player_name_row.add_child(_reroll)

	_tabs_row = HBoxContainer.new()
	_tabs_row.add_theme_constant_override("separation", 6)
	column.add_child(_tabs_row)

	_stage_box = ScreenResViewport.new()
	_stage_box.custom_minimum_size = stage_size
	_stage_box.gui_input.connect(_on_stage_input)
	column.add_child(_stage_box)

	_empty = _label(20)
	_empty.custom_minimum_size = stage_size
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.hide()
	column.add_child(_empty)

	_name_row = HBoxContainer.new()
	_name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_name_row)
	_prev = _arrow("<", -1)
	_name_row.add_child(_prev)
	_name = _label(NAME_FONT_SIZE)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_row.add_child(_name)
	_next = _arrow(">", 1)
	_name_row.add_child(_next)

	_kit = _label(SMALL_FONT_SIZE)
	_kit.modulate = Color(1, 1, 1, 0.75)
	column.add_child(_kit)

	_build_tabs()


## Who's choosing, e.g. "P1  Keyboard & Mouse". Empty = no header.
func set_header(text: String) -> void:
	_header.text = text
	_header.visible = text != ""


## Show `text` as the player's name, in `color` (their team's). Left alone
## while it's being typed in, so the caret doesn't jump.
func show_name(text: String, color: Color) -> void:
	if not _player_name.has_focus():
		_player_name.text = text
	_player_name.add_theme_color_override("font_color", color.lightened(0.45))


## Whether the name is being typed in, so the menu can leave the keys alone.
func is_typing() -> bool:
	return _player_name.has_focus()


## Show `new_team`'s lineup with `new_character` picked, tinted in the
## team's color.
func show_choice(new_team: int, new_character: int) -> void:
	_ensure_stage()
	_set_empty(false)
	if _tabs.size() != Players.team_count:
		_build_tabs()
	team = new_team
	character = new_character
	var color: Color = Players.team_color(team)
	_style.bg_color = color.darkened(0.72)
	_style.border_color = color.darkened(0.2)
	for i in _tabs.size():
		_tabs[i].button_pressed = i == team
		_tabs[i].modulate = Color.WHITE if i == team else Color(1, 1, 1, 0.55)
	_name.text = Roster.name_of(character)
	_fit_name.call_deferred()
	_kit.text = Roster.kit_name_of(character)
	_stage.show_choice(team, character)


## Nobody in this seat: just `text` (e.g. how to join) where the lineup goes.
func show_empty(text: String) -> void:
	_set_empty(true)
	_empty.text = text
	_style.bg_color = Color(0.08, 0.08, 0.1, 0.55)
	_style.border_color = Color(0.2, 0.2, 0.24)


func _set_empty(on: bool) -> void:
	_empty.visible = on
	_stage_box.visible = not on
	_tabs_row.visible = not on and teams_shown
	_player_name_row.visible = not on and names_shown
	if on and _player_name.has_focus():
		_player_name.release_focus()
	_name_row.visible = not on
	_kit.visible = not on
	if on and _viewport:
		# Nothing to draw: don't spend the frame on it
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	elif _viewport:
		_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE


## The 3D lineup, made the first time there's someone to show.
func _ensure_stage() -> void:
	if _stage:
		return
	_viewport = _stage_box.viewport
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_stage = CharacterStage3D.new()
	_viewport.add_child(_stage)
	# Only renders once its texture is drawn: don't wait for a relayout
	_stage_box.queue_redraw()


func _build_tabs() -> void:
	for tab: Button in _tabs:
		tab.queue_free()
	_tabs.clear()
	for i in Players.team_count:
		var tab := Button.new()
		tab.text = Players.team_name(i)
		tab.toggle_mode = true
		tab.custom_minimum_size = Vector2(0, TAB_HEIGHT)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.add_theme_font_size_override("font_size", 18)
		var color: Color = Players.team_color(i).lightened(0.55)
		for state: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
			tab.add_theme_color_override(state, color)
		tab.pressed.connect(func() -> void:
			tab.button_pressed = i == team  # Stays as is until the menu says otherwise
			team_picked.emit(i))
		_tabs_row.add_child(tab)
		_tabs.append(tab)
	interactive = interactive
	focusable = focusable


## Where keyboard/controller focus enters the panel: the arrows, which
## step through the lineup with left/right while focused.
func first_focus() -> Control:
	return _next


func _arrow(text: String, step: int) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.custom_minimum_size = Vector2(36, 0)
	button.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	button.pressed.connect(func() -> void: character_stepped.emit(step))
	button.gui_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
			character_stepped.emit(-1 if event.is_action_pressed("ui_left") else 1)
			button.accept_event())
	return button


## A long character name shrinks until it fits its row (once laid out).
func _fit_name() -> void:
	var font: Font = _name.get_theme_font(&"font")
	var font_size: int = NAME_FONT_SIZE
	while font_size > MIN_NAME_FONT_SIZE \
			and font.get_string_size(_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > _name.size.x:
		font_size -= 1
	_name.add_theme_font_size_override("font_size", font_size)


## Long text is cut short with "..." rather than widening the panel, so
## picking a character with a long name or kit doesn't shift the lobby.
func _label(font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", font_size)
	return label


## Clicking a figure picks it.
func _on_stage_input(event: InputEvent) -> void:
	if not interactive or not _stage or not event is InputEventMouseButton:
		return
	var click := event as InputEventMouseButton
	if not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	# The viewport is drawn stretched over the container
	var scale_to_viewport: Vector2 = Vector2(_viewport.size) / _stage_box.size
	var picked: int = _stage.character_at(click.position * scale_to_viewport)
	if picked >= 0:
		character_picked.emit(picked)
		accept_event()
