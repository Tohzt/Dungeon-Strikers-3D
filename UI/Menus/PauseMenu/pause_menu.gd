class_name PauseMenu extends CanvasLayer
## In-match pause overlay. Start (controller) or Esc (keyboard) toggles it;
## B also resumes. Runs while the tree is paused (process_mode = Always).
##
## Lists each local player's device: pick a player's row (with anything,
## e.g. the mouse), then press A or Enter on the device they should use.
## Taking another local player's device swaps the two. Next to it, each
## player can switch between Simple and Advanced controls.
##
## The Settings tab has the volume sliders (see Sfx.VOLUME_BUSES); LB/RB or
## Q/E switch tabs.
##
## Down the sides of the screen, each local player's perk cards: P1 and P3
## on the left, P2 and P4 on the right.

const MAIN_MENU := "res://UI/Menus/MainMenu/main_menu.tscn"
## The side columns of perk cards.
const PERK_CARD_WIDTH := 250.0
const PERK_SIDE_MARGIN := 24.0

@onready var resume_button: Button = %Resume
@onready var tabs: TabContainer = %Tabs

var device_buttons: Dictionary[PlayerSlot, Button] = {}
## Everything _build_device_rows added, so it can be cleared.
var device_rows: Array[Control] = []
## The slot waiting for a device press, if any.
var rebinding: PlayerSlot = null
## The left and right columns of perk cards, rebuilt on each pause.
var perk_sides: Array[VBoxContainer] = []


func _ready() -> void:
	hide()
	Players.slot_changed.connect(_on_slot_changed)
	# Online, each machine runs its own copy: resetting just ours would desync.
	%ResetBall.visible = not Net.in_session()
	%ResetGame.visible = not Net.in_session()
	resume_button.pressed.connect(resume)
	%ResetBall.pressed.connect(_on_reset_ball)
	%ResetGame.pressed.connect(_on_reset_game)
	%MainMenu.pressed.connect(_on_main_menu)
	%ExitGame.pressed.connect(get_tree().quit)
	_build_volume_rows()
	_build_perk_sides()
	tabs.tab_changed.connect(_on_tab_changed)


## Waiting on a device: A/Enter from any device takes it, B/Esc cancels.
## Handled before the UI so the press doesn't also click a button or unpause.
func _input(event: InputEvent) -> void:
	if not visible or not rebinding or not event.is_pressed() or event.is_echo():
		return
	if Players.is_join_press(event):
		Players.set_device(rebinding, Players.device_of(event))
	elif not Players.is_back_press(event):
		return
	_stop_rebinding()
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if visible:
			resume()
		else:
			pause()
	elif visible and event.is_action_pressed("ui_cancel"):
		resume()
	elif visible and _is_tab_switch(event):
		tabs.current_tab = posmod(tabs.current_tab + _is_tab_switch(event), tabs.get_tab_count())
	else:
		return
	get_viewport().set_input_as_handled()


func pause() -> void:
	_build_device_rows()
	_build_perk_lists()
	tabs.current_tab = 0
	show()
	# Online, the match keeps running for everyone else, so it does here too.
	get_tree().paused = not Net.in_session()
	resume_button.grab_focus()


func resume() -> void:
	_stop_rebinding()
	hide()
	get_tree().paused = false


## One row per local player (online, just ours), right under Resume. Rebuilt
## on each pause, since players are seated after this menu is ready.
func _build_device_rows() -> void:
	for node: Node in device_rows:
		node.queue_free()
	device_rows.clear()
	device_buttons.clear()

	var slots: Array[PlayerSlot] = Players.human_slots()
	slots.sort_custom(func(a: PlayerSlot, b: PlayerSlot) -> bool: return a.index < b.index)
	var at: int = resume_button.get_index() + 1
	var caption := Label.new()
	device_rows.append(caption)
	caption.text = "Players"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 16)
	resume_button.get_parent().add_child(caption)
	resume_button.get_parent().move_child(caption, at)
	for slot: PlayerSlot in slots:
		at += 1
		var row := HBoxContainer.new()
		var button := _make_row_button(slot)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_start_rebinding.bind(slot))
		row.add_child(button)
		resume_button.get_parent().add_child(row)
		resume_button.get_parent().move_child(row, at)
		device_buttons[slot] = button
		device_rows.append(row)
	caption.visible = not slots.is_empty()
	_refresh_device_rows()


func _make_row_button(slot: PlayerSlot) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 40)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", slot.color.lightened(0.4))
	return button


func _refresh_device_rows() -> void:
	for slot: PlayerSlot in device_buttons:
		device_buttons[slot].text = "%s: %s" % [slot.label(),
			"Press A or Enter on new device..." if slot == rebinding else Players.device_name(slot.device)]


func _on_slot_changed(_slot: PlayerSlot) -> void:
	_refresh_device_rows()


func _start_rebinding(slot: PlayerSlot) -> void:
	rebinding = slot
	_refresh_device_rows()


func _stop_rebinding() -> void:
	rebinding = null
	_refresh_device_rows()


# ===== PERKS =====

## A scrolling column down each side of the screen, behind nothing.
func _build_perk_sides() -> void:
	for left: bool in [true, false]:
		var scroll := ScrollContainer.new()
		scroll.anchor_left = 0.0 if left else 1.0
		scroll.anchor_right = scroll.anchor_left
		scroll.anchor_bottom = 1.0
		scroll.offset_left = PERK_SIDE_MARGIN if left else -PERK_SIDE_MARGIN - PERK_CARD_WIDTH
		scroll.offset_right = scroll.offset_left + PERK_CARD_WIDTH
		scroll.offset_top = PERK_SIDE_MARGIN
		scroll.offset_bottom = -PERK_SIDE_MARGIN
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.focus_mode = Control.FOCUS_NONE
		add_child(scroll)
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 8)
		scroll.add_child(column)
		perk_sides.append(column)


## Each person on this machine's perks (wild items' passing effects left
## out), the same perk stacked into one card.
func _build_perk_lists() -> void:
	for column: VBoxContainer in perk_sides:
		for child: Node in column.get_children():
			child.queue_free()
	if not Global.Game3D:
		return
	var players: Array[PlayerClass3D] = []
	for player: PlayerClass3D in Global.Game3D.players:
		if is_instance_valid(player) and player.slot and player.is_local_person():
			players.append(player)
	players.sort_custom(func(a: PlayerClass3D, b: PlayerClass3D) -> bool: return a.slot.index < b.slot.index)
	for i in players.size():
		var player: PlayerClass3D = players[i]
		var column: VBoxContainer = perk_sides[i % 2]
		var owned: Array[Perk] = []
		for perk: Perk in player.perks.perks:
			if not owned.has(perk) and not player.timed_perks.has(perk):
				owned.append(perk)
		var heading := _perk_label("%s's Perks" % player.slot.label(), 20, player.slot.color.lightened(0.4))
		if column.get_child_count() > 0:
			heading.custom_minimum_size.y = 40  # Gap after the player above
			heading.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		column.add_child(heading)
		if owned.is_empty():
			column.add_child(_perk_label("None yet", 16, Color(0.7, 0.7, 0.7)))
		for perk: Perk in owned:
			column.add_child(_make_perk_card(perk, player.perks.count(perk)))


func _make_perk_card(perk: Perk, owned: int) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.13, 0.92)
	style.border_color = perk.category_color()
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	card.add_child(column)
	column.add_child(_perk_label(perk.category_name().to_upper(), 12, perk.category_color()))
	column.add_child(_perk_label(perk.title + (" x%d" % owned if owned > 1 else ""), 18, Color.WHITE))
	column.add_child(_perk_label(perk.description, 14, Color(0.85, 0.85, 0.85)))
	return card


func _perk_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	return label


## One slider per volume, 0 to 100%, saved as it moves.
func _build_volume_rows() -> void:
	var settings: Control = %Settings
	for bus: StringName in Sfx.VOLUME_BUSES:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 40)
		var name_label := Label.new()
		name_label.text = Sfx.VOLUME_BUSES[bus]
		name_label.custom_minimum_size = Vector2(90, 0)
		name_label.add_theme_font_size_override("font_size", 18)
		var slider := HSlider.new()
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = Sfx.get_volume(bus)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var percent := Label.new()
		percent.custom_minimum_size = Vector2(56, 0)
		percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		percent.add_theme_font_size_override("font_size", 18)
		percent.text = "%d%%" % roundi(slider.value * 100.0)
		slider.value_changed.connect(func(value: float) -> void:
			Sfx.set_volume(bus, value)
			percent.text = "%d%%" % roundi(value * 100.0))
		row.add_child(name_label)
		row.add_child(slider)
		row.add_child(percent)
		settings.add_child(row)


## -1 / +1 for the previous / next tab, 0 for anything else.
func _is_tab_switch(event: InputEvent) -> int:
	if not event.is_pressed() or event.is_echo():
		return 0
	if event is InputEventJoypadButton:
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_LEFT_SHOULDER: return -1
			JOY_BUTTON_RIGHT_SHOULDER: return 1
	elif event is InputEventKey:
		match (event as InputEventKey).physical_keycode:
			KEY_Q: return -1
			KEY_E: return 1
	return 0


## Focus follows the tab, so a controller lands on something usable.
func _on_tab_changed(tab: int) -> void:
	_stop_rebinding()
	if tab == 0:
		resume_button.grab_focus()
	else:
		var first: Control = tabs.get_tab_control(tab).get_child(0)
		var slider: HSlider = first.get_child(1) as HSlider if first.get_child_count() > 1 else null
		if slider:
			slider.grab_focus()


func _on_reset_ball() -> void:
	if Global.Game3D:
		Global.Game3D.reset_ball()
	resume()


## Restart the match with the same players (they stay joined in Players).
func _on_reset_game() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_main_menu() -> void:
	get_tree().paused = false
	Net.leave()  # Online: out of the session too, not back to its lobby
	get_tree().change_scene_to_file(MAIN_MENU)
