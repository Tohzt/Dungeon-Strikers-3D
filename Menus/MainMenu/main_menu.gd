extends Control
## Title screen: start single player on a chosen device, open the local
## multiplayer lobby where each device joins by pressing a button on it, or
## host/join an online session by access code (through the Net autoload).
## Joined players go into the Players autoload, which Game3D spawns from.

const GAME_SCENE := "res://3D/Game/Game3D.tscn"
const MIN_LOBBY_PLAYERS := 2
const NO_DEVICE := -2
const COPIED_FEEDBACK_TIME := 1.5

@onready var home: Control = %Home
@onready var single_player: Control = %SinglePlayer
@onready var lobby: Control = %Lobby
@onready var controller_button: Button = %Controller
@onready var cards: HBoxContainer = %Cards
@onready var start_button: Button = %Start
@onready var online: Control = %Online
@onready var host_setup: Control = %HostSetup
@onready var join_setup: Control = %JoinSetup
@onready var online_lobby: Control = %OnlineLobby
@onready var host_code_input: LineEdit = %HostCodeInput
@onready var join_code_input: LineEdit = %JoinCodeInput
@onready var host_status: Label = %HostStatus
@onready var join_status: Label = %JoinStatus
@onready var code_label: Label = %CodeLabel
@onready var copy_button: Button = %CopyCode
@onready var online_cards: HBoxContainer = %OnlineCards
@onready var online_status: Label = %OnlineStatus
@onready var online_start: Button = %OnlineStart

## Last joypad that sent input, so "Controller" picks the pad that pressed it.
var last_joypad: int = -1
## Device that last sent input; seats the local player in an online match.
var last_device: int = PlayerSlot.KEYBOARD_MOUSE
var card_styles: Array[StyleBoxFlat] = []
var card_labels: Array[Label] = []
var online_card_styles: Array[StyleBoxFlat] = []
var online_card_labels: Array[Label] = []
var copy_feedback: Tween


func _ready() -> void:
	# Returning from a match: start with nobody seated.
	Players.leave_all()
	Net.leave()

	%SinglePlayerButton.pressed.connect(_show.bind(single_player, %KeyboardMouse))
	%LocalMultiplayerButton.pressed.connect(_show.bind(lobby, start_button))
	%OnlineButton.pressed.connect(_show.bind(online, %HostButton))
	%QuitButton.pressed.connect(get_tree().quit)
	%KeyboardMouse.pressed.connect(_start_single_player.bind(PlayerSlot.KEYBOARD_MOUSE))
	controller_button.pressed.connect(_start_single_player_controller)
	%SinglePlayerBack.pressed.connect(_back_to_home)
	start_button.pressed.connect(_start_game)
	%LobbyBack.pressed.connect(_back_to_home)

	%HostButton.pressed.connect(_open_host_setup)
	%JoinButton.pressed.connect(_open_join_setup)
	%OnlineBack.pressed.connect(_back_to_home)
	%RandomCode.pressed.connect(_on_random_code)
	%HostConfirm.pressed.connect(_host)
	%HostBack.pressed.connect(_back_to_online)
	%PasteCode.pressed.connect(_on_paste_code)
	%JoinConfirm.pressed.connect(_join)
	%JoinBack.pressed.connect(_back_to_online)
	copy_button.pressed.connect(_on_copy_code)
	online_start.pressed.connect(Net.start_match)
	%OnlineLeave.pressed.connect(_back_to_online)
	for input: LineEdit in [host_code_input, join_code_input]:
		input.text_changed.connect(_on_code_text_changed.bind(input))
	host_code_input.text_submitted.connect(func(_text: String) -> void: _host())
	join_code_input.text_submitted.connect(func(_text: String) -> void: _join())

	Net.hosted.connect(_on_net_hosted)
	Net.joined.connect(_on_net_joined)
	Net.failed.connect(_on_net_failed)
	Net.peers_changed.connect(_refresh_online_lobby)
	Net.session_ended.connect(_on_net_session_ended)
	Net.match_started.connect(_on_match_started)

	Input.joy_connection_changed.connect(func(_device: int, _connected: bool) -> void: _refresh_controller_button())
	Players.slot_joined.connect(func(_slot: PlayerSlot) -> void: _refresh_lobby())
	Players.slot_left.connect(func(_slot: PlayerSlot) -> void: _refresh_lobby())

	_build_cards(cards, card_styles, card_labels)
	_build_cards(online_cards, online_card_styles, online_card_labels)
	_show(home, %SinglePlayerButton)


func _show(screen: Control, focus: Control) -> void:
	for s: Control in [home, single_player, lobby, online, host_setup, join_setup, online_lobby]:
		s.visible = s == screen
	_refresh_controller_button()
	_refresh_lobby()
	_refresh_online_lobby()
	focus.grab_focus()


func _back_to_home() -> void:
	Players.leave_all()
	Net.leave()
	_show(home, %SinglePlayerButton)


## Back from any online sub-screen; leaves the session if we were in one.
func _back_to_online() -> void:
	Net.leave()
	_show(online, %HostButton)


func _go_back() -> void:
	if host_setup.visible or join_setup.visible or online_lobby.visible:
		_back_to_online()
	else:
		_back_to_home()


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
		last_device = event.device
	elif event is InputEventKey or event is InputEventMouseButton:
		last_device = PlayerSlot.KEYBOARD_MOUSE

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
		_go_back()
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


func _build_cards(container: HBoxContainer, styles: Array[StyleBoxFlat], labels: Array[Label]) -> void:
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
		container.add_child(card)
		styles.append(style)
		labels.append(label)


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


# ===== ONLINE =====

func _open_host_setup() -> void:
	host_status.text = ""
	_show(host_setup, host_code_input)


func _open_join_setup() -> void:
	join_status.text = ""
	_show(join_setup, join_code_input)


func _on_random_code() -> void:
	host_code_input.text = Net.generate_code()


func _on_paste_code() -> void:
	join_code_input.text = Net.normalize_code(DisplayServer.clipboard_get()).left(join_code_input.max_length)
	join_code_input.caret_column = join_code_input.text.length()


## Keep typed/pasted codes uppercase letters and digits only.
func _on_code_text_changed(text: String, input: LineEdit) -> void:
	var clean: String = Net.normalize_code(text)
	if clean != text:
		var caret: int = input.caret_column
		input.text = clean
		input.caret_column = mini(caret, clean.length())


func _host() -> void:
	host_status.text = ""
	Net.host(host_code_input.text)


func _join() -> void:
	join_status.text = "Connecting..."
	%JoinConfirm.disabled = true
	Net.join(join_code_input.text)


func _on_net_hosted(_code: String) -> void:
	_show(online_lobby, online_start)


func _on_net_joined(_code: String) -> void:
	%JoinConfirm.disabled = false
	_show(online_lobby, %OnlineLeave)


func _on_net_failed(reason: String) -> void:
	%JoinConfirm.disabled = false
	host_status.text = reason
	join_status.text = reason


func _on_net_session_ended(reason: String) -> void:
	_show(join_setup, join_code_input)
	join_status.text = reason


func _on_copy_code() -> void:
	DisplayServer.clipboard_set(Net.access_code)
	copy_button.text = "Copied!"
	if copy_feedback:
		copy_feedback.kill()
	copy_feedback = create_tween()
	copy_feedback.tween_callback(func() -> void: copy_button.text = "Copy").set_delay(COPIED_FEEDBACK_TIME)


func _refresh_online_lobby() -> void:
	code_label.text = Net.access_code
	var my_id: int = multiplayer.get_unique_id()
	for i in online_card_labels.size():
		if i < Net.peers.size():
			var id: int = Net.peers[i]
			online_card_styles[i].bg_color = Players.TEAM_COLORS[i].darkened(0.35)
			online_card_labels[i].text = "P%d\n%s%s" % [i + 1, "Host" if i == 0 else "Guest", " (You)" if id == my_id else ""]
		else:
			online_card_styles[i].bg_color = Color(1, 1, 1, 0.06)
			online_card_labels[i].text = "Waiting for\nplayer..."
	online_start.visible = Net.is_host
	online_start.disabled = Net.peers.size() < MIN_LOBBY_PLAYERS
	if Net.is_host:
		online_status.text = "Send the code to your friends."
	else:
		online_status.text = "Waiting for the host to start."


## Each machine seats only its own player, in its session seat; Game3D
## spawns everyone else as remote players.
func _on_match_started() -> void:
	Players.leave_all()
	Players.join(last_device, Net.local_seat(), Net.local_seat())
	_start_game()


func _start_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)
