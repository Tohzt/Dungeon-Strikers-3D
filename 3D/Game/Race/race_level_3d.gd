@tool
class_name RaceLevel3D extends Node3D
## Builds a race level from a RaceLayout when the match loads: walls, floors,
## doors, bosses, start rooms, loot and the finish altar. Nothing about the
## map is saved in the scene, so swapping test_layout() for a generated
## layout is all it takes to get a new map each match.
##
## In the editor it builds a preview of the walls and doors (not saved with
## the scene) so the layout can be looked at without running the game.
##
## Each machine builds its own copy, in the same order, so nodes get the
## same names everywhere (bosses and doors are found by name online).

const G := RaceLayout.CELL
const Kind := RaceLayout.Kind
const DoorKind := RaceLayout.DoorKind
const Feature := RaceLayout.Feature
const NAV_GROUP := "dungeon_nav"
## Boss-only collision (the cage that keeps each boss in its room).
const BOSS_BARRIER_LAYER := 32
const PLAYER_LAYER := 2
## How far into the room a wall's face is from the wall's center line.
const WALL_FACE := 0.9

const DOOR_SCENE := preload("res://3D/Game/Level/door_3d.tscn")
const TORCH_SCENE := preload("res://3D/Game/Level/wall_torch.tscn")
const BOSS_SCENE := preload("res://3D/Entities/Boss_Slime/boss.tscn")
const ALTAR_SCENE := preload("res://3D/Weapons/Altar.tscn")
const CHEST_SCENE := preload("res://3D/Weapons/Chest/chest.tscn")
const ARMOR_SCENE := preload("res://3D/Items/Armor/armor_pickup.tscn")
const ORB_SCENE := preload("res://3D/Items/Boost/boost_orb.tscn")
const STRUCT_LIB := preload("res://Game/Dungeon/dungeon_mesh_library.res")
const FLOOR_LIB := preload("res://Game/Dungeon/dungeon_floor_library.res")

## Editor only: show the test layout's walls and doors.
@export var preview_in_editor: bool = true:
	set(value):
		preview_in_editor = value
		if Engine.is_editor_hint() and is_node_ready():
			_preview()

var layout: RaceLayout
## Gameplay nodes go here (Game3D looks for its bosses and altars among its
## own children). Null in the editor preview.
var _game: Node3D
var _walls_map: GridMap
var _floor_map: GridMap
var _decor: Node3D
var _walls: Dictionary[Vector2i, bool] = {}
## Room index -> its boss, for doors it holds the key to.
var _bosses: Dictionary[int, Boss3D] = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		_preview()


func _preview() -> void:
	_clear()
	if preview_in_editor:
		build(RaceLayout.test_layout(), null)


func _clear() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_walls.clear()
	_bosses.clear()


## Lay out `new_layout`. Bosses, altars, spawn points and the finish go into
## `game` (the RaceGame3D this level belongs to); null = geometry only.
func build(new_layout: RaceLayout, game: Node3D) -> void:
	layout = new_layout
	_game = game
	_build_grids()
	_lay_walls()
	_lay_floors()
	_light_rooms()
	if _game:
		_place_bosses()
	_place_doors()
	if _game:
		_furnish_rooms()
		_add_bounds()
		_add_navigation()  # Last, so it bakes with everything in place


# ===== GEOMETRY =====

func _build_grids() -> void:
	var bounds: Rect2 = _bounds()
	# One flat floor for everything to stand on; the tiles are just looks.
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_mask = 0
	floor_body.add_to_group(NAV_GROUP)
	add_child(floor_body)
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(bounds.size.x, 4.0, bounds.size.y)  # Thick: thrown weapons can't tunnel through
	floor_shape.shape = box
	floor_shape.position = Vector3(bounds.get_center().x, -2.0, bounds.get_center().y)
	floor_body.add_child(floor_shape)

	# The rock between rooms: a dark slab just under the tiles.
	var bedrock := MeshInstance3D.new()
	bedrock.name = "Bedrock"
	var plane := PlaneMesh.new()
	plane.size = bounds.size + Vector2(60.0, 60.0)
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.06, 0.055, 0.06)
	rock.roughness = 1.0
	plane.material = rock
	bedrock.mesh = plane
	bedrock.position = Vector3(bounds.get_center().x, -0.03, bounds.get_center().y)
	add_child(bedrock)

	_walls_map = GridMap.new()
	_walls_map.name = "WallGrid"
	_walls_map.mesh_library = STRUCT_LIB
	_walls_map.cell_size = Vector3(G, G, G)
	_walls_map.cell_center_y = false
	_walls_map.position = Vector3(-G / 2.0, 0.0, -G / 2.0)  # Cell (i, j) centered on (4i, 4j)
	_walls_map.collision_mask = 0
	_walls_map.add_to_group(NAV_GROUP)
	add_child(_walls_map)

	_floor_map = GridMap.new()
	_floor_map.name = "FloorGrid"
	_floor_map.mesh_library = FLOOR_LIB
	_floor_map.cell_size = Vector3(G, G, G)
	_floor_map.cell_center_y = false
	_floor_map.collision_layer = 0
	_floor_map.collision_mask = 0
	add_child(_floor_map)

	_decor = Node3D.new()
	_decor.name = "Decor"
	add_child(_decor)


## Every room's walls; doorways get a gate-wall piece, or no wall at all
## for a GAP. Each piece is picked from which neighbours are walls too.
func _lay_walls() -> void:
	_walls = layout.wall_cells()
	var forced: Dictionary[Vector2i, String] = {}
	for door: RaceLayout.Doorway in layout.doorways:
		if door.kind == DoorKind.GAP:
			_walls.erase(door.cell)
		else:
			forced[door.cell] = "wall_gateDoor"
	for cell: Vector2i in _walls:
		var links: Array[Vector3] = []
		for dir: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.RIGHT, Vector3.LEFT]:
			if _walls.has(cell + Vector2i(int(dir.x), int(dir.z))):
				links.append(dir)
		var shape: String
		var base: Array[Vector3]
		match links.size():
			0:
				shape = "pillar"
			1:
				shape = "wall_end"; base = [Vector3.RIGHT]
			2:
				if links[0].dot(links[1]) < -0.5:
					shape = forced.get(cell, _wall_variant(cell)); base = [Vector3.LEFT, Vector3.RIGHT]
				else:
					shape = "wallCorner"; base = [Vector3.LEFT, Vector3.BACK]
			3:
				shape = "wallSplit"; base = [Vector3.LEFT, Vector3.RIGHT, Vector3.BACK]
			_:
				shape = "wallIntersection"
		var basis := Basis(Vector3.UP, _turn_for(base, links) * PI / 2.0)
		_walls_map.set_cell_item(Vector3i(cell.x, 0, cell.y), STRUCT_LIB.find_item_by_name(shape),
				_walls_map.get_orthogonal_index_from_basis(basis))


## Quarter turns that line `base` links up with `links`.
func _turn_for(base: Array[Vector3], links: Array[Vector3]) -> int:
	for turn in 4:
		var basis := Basis(Vector3.UP, turn * PI / 2.0)
		var fits: bool = true
		for dir: Vector3 in base:
			var turned: Vector3 = (basis * dir).round()
			fits = fits and links.any(func(l: Vector3) -> bool: return l.is_equal_approx(turned))
		if fits:
			return turn
	return 0


## Mostly plain wall, sometimes decorated or crumbling.
func _wall_variant(cell: Vector2i) -> String:
	var roll: int = _hash(cell) % 100
	if roll < 12: return "wallDecorationA"
	if roll < 22: return "wallDecorationB"
	if roll < 28: return "wall_broken"
	return "wall"


func _hash(cell: Vector2i) -> int:
	return absi((cell.x * 73856093) ^ (cell.y * 19349663) ^ 0x5bd1e995) % 100003


func _lay_floors() -> void:
	var a_tile: int = FLOOR_LIB.find_item_by_name("tileBrickA_medium")
	var b_tile: int = FLOOR_LIB.find_item_by_name("tileBrickB_medium")
	for room: RaceLayout.Room in layout.rooms:
		for x in range(room.rect.position.x, room.rect.end.x):
			for z in range(room.rect.position.y, room.rect.end.y):
				var key: int = _hash(Vector2i(x, z))
				var item: int
				match room.kind:
					Kind.ARENA, Kind.ALTAR: item = b_tile if (x + z) % 2 == 0 else a_tile
					Kind.START: item = a_tile if key % 4 else b_tile
					_: item = b_tile if key % 3 else a_tile
				var basis := Basis(Vector3.UP, (key % 4) * PI / 2.0)
				_floor_map.set_cell_item(Vector3i(x, 0, z), item, _floor_map.get_orthogonal_index_from_basis(basis))


## Torches along every room's walls, kept clear of doorways.
func _light_rooms() -> void:
	var door_cells: Array[Vector2i] = []
	for door: RaceLayout.Doorway in layout.doorways:
		door_cells.append(door.cell)
	for room: RaceLayout.Room in layout.rooms:
		var r: Rect2i = room.rect
		var step: int = 2 if room.kind in [Kind.START, Kind.ALTAR] else 3
		# Each wall: its cells, where its face is, and which way the torch points
		var sides: Array = [
			[range(r.position.x + 1, r.end.x), func(i: int) -> Vector2i: return Vector2i(i, r.position.y), Vector3(0, 0, WALL_FACE), 0.0],
			[range(r.position.x + 1, r.end.x), func(i: int) -> Vector2i: return Vector2i(i, r.end.y), Vector3(0, 0, -WALL_FACE), 180.0],
			[range(r.position.y + 1, r.end.y), func(i: int) -> Vector2i: return Vector2i(r.position.x, i), Vector3(WALL_FACE, 0, 0), 90.0],
			[range(r.position.y + 1, r.end.y), func(i: int) -> Vector2i: return Vector2i(r.end.x, i), Vector3(-WALL_FACE, 0, 0), -90.0],
		]
		for side: Array in sides:
			var cells: Array = side[0]
			for n in range(1, cells.size() - 1, step):
				var cell: Vector2i = side[1].call(cells[n])
				if not _walls.has(cell) or door_cells.any(func(d: Vector2i) -> bool: return (d - cell).length_squared() <= 1):
					continue
				var torch: Node3D = TORCH_SCENE.instantiate()
				torch.name = "Torch_%s_%d" % [room.name, _decor.get_child_count()]
				torch.position = _world(cell) + side[2] + Vector3.UP * 1.9
				torch.rotation_degrees.y = side[3]
				_decor.add_child(torch)


# ===== DOORS & BOSSES =====

func _place_doors() -> void:
	for door: RaceLayout.Doorway in layout.doorways:
		if door.kind in [DoorKind.GAP, DoorKind.ARCH]:
			continue
		var gate: Door3D = DOOR_SCENE.instantiate()
		gate.name = "Door_%d_%d" % [door.cell.x, door.cell.y]
		gate.position = _world(door.cell)
		# The gate runs along its wall: along X unless the wall runs along Z
		if _walls.has(door.cell + Vector2i(0, 1)):
			gate.rotation_degrees.y = 90.0
		if door.kind == DoorKind.START:
			gate.add_to_group("StartGate")
		elif _bosses.has(door.key_room):
			gate.key_boss = _bosses[door.key_room]
			gate.message = "The way on is open!" if layout.rooms[door.key_room] == layout.room_of_kind(Kind.ARENA) \
				else "The sanctum opens! Reach the altar!"
		add_child(gate)


## A sleeping boss in the middle of each ARENA room, kept in by a cage only
## bosses collide with (their stomp leap clears walls), woken by the first
## player to walk in.
func _place_bosses() -> void:
	for i in layout.rooms.size():
		var room: RaceLayout.Room = layout.rooms[i]
		if room.kind != Kind.ARENA:
			continue
		var boss: Boss3D = BOSS_SCENE.instantiate()
		boss.name = "Boss_%s" % room.name
		boss.max_hp = room.boss_hp
		boss.wait_for_players = true
		boss.drop = BossDrop.Kind.NONE  # Its prize is the door it unlocks
		boss.position = room.center()
		_game.add_child(boss)
		_bosses[i] = boss

		var cage := StaticBody3D.new()
		cage.name = "BossCage_%s" % room.name
		cage.collision_layer = BOSS_BARRIER_LAYER
		cage.collision_mask = 0
		add_child(cage)
		var size: Vector2 = room.size()
		var c: Vector3 = room.center()
		for spec: Array in [
			[Vector3(c.x - size.x / 2.0, 20, c.z), Vector3(1.5, 40, size.y + 1.5)],
			[Vector3(c.x + size.x / 2.0, 20, c.z), Vector3(1.5, 40, size.y + 1.5)],
			[Vector3(c.x, 20, c.z - size.y / 2.0), Vector3(size.x + 1.5, 40, 1.5)],
			[Vector3(c.x, 20, c.z + size.y / 2.0), Vector3(size.x + 1.5, 40, 1.5)],
		]:
			cage.add_child(_box_shape(spec[0], spec[1]))

		var trigger := BossTrigger3D.new()
		trigger.name = "BossTrigger_%s" % room.name
		trigger.collision_layer = 0
		trigger.collision_mask = PLAYER_LAYER
		trigger.monitorable = false
		trigger.bosses = [boss]
		trigger.add_to_group("ArenaZone")  # The camera widens to show the fight in here
		add_child(trigger)
		# Just inside the walls, so standing in a doorway doesn't count
		trigger.add_child(_box_shape(c + Vector3.UP * 3.0, Vector3(size.x - 3.0, 6.0, size.y - 3.0)))


# ===== ROOMS' CONTENTS =====

func _furnish_rooms() -> void:
	for room: RaceLayout.Room in layout.rooms:
		match room.kind:
			Kind.START: _start_room(room)
			Kind.ALTAR: _altar_room(room)
		for feature: Array in room.features:
			_feature(room, feature[0], feature[1])


## A team's spawn point facing its gate, and its altar (a weapon stand)
## at the back, under a light in the team's color.
func _start_room(room: RaceLayout.Room) -> void:
	var to_gate: Vector3 = Vector3.FORWARD
	for door: RaceLayout.Doorway in layout.doorways:
		if door.kind == DoorKind.START and layout.rooms[door.key_room] == room:
			to_gate = (_world(door.cell) - room.center()).normalized()
	var facing: float = atan2(to_gate.x, to_gate.z)
	var depth: float = (room.size().x if absf(to_gate.x) > 0.5 else room.size().y) / 2.0

	var spawn := SpawnPoint3D.new()
	spawn.name = "Spawn_Team%d" % room.team
	spawn.team = room.team
	spawn.position = room.center() + to_gate * 1.5
	spawn.rotation.y = facing  # Teammates line up across the room
	_game.add_child(spawn)

	var altar: Altar3D = ALTAR_SCENE.instantiate()
	altar.name = "Altar_Team%d" % room.team
	altar.owner_team = room.team
	altar.position = room.center() - to_gate * (depth - 3.0)
	altar.rotation.y = facing
	altar.add_to_group(NAV_GROUP)
	_game.add_child(altar)

	var glow := OmniLight3D.new()
	glow.name = "TeamGlow%d" % room.team
	glow.light_color = Players.TEAM_COLORS[room.team % Players.TEAM_COLORS.size()]
	glow.light_energy = 1.6
	glow.omni_range = 12.0
	glow.position = room.center() + Vector3.UP * 5.0
	_decor.add_child(glow)


func _altar_room(room: RaceLayout.Room) -> void:
	var finish := FinishAltar3D.new()
	finish.name = "FinishAltar"
	finish.position = room.center()
	_game.add_child(finish)


func _feature(room: RaceLayout.Room, feature: RaceLayout.Feature, offset: Vector2) -> void:
	var at: Vector3 = room.center() + Vector3(offset.x, 0.0, offset.y)
	var node: Node3D
	match feature:
		Feature.CHEST:
			node = CHEST_SCENE.instantiate()
			node.add_to_group(NAV_GROUP)
		Feature.ARMOR:
			node = ARMOR_SCENE.instantiate()
		Feature.ORB, Feature.BIG_ORB:
			node = ORB_SCENE.instantiate()
			if feature == Feature.BIG_ORB:
				node.set(&"amount", 100.0)
				node.set(&"respawn_time", 10.0)
	node.name = "%s_%s" % [RaceLayout.Feature.keys()[feature].capitalize().replace(" ", ""), room.name]
	node.position = at
	_game.add_child(node)


# ===== LEVEL-WIDE =====

## Nothing leaves the level: a tall invisible fence just outside the outer
## walls (thrown weapons can sail over them).
func _add_bounds() -> void:
	var bounds: Rect2 = _bounds()
	var fence := StaticBody3D.new()
	fence.name = "LevelBounds"
	fence.collision_mask = 0
	add_child(fence)
	var c: Vector2 = bounds.get_center()
	var s: Vector2 = bounds.size
	for spec: Array in [
		[Vector3(bounds.position.x, 20, c.y), Vector3(2, 40, s.y)],
		[Vector3(bounds.end.x, 20, c.y), Vector3(2, 40, s.y)],
		[Vector3(c.x, 20, bounds.position.y), Vector3(s.x, 40, 2)],
		[Vector3(c.x, 20, bounds.end.y), Vector3(s.x, 40, 2)],
	]:
		fence.add_child(_box_shape(spec[0], spec[1]))


## Bots and the walk-to-altar find their way with this (see NavPath). Doors
## aren't part of it, so routes run through them whether they're open or not.
func _add_navigation() -> void:
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	mesh.geometry_source_group_name = NAV_GROUP
	mesh.agent_radius = 0.5  # Doorways are under 2m wide (and a multiple of cell_size)
	mesh.agent_height = 2.0
	mesh.agent_max_climb = 0.25
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	var nav := AutoBakeNavigation3D.new()
	nav.name = "Navigation"
	nav.navigation_mesh = mesh
	add_child(nav)


## The whole layout in metres (x, z), with a cell of margin.
func _bounds() -> Rect2:
	var cells := Rect2i()
	for i in layout.rooms.size():
		cells = layout.rooms[i].rect if i == 0 else cells.merge(layout.rooms[i].rect)
	cells = cells.grow(1)
	return Rect2(Vector2(cells.position) * G, Vector2(cells.size) * G)


func _world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * G, 0.0, cell.y * G)


func _box_shape(at: Vector3, size: Vector3) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	return shape
