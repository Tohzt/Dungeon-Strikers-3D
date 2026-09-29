extends CanvasLayer
## In-match pause overlay. Start (controller) or Esc (keyboard) toggles it;
## B also resumes. Runs while the tree is paused (process_mode = Always).
##
## Lists each local player's device: pick a player's row (with anything,
## e.g. the mouse), then press A or Enter on the device they should use.
## Taking another local player's device swaps the two.

const MAIN_MENU := "res://Menus/MainMenu/main_menu.tscn"

@onready var resume_button: Button = %Resume

var device_buttons: Dictionary[PlayerSlot, Button] = {}
## Everything _build_device_rows added, so it can be cleared.
var device_rows: Array[Control] = []
## The slot waiting for a device press, if any.
var rebinding: PlayerSlot = null


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
	else:
		return
	get_viewport().set_input_as_handled()


func pause() -> void:
	_build_device_rows()
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

	var slots: Array[PlayerSlot] = Players.slots.duplicate()
	slots.sort_custom(func(a: PlayerSlot, b: PlayerSlot) -> bool: return a.index < b.index)
	var at: int = resume_button.get_index() + 1
	var caption := Label.new()
	device_rows.append(caption)
	caption.text = "Devices"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 16)
	resume_button.get_parent().add_child(caption)
	resume_button.get_parent().move_child(caption, at)
	for slot: PlayerSlot in slots:
		at += 1
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 40)
		button.add_theme_font_size_override("font_size", 18)
		button.add_theme_color_override("font_color", slot.color.lightened(0.4))
		button.pressed.connect(_start_rebinding.bind(slot))
		resume_button.get_parent().add_child(button)
		resume_button.get_parent().move_child(button, at)
		device_buttons[slot] = button
		device_rows.append(button)
	caption.visible = not slots.is_empty()
	_refresh_device_rows()


func _refresh_device_rows() -> void:
	for slot: PlayerSlot in device_buttons:
		device_buttons[slot].text = "P%d: %s" % [slot.index + 1,
			"Press A or Enter on new device..." if slot == rebinding else Players.device_name(slot.device)]


func _on_slot_changed(_slot: PlayerSlot) -> void:
	_refresh_device_rows()


func _start_rebinding(slot: PlayerSlot) -> void:
	rebinding = slot
	_refresh_device_rows()


func _stop_rebinding() -> void:
	rebinding = null
	_refresh_device_rows()


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
	get_tree().change_scene_to_file(MAIN_MENU)
