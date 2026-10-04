@tool
class_name GameTools3D extends Node
## Editor tools for the arena. Settings here take effect when the match
## starts; in the editor they also show a preview of what they'll add
## (preview nodes aren't saved into the scene).

## Builds a room behind each altar with a circle of weapon stands in it, one
## for every weapon in the game, for trying them out. Weapons are found by
## searching `weapons_dir`, so new ones show up without touching this.
@export var testing_mode: bool = false:
	set(value):
		testing_mode = value
		if is_node_ready():
			_refresh_test_rooms()

@export_group("Testing Mode")
@export var stand_scene: PackedScene = preload("res://3D/Weapons/weapon_stand.tscn")
## Searched (with its subfolders) for weapons: every scene whose root is in
## the "Weapon" group gets a stand.
@export_dir var weapons_dir: String = "res://3D/Weapons"
## Gap between neighbouring stands around the circle.
@export var stand_spacing: float = 4.0
## The circle is never smaller than this, however few weapons there are.
@export var min_radius: float = 6.0
## Open floor between the circle and the room's walls.
@export var wall_margin: float = 5.0

## The dungeon's wall grid (see build_dungeon_arena.gd): cell (i, j) is
## centered on (G * i, G * j).
const G := 4.0
const NAV_GROUP := "dungeon_nav"
const WALL_LIB := "res://Game/Dungeon/dungeon_mesh_library.tres"
const FLOOR_LIB := "res://Game/Dungeon/dungeon_floor_library.tres"
## Wall cells either side of the middle of the doorway behind the altar.
const DOOR_HALF_WIDTH := 1
const N := Vector3(0, 0, -1)
const S := Vector3(0, 0, 1)
const E := Vector3(1, 0, 0)
const W := Vector3(-1, 0, 0)

## Stands and room nodes this added, to free on a refresh.
var _built: Array[Node] = []
## Level wall cells changed for the doorways: Vector2i -> [item, orientation].
var _grid_restore: Dictionary = {}
var _restore_grid: GridMap = null
## Level bounds pushed back to fit the rooms: CollisionShape3D -> old position.
var _bounds_restore: Dictionary = {}


func _ready() -> void:
	_refresh_test_rooms()


## Every weapon scene under `dir`, sorted by path so the order (and the
## stands' names) is the same on every machine online.
static func find_weapon_scenes(dir: String) -> Array[PackedScene]:
	var paths := PackedStringArray()
	_collect_scenes(dir, paths)
	paths.sort()
	var found: Array[PackedScene] = []
	for path: String in paths:
		var scene := load(path) as PackedScene
		if scene and _is_weapon(scene.get_state()):
			found.append(scene)
	return found


static func _collect_scenes(dir: String, out: PackedStringArray) -> void:
	for entry: String in ResourceLoader.list_directory(dir):
		if entry.ends_with("/"):
			_collect_scenes(dir.path_join(entry.trim_suffix("/")), out)
		elif entry.get_extension() == "tscn":
			out.append(dir.path_join(entry))


## Whether the scene's root is in the "Weapon" group (here or in the scene
## it inherits from).
static func _is_weapon(state: SceneState) -> bool:
	if state == null or state.get_node_count() == 0:
		return false
	if "Weapon" in state.get_node_groups(0):
		return true
	return _is_weapon(state.get_base_scene_state())


## Takes out the testing rooms, then puts them back if testing mode is on.
## Names are fixed so they match on every machine online.
func _refresh_test_rooms() -> void:
	_clear()
	if not testing_mode or not stand_scene:
		return
	var level: Node = get_parent()
	var weapons_root: Node = level.get_node_or_null("Weapons")
	if not weapons_root:
		push_warning("Tools: no Weapons node to put the testing stands in.")
		return
	var weapons: Array[PackedScene] = find_weapon_scenes(weapons_dir)
	if weapons.is_empty():
		push_warning("Tools: no weapons found in %s." % weapons_dir)
		return
	var radius: float = maxf(min_radius, weapons.size() * stand_spacing / TAU)
	for child: Node in level.get_children():
		if child is Altar3D:
			_build_room(child, weapons, radius, weapons_root)


func _clear() -> void:
	for node: Node in _built:
		if is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.queue_free()
	_built.clear()
	if is_instance_valid(_restore_grid):
		for cell: Vector2i in _grid_restore:
			var was: Array = _grid_restore[cell]
			_restore_grid.set_cell_item(Vector3i(cell.x, 0, cell.y), was[0], was[1])
	_grid_restore.clear()
	_restore_grid = null
	for shape: CollisionShape3D in _bounds_restore:
		if is_instance_valid(shape):
			shape.global_position = _bounds_restore[shape]
	_bounds_restore.clear()


## A walled room on the far side of the wall behind `altar` (away from the
## middle of the level), with a doorway through that wall and the stands in
## a circle in the middle. In the editor the level's own walls are left
## alone, so the doorway only opens once the match starts.
func _build_room(altar: Altar3D, weapons: Array[PackedScene], radius: float, weapons_root: Node) -> void:
	var level: Node = get_parent()
	var flat := Vector2(altar.global_position.x, altar.global_position.z)
	if flat.length() < 0.01:
		return  # In the middle: no "behind"
	var out := Vector2i(int(signf(flat.x)), 0) if absf(flat.x) >= absf(flat.y) else Vector2i(0, int(signf(flat.y)))
	var side := Vector2i(-out.y, out.x)
	var level_grid := level.get_node_or_null("Walls/WallGrid") as GridMap

	# The room's front wall is the first level wall behind the altar.
	var altar_cell := Vector2i(roundi(flat.x / G), roundi(flat.y / G))
	var wall_cell: Vector2i = altar_cell + out
	if level_grid:
		for step: int in range(1, 6):
			if _item_at(level_grid, altar_cell + out * step) != GridMap.INVALID_CELL_ITEM:
				wall_cell = altar_cell + out * step
				break
	var half: int = ceili((radius + wall_margin) / G)
	var depth: int = 2 * half
	var cell_at := func(u: int, v: int) -> Vector2i: return wall_cell + out * u + side * v

	var room_walls := {}
	for u: int in range(0, depth + 1):
		room_walls[cell_at.call(u, -half)] = true
		room_walls[cell_at.call(u, half)] = true
	for v: int in range(-half, half + 1):
		room_walls[cell_at.call(depth, v)] = true
		if absi(v) > DOOR_HALF_WIDTH:
			room_walls[cell_at.call(0, v)] = true
	var door := {}
	for v: int in range(-DOOR_HALF_WIDTH, DOOR_HALF_WIDTH + 1):
		door[cell_at.call(0, v)] = true

	var holder := Node3D.new()
	holder.name = "TestRoom_%s" % altar.name
	add_child(holder)  # Not the level: it may still be setting up its children
	_built.append(holder)

	var edit_level: bool = level_grid != null and not Engine.is_editor_hint()
	var open_door: bool = level_grid == null or edit_level
	var level_has := func(c: Vector2i) -> bool:
		return level_grid != null and _item_at(level_grid, c) != GridMap.INVALID_CELL_ITEM
	var occupied := func(c: Vector2i) -> bool:
		return not (open_door and door.has(c)) and (room_walls.has(c) or level_has.call(c))
	var lib: MeshLibrary = level_grid.mesh_library if level_grid else load(WALL_LIB)

	if edit_level:
		# Into the level's own grid, so the walls join up with what's there.
		_restore_grid = level_grid
		var touched := {}
		for cell: Vector2i in room_walls.keys() + door.keys():
			touched[cell] = true
			for dir: Vector3 in [N, S, E, W]:
				touched[cell + Vector2i(int(dir.x), int(dir.z))] = true
		var links_before := {}
		for cell: Vector2i in touched:
			links_before[cell] = _links(cell, level_has)
		for cell: Vector2i in touched:
			var had: bool = level_has.call(cell)
			var has: bool = occupied.call(cell)
			if had == has and (not has or _links(cell, occupied) == links_before[cell]):
				continue  # Unchanged: keep its piece (and any decoration)
			if not _grid_restore.has(cell):
				var at := Vector3i(cell.x, 0, cell.y)
				_grid_restore[cell] = [level_grid.get_cell_item(at), level_grid.get_cell_item_orientation(at)]
			if has:
				_set_tile(level_grid, lib, cell, occupied)
			else:
				level_grid.set_cell_item(Vector3i(cell.x, 0, cell.y), GridMap.INVALID_CELL_ITEM)
	else:
		var grid := GridMap.new()
		grid.name = "WallGrid"
		grid.mesh_library = lib
		grid.cell_size = Vector3(G, G, G)
		grid.cell_center_y = false
		grid.position = Vector3(-G / 2, 0, -G / 2)
		grid.collision_mask = 0
		holder.add_child(grid)
		grid.add_to_group(NAV_GROUP)
		for cell: Vector2i in room_walls:
			if not level_has.call(cell):
				_set_tile(grid, lib, cell, occupied)

	# Floor, between the walls' center lines.
	var corner_a: Vector2i = cell_at.call(0, -half)
	var corner_b: Vector2i = cell_at.call(depth, half)
	var lo := Vector2(mini(corner_a.x, corner_b.x), mini(corner_a.y, corner_b.y)) * G
	var hi := Vector2(maxi(corner_a.x, corner_b.x), maxi(corner_a.y, corner_b.y)) * G
	var floor_grid := GridMap.new()
	floor_grid.name = "FloorGrid"
	floor_grid.mesh_library = load(FLOOR_LIB)
	floor_grid.cell_size = Vector3(G, G, G)
	floor_grid.cell_center_y = false
	floor_grid.collision_layer = 0
	floor_grid.collision_mask = 0
	holder.add_child(floor_grid)
	var tile: int = floor_grid.mesh_library.find_item_by_name("tileBrickA_medium")
	for x: int in range(floori(lo.x / G), ceili(hi.x / G)):
		for z: int in range(floori(lo.y / G), ceili(hi.y / G)):
			floor_grid.set_cell_item(Vector3i(x, 0, z), tile)

	# Push the level's outer fence back past the room, and give everything
	# out there (room and all) something to land on.
	var far_edge: float = Vector2(cell_at.call(depth, 0) * G).dot(Vector2(out)) + 2.0
	var floor_span: float = hi.dot(Vector2(absi(side.x), absi(side.y))) - lo.dot(Vector2(absi(side.x), absi(side.y)))
	if not Engine.is_editor_hint():
		var bounds: Node = level.find_child("LevelBounds", true, false)
		for shape: CollisionShape3D in bounds.find_children("*", "CollisionShape3D", false) if bounds else []:
			var box := shape.shape as BoxShape3D
			if not box:
				continue
			var pos := Vector2(shape.global_position.x, shape.global_position.z)
			var thin_along_out: bool = box.size.x < box.size.z if out.x != 0 else box.size.z < box.size.x
			if pos.dot(Vector2(out)) <= 0.0 or not thin_along_out or pos.dot(Vector2(out)) >= far_edge:
				continue
			if not _bounds_restore.has(shape):
				_bounds_restore[shape] = shape.global_position
			var moved := pos + Vector2(out) * (far_edge - pos.dot(Vector2(out)))
			shape.global_position = Vector3(moved.x, shape.global_position.y, moved.y)
			floor_span = maxf(floor_span, box.size.z if out.x != 0 else box.size.x)
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_mask = 0
	holder.add_child(floor_body)
	floor_body.add_to_group(NAV_GROUP)
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	var mid := (lo + hi) / 2.0
	var near_edge: float = Vector2(wall_cell * G).dot(Vector2(out)) - 2.0
	var length: float = far_edge + 2.0 - near_edge
	var along: float = near_edge + length / 2.0  # Along `out`
	floor_box.size = Vector3(length if out.x != 0 else floor_span, 4.0, floor_span if out.x != 0 else length)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(along * out.x + mid.x * absi(side.x), -2.0, along * out.y + mid.y * absi(side.y))
	floor_body.add_child(floor_shape)

	var center := Vector2(cell_at.call(half, 0)) * G
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color(1.0, 0.8, 0.55)
	light.light_energy = 1.5
	light.omni_range = half * G * 1.6
	light.position = Vector3(center.x, 6.0, center.y)
	holder.add_child(light)

	# The stands, in a circle starting from the side nearest the door.
	var start: float = Vector2(-out).angle()
	for i: int in weapons.size():
		var angle: float = start + TAU * i / weapons.size()
		var stand: WeaponStand3D = stand_scene.instantiate()
		stand.name = "TestStand_%s_%d" % [altar.name, i]
		stand.weapon_scene = weapons[i]
		stand.position = Vector3(center.x + cos(angle) * radius, 0.0, center.y + sin(angle) * radius)
		weapons_root.add_child(stand)
		_built.append(stand)


func _item_at(grid: GridMap, cell: Vector2i) -> int:
	return grid.get_cell_item(Vector3i(cell.x, 0, cell.y))


## Which of the four neighbours of `cell` are walls.
func _links(cell: Vector2i, occupied: Callable) -> Array[Vector3]:
	var links: Array[Vector3] = []
	for dir: Vector3 in [N, S, E, W]:
		if occupied.call(cell + Vector2i(int(dir.x), int(dir.z))):
			links.append(dir)
	return links


## Puts the wall piece that joins up with `cell`'s neighbours there (the
## same picking as build_dungeon_arena.gd).
func _set_tile(grid: GridMap, lib: MeshLibrary, cell: Vector2i, occupied: Callable) -> void:
	var links: Array[Vector3] = _links(cell, occupied)
	var shape: String
	var base: Array
	match links.size():
		0: shape = "pillar"; base = []
		1: shape = "wall_end"; base = [E]
		2:
			if links[0].dot(links[1]) < -0.5:
				shape = "wall"; base = [W, E]
			else:
				shape = "wallCorner"; base = [W, S]
		3: shape = "wallSplit"; base = [W, E, S]
		_: shape = "wallIntersection"; base = [N, S, E, W]
	var basis := Basis(Vector3.UP, _turn_for(base, links) * PI / 2.0)
	grid.set_cell_item(Vector3i(cell.x, 0, cell.y), lib.find_item_by_name(shape),
			grid.get_orthogonal_index_from_basis(basis))


## Quarter turns that line `base` links up with `links`.
func _turn_for(base: Array, links: Array[Vector3]) -> int:
	for turn: int in 4:
		var basis := Basis(Vector3.UP, turn * PI / 2.0)
		var ok := true
		for dir: Vector3 in base:
			var turned: Vector3 = (basis * dir).round()
			var found := false
			for l: Vector3 in links:
				if l.is_equal_approx(turned):
					found = true
			ok = ok and found
		if ok:
			return turn
	return 0
