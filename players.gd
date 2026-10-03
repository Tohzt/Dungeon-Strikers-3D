extends Node
## Tracks who is playing locally and which device each player uses.
##
## Each joined slot gets its own copy of every project input action
## ("p0_move_left", "p1_move_left", ...) containing only that slot's device's
## events, so bindings stay editable in Project Settings > Input Map and
## players never read each other's input.
##
## A future lobby/team-select menu should call join()/leave() and set each
## slot's team/color; Game3D only seats players automatically when nothing
## has been joined yet.
##
## team_count picks the match format: 2 teams play end to end on the 2P
## field, 4 teams get a goal on every side (4P field). Seats are spread
## across the teams in order, so 4 players make 2v2 or a four-way match.

signal slot_joined(slot: PlayerSlot)
signal slot_left(slot: PlayerSlot)
## A slot moved to a different device (see set_device) or switched control
## layout (Simple/Advanced).
signal slot_changed(slot: PlayerSlot)

const MAX_PLAYERS := 4
## What device_of() returns for input that can't pick a device (e.g. mouse motion).
const NO_DEVICE := -2
const TEAM_COLORS: Array[Color] = [
	Color(0, 0.08, 1),      # Blue
	Color(1, 0.15, 0.1),    # Red
	Color(0.1, 0.8, 0.2),   # Green
	Color(1, 0.85, 0.1),    # Yellow
]

## Team counts a match can be played with (see team_count).
const TEAM_COUNTS: Array[int] = [2, 4]

var slots: Array[PlayerSlot] = []
## Teams in the next match. Online, the leader's choice is sent to everyone
## with the match start (see Net.start_match).
var team_count: int = TEAM_COUNTS[0]

## Project actions captured before any per-slot copies are added.
var _base_actions: Array[StringName] = []


func _ready() -> void:
	for action_name: StringName in InputMap.get_actions():
		if not String(action_name).begins_with("ui_"):
			_base_actions.append(action_name)


## index picks a specific seat (online play uses the session seat); -1 = next free.
func join(device: int, team: int = -1, index: int = -1) -> PlayerSlot:
	if slots.size() >= MAX_PLAYERS or get_slot_for_device(device):
		return null
	var slot := PlayerSlot.new()
	slot.index = index if index >= 0 else _next_free_index()
	slot.device = device
	slot.team = team if team >= 0 else team_for_seat(slot.index)
	slot.color = team_color(slot.team)
	slots.append(slot)
	_register_actions(slot)
	slot_joined.emit(slot)
	return slot


func leave(slot: PlayerSlot) -> void:
	if not slots.has(slot):
		return
	slots.erase(slot)
	for base: StringName in _base_actions:
		if InputMap.has_action(slot.action(base)):
			InputMap.erase_action(slot.action(base))
	slot_left.emit(slot)


func leave_all() -> void:
	for slot: PlayerSlot in slots.duplicate():
		leave(slot)


## The team a seat plays on: seats take turns, P1 on Blue, P2 Red, P3 Blue
## (or Green with four teams), and so on.
func team_for_seat(index: int) -> int:
	return index % team_count


func team_color(team: int) -> Color:
	return TEAM_COLORS[team % TEAM_COLORS.size()]


## Switch the match format; every joined slot moves to its seat's new team.
func set_team_count(count: int) -> void:
	if not TEAM_COUNTS.has(count):
		return
	team_count = count
	for slot: PlayerSlot in slots:
		slot.team = team_for_seat(slot.index)
		slot.color = team_color(slot.team)
		slot_changed.emit(slot)


## The next format in TEAM_COUNTS after the current one (menu toggles).
func next_team_count() -> int:
	return TEAM_COUNTS[(TEAM_COUNTS.find(team_count) + 1) % TEAM_COUNTS.size()]


## "2 (2v2)"-style label for the current format with `player_count` players.
func format_name(player_count: int) -> String:
	var sizes: Array[String] = []
	for team: int in team_count:
		var size: int = 0
		for seat: int in player_count:
			if team_for_seat(seat) == team:
				size += 1
		if size > 0:
			sizes.append(str(size))
	return "%d (%s)" % [team_count, "v".join(sizes)] if sizes.size() > 1 else str(team_count)


func get_slot_for_device(device: int) -> PlayerSlot:
	for slot: PlayerSlot in slots:
		if slot.device == device:
			return slot
	return null


## Move a slot to another device, e.g. from the pause menu. If another slot
## already has that device, the two swap, so local players can trade.
func set_device(slot: PlayerSlot, device: int) -> void:
	if slot.device == device:
		return
	var other: PlayerSlot = get_slot_for_device(device)
	if other:
		other.device = slot.device
		_register_actions(other)
	slot.device = device
	_register_actions(slot)
	if other:
		slot_changed.emit(other)
	slot_changed.emit(slot)


# ===== DEVICE PICKING =====
# Players claim a device by pressing A/Start or Enter/Space on it, and back
# out with B/Back or Esc. Shared by the lobbies and the pause menu.

## The device an event came from, or NO_DEVICE if it can't claim one.
func device_of(event: InputEvent) -> int:
	if event is InputEventJoypadButton:
		return event.device
	if event is InputEventKey:
		return PlayerSlot.KEYBOARD_MOUSE
	return NO_DEVICE


func is_join_press(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		return event.button_index in [JOY_BUTTON_A, JOY_BUTTON_START]
	if event is InputEventKey:
		return event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	return false


func is_back_press(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		return event.button_index in [JOY_BUTTON_B, JOY_BUTTON_BACK]
	if event is InputEventKey:
		return event.physical_keycode == KEY_ESCAPE
	return false


func device_name(device: int) -> String:
	if device == PlayerSlot.KEYBOARD_MOUSE:
		return "Keyboard & Mouse"
	var pad_name: String = Input.get_joy_name(device)
	return pad_name if pad_name != "" else "Controller %d" % (device + 1)


## Stand-in until a lobby exists: seat connected controllers first, then
## keyboard/mouse, up to max_count players.
func join_default_devices(max_count: int) -> void:
	for joypad: int in Input.get_connected_joypads():
		if slots.size() >= max_count:
			return
		join(joypad)
	if slots.size() < max_count:
		join(PlayerSlot.KEYBOARD_MOUSE)


func _next_free_index() -> int:
	var index := 0
	while slots.any(func(s: PlayerSlot) -> bool: return s.index == index):
		index += 1
	return index


func _register_actions(slot: PlayerSlot) -> void:
	for base: StringName in _base_actions:
		var slot_action := slot.action(base)
		if InputMap.has_action(slot_action):
			InputMap.erase_action(slot_action)
		InputMap.add_action(slot_action, InputMap.action_get_deadzone(base))
		for event: InputEvent in InputMap.action_get_events(base):
			if not slot.accepts(event):
				continue
			var copy: InputEvent = event.duplicate()
			if not slot.uses_keyboard_mouse():
				copy.device = slot.device
			InputMap.action_add_event(slot_action, copy)
