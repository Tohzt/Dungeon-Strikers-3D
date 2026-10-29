class_name MainMenu extends Control
## Title screen: Local, Online, the Codex, Training (not built yet) and Quit.
##
## Local and Online lead to the same lobby: the players' character select
## panels (CharacterSelectPanel) in a row along the top, and the match
## settings under them. It changes a little with where it's played:
## - Local: a panel per seat on this machine, as many as the Players picker
##   shows (1 to LOCAL_SEATS). Each device joins by pressing A or Enter on
##   it (or a click on an empty seat, for the keyboard & mouse), which opens
##   another seat if they're all taken; picking Local with a controller or
##   the keyboard seats that device straight away. Each seat is steered from
##   its own device.
## - Online: one panel for our own pick, the access code, and who's in the
##   session (from the Net autoload). Only the leader sets the format.
## Each team's size is picked on its own, shown as people / seats (say
## "Humans: 2/3" for two people in three seats). With Fill with Bots on,
## bots take the empty seats (see Players.seats_per_team); off, only people
## play. Panels are a fixed size, so long names don't shift the layout.
##
## Everyone gets a random name (PlayerNames) they can type over on their
## panel or reroll (Y on a controller, R on the keyboard); it's their name
## and health bar in the match.
## Joined players go into the Players autoload, which Game3D spawns from.

const CODEX := "res://UI/Menus/Codex/codex_menu.tscn"
const MIN_LOBBY_PLAYERS := 2
const COPIED_FEEDBACK_TIME := 1.5
## How far a stick must be pushed sideways to change character in the lobby.
const STICK_STEP_THRESHOLD := 0.6
const TEAM_SIZE_BUTTON := Vector2(264, 44)
## People who can play on one machine (one panel each); bots fill the rest
## of the match (Players.MAX_PLAYERS).
const LOCAL_SEATS := 4
const LOCAL_STAGE_SIZE := Vector2(250, 215)
const ONLINE_STAGE_SIZE := Vector2(360, 300)
## Seconds a newly shown seat panel takes to fade in, while the frame
## (SmoothPanelContainer) grows to fit it.
const PANEL_FADE_TIME := 0.3
## Start pressed when the match can't start: the button shakes side to side
## by these offsets (px), one every SHAKE_STEP seconds, and a note says why
## for NOTE_TIME seconds, then fades over NOTE_FADE_TIME.
const SHAKE_OFFSETS: Array[float] = [10.0, -10.0, 7.0, -7.0, 3.0, 0.0]
const SHAKE_STEP := 0.04
const NOTE_TIME := 1.8
const NOTE_FADE_TIME := 0.4
const NOTE_GAP := 12.0

@onready var home: Control = %Home
@onready var lobby: Control = %Lobby
@onready var seats: HBoxContainer = %Seats
@onready var players_button: Button = %PlayersButton
@onready var bots_button: Button = %BotsButton
@onready var code_panel: Control = %CodePanel
@onready var online_roster: Label = %OnlineRoster
@onready var team_sizes: HBoxContainer = %TeamSizes
@onready var lobby_status: Label = %LobbyStatus
@onready var start_button: Button = %Start
@onready var back_button: Button = %LobbyBack
@onready var teams_button: Button = %TeamsButton
@onready var map_button: Button = %MapButton
@onready var drop_button: Button = %DropButton
@onready var score_button: Button = %ScoreButton
@onready var online: Control = %Online
@onready var host_setup: Control = %HostSetup
@onready var join_setup: Control = %JoinSetup
@onready var host_code_input: LineEdit = %HostCodeInput
@onready var join_code_input: LineEdit = %JoinCodeInput
@onready var host_status: Label = %HostStatus
@onready var join_status: Label = %JoinStatus
@onready var code_label: Label = %CodeLabel
@onready var copy_button: Button = %CopyCode

## Device that last pressed something (NO_DEVICE for the mouse): seats the
## local player in an online match if they never picked one, and picking
## Local with it seats it.
var last_device: int = Players.NO_DEVICE
## Device picked in the online lobby (A or Enter on it), which can differ
## from whatever is driving the menus.
var online_device: int = Players.NO_DEVICE
## One panel per local seat, and our own in the online lobby.
var seat_panels: Array[CharacterSelectPanel] = []
## Local lobby: how many seat panels are shown (the Players picker).
var local_seat_count: int = 1
var online_panel: CharacterSelectPanel
## Per team: its size picker.
var size_buttons: Array[Button] = []
var copy_feedback: Tween
## Why Start didn't start: floats over the lobby, outside the layout.
var start_note: PanelContainer
var start_note_label: Label
var start_note_fade: Tween
var start_shake: Tween
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

	%LocalButton.pressed.connect(_open_local)
	%OnlineButton.pressed.connect(_show.bind(online, %HostButton))
	%CodexButton.pressed.connect(get_tree().change_scene_to_file.bind(CODEX))
	%QuitButton.pressed.connect(get_tree().quit)
	start_button.pressed.connect(_start)
	back_button.pressed.connect(_go_back)
	teams_button.pressed.connect(_cycle_team_count)
	# Nothing to pick while there's only the one format or level
	teams_button.visible = Players.TEAM_COUNTS.size() > 1
	map_button.visible = MatchMap.MAPS.size() > 1
	drop_button.visible = MatchMap.DROPS.size() > 1
	%Options.visible = teams_button.visible or map_button.visible or drop_button.visible
	map_button.pressed.connect(_cycle_map)
	drop_button.pressed.connect(_cycle_boss_drop)
	_setup_cycler(score_button, _step_score_to_win)
	_setup_cycler(players_button, _step_local_seats)
	bots_button.pressed.connect(_toggle_fill_with_bots)

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
	for input: LineEdit in [host_code_input, join_code_input]:
		input.text_changed.connect(_on_code_text_changed.bind(input))
	host_code_input.text_submitted.connect(func(_text: String) -> void: _host())
	join_code_input.text_submitted.connect(func(_text: String) -> void: _join())

	Net.hosted.connect(_on_net_hosted)
	Net.joined.connect(_on_net_joined)
	Net.failed.connect(_on_net_failed)
	Net.peers_changed.connect(_refresh_lobby)
	Net.session_ended.connect(_on_net_session_ended)
	Net.match_started.connect(_on_match_started)

	Players.slot_joined.connect(func(_slot: PlayerSlot) -> void: _refresh_lobby())
	Players.slot_left.connect(func(_slot: PlayerSlot) -> void: _refresh_lobby())
	Players.slot_changed.connect(func(_slot: PlayerSlot) -> void: _refresh_lobby())

	_build_panels()
	_build_team_sizes()
	_build_start_note()
	if back_in_lobby:
		_show(lobby, start_button if Net.is_host else back_button)
	else:
		_show(home, %LocalButton)
	# Dropped out of an online match: say why
	if Net.end_reason:
		_on_net_session_ended(Net.end_reason)
		Net.end_reason = ""


func _show(screen: Control, focus: Control) -> void:
	for s: Control in [home, lobby, online, host_setup, join_setup]:
		s.visible = s == screen
	# The lobby is too tall to fit under the title
	%Title.visible = screen != lobby
	_refresh_lobby()
	focus.grab_focus()


func _back_to_home() -> void:
	Players.leave_all()
	Net.leave()
	_show(home, %LocalButton)


## Back from any online sub-screen; leaves the session if we were in one.
func _back_to_online() -> void:
	Net.leave()
	_show(online, %HostButton)


func _go_back() -> void:
	if host_setup.visible or join_setup.visible or (lobby.visible and Net.in_session()):
		_back_to_online()
	else:
		_back_to_home()


## The local lobby, with whoever picked Local already seated if they did it
## from a controller or the keyboard (a click leaves the seats open, since
## the mouse may not be what they play with).
func _open_local() -> void:
	Net.leave()
	Players.leave_all()
	local_seat_count = 1
	if last_device != Players.NO_DEVICE:
		_join_local(last_device)
	_show(lobby, start_button)


func _start() -> void:
	var problem: String = _start_problem()
	if problem != "":
		_refuse_start(problem)
	elif Net.in_session():
		Net.start_match()
	else:
		_start_game()


# ===== PANELS =====

## One panel per local seat, and our own in the online lobby, side by side.
func _build_panels() -> void:
	online_panel = CharacterSelectPanel.new(ONLINE_STAGE_SIZE)
	seats.add_child(online_panel)
	online_panel.team_picked.connect(func(team: int) -> void: _step_online_team(team - Net.local_loadout()[0]))
	online_panel.character_picked.connect(func(character: int) -> void:
		Net.set_loadout(Net.local_loadout()[0], character))
	online_panel.character_stepped.connect(_step_online_character)
	online_panel.name_typed.connect(_type_online_name)
	online_panel.name_rerolled.connect(Net.set_player_name.bind(""))

	for i in LOCAL_SEATS:
		var panel := CharacterSelectPanel.new(LOCAL_STAGE_SIZE)
		# Each seat steers its own panel from its own device; only the
		# keyboard & mouse player's panel takes clicks (see _refresh_lobby)
		panel.focusable = false
		panel.team_picked.connect(_on_seat_team_picked.bind(i))
		panel.character_picked.connect(_on_seat_character_picked.bind(i))
		panel.character_stepped.connect(_on_seat_character_stepped.bind(i))
		panel.name_typed.connect(_on_seat_name_typed.bind(i))
		panel.name_rerolled.connect(_on_seat_name_rerolled.bind(i))
		panel.gui_input.connect(_on_seat_clicked)
		seats.add_child(panel)
		seat_panels.append(panel)


## The local seat shown on panel `i`, if anyone sits there.
func _seat_slot(i: int) -> PlayerSlot:
	for slot: PlayerSlot in Players.slots:
		if slot.index == i:
			return slot
	return null


## A click on an empty seat joins the keyboard & mouse, if it isn't in yet.
func _on_seat_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and not Players.get_slot_for_device(PlayerSlot.KEYBOARD_MOUSE):
		_join_local(PlayerSlot.KEYBOARD_MOUSE)
		accept_event()


## Seat `device` in the first empty seat, showing another if every seat
## shown is taken. Nothing happens once all LOCAL_SEATS are.
func _join_local(device: int) -> void:
	for i in LOCAL_SEATS:
		if not _seat_slot(i):
			local_seat_count = maxi(local_seat_count, i + 1)
			Players.join(device, -1, i)
			return


## Players picker: show one seat more (step 1) or fewer (-1). Whoever sat
## in a seat that's taken away leaves the lobby.
func _step_local_seats(step: int) -> void:
	local_seat_count = clampi(local_seat_count + step, 1, LOCAL_SEATS)
	for slot: PlayerSlot in Players.slots.duplicate():
		if slot.index >= local_seat_count:
			Players.leave(slot)
	_refresh_lobby()


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


# ===== TEAMS =====

## A size picker per team there could be; _refresh_lobby shows the ones
## in play.
func _build_team_sizes() -> void:
	for team in Players.TEAM_NAMES.size():
		var size_button := Button.new()
		size_button.custom_minimum_size = TEAM_SIZE_BUTTON
		size_button.add_theme_font_size_override("font_size", 20)
		for state: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
			size_button.add_theme_color_override(state, Players.team_color(team).lightened(0.45))
		_setup_cycler(size_button, _step_team_size.bind(team))
		team_sizes.add_child(size_button)
		size_buttons.append(size_button)


## Everyone in the lobby, people then bots, as [team, name] each (a bot's
## name is "" offline, where they're only named in the match).
func _lobby_seats() -> Array[Array]:
	var list: Array[Array] = []
	if Net.in_session():
		var my_id: int = multiplayer.get_unique_id()
		for i in Net.peers.size():
			var id: int = Net.peers[i]
			var loadout: Array = Net.loadout_of(id)
			var tags: Array[String] = ["Host" if i == 0 else "Guest"]
			if id == my_id:
				tags.append("You")
			list.append([loadout[0], "%s (%s)" % [Net.name_in(loadout), ", ".join(tags)]])
		for loadout: Array in Net.bots:
			list.append([loadout[0], ""])
		return list
	for slot: PlayerSlot in Players.slots:
		list.append([slot.team, slot.display_name])
	var seated: Array[int] = Players.slot_teams()
	var with_bots: Array[int] = Players.teams_with_bots(seated)
	for i in range(seated.size(), with_bots.size()):
		list.append([with_bots[i], ""])
	return list


## The teams of everyone in the lobby, people then bots.
func _lobby_teams() -> Array[int]:
	var teams: Array[int] = []
	for seat: Array in _lobby_seats():
		teams.append(seat[0])
	return teams


## How many people (not bots) are on `team`.
func _people_on(team: int) -> int:
	if Net.in_session():
		return Net.people_on(team)
	return Players.team_sizes(Players.slot_teams())[team]


## A team's size picker: one seat more (step 1) or fewer (-1). Online the
## leader asks the server, which seats or unseats its bots to match.
func _step_team_size(step: int, team: int) -> void:
	var seats: int = _team_size(team) + step
	if Net.in_session():
		Net.set_team_size(team, seats)
		return
	Players.set_team_size(team, seats, _people_on(team))
	_refresh_lobby()


## `team`'s seats: what its picker is set to, or more if more people joined it.
func _team_size(team: int) -> int:
	return maxi(Players.seats_per_team[team], _people_on(team))


## Fill with Bots button: on, bots take the empty seats; off, only people
## play. Online only the leader has it.
func _toggle_fill_with_bots() -> void:
	if Net.in_session():
		Net.set_fill_with_bots(not Players.fill_with_bots)
		return
	Players.fill_with_bots = not Players.fill_with_bots
	_refresh_lobby()


func _refresh_team_sizes() -> void:
	var can_edit: bool = not Net.in_session() or Net.is_host
	for team in size_buttons.size():
		size_buttons[team].visible = team < Players.team_count
		if size_buttons[team].visible:
			size_buttons[team].text = "%s:  <  %d/%d  >" % [Players.team_name(team), _people_on(team), _team_size(team)]
			size_buttons[team].disabled = not can_edit
	bots_button.text = "Fill with Bots: " + ("On" if Players.fill_with_bots else "Off")
	bots_button.disabled = not can_edit


## Who's in the online session, a line per team, e.g.
## "Humans: Bungle (Host, You), Pip + 2 bots".
func _online_roster_text() -> String:
	var lines: Array[String] = []
	var seats_list: Array[Array] = _lobby_seats()
	for team in Players.team_count:
		var names: Array[String] = []
		var bot_count: int = 0
		for seat: Array in seats_list:
			if seat[0] != team:
				continue
			if seat[1] == "":
				bot_count += 1
			else:
				names.append(seat[1])
		var text: String = ", ".join(names)
		if bot_count > 0:
			text += (" + " if text != "" else "") + "%d bot%s" % [bot_count, "" if bot_count == 1 else "s"]
		lines.append("%s: %s" % [Players.team_name(team), text if text != "" else "nobody"])
	return "\n".join(lines)


# ===== PICKERS =====

## A "<  value  >" button: clicking its left half steps back and its right
## half forward, like the arrows drawn on it. With a controller or the
## keyboard, Left steps back, and Right or A / Enter forward. `on_step`
## gets 1 or -1.
func _setup_cycler(button: Button, on_step: Callable) -> void:
	button.pressed.connect(func() -> void: on_step.call(1))
	button.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click and click.button_index == MOUSE_BUTTON_LEFT:
			# Handled here, so the button's own press doesn't also step forward
			if click.pressed:
				on_step.call(-1 if click.position.x < button.size.x / 2.0 else 1)
			button.accept_event()
			return
		var step: int = 0
		if event.is_action_pressed("ui_left"):
			step = -1
		elif event.is_action_pressed("ui_right"):
			step = 1
		if step != 0:
			on_step.call(step)
			button.accept_event())


## Teams button: 2 teams (2P field) <-> 4 teams (4P field). Online, only
## the leader has it, and the server passes it on to everyone.
func _cycle_team_count() -> void:
	if Net.in_session():
		Net.set_team_count(Players.next_team_count())
		return
	Players.set_team_count(Players.next_team_count())
	_refresh_lobby()


## Map button: the next level. One that can't host the current boss drop
## or team count changes those to fit (see Players.set_map).
func _cycle_map() -> void:
	if Net.in_session():
		Net.set_map(Players.next_map())
		return
	Players.set_map(Players.next_map())
	_refresh_lobby()


## Ball button: what every boss drops, and on the pitch what kicks off (a
## ball or a bomb). A bomb needs goals, so picking it moves the match to a
## map that has them.
func _cycle_boss_drop() -> void:
	if Net.in_session():
		Net.set_boss_drop(Players.next_boss_drop())
		return
	Players.set_boss_drop(Players.next_boss_drop())
	_refresh_lobby()


## Score to Win button: one more (step 1) or fewer (step -1) point to win,
## wrapping around.
func _step_score_to_win(step: int) -> void:
	var span: int = Players.MAX_SCORE_TO_WIN - Players.MIN_SCORE_TO_WIN + 1
	var score: int = Players.MIN_SCORE_TO_WIN + posmod(Players.score_to_win - Players.MIN_SCORE_TO_WIN + step, span)
	if Net.in_session():
		Net.set_score_to_win(score)
		return
	Players.set_score_to_win(score)
	_refresh_lobby()


# ===== INPUT =====

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventKey:
		last_device = Players.device_of(event)
	elif event is InputEventMouseButton:
		last_device = Players.NO_DEVICE

	var local_lobby: bool = lobby.visible and not Net.in_session()
	if local_lobby and event is InputEventJoypadMotion:
		_lobby_stick_input(event)
	if not event.is_pressed() or event.is_echo():
		return
	# Typing a name: the keys are letters, not lobby controls
	if event is InputEventKey and _typing():
		return
	var device: int = Players.device_of(event)
	if device == Players.NO_DEVICE or not lobby.visible:
		return
	if local_lobby:
		_lobby_input(event, device)
	else:
		_online_lobby_input(event, device)


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
		_join_local(device)
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
		_refresh_lobby()
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


# ===== LOBBY =====

func _refresh_lobby() -> void:
	if seat_panels.is_empty() or not lobby.visible:
		return  # Not built yet, or not showing
	var in_session: bool = Net.in_session()
	code_panel.visible = in_session
	online_panel.visible = in_session
	back_button.text = "Leave" if in_session else "Back"
	players_button.visible = not in_session
	players_button.text = "Players:  <  %d  >" % local_seat_count
	for i in seat_panels.size():
		var panel: CharacterSelectPanel = seat_panels[i]
		_show_faded(panel, not in_session and i < local_seat_count)
		var slot: PlayerSlot = _seat_slot(i)
		if slot:
			panel.set_header("P%d  %s" % [i + 1, Players.device_name(slot.device)])
			panel.interactive = slot.uses_keyboard_mouse()
			panel.show_choice(slot.team, slot.character)
			panel.show_name(slot.display_name, slot.color)
		else:
			panel.set_header("P%d" % (i + 1))
			panel.show_empty("Press A or Enter to join")
	online_roster.visible = in_session
	if in_session:
		_refresh_online_panel()
		online_roster.text = _online_roster_text()
	_refresh_team_sizes()

	var teams_text: String = Players.team_split(_lobby_teams())
	teams_button.text = "Teams: " + Players.format_name(_lobby_teams())
	map_button.text = "Map: " + MatchMap.name_of(Players.map)
	drop_button.text = "Ball: " + MatchMap.drop_name(Players.boss_drop)
	score_button.text = "Score to Win:  <  %d  >" % Players.score_to_win
	# Only the online leader picks the format (it's sent with the match
	# start), but everyone sees it
	for button: Button in [teams_button, map_button, drop_button, score_button]:
		button.disabled = in_session and not Net.is_host
	start_button.visible = not in_session or Net.is_host

	# Online, what's left to do; what's stopping the start is only said when
	# Start is pressed (see _refuse_start), so the layout stays put
	lobby_status.visible = in_session
	lobby_status.text = "Send the code to your friends." if Net.is_host else "Waiting for the host to start."
	start_button.text = "Start " + teams_text if _start_problem() == "" else "Start"
	_chain_lobby_focus()


## What's stopping the match from starting, or "" if nothing is.
func _start_problem() -> String:
	if Net.in_session():
		if online_device == Players.NO_DEVICE:
			return "Press A or Enter on the device you'll play with."
		if Net.seat_count() < MIN_LOBBY_PLAYERS:
			return "Needs at least %d players (or bots)." % MIN_LOBBY_PLAYERS
	elif Players.slots.is_empty():
		return "Press A or Enter (or click a seat) to join first."
	if Players.team_split(_lobby_teams()) == "":
		return "Both teams need someone: switch a team, or turn on Fill with Bots."
	return ""


func _build_start_note() -> void:
	start_note = PanelContainer.new()
	start_note.theme_type_variation = &"PlankPanel"
	start_note.top_level = true  # Floats over the lobby without moving it
	start_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_note.hide()
	start_note_label = Label.new()
	start_note_label.add_theme_font_size_override("font_size", 20)
	start_note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_note.add_child(start_note_label)
	add_child(start_note)


## Start was pressed but the match can't start: shake the button and say
## why, floating over the lobby.
func _refuse_start(problem: String) -> void:
	if start_shake:
		start_shake.kill()
	start_shake = start_button.create_tween()
	var rest: float = start_button.position.x
	for offset: float in SHAKE_OFFSETS:
		start_shake.tween_property(start_button, "position:x", rest + offset, SHAKE_STEP)

	start_note_label.text = problem
	start_note.reset_size()
	start_note.scale = start_button.get_global_transform().get_scale()
	# Centered on the lobby, just over the settings (the bottom of the seat
	# panels), so it never covers a button you might press to fix it
	var lobby_rect: Rect2 = Rect2(lobby.get_global_transform() * Vector2.ZERO, lobby.size * start_note.scale)
	var settings_top: float = (%MatchRow.get_global_transform() * Vector2.ZERO).y
	var note_size: Vector2 = start_note.size * start_note.scale
	start_note.global_position = Vector2(lobby_rect.get_center().x - note_size.x / 2.0,
		settings_top - note_size.y - NOTE_GAP)
	start_note.modulate.a = 1.0
	start_note.show()
	if start_note_fade:
		start_note_fade.kill()
	start_note_fade = start_note.create_tween()
	start_note_fade.tween_interval(NOTE_TIME)
	start_note_fade.tween_property(start_note, "modulate:a", 0.0, NOTE_FADE_TIME)
	start_note_fade.tween_callback(start_note.hide)


## Show `control` (fading it in, if it was hidden) or hide it.
func _show_faded(control: Control, on: bool) -> void:
	if on and not control.visible:
		control.modulate.a = 0.0
		control.create_tween().tween_property(control, "modulate:a", 1.0, PANEL_FADE_TIME)
	control.visible = on


func _refresh_online_panel() -> void:
	var mine: Array = Net.local_loadout()
	online_panel.set_header("You  ·  " + ("Press A or Enter on your device" if online_device == Players.NO_DEVICE
		else Players.device_name(online_device)))
	online_panel.show_choice(mine[0], mine[1])
	online_panel.show_name(Net.name_in(mine), Players.team_color(mine[0]))
	code_label.text = Net.access_code


## The lobby buttons sit in rows, but the pickers use left/right to cycle,
## so up/down walks every visible button in reading order.
func _chain_lobby_focus() -> void:
	var chain: Array[Control] = []
	var candidates: Array[Control] = []
	if Net.in_session():
		candidates.append(online_panel.first_focus())
	candidates.append_array([players_button, score_button, bots_button])
	candidates.append_array(size_buttons)
	candidates.append_array([teams_button, map_button, drop_button, start_button, back_button])
	for control: Control in candidates:
		var button := control as BaseButton
		if control.is_visible_in_tree() and not (button and button.disabled):
			chain.append(control)
	for i in chain.size():
		var prev: Control = chain[i - 1] if i > 0 else chain[i]
		var next: Control = chain[i + 1] if i < chain.size() - 1 else chain[i]
		chain[i].focus_neighbor_top = chain[i].get_path_to(prev)
		chain[i].focus_neighbor_bottom = chain[i].get_path_to(next)


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
	_show(lobby, start_button)
	_on_copy_code()


func _on_net_joined(_code: String) -> void:
	online_device = Players.NO_DEVICE
	%JoinConfirm.disabled = false
	_send_saved_name()
	_show(lobby, back_button)


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


func _step_online_character(step: int) -> void:
	var mine: Array = Net.local_loadout()
	Net.set_loadout(mine[0], Roster.step(mine[1], mine[0], step))


func _step_online_team(step: int) -> void:
	var mine: Array = Net.local_loadout()
	Net.set_loadout(mine[0] + step, mine[1])


## Each machine seats only its own player, in its session seat, as the
## team and character picked in the lobby; Game3D spawns everyone else as
## remote players. A guest who never picked a device gets the last one they
## touched (and can change it from the pause menu).
func _on_match_started() -> void:
	Players.leave_all()
	var device: int = online_device
	if device == Players.NO_DEVICE:
		device = last_device if last_device != Players.NO_DEVICE else PlayerSlot.KEYBOARD_MOUSE
	var mine: Array = Net.local_loadout()
	var slot: PlayerSlot = Players.join(device, mine[0], Net.local_seat(), mine[1])
	slot.display_name = Net.name_in(mine)
	_start_game()


func _start_game() -> void:
	get_tree().change_scene_to_file(MatchMap.scene_of(Players.map))
