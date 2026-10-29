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
## players automatically when nothing has been joined yet. Teams are sides:
## Humans against Skeletons, and each side has its own characters (see
## Roster), so changing team changes character too.
##
## team_count picks the match format: 2 teams play end to end on the 2P
## field, 4 teams get a goal on every side (4P field; hidden for now, see
## TEAM_COUNTS). New seats start out
## spread across the teams in order (see team_for_seat), and bots fill
## whatever seats each team has left (seats_per_team). The format also picks the level (map) and
## what every boss drops (boss_drop); see MatchMap for which go together.
## score_to_win is the goals (or kills, on levels without goals) to win.

signal slot_joined(slot: PlayerSlot)
signal slot_left(slot: PlayerSlot)
## A slot moved to a different device (see set_device) or switched control
## layout (Simple/Advanced).
signal slot_changed(slot: PlayerSlot)

## 4v4.
const MAX_PLAYERS := 8
## What device_of() returns for input that can't pick a device (e.g. mouse motion).
const NO_DEVICE := -2
const TEAM_COLORS: Array[Color] = [
	Color(0, 0.08, 1),      # Blue
	Color(1, 0.15, 0.1),    # Red
	Color(0.1, 0.8, 0.2),   # Green
	Color(1, 0.85, 0.1),    # Yellow
]
## Matches TEAM_COLORS. The first two are the sides (see Roster).
const TEAM_NAMES: Array[String] = ["Humans", "Skeletons", "Green", "Yellow"]

## Choices for score_to_win.
const MIN_SCORE_TO_WIN := 1
const MAX_SCORE_TO_WIN := 20

## Team counts a match can be played with (see team_count). Humans vs
## Skeletons is two teams; the 4-team format still works but is hidden
## until it has sides of its own: add 4 back here to offer it.
const TEAM_COUNTS: Array[int] = [2]

var slots: Array[PlayerSlot] = []
## Teams in the next match. Online, the leader's choice is sent to everyone
## with the match start (see Net.start_match).
var team_count: int = TEAM_COUNTS[0]
## Level for the next match. Online, sent with the match start like team_count.
var map: MatchMap.Map = MatchMap.MAPS[0] as MatchMap.Map
## What every boss drops in the next match.
var boss_drop: BossDrop.Kind = MatchMap.DROPS[0] as BossDrop.Kind
## Points to win the next match: goals where the level is won by goals,
## kills otherwise (see Game3D). Online, sent with the match start too.
var score_to_win: int = 5
## Rolls this match's chance the same way on every machine (which element
## each boss is, see SlimeElement.pick). Online the server picks it and
## sends it with the match start; offline each match rolls its own.
var match_seed: int = 0
## How many seats each team has in the next match (index = team): people
## take them first and bots fill the rest (see fill_bots). Never fewer than
## the people on that team, nor more than max_team_size(). Online the server
## keeps this and seats its bots to match (see Net.set_team_size). Starts
## at a full 4v4.
var seats_per_team: Array[int] = [MAX_PLAYERS / 2, MAX_PLAYERS / 2]
## Whether bots take the seats nobody's in. Off, only people play (a team
## with nobody on it can't start the match).
var fill_with_bots: bool = true

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
	slot.character = Roster.for_team(character if character >= 0 else default_character(slot.index), slot.team)
	# Whoever's at the keyboard is likely the one who typed the saved name
	var saved: String = PlayerNames.saved() if slot.uses_keyboard_mouse() else ""
	slot.display_name = saved if saved != "" else PlayerNames.random(slot_names())
	slots.append(slot)
	_register_actions(slot)
	slot_joined.emit(slot)
	return slot


## A computer-controlled player in the next free seat (offline only), on
## `team` (-1 = the smallest).
func add_bot(team: int = -1) -> PlayerSlot:
	if slots.size() >= MAX_PLAYERS:
		return null
	var slot := PlayerSlot.new()
	slot.index = _next_free_index()
	slot.device = PlayerSlot.BOT
	slot.is_bot = true
	_assign_team(slot, team if team >= 0 else smallest_team(slot_teams()))
	slot.character = unused_character(slot.team)
	slot.display_name = PlayerNames.random(slot_names())
	slots.append(slot)
	slot_joined.emit(slot)
	return slot


## Seat bots until every team has its seats_per_team (if fill_with_bots).
func fill_bots() -> void:
	if not fill_with_bots:
		return
	for team in team_count:
		while team_sizes(slot_teams())[team] < seats_per_team[team] and add_bot(team):
			pass


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


## Put `slot` on `team` (wrapping around the teams in play), switching to
## that side's character in the same place on its list.
func set_team(slot: PlayerSlot, team: int) -> void:
	_assign_team(slot, team)
	slot.character = Roster.for_team(slot.character, slot.team)
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


## `seated` (the teams of the people already in), plus the teams of the
## bots fill_bots() would add.
func teams_with_bots(seated: Array[int]) -> Array[int]:
	var teams: Array[int] = seated.duplicate()
	if not fill_with_bots:
		return teams
	var sizes: Array[int] = team_sizes(seated)
	for team in team_count:
		for i in seats_per_team[team] - sizes[team]:
			teams.append(team)
	return teams


## The most seats one team can have: an even share of MAX_PLAYERS.
func max_team_size() -> int:
	return MAX_PLAYERS / team_count


## Give `team` `size` seats, kept between the `people` already on it (and
## at least one) and max_team_size().
func set_team_size(team: int, size: int, people: int = 0) -> void:
	if team >= 0 and team < seats_per_team.size():
		seats_per_team[team] = clampi(size, maxi(people, 1), max_team_size())


# ===== NAMES =====

## Everyone seated's names.
func slot_names() -> Array[String]:
	var names: Array[String] = []
	for slot: PlayerSlot in slots:
		names.append(slot.display_name)
	return names


## Rename `slot` (cleaned up; blank gets a random name). `remember` saves
## it for next time (see PlayerNames.saved), for a name someone typed.
func set_player_name(slot: PlayerSlot, text: String, remember: bool = false) -> void:
	var clean: String = PlayerNames.clean(text)
	slot.display_name = clean if clean != "" else PlayerNames.random(slot_names())
	if remember and clean != "":
		PlayerNames.save(clean)
	slot_changed.emit(slot)


## Give `slot` a different random name.
func reroll_name(slot: PlayerSlot) -> void:
	set_player_name(slot, PlayerNames.random(slot_names()))


# ===== CHARACTERS =====

func character_count() -> int:
	return Roster.count()


func character_name(character: int) -> String:
	return Roster.name_of(character)


## Seats start on different characters so players don't all look alike.
## Not yet fitted to a team (see Roster.for_team).
func default_character(index: int) -> int:
	return index % character_count()


## The first of `team`'s characters nobody seated is playing (bots spread
## out over the roster), or one at random if all are taken.
func unused_character(team: int) -> int:
	var choices: Array[int] = Roster.characters_of_team(team)
	for character: int in choices:
		if not slots.any(func(s: PlayerSlot) -> bool: return s.character == character):
			return character
	return choices.pick_random()


## Switch `slot` to `character`, if its team can play it.
func set_character(slot: PlayerSlot, character: int) -> void:
	if Roster.fits_team(character, slot.team):
		slot.character = character
		slot_changed.emit(slot)


## Switch `slot` to the next (step 1) or previous (step -1) character on
## its team.
func cycle_character(slot: PlayerSlot, step: int) -> void:
	slot.character = Roster.step(slot.character, slot.team, step)
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
	seats_per_team.resize(team_count)
	for team in team_count:
		seats_per_team[team] = clampi(seats_per_team[team] if seats_per_team[team] > 0 else max_team_size(),
			1, max_team_size())
	for slot: PlayerSlot in slots:
		_assign_team(slot, slot.team)
		slot.character = Roster.for_team(slot.character, slot.team)
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
## consistent, so nothing gives way): team count, map, drop, score to win,
## seats_per_team and fill_with_bots.
func set_match_format(count: int, new_map: MatchMap.Map, kind: BossDrop.Kind, score: int,
		seats: Array = [], fill: bool = true) -> void:
	map = new_map
	boss_drop = kind
	set_score_to_win(score)
	if not seats.is_empty():
		seats_per_team.assign(seats)
	fill_with_bots = fill
	set_team_count(count)


func set_score_to_win(score: int) -> void:
	score_to_win = clampi(score, MIN_SCORE_TO_WIN, MAX_SCORE_TO_WIN)


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
