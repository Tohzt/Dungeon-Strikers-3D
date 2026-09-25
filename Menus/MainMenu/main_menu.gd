extends Control
## Title screen: start single player on a chosen device, or open the local
## multiplayer lobby where each device joins by pressing a button on it.
## Joined players go into the Players autoload, which Game3D spawns from.

const GAME_SCENE := "res://3D/Game/Game3D.tscn"
const MIN_LOBBY_PLAYERS := 2
const NO_DEVICE := -2

@onready var home: Control = %Home
@onready var single_player: Control = %SinglePlayer
@onready var lobby: Control = %Lobby
@onready var controller_button: Button = %Controller
@onready var cards: HBoxContainer = %Cards
@onready var start_button: Button = %Start

## Last joypad that sent input, so "Controller" picks the pad that pressed it.
var last_joypad: int = -1
var card_styles: Array[StyleBoxFlat] = []
var card_labels: Array[Label] = []


func _ready() -> void:
	# Returning from a match: start with nobody seated.
	Players.leave_all()

	%SinglePlayerButton.pressed.connect(_show.bind(single_player, %KeyboardMouse))
	%LocalMultiplayerButton.pressed.connect(_show.bind(lobby, start_button))
	%QuitButton.pressed.connect(get_tree().quit)
	%KeyboardMouse.pressed.connect(_start_single_player.bind(PlayerSlot.KEYBOARD_MOUSE))
	controller_button.pressed.connect(_start_single_player_controller)
	%SinglePlayerBack.pressed.connect(_back_to_home)
	start_button.pressed.connect(_start_game)
	%LobbyBack.pressed.connect(_back_to_home)

	Input.joy_connection_changed.connect(func(_device: int, _connected: bool) -> void: _refresh_controller_button())
	Players.slot_joined.connect(func(_slot: PlayerSlot) -> void: _refresh_lobby())
	Players.slot_left.connect(func(_slot: PlayerSlot) -> void: _refresh_lobby())

	_build_cards()
	_show(home, %SinglePlayerButton)


func _show(screen: Control, focus: Control) -> void:
	for s: Control in [home, single_player, lobby]:
		s.visible = s == screen
	_refresh_controller_button()
	_refresh_lobby()
	focus.grab_focus()


func _back_to_home() -> void:
	Players.leave_all()
	_show(home, %SinglePlayerButton)


# ===== SINGLE PLAYER =====

func _start_single_player(device: int) -> void:
	Players.leave_all()
	Players.join(device)
	_start_game()


func _start_single_player_controller() -> void:
	var pads: Array[int] = Input.get_connected_joypads()
	if pads.is_empty(): return
	_start_single_player(last_joypad if pads.has(last_joypad) else pads[0])


func _refresh_controller_button() -> void:
	var has_pad: bool = not Input.get_connected_joypads().is_empty()
	controller_button.disabled = not has_pad
	controller_button.text = "Controller" if has_pad else "Controller (none connected)"


# ===== LOCAL MULTIPLAYER LOBBY =====

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		last_joypad = event.device

	if not lobby.visible or not event.is_pressed() or event.is_echo():
		return
	var device: int = _device_of(event)
	if device == NO_DEVICE:
		return

	# Consume join/leave presses so they don't also click the focused button.
	# Presses from players already seated fall through to the UI (e.g. Start).
	var slot: PlayerSlot = Players.get_slot_for_device(device)
	if not slot and _is_join_press(event):
		Players.join(device)
		accept_event()
	elif slot and _is_back_press(event):
		Players.leave(slot)
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and _is_back_press(event) and not home.visible:
		_back_to_home()
		accept_event()


func _device_of(event: InputEvent) -> int:
	if event is InputEventJoypadButton:
		return event.device
	if event is InputEventKey:
		return PlayerSlot.KEYBOARD_MOUSE
	return NO_DEVICE


func _is_join_press(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		return event.button_index in [JOY_BUTTON_A, JOY_BUTTON_START]
	if event is InputEventKey:
		return event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	return false


func _is_back_press(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		return event.button_index in [JOY_BUTTON_B, JOY_BUTTON_BACK]
	if event is InputEventKey:
		return event.physical_keycode == KEY_ESCAPE
	return false


func _build_cards() -> void:
	for i in Players.MAX_PLAYERS:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(200, 150)
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(8)
		style.set_content_margin_all(12)
		card.add_theme_stylebox_override("panel", style)

		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 20)
		card.add_child(label)
		cards.add_child(card)
		card_styles.append(style)
		card_labels.append(label)


func _refresh_lobby() -> void:
	for i in card_labels.size():
		var slot: PlayerSlot = null
		for s: PlayerSlot in Players.slots:
			if s.index == i:
				slot = s
		if slot:
			card_styles[i].bg_color = slot.color.darkened(0.35)
			card_labels[i].text = "P%d\n%s" % [i + 1, _device_name(slot.device)]
		else:
			card_styles[i].bg_color = Color(1, 1, 1, 0.06)
			card_labels[i].text = "Press A or Enter\nto join"
	start_button.disabled = Players.slots.size() < MIN_LOBBY_PLAYERS


func _device_name(device: int) -> String:
	if device == PlayerSlot.KEYBOARD_MOUSE:
		return "Keyboard & Mouse"
	var pad_name: String = Input.get_joy_name(device)
	return pad_name if pad_name != "" else "Controller %d" % (device + 1)


func _start_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)
