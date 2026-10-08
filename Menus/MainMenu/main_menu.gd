extends Control
## Title screen: start single player on a chosen device, open the local
## multiplayer lobby where each device joins by pressing a button on it, or
## host/join an online session by access code (through the Net autoload).
## Every player picks a character and a team (which sets their color) on
## the way in; the host also picks the format: teams, map and boss drop.
## Joined players go into the Players autoload, which Game3D spawns from.

const MIN_LOBBY_PLAYERS := 2
const COPIED_FEEDBACK_TIME := 1.5
## How far a stick must be pushed sideways to change character in the lobby.
const STICK_STEP_THRESHOLD := 0.6
## Lobby cards for empty seats: dark recesses in the wooden frame.
const EMPTY_CARD_COLOR := Color(0.12, 0.06, 0.04, 0.55)
const EMPTY_CARD_BORDER := Color(0.2, 0.09, 0.05, 1)

@onready var home: Control = %Home
@onready var single_player: Control = %SinglePlayer
@onready var lobby: Control = %Lobby
@onready var controller_button: Button = %Controller
@onready var cards: HBoxContainer = %Cards
@onready var start_button: Button = %Start
@onready var lobby_teams: Button = %LobbyTeams
@onready var lobby_bots: Button = %LobbyBots
@onready var solo_teams: Button = %SoloTeams
@onready var solo_bots: Button = %SoloBots
@onready var solo_map: Button = %SoloMap
@onready var solo_drop: Button = %SoloDrop
@onready var lobby_map: Button = %LobbyMap
@onready var lobby_drop: Button = %LobbyDrop
@onready var solo_character: Button = %SoloCharacter
@onready var solo_team: Button = %SoloTeam
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
@onready var online_teams: Button = %OnlineTeams
@onready var online_bots: Button = %OnlineBots
@onready var online_map: Button = %OnlineMap
@onready var online_drop: Button = %OnlineDrop
@onready var online_character: Button = %OnlineCharacter
@onready var online_team: Button = %OnlineTeam

## Last joypad that sent input, so "Controller" picks the pad that pressed it.
var last_joypad: int = -1
## Device that last sent input; seats the local player in an online match
## if they never picked one in the online lobby.
var last_device: int = PlayerSlot.KEYBOARD_MOUSE
## Device picked in the online lobby (A or Enter on it), which can differ
## from whatever is driving the menus.
var online_device: int = Players.NO_DEVICE
var card_styles: Array[StyleBoxFlat] = []
var card_labels: Array[Label] = []
var online_card_styles: Array[StyleBoxFlat] = []
var online_card_labels: Array[Label] = []
var copy_feedback: Tween
## Single player's picks, used when they choose a device to start on.
var solo_team_choice: int = 0
var solo_character_choice: int = 0
## Local lobby: which way each joypad's left stick is pushed (-1, 0, 1), so
## holding it changes character once rather than every frame.
var stick_dirs: Dictionary[int, int] = {}


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
	lobby_teams.pressed.connect(_cycle_team_count)
	online_teams.pressed.connect(_cycle_team_count)
	solo_teams.pressed.connect(_cycle_team_count)
	for button: Button in [solo_map, lobby_map, online_map]:
		button.pressed.connect(_cycle_map)
	for button: Button in [solo_drop, lobby_drop, online_drop]:
		button.pressed.connect(_cycle_boss_drop)
	lobby_bots.pressed.connect(_toggle_bots)
	solo_bots.pressed.connect(_toggle_bots)
	_setup_cycler(solo_character, _step_solo_character)
	_setup_cycler(solo_team, _step_solo_team)
	_setup_cycler(online_character, _step_online_character)
	_setup_cycler(online_team, _step_online_team)
	_setup_cycler(online_bots, _step_online_bots)
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
	Players.slot_changed.connect(func(_slot: PlayerSlot) -> void: _refresh_lobby())

	_build_cards(cards, card_styles, card_labels)
	_build_cards(online_cards, online_card_styles, online_card_labels)
	_show(home, %SinglePlayerButton)


func _show(screen: Control, focus: Control) -> void:
	for s: Control in [home, single_player, lobby, online, host_setup, join_setup, online_lobby]:
		s.visible = s == screen
	# The lobbies are too tall to fit under the title
	%Title.visible = screen != lobby and screen != online_lobby
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
	Players.join(device, solo_team_choice, -1, solo_character_choice)
	_start_game()


func _step_solo_character(step: int) -> void:
	solo_character_choice = posmod(solo_character_choice + step, Players.character_count())
	_refresh_lobby()


func _step_solo_team(step: int) -> void:
	solo_team_choice = posmod(solo_team_choice + step, Players.team_count)
	_refresh_lobby()


# ===== PICKERS =====

## A button that cycles through choices: click, A or Enter (and Right) step
## forward; right-click and Left step back. `on_step` gets 1 or -1.
func _setup_cycler(button: Button, on_step: Callable) -> void:
	button.pressed.connect(on_step.bind(1))
	button.gui_input.connect(func(event: InputEvent) -> void:
		var step: int = 0
		if event.is_action_pressed("ui_left"):
			step = -1
		elif event.is_action_pressed("ui_right"):
			step = 1
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			step = -1
		if step != 0:
			on_step.call(step)
			button.accept_event())


func _character_text(character: int) -> String:
	return "Character:  <  %s  >" % Players.character_name(character)


func _team_text(team: int) -> String:
	return "Team:  <  %s  >" % Players.team_name(team)


## Tint a picker button with the team's color, so it reads at a glance.
func _tint_team_button(button: Button, team: int) -> void:
	var color: Color = Players.team_color(team)
	for state: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		button.add_theme_color_override(state, color.lightened(0.6))


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

	if lobby.visible and event is InputEventJoypadMotion:
		_lobby_stick_input(event)
	if not event.is_pressed() or event.is_echo():
		return
	var device: int = Players.device_of(event)
	if device == Players.NO_DEVICE:
		return
	if lobby.visible:
		_lobby_input(event, device)
	elif online_lobby.visible:
		_online_lobby_input(event, device)


## Consume join/leave presses so they don't also click the focused button.
## Presses from players already seated fall through to the UI (e.g. Start).
func _lobby_input(event: InputEvent, device: int) -> void:
	var slot: PlayerSlot = Players.get_slot_for_device(device)
	if not slot and Players.is_join_press(event):
		Players.join(device)
		accept_event()
	elif slot and Players.is_back_press(event):
		Players.leave(slot)
		accept_event()
	elif slot and _character_step(event) != 0:
		Players.cycle_character(slot, _character_step(event))
		accept_event()
	elif slot and _team_step(event) != 0:
		Players.cycle_team(slot, _team_step(event))
		accept_event()


## Lobby: D-pad left/right, or A/D and the arrow keys, change character.
func _character_step(event: InputEvent) -> int:
	if event is InputEventJoypadButton:
		match event.button_index:
			JOY_BUTTON_DPAD_LEFT: return -1
			JOY_BUTTON_DPAD_RIGHT: return 1
	elif event is InputEventKey:
		match event.physical_keycode:
			KEY_A, KEY_LEFT: return -1
			KEY_D, KEY_RIGHT: return 1
	return 0


## Lobby: the shoulder buttons, or Q/E, change team.
func _team_step(event: InputEvent) -> int:
	if event is InputEventJoypadButton:
		match event.button_index:
			JOY_BUTTON_LEFT_SHOULDER: return -1
			JOY_BUTTON_RIGHT_SHOULDER: return 1
	elif event is InputEventKey:
		match event.physical_keycode:
			KEY_Q: return -1
			KEY_E: return 1
	return 0


## Lobby: pushing a seated pad's left stick sideways changes character once
## per push.
func _lobby_stick_input(event: InputEventJoypadMotion) -> void:
	if event.axis != JOY_AXIS_LEFT_X:
		return
	var dir: int = 0
	if absf(event.axis_value) >= STICK_STEP_THRESHOLD:
		dir = int(signf(event.axis_value))
	if dir == stick_dirs.get(event.device, 0):
		return
	stick_dirs[event.device] = dir
	var slot: PlayerSlot = Players.get_slot_for_device(event.device)
	if slot and dir != 0:
		Players.cycle_character(slot, dir)
		accept_event()


## A or Enter on any device picks it to play with; the menus themselves can
## still be driven by anything (e.g. the mouse). Presses from the picked
## device fall through to the UI, so it can press Start.
func _online_lobby_input(event: InputEvent, device: int) -> void:
	if device != online_device and Players.is_join_press(event):
		online_device = device
		accept_event()
		_refresh_online_lobby()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and Players.is_back_press(event) and not home.visible:
		_go_back()
		accept_event()


## Teams button: 2 teams (2P field) <-> 4 teams (4P field). Online, only
## the leader has it, and the server passes it on to everyone.
func _cycle_team_count() -> void:
	if online_lobby.visible:
		Net.set_team_count(Players.next_team_count())
		return
	Players.set_team_count(Players.next_team_count())
	solo_team_choice = posmod(solo_team_choice, Players.team_count)
	_refresh_lobby()


## Map button: the next level. One that can't host the current boss drop
## or team count changes those to fit (see Players.set_map).
func _cycle_map() -> void:
	if online_lobby.visible:
		Net.set_map(Players.next_map())
		return
	Players.set_map(Players.next_map())
	solo_team_choice = posmod(solo_team_choice, Players.team_count)
	_refresh_lobby()


## Boss Drop button: what every boss drops. A ball needs goals, so picking
## it moves the match to a map that has them.
func _cycle_boss_drop() -> void:
	if online_lobby.visible:
		Net.set_boss_drop(Players.next_boss_drop())
		return
	Players.set_boss_drop(Players.next_boss_drop())
	_refresh_lobby()


## Map and Boss Drop button labels for the current format.
func _map_text() -> String:
	return "Map: " + MatchMap.name_of(Players.map)


func _drop_text() -> String:
	return "Boss Drop: " + MatchMap.drop_name(Players.boss_drop)


## Bots button: cycle the match size bots fill up to (Off, 1v1, 2v2, ...).
func _toggle_bots() -> void:
	Players.bot_fill_count = Players.next_bot_fill_count()
	_refresh_lobby()


func _build_cards(container: HBoxContainer, styles: Array[StyleBoxFlat], labels: Array[Label]) -> void:
	for i in Players.MAX_PLAYERS:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(200, 150)
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(4)
		style.set_border_width_all(3)
		style.border_color = EMPTY_CARD_BORDER
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
			card_labels[i].text = "P%d\n%s\n\n<  %s  >\nTeam %s" % [i + 1, Players.device_name(slot.device),
				Players.character_name(slot.character), Players.team_name(slot.team)]
		else:
			card_styles[i].bg_color = EMPTY_CARD_COLOR
			var bot: bool = i < Players.bot_fill_count
			card_labels[i].text = ("Bot\n" if bot else "") + "Press A or Enter\nto join"
	var bots: bool = Players.bot_fill_count > 0
	# Bots fill up to bot_fill_count; more joined players still all play
	var seated: Array[int] = Players.slot_teams()
	var match_teams: Array[int] = Players.teams_with_bots(Players.bot_fill_count, seated)
	var enough: bool = Players.slots.size() >= (1 if bots else MIN_LOBBY_PLAYERS)
	var split: bool = Players.team_split(match_teams) != ""
	start_button.disabled = not enough or not split
	if not enough:
		start_button.text = "Start (2+ players)"
	elif not split:
		start_button.text = "Start (2+ teams)"
	else:
		start_button.text = "Start"
	var seats: int = maxi(Players.slots.size(), Players.bot_fill_count if bots else MIN_LOBBY_PLAYERS)
	var lobby_match: Array[int] = Players.teams_with_bots(seats, seated)
	lobby_teams.text = "Teams: " + Players.format_name(lobby_match)
	lobby_bots.text = _bots_text(lobby_match)
	for button: Button in [solo_map, lobby_map]:
		button.text = _map_text()
	for button: Button in [solo_drop, lobby_drop]:
		button.text = _drop_text()

	var solo_match: Array[int] = Players.teams_with_bots(Players.bot_fill_count, [solo_team_choice])
	solo_teams.text = "Teams: " + Players.format_name(solo_match)
	solo_bots.text = _bots_text(solo_match)
	solo_character.text = _character_text(solo_character_choice)
	solo_team.text = _team_text(solo_team_choice)
	_tint_team_button(solo_team, solo_team_choice)


## "Bots: Fill to 2v2"-style label for the Bots buttons, for a match of
## players on `teams`.
func _bots_text(teams: Array[int]) -> String:
	if Players.bot_fill_count == 0:
		return "Bots: Off"
	return "Bots: Fill to " + Players.team_split(teams)


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


## Copy the code straight away so it's ready to paste to friends.
func _on_net_hosted(_code: String) -> void:
	online_device = Players.NO_DEVICE
	_show(online_lobby, online_start)
	_on_copy_code()


func _on_net_joined(_code: String) -> void:
	online_device = Players.NO_DEVICE
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
		var bot: int = i - Net.peers.size()
		if i < Net.peers.size():
			var id: int = Net.peers[i]
			var loadout: Array = Net.loadout_of(id)
			online_card_styles[i].bg_color = Players.team_color(loadout[0]).darkened(0.35)
			var text: String = "P%d\n%s" % [i + 1, "Host" if i == 0 else "Guest"]
			if id == my_id:
				text += " (You)\n" + ("Press A or Enter\nto pick your device" if online_device == Players.NO_DEVICE
					else Players.device_name(online_device))
			text += "\n\n%s\nTeam %s" % [Players.character_name(loadout[1]), Players.team_name(loadout[0])]
			online_card_labels[i].text = text
		elif bot < Net.bots.size():
			var loadout: Array = Net.bots[bot]
			online_card_styles[i].bg_color = Players.team_color(loadout[0]).darkened(0.35)
			online_card_labels[i].text = "P%d\nBot\n\n%s\nTeam %s" % [i + 1, Players.character_name(loadout[1]),
				Players.team_name(loadout[0])]
		else:
			online_card_styles[i].bg_color = EMPTY_CARD_COLOR
			online_card_labels[i].text = "Waiting for\nplayer..."
	online_start.visible = Net.is_host
	# Only the leader picks the format (it's sent with the match start), but
	# everyone sees it
	for button: Button in [online_teams, online_bots, online_map, online_drop]:
		button.disabled = not Net.is_host
	online_map.text = _map_text()
	online_drop.text = _drop_text()
	online_bots.text = "Bots:  <  %d  >" % Net.bots.size()
	var teams: Array[int] = Net.seat_teams()
	var split: bool = Players.team_split(teams) != ""
	online_teams.text = "Teams: " + Players.format_name(teams)
	online_start.disabled = Net.seat_count() < MIN_LOBBY_PLAYERS or online_device == Players.NO_DEVICE or not split
	var mine: Array = Net.local_loadout()
	online_character.text = _character_text(mine[1])
	online_team.text = _team_text(mine[0])
	_tint_team_button(online_team, mine[0])
	if online_device == Players.NO_DEVICE:
		online_status.text = "Press A or Enter on the device you'll play with."
	elif Net.seat_count() >= MIN_LOBBY_PLAYERS and not split:
		online_status.text = "Everyone's on one team. Someone needs to switch."
	elif Net.is_host:
		online_status.text = "Send the code to your friends."
	else:
		online_status.text = "Waiting for the host to start."
	_chain_online_focus()


## The lobby buttons sit in two rows, but Character and Team use left/right
## to cycle, so up/down walks every visible button in reading order.
func _chain_online_focus() -> void:
	var chain: Array[Control] = []
	for button: Button in [online_character, online_team, online_teams, online_bots, online_map, online_drop,
			online_start, %OnlineLeave]:
		if button.visible and not button.disabled:
			chain.append(button)
	for i in chain.size():
		var prev: Control = chain[i - 1] if i > 0 else chain[i]
		var next: Control = chain[i + 1] if i < chain.size() - 1 else chain[i]
		chain[i].focus_neighbor_top = chain[i].get_path_to(prev)
		chain[i].focus_neighbor_bottom = chain[i].get_path_to(next)


func _step_online_character(step: int) -> void:
	var mine: Array = Net.local_loadout()
	Net.set_loadout(mine[0], mine[1] + step)


func _step_online_team(step: int) -> void:
	var mine: Array = Net.local_loadout()
	Net.set_loadout(mine[0] + step, mine[1])


## Leader's Bots picker: add a bot (to the smallest team) or remove the
## last one added. The server runs them in the match.
func _step_online_bots(step: int) -> void:
	if step > 0:
		Net.add_bot()
	else:
		Net.remove_bot()


## Each machine seats only its own player, in its session seat, as the
## team and character picked in the lobby; Game3D spawns everyone else as
## remote players. A guest who never picked a device gets the last one they
## touched (and can change it from the pause menu).
func _on_match_started() -> void:
	Players.leave_all()
	var device: int = online_device if online_device != Players.NO_DEVICE else last_device
	var mine: Array = Net.local_loadout()
	Players.join(device, mine[0], Net.local_seat(), mine[1])
	_start_game()


func _start_game() -> void:
	get_tree().change_scene_to_file(MatchMap.scene_of(Players.map))
