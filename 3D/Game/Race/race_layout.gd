class_name RaceLayout extends RefCounted
## What a race level is made of, as plain data: rooms on the 4m wall grid,
## the doorways between them, and what's in each room. RaceLevel3D builds
## the level from it, so a layout can come from a generator just as well as
## from the hand-made test_layout() below. A generator must give the same
## layout on every machine (same seed), since each builds its own copy.
##
## Grid: wall cell (x, z) is centered on (4x, 0, 4z) metres. A room's walls
## run along the edges of its rect and its floor is everything inside, so
## two rooms side by side share the wall between them.
##
## The race: each team starts sealed in its own START room; the gates open
## together onto the first ARENA, whose boss holds the key (a BOSS door) to
## the rest of the dungeon. Somewhere in there is the ALTAR room, behind a
## second boss: the first player to touch its altar wins for their team.

const CELL := 4.0

enum Kind {
	START,     ## A team's sealed starting room (has `team`)
	ARENA,     ## A boss fight (has `boss_hp`); wakes when the first player walks in
	ROOM,      ## Plain room on the way
	CORRIDOR,  ## Long and narrow: a connector
	TREASURE,  ## A detour with loot
	ALTAR,     ## The finish: holds the race altar
}

enum DoorKind {
	GAP,    ## No wall at all: a 4m opening
	ARCH,   ## An open doorway (a gate-wall with no gate)
	START,  ## A start room's gate; opens when the race starts
	BOSS,   ## Locked until `key_room`'s boss falls
}

## What a room holds besides its boss: Feature, position (metres, relative
## to the room's center).
enum Feature { CHEST, ARMOR, ORB, BIG_ORB }


class Room:
	var name: String
	var kind: Kind
	## Wall cells, both corners included: walls on the edges, floor inside.
	var rect: Rect2i
	## START rooms: the team that starts here.
	var team: int = -1
	## ARENA rooms: the boss's max HP.
	var boss_hp: float = 0.0
	## [Feature, Vector2 offset from the center in metres], ...
	var features: Array = []

	## The room's middle, in metres.
	func center() -> Vector3:
		var mid: Vector2 = (Vector2(rect.position) + Vector2(rect.end)) * 0.5 * CELL
		return Vector3(mid.x, 0.0, mid.y)

	## Floor size in metres (wall center to wall center).
	func size() -> Vector2:
		return Vector2(rect.size) * CELL

	func has_inside(cell: Vector2i) -> bool:
		return cell.x > rect.position.x and cell.x < rect.end.x \
			and cell.y > rect.position.y and cell.y < rect.end.y

	func has_wall(cell: Vector2i) -> bool:
		var on_x: bool = cell.x == rect.position.x or cell.x == rect.end.x
		var on_z: bool = cell.y == rect.position.y or cell.y == rect.end.y
		var within: bool = cell.x >= rect.position.x and cell.x <= rect.end.x \
			and cell.y >= rect.position.y and cell.y <= rect.end.y
		return within and (on_x or on_z)


class Doorway:
	## A wall cell on a straight stretch of wall, between two rooms.
	var cell: Vector2i
	var kind: DoorKind
	## START: the start room it seals. BOSS: the room whose boss opens it.
	var key_room: int = -1


var rooms: Array[Room] = []
var doorways: Array[Doorway] = []


## Adds a room with walls from `from` to `to` (cells, inclusive). Returns its index.
func add_room(room_name: String, kind: Kind, from: Vector2i, to: Vector2i) -> int:
	var room := Room.new()
	room.name = room_name
	room.kind = kind
	room.rect = Rect2i(from, to - from)
	rooms.append(room)
	return rooms.size() - 1


func add_door(cell: Vector2i, kind: DoorKind, key_room: int = -1) -> void:
	var door := Doorway.new()
	door.cell = cell
	door.kind = kind
	door.key_room = key_room
	doorways.append(door)


func room_of_kind(kind: Kind) -> Room:
	for room: Room in rooms:
		if room.kind == kind:
			return room
	return null


## Every wall cell, doorways included (a GAP's cell is left out when built).
func wall_cells() -> Dictionary[Vector2i, bool]:
	var cells: Dictionary[Vector2i, bool] = {}
	for room: Room in rooms:
		for x in range(room.rect.position.x, room.rect.end.x + 1):
			cells[Vector2i(x, room.rect.position.y)] = true
			cells[Vector2i(x, room.rect.end.y)] = true
		for z in range(room.rect.position.y, room.rect.end.y + 1):
			cells[Vector2i(room.rect.position.x, z)] = true
			cells[Vector2i(room.rect.end.x, z)] = true
	return cells


## Everything the builder relies on, as a list of problems (empty = fine).
## For generators: reject (or retry) a layout that comes back with any.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	var walls: Dictionary[Vector2i, bool] = wall_cells()
	for i in rooms.size():
		var room: Room = rooms[i]
		if room.rect.size.x < 2 or room.rect.size.y < 2:
			problems.append("%s has no floor" % room.name)
		for cell: Vector2i in walls:
			if room.has_inside(cell):
				problems.append("%s has a wall running through it at %s" % [room.name, cell])
				break
	for door: Doorway in doorways:
		var straight_x: bool = walls.has(door.cell + Vector2i.LEFT) and walls.has(door.cell + Vector2i.RIGHT) \
			and not walls.has(door.cell + Vector2i.UP) and not walls.has(door.cell + Vector2i.DOWN)
		var straight_z: bool = walls.has(door.cell + Vector2i.UP) and walls.has(door.cell + Vector2i.DOWN) \
			and not walls.has(door.cell + Vector2i.LEFT) and not walls.has(door.cell + Vector2i.RIGHT)
		if not walls.has(door.cell) or not (straight_x or straight_z):
			problems.append("Doorway %s isn't on a straight wall" % door.cell)
			continue
		var across: Vector2i = Vector2i(0, 1) if straight_x else Vector2i(1, 0)
		if _room_around(door.cell + across) < 0 or _room_around(door.cell - across) < 0:
			problems.append("Doorway %s doesn't lead between two rooms" % door.cell)
		if door.kind in [DoorKind.START, DoorKind.BOSS] and (door.key_room < 0 or door.key_room >= rooms.size()):
			problems.append("Doorway %s has no key room" % door.cell)
	for kind: Kind in [Kind.ARENA, Kind.ALTAR]:
		if not room_of_kind(kind):
			problems.append("No %s room" % Kind.keys()[kind])
	return problems


## The room whose floor includes `cell`, or -1.
func _room_around(cell: Vector2i) -> int:
	for i in rooms.size():
		if rooms[i].has_inside(cell):
			return i
	return -1


## The hand-made map for trying the mode out, for up to four teams.
##
##   z=-31        +-----+
##                |ALTAR|            sanctum (the altar), locked by the guardian
##   z=-27     +--D-----+--+
##             |  GUARDIAN |         second boss
##   z=-15 +---+-----a-----+---+
##         |ARM'   GREAT HALL  'LIB|  armory / library: loot detours
##   z=-11 |   +--'---+---+--'-+   |
##   z=-9  +---|  NW  | N |  NE|---+  N = Yellow's start room
##             |      |   |    |
##   z=-5      +-D----+-S-+---D+     D = locked by the arena boss
##       +-----+               +-----+
##       |  W  S     ARENA     S  E  |   W = Blue, E = Red
##       +-----+               +-----+
##   z=5       +------+-S-+----+
##                    | S |          S = Green
##   z=9              +---+
##      x=-15 -9  -5  -2  2   5   9  15
static func test_layout() -> RaceLayout:
	var layout := RaceLayout.new()
	var arena: int = layout.add_room("Arena", Kind.ARENA, Vector2i(-5, -5), Vector2i(5, 5))
	layout.rooms[arena].boss_hp = 900.0
	for team in 4:
		# Blue west, Red east, Green south, Yellow north (as Game3D.TEAM_SIDES)
		var from: Vector2i = [Vector2i(-9, -2), Vector2i(5, -2), Vector2i(-2, 5), Vector2i(-2, -9)][team]
		var gate: Vector2i = [Vector2i(-5, 0), Vector2i(5, 0), Vector2i(0, 5), Vector2i(0, -5)][team]
		var start: int = layout.add_room("Start%d" % team, Kind.START, from, from + Vector2i(4, 4))
		layout.rooms[start].team = team
		layout.add_door(gate, DoorKind.START, start)

	var nw: int = layout.add_room("GuardRoomWest", Kind.ROOM, Vector2i(-9, -11), Vector2i(-2, -5))
	var ne: int = layout.add_room("GuardRoomEast", Kind.ROOM, Vector2i(2, -11), Vector2i(9, -5))
	layout.rooms[nw].features = [[Feature.ORB, Vector2(-6, 0)]]
	layout.rooms[ne].features = [[Feature.ORB, Vector2(6, 0)]]
	layout.add_door(Vector2i(-4, -5), DoorKind.BOSS, arena)
	layout.add_door(Vector2i(4, -5), DoorKind.BOSS, arena)

	layout.add_room("GreatHall", Kind.CORRIDOR, Vector2i(-9, -15), Vector2i(9, -11))
	layout.add_door(Vector2i(-6, -11), DoorKind.GAP)
	layout.add_door(Vector2i(6, -11), DoorKind.GAP)

	var armory: int = layout.add_room("Armory", Kind.TREASURE, Vector2i(-15, -17), Vector2i(-9, -9))
	layout.rooms[armory].features = [[Feature.CHEST, Vector2(-4, 0)], [Feature.ARMOR, Vector2(4, -8)]]
	layout.add_door(Vector2i(-9, -13), DoorKind.GAP)
	var library: int = layout.add_room("Library", Kind.TREASURE, Vector2i(9, -17), Vector2i(15, -9))
	layout.rooms[library].features = [[Feature.CHEST, Vector2(4, 0)], [Feature.BIG_ORB, Vector2(-4, 8)]]
	layout.add_door(Vector2i(9, -13), DoorKind.GAP)

	var guardian: int = layout.add_room("GuardianHall", Kind.ARENA, Vector2i(-6, -27), Vector2i(6, -15))
	layout.rooms[guardian].boss_hp = 1400.0
	layout.add_door(Vector2i(0, -15), DoorKind.ARCH)

	layout.add_room("Sanctum", Kind.ALTAR, Vector2i(-3, -31), Vector2i(3, -27))
	layout.add_door(Vector2i(0, -27), DoorKind.BOSS, guardian)
	return layout
