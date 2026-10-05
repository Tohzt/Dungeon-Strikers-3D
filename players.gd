extends Node
## Tracks who is playing locally and which device each player uses.
##
## Each joined slot gets its own copy of every project input action
## ("p0_move_left", "p1_move_left", ...) containing only that slot's device's
## events, so bindings stay editable in Project Settings > Input Map and
## players never read each other's input.
##
## The menus call join()/leave() and let each player pick their team and
## character (set_team, cycle_team, cycle_character); Game3D only seats
## players automatically when nothing has been joined yet.
##
## team_count picks the match format: 2 teams play end to end on the 2P
## field, 4 teams get a goal on every side (4P field). New seats start out
## spread across the teams in order (see team_for_seat), and bots join
## whichever team is smallest. The format also picks the level (map) and
## what every boss drops (boss_drop); see MatchMap for which go together.

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
## Matches TEAM_COLORS.
const TEAM_NAMES: Array[String] = ["Blue", "Red", "Green", "Yellow"]

## Team counts a match can be played with (see team_count).
const TEAM_COUNTS: Array[int] = [2, 4]

var slots: Array[PlayerSlot] = []
## Teams in the next match. Online, the leader's choice is sent to everyone
## with the match start (see Net.start_match).
var team_count: int = TEAM_COUNTS[0]
## Level for the next match. Online, sent with the match start like team_count.
var map: MatchMap.Map = MatchMap.MAPS[0]
## What every boss drops in the next match.
var boss_drop: BossDrop.Kind = MatchMap.DROPS[0]
## Offline: seat bots until the match has this many players (0 = no bots).
## Always a whole number of players per team; see bot_fill_options().
var bot_fill_count: int = 0

## Project actions captured before any per-slot copies are added.
var _base_actions: Array[StringName] = []


func _ready() -> void:
	for action_name: StringName in InputMap.get_actions():
		if not String(action_name).begins_with("ui_"):
			_base_actions.append(action_name)


## index picks a specific seat (online play uses the session seat); -1 = next
## free. team and character default by seat.
func join(device: int, team: int = -1, index: int = -1, character: int = -1) -> PlayerSlot:
	if slots.size() >= MAX_PLAYERS or get_slot_for_device(device):
		return null
	var slot := PlayerSlot.new()
	slot.index = index if index >= 0 else _next_free_index()
	slot.device = device
	_assign_team(slot, team if team >= 0 else team_for_seat(slot.index))
	slot.character = character if character >= 0 else default_character(slot.index)
	slots.append(slot)
	_register_actions(slot)
	slot_joined.emit(slot)
	return slot


## A computer-controlled player in the next free seat (offline only).
func add_bot() -> PlayerSlot:
	if slots.size() >= MAX_PLAYERS:
		return null
	var slot := PlayerSlot.new()
	slot.index = _next_free_index()
	slot.device = PlayerSlot.BOT
	slot.is_bot = true
	_assign_team(slot, smallest_team(slot_teams()))
	slot.character = unused_character()
	slots.append(slot)
	slot_joined.emit(slot)
	return slot


## Seat bots until the match has bot_fill_count players.
func fill_bots() -> void:
	while slots.size() < bot_fill_count and add_bot():
		pass


## Match sizes the Bots option can fill to with the current team_count:
## 0 (off), then every even split, e.g. 2 (1v1) and 4 (2v2) for two teams.
func bot_fill_options() -> Array[int]:
	var options: Array[int] = [0]
	for count: int in range(team_count, MAX_PLAYERS + 1, team_count):
		options.append(count)
	return options


## The next match size after bot_fill_count (menu toggles).
func next_bot_fill_count() -> int:
	var options: Array[int] = bot_fill_options()
	return options[(options.find(bot_fill_count) + 1) % options.size()]


## Seats played by people, not bots.
func human_slots() -> Array[PlayerSlot]:
	var humans: Array[PlayerSlot] = []
	for slot: PlayerSlot in slots:
		if not slot.is_bot:
			humans.append(slot)
	return humans


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


## The team a seat starts on: seats take turns, P1 on Blue, P2 Red, P3 Blue
## (or Green with four teams), and so on.
func team_for_seat(index: int) -> int:
	return index % team_count


func team_color(team: int) -> Color:
	return TEAM_COLORS[team % TEAM_COLORS.size()]


func team_name(team: int) -> String:
	return TEAM_NAMES[team % TEAM_NAMES.size()]


## Put `slot` on `team` (wrapping around the teams in play).
func set_team(slot: PlayerSlot, team: int) -> void:
	_assign_team(slot, team)
	slot_changed.emit(slot)


## Move `slot` to the next (step 1) or previous (step -1) team.
func cycle_team(slot: PlayerSlot, step: int) -> void:
	set_team(slot, slot.team + step)


func _assign_team(slot: PlayerSlot, team: int) -> void:
	slot.team = posmod(team, team_count)
	slot.color = team_color(slot.team)


## The teams of everyone seated, in seat order.
func slot_teams() -> Array[int]:
	var teams: Array[int] = []
	for slot: PlayerSlot in slots:
		teams.append(slot.team)
	return teams


## How many of `teams` are on each team in play.
func team_sizes(teams: Array[int]) -> Array[int]:
	var sizes: Array[int] = []
	sizes.resize(team_count)
	for team: int in teams:
		sizes[posmod(team, team_count)] += 1
	return sizes


## The team with the fewest of `teams` on it (the first one on a tie).
func smallest_team(teams: Array[int]) -> int:
	var sizes: Array[int] = team_sizes(teams)
	return sizes.find(sizes.min())


## `seated` (the teams of players already in), plus the teams of the bots
## fill_bots() would add to reach `total` players.
func teams_with_bots(total: int, seated: Array[int]) -> Array[int]:
	var teams: Array[int] = seated.duplicate()
	while teams.size() < total:
		teams.append(smallest_team(teams))
	return teams


# ===== CHARACTERS =====

func character_count() -> int:
	return PlayerVisual3D.CHARACTERS.size()


func character_name(character: int) -> String:
	return PlayerVisual3D.CHARACTER_NAMES[posmod(character, character_count())]


## Seats start on different characters so players don't all look alike.
func default_character(index: int) -> int:
	return index % character_count()


## The first character nobody seated is playing (the first one if all are).
func unused_character() -> int:
	for character: int in character_count():
		if not slots.any(func(s: PlayerSlot) -> bool: return s.character == character):
			return character
	return 0


## Switch `slot` to the next (step 1) or previous (step -1) character.
func cycle_character(slot: PlayerSlot, step: int) -> void:
	slot.character = posmod(slot.character + step, character_count())
	slot_changed.emit(slot)


## Switch the match format. Players keep their team when it's still in
## play; teams that aren't wrap around onto ones that are. A level with
## too few sides gives way to one that has enough.
func set_team_count(count: int) -> void:
	if not TEAM_COUNTS.has(count):
		return
	team_count = count
	if not MatchMap.fits(map, team_count, boss_drop):
		map = MatchMap.first_fitting(team_count, boss_drop)
	if not bot_fill_options().has(bot_fill_count):
		bot_fill_count = bot_fill_options()[-1]
	for slot: PlayerSlot in slots:
		_assign_team(slot, slot.team)
		slot_changed.emit(slot)


## The next format in TEAM_COUNTS after the current one (menu toggles).
func next_team_count() -> int:
	return TEAM_COUNTS[(TEAM_COUNTS.find(team_count) + 1) % TEAM_COUNTS.size()]


## Switch level. Whatever it can't host gives way: too many teams are cut
## down, and a drop it has no place for (a ball without goals) is swapped
## for the first one it does.
func set_map(new_map: MatchMap.Map) -> void:
	map = new_map
	var teams: int = mini(team_count, MatchMap.max_teams(map))
	if not MatchMap.fits(map, teams, boss_drop):
		for kind: BossDrop.Kind in MatchMap.DROPS:
			if MatchMap.fits(map, teams, kind):
				boss_drop = kind
				break
	set_team_count(teams)


## Switch what bosses drop, moving to a level that can host it if need be
## (a ball needs goals).
func set_boss_drop(kind: BossDrop.Kind) -> void:
	boss_drop = kind
	if not MatchMap.fits(map, team_count, boss_drop):
		map = MatchMap.first_fitting(team_count, boss_drop)


## The whole format at once, as the online leader picked it (already
## consistent, so nothing gives way).
func set_match_format(count: int, new_map: MatchMap.Map, kind: BossDrop.Kind) -> void:
	map = new_map
	boss_drop = kind
	set_team_count(count)


func next_map() -> MatchMap.Map:
	return MatchMap.MAPS[(MatchMap.MAPS.find(map) + 1) % MatchMap.MAPS.size()]


func next_boss_drop() -> BossDrop.Kind:
	return MatchMap.DROPS[(MatchMap.DROPS.find(boss_drop) + 1) % MatchMap.DROPS.size()]


## "2 (2v1)"-style label for the current format with players on `teams`.
func format_name(teams: Array[int]) -> String:
	return "%d (%s)" % [team_count, team_split(teams)] if team_split(teams) != "" else str(team_count)


## "2v1"-style split of `teams`, or "" if fewer than two teams have players.
func team_split(teams: Array[int]) -> String:
	var sizes: Array[String] = []
	for size: int in team_sizes(teams):
		if size > 0:
			sizes.append(str(size))
	return "v".join(sizes) if sizes.size() > 1 else ""


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
