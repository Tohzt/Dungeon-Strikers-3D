class_name PlayerSlot extends Resource
## One seat at the local game: which device drives it and which team it's on.
## Created through the Players autoload (Players.join); a lobby menu can edit
## team/color before the match starts.

## Sentinel device id for the keyboard + mouse player. Joypad ids are >= 0.
const KEYBOARD_MOUSE := -1

@export var index: int = 0
@export var device: int = KEYBOARD_MOUSE
@export var team: int = 0
@export var color: Color = Color.WHITE


func uses_keyboard_mouse() -> bool:
	return device == KEYBOARD_MOUSE


## This slot's copy of a project input action, e.g. "move_left" -> "p1_move_left".
func action(base: StringName) -> StringName:
	return StringName("p%d_%s" % [index, base])


## Whether an event from the project's Input Map belongs to this slot's device type.
func accepts(event: InputEvent) -> bool:
	if uses_keyboard_mouse():
		return event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion
	return event is InputEventJoypadButton or event is InputEventJoypadMotion
