extends Control
## Title screen: start single player on a chosen device, open the local
## multiplayer lobby where each device joins by pressing a button on it, or
## host/join an online session by access code (through the Net autoload).
## Every player picks a team (Humans or Skeletons, which sets their color)
## and one of that team's characters on the way in, on a character select
## panel (CharacterSelectPanel) showing the team's lineup in 3D; the host
## also picks the format: map, boss drop and how many bots fill the teams
## (up to 4v4).
## Everyone gets a random name (PlayerNames) they can type over on their
## panel or reroll (Y on a controller, R on the keyboard); it's their name
## and health bar in the match.
## Joined players go into the Players autoload, which Game3D spawns from.

const MIN_LOBBY_PLAYERS := 2
const COPIED_FEEDBACK_TIME := 1.5
## How far a stick must be pushed sideways to change character in the lobby.
const STICK_STEP_THRESHOLD := 0.6
## Online seat cards for empty seats: dark recesses in the wooden frame.
const EMPTY_CARD_COLOR := Color(0.12, 0.06, 0.04, 0.55)
const EMPTY_CARD_BORDER := Color(0.2, 0.09, 0.05, 1)
## People who can join the local lobby (one panel each); bots fill the rest
## of the match (Players.MAX_PLAYERS).
const LOCAL_SEATS := 4
const SOLO_STAGE_SIZE := Vector2(620, 250)
const LOBBY_STAGE_SIZE := Vector2(250, 215)
const ONLINE_STAGE_SIZE := Vector2(360, 300)

@onready var home: Control = %Home
@onready var single_player: Control = %SinglePlayer
@onready var lobby: Control = %Lobby
@onready var controller_button: Button = %Controller
@onready var seats: HBoxContainer = %Seats
@onready var lobby_roster: Label = %LobbyRoster
@onready var start_button: Button = %Start
@onready var lobby_teams: Button = %LobbyTeams
@onready var lobby_bots: Button = %LobbyBots
@onready var solo_teams: Button = %SoloTeams
@onready var solo_bots: Button = %SoloBots
@onready var solo_map: Button = %SoloMap
@onready var solo_drop: Button = %SoloDrop
@onready var lobby_map: Button = %LobbyMap
@onready var lobby_drop: Button = %LobbyDrop
@onready var solo_score: Button = %SoloScore
@onready var lobby_score: Button = %LobbyScore
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
@onready var online_cards: GridContainer = %OnlineCards
@onready var online_status: Label = %OnlineStatus
@onready var online_start: Button = %OnlineStart
@onready var online_teams: Button = %OnlineTeams
@onready var online_bots: Button = %OnlineBots
@onready var online_map: Button = %OnlineMap
@onready var online_drop: Button = %OnlineDrop
@onready var online_score: Button = %OnlineScore

## Last joypad that sent input, so "Controller" picks the pad that pressed it.
var last_joypad: int = -1
## Device that last sent input; seats the local player in an online match
## if they never picked one in the online lobby.
var last_device: int = PlayerSlot.KEYBOARD_MOUSE
## Device picked in the online lobby (A or Enter on it), which can differ
## from whatever is driving the menus.
var online_device: int = Players.NO_DEVICE
## Character select panels: single player's, one per local lobby seat, and
## our own in the online lobby.
var solo_panel: CharacterSelectPanel
var seat_panels: Array[CharacterSelectPanel] = []
var online_panel: CharacterSelectPanel
var online_card_styles: Array[StyleBoxFlat] = []
var online_card_labels: Array[Label] = []
var copy_feedback: Tween
## Single player's picks, used when they choose a device to start on.
var solo_team_choice: int = 0
var solo_character_choice: int = 0
var solo_name_choice: String = ""
## Local lobby: which way each joypad's left stick is pushed (-1, 0, 1), so
## holding it changes character once rather than every frame.
var stick_dirs: Dictionary[int, int] = {}


func _ready() -> void:
	# Back from an online match that ended (Net.match_ended): still in the
	# session, so straight back to its lobby, on the device we played with.
	var back_in_lobby: bool = Net.in_session() and not Net.in_match
	if back_in_lobby and not Players.slots.is_empty():
		online_device = Players.slots[0].device
	# Returning from a match: start with nobody seated.
	Players.leave_all()
	if not back_in_lobby:
		Net.leave()
	solo_name_choice = PlayerNames.saved()
	if solo_name_choice == "":
		solo_name_choice = PlayerNames.random()

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
		# Nothing to pick while there's only the one level
		button.visible = MatchMap.MAPS.size() > 1
	for button: Button in [solo_drop, lobby_drop, online_drop]:
		button.pressed.connect(_cycle_boss_drop)
	for button: Button in [solo_score, lobby_score, online_score]:
		_setup_cycler(button, _step_score_to_win)
	lobby_bots.pressed.connect(_toggle_bots)
	solo_bots.pressed.connect(_toggle_bots)
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

	_build_panels()
	_build_cards(online_cards, online_card_styles, online_card_labels)
	# Only one format (Humans vs Skeletons) for now; see Players.TEAM_COUNTS
	for button: Button in [lobby_teams, online_teams, solo_teams]:
		button.visible = Players.TEAM_COUNTS.size() > 1
	if back_in_lobby:
		_show(online_lobby, online_start if Net.is_host else %OnlineLeave)
	else:
		_show(home, %SinglePlayerButton)
	# Dropped out of an online match: say why
	if Net.end_reason:
		_on_net_session_ended(Net.end_reason)
		Net.end_reason = ""


func _show(screen: Control, focus: Control) -> void:
	for s: Control in [home, single_player, lobby, online, host_setup, join_setup, online_lobby]:
		s.visible = s == screen
	# Character select screens are too tall to fit under the title
	%Title.visible = not screen in [single_player, lobby, online_lobby]
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
	var slot: PlayerSlot = Players.join(device, solo_team_choice, -1, solo_character_choice)
	slot.display_name = solo_name_choice
	_start_game()


func _step_solo_character(step: int) -> void:
	_pick_solo_character(Roster.step(solo_character_choice, solo_team_choice, step))


func _pick_solo_character(character: int) -> void:
	solo_character_choice = Roster.for_team(character, solo_team_choice)
	_refresh_lobby()


func _type_solo_name(text: String) -> void:
	var clean: String = PlayerNames.clean(text)
	if clean != "":
		solo_name_choice = clean
		PlayerNames.save(clean)
	_refresh_lobby()


func _reroll_solo_name() -> void:
	solo_name_choice = PlayerNames.random([solo_name_choice])
	_refresh_lobby()


## The character follows the team: each side has its own.
func _pick_solo_team(team: int) -> void:
	solo_team_choice = posmod(team, Players.team_count)
	solo_character_choice = Roster.for_team(solo_character_choice, solo_team_choice)
	_refresh_lobby()


# ===== CHARACTER SELECT PANELS =====

## Single player's panel (above its options), one panel per local lobby
## seat, and our own in the online lobby (beside the code and seat list).
func _build_panels() -> void:
	solo_panel = CharacterSelectPanel.new(SOLO_STAGE_SIZE)
	solo_panel.set_header("")
	single_player.add_child(solo_panel)
	single_player.move_child(solo_panel, 0)
	solo_panel.team_picked.connect(_pick_solo_team)
	solo_panel.character_picked.connect(_pick_solo_character)
	solo_panel.character_stepped.connect(_step_solo_character)
	solo_panel.name_typed.connect(_type_solo_name)
	solo_panel.name_rerolled.connect(_reroll_solo_name)

	for i in LOCAL_SEATS:
		var panel := CharacterSelectPanel.new(LOBBY_STAGE_SIZE)
		# Each seat steers its own panel from its own device; only the
		# keyboard & mouse player's panel takes clicks (see _refresh_lobby)
		panel.focusable = false
		panel.team_picked.connect(_on_seat_team_picked.bind(i))
		panel.character_picked.connect(_on_seat_character_picked.bind(i))
		panel.character_stepped.connect(_on_seat_character_stepped.bind(i))
		panel.name_typed.connect(_on_seat_name_typed.bind(i))
		panel.name_rerolled.connect(_on_seat_name_rerolled.bind(i))
		seats.add_child(panel)
		seat_panels.append(panel)

	online_panel = CharacterSelectPanel.new(ONLINE_STAGE_SIZE)
	%Main.add_child(online_panel)
	%Main.move_child(online_panel, 0)
	online_panel.team_picked.connect(func(team: int) -> void: _step_online_team(team - Net.local_loadout()[0]))
	online_panel.character_picked.connect(func(character: int) -> void:
		Net.set_loadout(Net.local_loadout()[0], character))
	online_panel.character_stepped.connect(_step_online_character)
	online_panel.name_typed.connect(_type_online_name)
	online_panel.name_rerolled.connect(Net.set_player_name.bind(""))
	online_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	online_status.custom_minimum_size = Vector2(440, 0)


## The local lobby seat shown on panel `i`, if anyone sits there.
func _seat_slot(i: int) -> PlayerSlot:
	for slot: PlayerSlot in Players.slots:
		if slot.index == i:
			return slot
	return null


func _on_seat_team_picked(team: int, i: int) -> void:
	var slot: PlayerSlot = _seat_slot(i)
	if slot:
		Players.set_team(slot, team)


func _on_seat_character_picked(character: int, i: int) -> void:
	var slot: PlayerSlot = _seat_slot(i)
	if slot:
		Players.set_character(slot, character)


func _on_seat_character_stepped(step: int, i: int) -> void:
	var slot: PlayerSlot = _seat_slot(i)
	if slot:
		Players.cycle_character(slot, step)


## Typed in at the keyboard; remembered if it's the keyboard player's own.
## Blank while typing is left for them to finish.
func _on_seat_name_typed(text: String, i: int) -> void:
	var slot: PlayerSlot = _seat_slot(i)
	if slot and (PlayerNames.clean(text) != "" or not seat_panels[i].is_typing()):
		Players.set_player_name(slot, text, slot.uses_keyboard_mouse())


func _on_seat_name_rerolled(i: int) -> void:
	var slot: PlayerSlot = _seat_slot(i)
	if slot:
		Players.reroll_name(slot)


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
	# Typing a name: the keys are letters, not lobby controls
	if event is InputEventKey and _typing():
		return
	var device: int = Players.device_of(event)
	if device == Players.NO_DEVICE:
		return
	if lobby.visible:
		_lobby_input(event, device)
	elif online_lobby.visible:
		_online_lobby_input(event, device)
	elif single_player.visible and _team_step(event) != 0:
		_pick_solo_team(solo_team_choice + _team_step(event))
		accept_event()
	elif single_player.visible and _is_reroll_press(event):
		_reroll_solo_name()
		accept_event()


## A name field has the keyboard.
func _typing() -> bool:
	return get_viewport().gui_get_focus_owner() is LineEdit


## Y on a controller, R on the keyboard: a new random name.
func _is_reroll_press(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		return event.button_index == JOY_BUTTON_Y
	if event is InputEventKey:
		return event.physical_keycode == KEY_R
	return false


## Consume join/leave presses so they don't also click the focused button.
## Presses from players already seated fall through to the UI (e.g. Start).
func _lobby_input(event: InputEvent, device: int) -> void:
	var slot: PlayerSlot = Players.get_slot_for_device(device)
	if not slot and Players.is_join_press(event):
		if Players.slots.size() < LOCAL_SEATS:
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
	elif slot and _is_reroll_press(event):
		Players.reroll_name(slot)
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
	elif _team_step(event) != 0:
		_step_online_team(_team_step(event))
		accept_event()
	elif device == online_device and _is_reroll_press(event):
		Net.set_player_name("")
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and _typing():
		# Esc stops typing rather than leaving the screen
		if Players.is_back_press(event):
			get_viewport().gui_get_focus_owner().release_focus()
			accept_event()
		return
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
	solo_character_choice = Roster.for_team(solo_character_choice, solo_team_choice)
	_refresh_lobby()


## Map button: the next level. One that can't host the current boss drop
## or team count changes those to fit (see Players.set_map).
func _cycle_map() -> void:
	if online_lobby.visible:
		Net.set_map(Players.next_map())
		return
	Players.set_map(Players.next_map())
	solo_team_choice = posmod(solo_team_choice, Players.team_count)
	solo_character_choice = Roster.for_team(solo_character_choice, solo_team_choice)
	_refresh_lobby()


## Ball button: what every boss drops, and on the pitch what kicks off (a
## ball or a bomb). A bomb needs goals, so picking it moves the match to a
## map that has them.
func _cycle_boss_drop() -> void:
	if online_lobby.visible:
		Net.set_boss_drop(Players.next_boss_drop())
		return
	Players.set_boss_drop(Players.next_boss_drop())
	_refresh_lobby()


## Score to Win button: one more (step 1) or fewer (step -1) point to win,
## wrapping around.
func _step_score_to_win(step: int) -> void:
	var span: int = Players.MAX_SCORE_TO_WIN - Players.MIN_SCORE_TO_WIN + 1
	var score: int = Players.MIN_SCORE_TO_WIN + posmod(Players.score_to_win - Players.MIN_SCORE_TO_WIN + step, span)
	if online_lobby.visible:
		Net.set_score_to_win(score)
		return
	Players.set_score_to_win(score)
	_refresh_lobby()


## Map, Boss Drop and Score to Win button labels for the current format.
func _map_text() -> String:
	return "Map: " + MatchMap.name_of(Players.map)


func _drop_text() -> String:
	return "Ball: " + MatchMap.drop_name(Players.boss_drop)


func _score_text() -> String:
	return "Score to Win:  <  %d  >" % Players.score_to_win


## Bots button: cycle the match size bots fill up to (Off, 1v1, 2v2, ...).
func _toggle_bots() -> void:
	Players.bot_fill_count = Players.next_bot_fill_count()
	_refresh_lobby()


func _build_cards(container: GridContainer, styles: Array[StyleBoxFlat], labels: Array[Label]) -> void:
	for i in Players.MAX_PLAYERS:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(216, 52)
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(4)
		style.set_border_width_all(3)
		style.border_color = EMPTY_CARD_BORDER
		style.set_content_margin_all(6)
		card.add_theme_stylebox_override("panel", style)

		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 14)
		card.add_child(label)
		container.add_child(card)
		styles.append(style)
		labels.append(label)


func _refresh_lobby() -> void:
	if seat_panels.is_empty():
		return  # Not built yet
	for i in seat_panels.size():
		var slot: PlayerSlot = _seat_slot(i)
		var panel: CharacterSelectPanel = seat_panels[i]
		if slot:
			panel.set_header("P%d  %s" % [i + 1, Players.device_name(slot.device)])
			panel.interactive = slot.uses_keyboard_mouse()
			panel.show_choice(slot.team, slot.character)
			panel.show_name(slot.display_name, slot.color)
		else:
			panel.set_header("P%d" % (i + 1))
			panel.show_empty("Press A or Enter to join")
	lobby_roster.text = _roster_text()
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
	var seat_count: int = maxi(Players.slots.size(), Players.bot_fill_count if bots else MIN_LOBBY_PLAYERS)
	var lobby_match: Array[int] = Players.teams_with_bots(seat_count, seated)
	lobby_teams.text = "Teams: " + Players.format_name(lobby_match)
	lobby_bots.text = _bots_text(lobby_match)
	for button: Button in [solo_map, lobby_map]:
		button.text = _map_text()
	for button: Button in [solo_drop, lobby_drop]:
		button.text = _drop_text()
	for button: Button in [solo_score, lobby_score]:
		button.text = _score_text()

	var solo_match: Array[int] = Players.teams_with_bots(Players.bot_fill_count, [solo_team_choice])
	solo_teams.text = "Teams: " + Players.format_name(solo_match)
	solo_bots.text = _bots_text(solo_match)
	solo_panel.show_choice(solo_team_choice, solo_character_choice)
	solo_panel.show_name(solo_name_choice, Players.team_color(solo_team_choice))


## Who's on each team in the local lobby, and how many bots join them, e.g.
## "Humans: Bonk, Pip + 2 bots     Skeletons: Grub + 3 bots".
func _roster_text() -> String:
	var seated: Array[int] = Players.slot_teams()
	var sizes: Array[int] = Players.team_sizes(Players.teams_with_bots(Players.bot_fill_count, seated))
	var parts: Array[String] = []
	for team in Players.team_count:
		var names: Array[String] = []
		for slot: PlayerSlot in Players.slots:
			if slot.team == team:
				names.append(slot.label())
		var bot_count: int = sizes[team] - names.size()
		var text: String = ", ".join(names) if not names.is_empty() else ""
		if bot_count > 0:
			text += (" + " if text != "" else "") + "%d bot%s" % [bot_count, "" if bot_count == 1 else "s"]
		parts.append("%s: %s" % [Players.team_name(team), text if text != "" else "nobody"])
	return "     ".join(parts)


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
	_send_saved_name()
	_show(online_lobby, online_start)
	_on_copy_code()


func _on_net_joined(_code: String) -> void:
	online_device = Players.NO_DEVICE
	%JoinConfirm.disabled = false
	_send_saved_name()
	_show(online_lobby, %OnlineLeave)


## The server starts us on a random name; go by the one we last typed.
func _send_saved_name() -> void:
	if PlayerNames.saved() != "":
		Net.set_player_name(PlayerNames.saved())


## Blank while typing is left for them to finish.
func _type_online_name(text: String) -> void:
	var clean: String = PlayerNames.clean(text)
	if clean != "":
		PlayerNames.save(clean)
	if clean != "" or not online_panel.is_typing():
		Net.set_player_name(clean)


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
			var text: String = "P%d  %s  (%s%s)" % [i + 1, Net.name_in(loadout), "Host" if i == 0 else "Guest",
				", You" if id == my_id else ""]
			online_card_labels[i].text = text + "\n" + Players.character_name(loadout[1])
		elif bot < Net.bots.size():
			var loadout: Array = Net.bots[bot]
			online_card_styles[i].bg_color = Players.team_color(loadout[0]).darkened(0.35)
			online_card_labels[i].text = "P%d  %s  (Bot)\n%s" % [i + 1, Net.name_in(loadout),
				Players.character_name(loadout[1])]
		else:
			online_card_styles[i].bg_color = EMPTY_CARD_COLOR
			online_card_labels[i].text = "Waiting for player..."
	online_start.visible = Net.is_host
	# Only the leader picks the format (it's sent with the match start), but
	# everyone sees it
	for button: Button in [online_teams, online_bots, online_map, online_drop, online_score]:
		button.disabled = not Net.is_host
	online_map.text = _map_text()
	online_drop.text = _drop_text()
	online_score.text = _score_text()
	online_bots.text = "Bots:  <  %d  >" % Net.bots.size()
	var teams: Array[int] = Net.seat_teams()
	var split: bool = Players.team_split(teams) != ""
	online_teams.text = "Teams: " + Players.format_name(teams)
	online_start.disabled = Net.seat_count() < MIN_LOBBY_PLAYERS or online_device == Players.NO_DEVICE or not split
	var mine: Array = Net.local_loadout()
	online_panel.set_header("You  ·  " + ("Press A or Enter on your device" if online_device == Players.NO_DEVICE
		else Players.device_name(online_device)))
	if online_lobby.visible:
		online_panel.show_choice(mine[0], mine[1])
		online_panel.show_name(Net.name_in(mine), Players.team_color(mine[0]))
	if online_device == Players.NO_DEVICE:
		online_status.text = "Press A or Enter on the device you'll play with."
	elif Net.seat_count() >= MIN_LOBBY_PLAYERS and not split:
		online_status.text = "Everyone's on one team. Someone needs to switch."
	elif Net.is_host:
		online_status.text = "Send the code to your friends."
	else:
		online_status.text = "Waiting for the host to start."
	_chain_online_focus()


## The lobby buttons sit in rows, but the character arrows and Bots use
## left/right to cycle, so up/down walks every visible button in reading order.
func _chain_online_focus() -> void:
	var chain: Array[Control] = []
	for button: Button in [online_panel.first_focus(), online_teams, online_bots, online_map, online_drop,
			online_score, online_start, %OnlineLeave]:
		if button.visible and not button.disabled:
			chain.append(button)
	for i in chain.size():
		var prev: Control = chain[i - 1] if i > 0 else chain[i]
		var next: Control = chain[i + 1] if i < chain.size() - 1 else chain[i]
		chain[i].focus_neighbor_top = chain[i].get_path_to(prev)
		chain[i].focus_neighbor_bottom = chain[i].get_path_to(next)


func _step_online_character(step: int) -> void:
	var mine: Array = Net.local_loadout()
	Net.set_loadout(mine[0], Roster.step(mine[1], mine[0], step))


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
	var slot: PlayerSlot = Players.join(device, mine[0], Net.local_seat(), mine[1])
	slot.display_name = Net.name_in(mine)
	_start_game()


func _start_game() -> void:
	get_tree().change_scene_to_file(MatchMap.scene_of(Players.map))
