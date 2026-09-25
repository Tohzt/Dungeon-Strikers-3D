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

signal slot_joined(slot: PlayerSlot)
signal slot_left(slot: PlayerSlot)

const MAX_PLAYERS := 4
const TEAM_COLORS: Array[Color] = [
	Color(0, 0.08, 1),      # Blue
	Color(1, 0.15, 0.1),    # Red
	Color(0.1, 0.8, 0.2),   # Green
	Color(1, 0.85, 0.1),    # Yellow
]

var slots: Array[PlayerSlot] = []

## Project actions captured before any per-slot copies are added.
var _base_actions: Array[StringName] = []


func _ready() -> void:
	for action_name: StringName in InputMap.get_actions():
		if not String(action_name).begins_with("ui_"):
			_base_actions.append(action_name)


func join(device: int, team: int = -1) -> PlayerSlot:
	if slots.size() >= MAX_PLAYERS or get_slot_for_device(device):
		return null
	var slot := PlayerSlot.new()
	slot.index = _next_free_index()
	slot.device = device
	slot.team = team if team >= 0 else slot.index
	slot.color = TEAM_COLORS[slot.team % TEAM_COLORS.size()]
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


func get_slot_for_device(device: int) -> PlayerSlot:
	for slot: PlayerSlot in slots:
		if slot.device == device:
			return slot
	return null


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
