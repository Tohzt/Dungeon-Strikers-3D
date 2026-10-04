extends Node
## Generator for res://3D/Game/DungeonArena.tscn (and the wall torch scene).
## Lays out Blue's half (x < 0) and mirrors it for Red, so both sides are
## identical. Kept as a record of the layout and for big changes (moving
## rooms); for small ones just edit DungeonArena.tscn in the editor.
##
## WARNING: running it OVERWRITES DungeonArena.tscn, losing hand edits.
## To run: attach this script to a Node in an empty scene and run that scene
## (F6). It needs the autoloads, so `godot --script` won't work.
##
## Map (grid cells of 4m; Blue side, Red is the mirror). Every route from
## the spawn hall to the arena passes an encounter room (guard room, treasure
## hall or crypt), each with MobSpawns markers for future mobs.
##
##   z=-8  +--------+-----------------+
##         | ARMORY ' GUARD ROOM      '-------------------------+
##   z=-6  |        |                 |      flank passage      |
##   z=-4  +--  ---+-------  ---------+-------------------------+--  +---- arena
##         |        |                 ' corridor  '                     |
##   z=-2  |        |      o     o    +-----------+                     |
##         | SPAWN  '    TREASURE     #  VAULT    | goal   ARENA  boss  |
##   z=2   | HALL   |    HALL (chest) +-----------+                     |
##         |        |      o     o    ' corridor  '                     |
##   z=4   +--  ---+-------  ---------+-------------------------+--  +----
##   z=6   |        |                 |      flank passage      |
##         |LIBRARY ' CRYPT           '-------------------------+
##   z=8   +--------+-----------------+
##      x=-21    x=-17              x=-9        x=-5          x=-2       x=0

const G := 4.0  # Wall grid
const OUT := "res://3D/Game/DungeonArena.tscn"
const TORCH_OUT := "res://3D/Game/Level/wall_torch.tscn"
const GLB := "res://Assets/BetterDungeon/glb/%s.glb"
const NAV_GROUP := "dungeon_nav"

const N := Vector3(0, 0, -1)
const S := Vector3(0, 0, 1)
const E := Vector3(1, 0, 0)
const W := Vector3(-1, 0, 0)

var struct_lib: MeshLibrary = load("res://Game/Dungeon/dungeon_mesh_library.tres")
var floor_lib: MeshLibrary = load("res://Game/Dungeon/dungeon_floor_library.tres")
var props_lib: MeshLibrary = load("res://Game/Dungeon/dungeon_props_library.tres")

var walls := {}   # Vector2i -> true
var forced := {}  # Vector2i -> piece name (straight pieces)
var root: Node3D
var walls_map: GridMap
var floor_map: GridMap
var props_map: GridMap
var decor: Node3D
var torch_scene: PackedScene
var _counter: int = 0
## Added to Blue x coordinates while placing (the base was moved out as a block).
var _dx: float = 0.0


func _ready() -> void:
	torch_scene = _make_torch_scene()
	var ref: Node = load("res://3D/Game/Game3D.tscn").instantiate()

	root = Node3D.new()
	root.name = "DungeonArena"
	root.set_script(load("res://3D/Game/game_3d.gd"))
	root.set("player_scene", load("res://3D/player_3d/player_3d.tscn"))
	root.set("max_team_count", 2)
	root.set("spawn_distance", 30.0)

	var tools := Node.new(); tools.name = "Tools"; tools.set_script(load("res://3D/Game/tools.gd")); _add(root, tools)
	_add(root, _inst("res://3D/HUD/hud.tscn", "HUD"))
	_add(root, _inst("res://3D/HUD/scoreboard.tscn", "Scoreboard"))
	_add(root, _inst("res://Menus/PauseMenu/pause_menu.tscn", "PauseMenu"))
	var cam := _inst("res://3D/Game/game_camera.tscn", "Camera3D") as Node3D
	# Steeper than the soccer field's camera, so walls hide less behind them.
	var pitch: float = deg_to_rad(-66.0)
	cam.transform = Transform3D(Basis(Vector3.RIGHT, pitch), Vector3(0, 30, 30 / tan(-pitch)))
	cam.set("group_max_fov", 82.0)  # Bases are far apart: zoom out further to fit both teams
	_add(root, cam)

	_environment()
	_build_level(ref)

	var weapons := Node.new(); weapons.name = "Weapons"; _add(root, weapons)
	for team in 2:
		var altar := _inst("res://3D/Weapons/Altar.tscn", "Altar%s" % ("" if team == 0 else "2")) as Node3D
		var ref_altar: Node3D = ref.get_node("Altar" if team == 0 else "Altar2")
		# At the back of the spawn hall: where each team starts (and picks perks)
		altar.transform = Transform3D(ref_altar.transform.basis, Vector3(_mx(team, -81.0), 0, 0))
		altar.set("owner_team", team)
		altar.set("weapon_scene", ref_altar.get("weapon_scene"))
		_add(root, altar)
		altar.add_to_group(NAV_GROUP, true)

	var boss := _inst("res://3D/Entities/Boss_Slime/boss.tscn", "Boss")
	boss.set("max_hp", 900.0)
	boss.set("wait_for_players", true)
	_add(root, boss)
	var bar := _inst("res://3D/HUD/boss_health_bar.tscn", "BossHealthBar")
	_add(root, bar)
	bar.set("boss", boss)
	var picker := _inst("res://3D/HUD/perk_picker.tscn", "PerkPicker")
	_add(root, picker)
	var perks := Node.new(); perks.name = "Perks"; perks.set_script(load("res://3D/Perks/perk_director.gd"))
	_add(root, perks)
	perks.set("picker", picker)

	ref.free()
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("pack failed %s" % err)
	err = ResourceSaver.save(packed, OUT)
	print("saved ", OUT, " err=", err)
	root.free()
	get_tree().quit()


# ===== HELPERS =====

func _add(parent: Node, node: Node) -> Node:
	parent.add_child(node)
	node.owner = root
	return node


func _inst(path: String, node_name: String) -> Node:
	var node: Node = (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	node.name = node_name
	return node


## Blue is the x < 0 half; Red gets the mirror image.
func _mx(team: int, x: float) -> float:
	return x if team == 0 else -x


func _rot(team: int, deg: float) -> float:
	return deg if team == 0 else -deg


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.015, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.45, 0.6)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_bloom = 0.05
	env.ssao_enabled = true
	var world_env := WorldEnvironment.new(); world_env.name = "WorldEnvironment"; world_env.environment = env
	_add(root, world_env)
	var moon := DirectionalLight3D.new(); moon.name = "DirectionalLight3D"
	moon.rotation_degrees = Vector3(-62, 35, 0)
	moon.light_color = Color(0.75, 0.8, 1.0)
	moon.light_energy = 0.55
	moon.shadow_enabled = true
	_add(root, moon)


# ===== LEVEL =====

func _build_level(ref: Node) -> void:
	var walls_root := Node3D.new(); walls_root.name = "Walls"; _add(root, walls_root)

	var nav := NavigationRegion3D.new(); nav.name = "Navigation"
	nav.set_script(load("res://3D/Game/Level/auto_bake_navigation.gd"))
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	mesh.geometry_source_group_name = NAV_GROUP
	mesh.agent_radius = 0.75
	mesh.agent_height = 2.0
	mesh.agent_max_climb = 0.25
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	nav.navigation_mesh = mesh
	_add(walls_root, nav)

	# One flat floor for everything to stand on; the tiles are just looks.
	var floor_body := StaticBody3D.new(); floor_body.name = "Floor"; floor_body.collision_mask = 0
	_add(walls_root, floor_body)
	floor_body.add_to_group(NAV_GROUP, true)
	var floor_shape := CollisionShape3D.new(); floor_shape.name = "CollisionShape3D"
	# Thick, so a hard-thrown weapon can't tunnel through it.
	var box := BoxShape3D.new(); box.size = Vector3(176, 4, 72); floor_shape.shape = box
	floor_shape.position = Vector3(0, -2, 0)
	_add(floor_body, floor_shape)
	# The rock between rooms: a dark slab just under the tiles.
	var void_mesh := MeshInstance3D.new(); void_mesh.name = "Bedrock"
	var plane := PlaneMesh.new(); plane.size = Vector2(240, 130)
	var rock := StandardMaterial3D.new(); rock.albedo_color = Color(0.06, 0.055, 0.06); rock.roughness = 1.0
	plane.material = rock
	void_mesh.mesh = plane; void_mesh.position = Vector3(0, -0.03, 0)
	_add(walls_root, void_mesh)

	walls_map = GridMap.new(); walls_map.name = "WallGrid"
	walls_map.mesh_library = struct_lib
	walls_map.cell_size = Vector3(G, G, G); walls_map.cell_center_y = false
	walls_map.position = Vector3(-G / 2, 0, -G / 2)  # Cell (i, j) centered on (4i, 4j)
	walls_map.collision_mask = 0
	_add(walls_root, walls_map)
	walls_map.add_to_group(NAV_GROUP, true)

	floor_map = GridMap.new(); floor_map.name = "FloorGrid"
	floor_map.mesh_library = floor_lib
	floor_map.cell_size = Vector3(G, G, G); floor_map.cell_center_y = false
	floor_map.collision_layer = 0; floor_map.collision_mask = 0
	_add(walls_root, floor_map)

	props_map = GridMap.new(); props_map.name = "PropGrid"
	props_map.mesh_library = props_lib
	props_map.cell_size = Vector3(0.5, 0.5, 0.5); props_map.cell_center_y = false
	props_map.collision_mask = 0
	_add(walls_root, props_map)
	props_map.add_to_group(NAV_GROUP, true)

	decor = Node3D.new(); decor.name = "Decor"; _add(walls_root, decor)

	_layout_walls()
	_tile_walls()
	_lay_floors()
	_rooms()
	_arena(ref, walls_root)


## Wall lines, in grid cells (1 cell = 4m), Blue's half. See the map in
## the level notes: spawn hall, armory (north), library (south), the
## sealed vault behind the goal, two corridors and two flanking passages
## into the arena.
func _layout_walls() -> void:
	var blue := {}
	var h := func(z: int, x0: int, x1: int) -> void:
		for x in range(x0, x1 + 1): blue[Vector2i(x, z)] = true
	var v := func(x: int, z0: int, z1: int) -> void:
		for z in range(z0, z1 + 1): blue[Vector2i(x, z)] = true
	h.call(-8, -21, -9); h.call(8, -21, -9)       # Outer walls of the side rooms
	h.call(-6, -9, -2); h.call(6, -9, -2)         # Flank passages, outer side
	h.call(-4, -21, 0); h.call(4, -21, 0)         # Arena long walls, run on west
	h.call(-2, -9, -5); h.call(2, -9, -5)         # Corridors, inner side (vault)
	v.call(-21, -8, 8)                            # Back of the base
	v.call(-17, -8, 8)                            # Spawn hall / armory / library east wall
	v.call(-9, -8, 8)                             # Treasure hall east wall
	v.call(-5, -4, 4)                             # Arena end wall (goal)
	v.call(-2, -6, -4); v.call(-2, 4, 6)          # Flank passage ends
	for pillar: Vector2i in [Vector2i(-15, -2), Vector2i(-11, -2), Vector2i(-15, 2), Vector2i(-11, 2)]:
		blue[pillar] = true                       # Treasure hall pillars
	for gap: Vector2i in [
		Vector2i(-19, -4), Vector2i(-19, 4),      # Spawn hall <-> armory / library
		Vector2i(-17, -6), Vector2i(-17, 6),      # Armory / library <-> guard room / crypt
		Vector2i(-17, 0),                         # Spawn hall <-> treasure hall
		Vector2i(-13, -4), Vector2i(-13, 4),      # Treasure hall <-> guard room / crypt
		Vector2i(-9, -5), Vector2i(-9, 5),        # Guard room / crypt <-> flank
		Vector2i(-9, -3), Vector2i(-9, 3),        # Treasure hall <-> corridors
		Vector2i(-5, -3), Vector2i(-5, 3),        # Corridors <-> arena
		Vector2i(-3, -4), Vector2i(-3, 4),        # Flanks <-> arena
	]:
		blue.erase(gap)
	for cell: Vector2i in blue:
		walls[cell] = true
		walls[Vector2i(-cell.x, cell.y)] = true
	for crypt_pillar: Vector2i in [Vector2i(-15, 6), Vector2i(-11, 6)]:
		walls[crypt_pillar] = true
		walls[Vector2i(-crypt_pillar.x, crypt_pillar.y)] = true
		forced[crypt_pillar] = "pillar_broken"
		forced[Vector2i(-crypt_pillar.x, crypt_pillar.y)] = "pillar_broken"
	forced[Vector2i(-9, 0)] = "wall_gate"  # Portcullis into the vault
	forced[Vector2i(9, 0)] = "wall_gate"


## Picks each wall cell's piece from which neighbours are walls too.
func _tile_walls() -> void:
	for cell: Vector2i in walls:
		var links: Array[Vector3] = []
		for dir: Vector3 in [N, S, E, W]:
			if walls.has(cell + Vector2i(int(dir.x), int(dir.z))):
				links.append(dir)
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
		var piece_name: String = shape
		if shape == "pillar":
			piece_name = forced.get(cell, "pillar")
		elif shape == "wall":
			piece_name = forced.get(cell, _wall_variant(cell))
		var basis := Basis(Vector3.UP, _turn_for(base, links) * PI / 2.0)
		walls_map.set_cell_item(Vector3i(cell.x, 0, cell.y), struct_lib.find_item_by_name(piece_name),
				walls_map.get_orthogonal_index_from_basis(basis))


## Quarter turns that line `base` links up with `links`.
func _turn_for(base: Array, links: Array[Vector3]) -> int:
	for turn in 4:
		var basis := Basis(Vector3.UP, turn * PI / 2.0)
		var ok := true
		for dir: Vector3 in base:
			var turned: Vector3 = (basis * dir).round()
			var found := false
			for l: Vector3 in links:
				if l.is_equal_approx(turned): found = true
			ok = ok and found
		if ok:
			return turn
	return 0


## Mostly plain wall, sometimes decorated or crumbling (same on both sides).
func _wall_variant(cell: Vector2i) -> String:
	var roll: int = _hash(absi(cell.x), cell.y) % 100
	if roll < 12: return "wallDecorationA"
	if roll < 22: return "wallDecorationB"
	if roll < 28: return "wall_broken"
	return "wall"


func _hash(a: int, b: int) -> int:
	return absi((a * 73856093) ^ (b * 19349663) ^ 0x5bd1e995) % 100003


## Rooms' floor cells: [x0, x1) x [z0, z1) in wall cells, plus the tile mix.
func _lay_floors() -> void:
	var areas := [
		# x0, x1, z0, z1, style
		[-5, 5, -4, 4, "arena"],
		[-21, -17, -4, 4, "hall"],
		[-21, -17, -8, -4, "armory"], [-21, -17, 4, 8, "library"],
		[-17, -9, -4, 4, "hall"],
		[-17, -9, -8, -4, "armory"], [-17, -9, 4, 8, "crypt"],
		[-9, -5, -4, -2, "corridor"], [-9, -5, 2, 4, "corridor"],
		[-9, -2, -6, -4, "corridor"], [-9, -2, 4, 6, "corridor"],
		[-9, -5, -2, 2, "vault"],
	]
	var a_tile: int = floor_lib.find_item_by_name("tileBrickA_medium")
	var b_tile: int = floor_lib.find_item_by_name("tileBrickB_medium")
	for area: Array in areas:
		for mirror in 2:
			if mirror == 1 and area[4] == "arena":
				continue
			for x in range(area[0], area[1]):
				for z in range(area[2], area[3]):
					var cx: int = x if mirror == 0 else -x - 1
					var key: int = _hash(x if x >= 0 else -x - 1, z)
					var item: int = a_tile
					match area[4]:
						"arena": item = b_tile if (x + z) % 2 == 0 else a_tile
						"hall", "vault": item = a_tile if key % 4 else b_tile
						"crypt": item = a_tile
						_: item = b_tile if key % 3 else a_tile
					var basis := Basis(Vector3.UP, (key % 4) * PI / 2.0)
					floor_map.set_cell_item(Vector3i(cx, 0, z), item, floor_map.get_orthogonal_index_from_basis(basis))


# ===== PLACING THINGS (Blue coordinates; Red mirrors) =====

## A prop on the 0.5m prop grid, on both sides.
func _prop(piece: String, x: float, z: float, deg: float = 0.0, y: float = 0.0) -> void:
	var item: int = props_lib.find_item_by_name(piece)
	if item < 0:
		push_error("no prop " + piece)
		return
	for team in 2:
		var px: float = _mx(team, x + _dx)
		var cell := Vector3i(floori(px / 0.5), roundi(y / 0.5), floori(z / 0.5))
		var basis := Basis(Vector3.UP, deg_to_rad(_rot(team, deg)))
		props_map.set_cell_item(cell, item, props_map.get_orthogonal_index_from_basis(basis))


## A freely placed model (for things off the grid: stacked, hung, tilted).
## `y` is the height of the surface it stands on (props sit on their base).
func _model(piece: String, x: float, y: float, z: float, deg: float = 0.0, team_tint: bool = false) -> void:
	var item: int = props_lib.find_item_by_name(piece)
	for team in 2:
		var at := Transform3D(Basis(Vector3.UP, deg_to_rad(_rot(team, deg))), Vector3(_mx(team, x + _dx), y, z))
		var node: Node3D
		if item >= 0:
			var mi := MeshInstance3D.new()
			mi.mesh = props_lib.get_item_mesh(item)
			mi.transform = at * props_lib.get_item_mesh_transform(item)
			node = mi
		else:
			node = _inst(GLB % piece, piece)
			node.transform = at
		_counter += 1
		node.name = "%s_%s%d" % [piece, "Blue" if team == 0 else "Red", _counter]
		_add(decor, node)
		if team_tint and team == 1:
			_tint_red(node)


## Banners come blue; Red's get red cloth.
func _tint_red(mi: MeshInstance3D) -> void:
	for i in mi.mesh.get_surface_count():
		var mat: Material = mi.mesh.surface_get_material(i)
		if mat and mat.resource_name.begins_with("Blue"):
			var red := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			red.albedo_color = Color(0.55, 0.08, 0.06) if mat.resource_name == "BlueDark" else Color(0.85, 0.22, 0.15)
			mi.set_surface_override_material(i, red)


## A lit torch on the wall face at (x, z), pointing `deg` (0 = +z).
func _torch(x: float, z: float, deg: float) -> void:
	for team in 2:
		var t: Node3D = torch_scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		_counter += 1
		t.name = "WallTorch_%s%d" % ["Blue" if team == 0 else "Red", _counter]
		t.position = Vector3(_mx(team, x + _dx), 1.9, z)
		t.rotation_degrees.y = _rot(team, deg)
		_add(decor, t)


func _orb(x: float, z: float, big: bool) -> void:
	var holder: Node = root.get_node_or_null("BoostOrbs")
	if holder == null:
		holder = Node3D.new(); holder.name = "BoostOrbs"; _add(root, holder)
	for team in 2:
		var orb: Node3D = _inst("res://3D/Items/Boost/boost_orb.tscn", "%sOrb%d" % ["Big" if big else "", holder.get_child_count() + 1])
		orb.position = Vector3(_mx(team, x + _dx), 0, z)
		if big:
			orb.set("amount", 100.0)
			orb.set("respawn_time", 10.0)
		_add(holder, orb)


func _stand(weapon: String, x: float, z: float) -> void:
	var holder: Node = root.get_node_or_null("WeaponStands")
	if holder == null:
		holder = Node3D.new(); holder.name = "WeaponStands"; _add(root, holder)
	for team in 2:
		var stand: Node3D = _inst("res://3D/Weapons/weapon_stand.tscn", "%s_%s" % [weapon.get_file().get_basename(), "Blue" if team == 0 else "Red"])
		stand.position = Vector3(_mx(team, x + _dx), 0, z)
		stand.set("weapon_scene", load(weapon))
		_add(holder, stand)


## The team's treasure chest (one per side), facing `deg`.
func _chest(x: float, z: float, deg: float) -> void:
	var holder: Node = root.get_node_or_null("Chests")
	if holder == null:
		holder = Node3D.new(); holder.name = "Chests"; _add(root, holder)
	for team in 2:
		var chest: Node3D = _inst("res://3D/Weapons/Chest/chest.tscn", "Chest%s" % ("Blue" if team == 0 else "Red"))
		chest.position = Vector3(_mx(team, x + _dx), 0, z)
		chest.rotation_degrees.y = _rot(team, deg)
		_add(holder, chest)
		chest.add_to_group(NAV_GROUP, true)


## Where mobs will come from (nothing spawns them yet). Grouped "MobSpawn".
func _mob_spawn(room: String, x: float, z: float) -> void:
	var holder: Node = root.get_node_or_null("MobSpawns")
	if holder == null:
		holder = Node3D.new(); holder.name = "MobSpawns"; _add(root, holder)
	for team in 2:
		var marker := Marker3D.new()
		_counter += 1
		marker.name = "%s_%s%d" % [room, "Blue" if team == 0 else "Red", _counter]
		marker.position = Vector3(_mx(team, x + _dx), 0, z)
		_add(holder, marker)
		marker.add_to_group("MobSpawn", true)


func _rooms() -> void:
	# The spawn hall, armory and library sit one room further out (x -84..-68)
	# than these coordinates say.
	_dx = -32.0
	# --- Spawn hall: x (-52, -36), z (-16, 16) ---
	for team in 2:
		var spawn: Node3D = Marker3D.new()
		spawn.set_script(load("res://3D/Game/Level/spawn_point.gd"))
		spawn.name = "Spawn%s" % ("Blue" if team == 0 else "Red")
		spawn.set("team", team)
		spawn.position = Vector3(_mx(team, -43.0 + _dx), 0, 0)
		spawn.rotation_degrees.y = 90.0
		_add(root, spawn)
		var glow := OmniLight3D.new(); glow.name = "TeamGlow%s" % ("Blue" if team == 0 else "Red")
		glow.light_color = Color(0.35, 0.5, 1.0) if team == 0 else Color(1.0, 0.35, 0.3)
		glow.light_energy = 2.0; glow.omni_range = 16.0
		glow.position = Vector3(_mx(team, -46.0 + _dx), 5.0, 0)
		_add(decor, glow)
	for z: float in [-9.0, 9.0]:
		_model("banner", -51.2, 3.7, z, 90.0, true)
	for z: float in [-13.0, 0.0, 13.0]:
		_torch(-51.1, z, 90.0)
	_torch(-44.0, -15.1, 0.0); _torch(-44.0, 15.1, 180.0)
	# Long tables down the back wall, a barrel corner and a crate corner
	_prop("tableLarge", -49.25, -5.25, 90.0); _prop("bench", -47.75, -6.25, 90.0)
	_prop("tableLarge", -49.25, 5.25, 90.0); _prop("bench", -47.75, 4.25, 90.0)
	_model("plateFull", -49.3, 0.71, -6.0); _model("mug", -49.0, 0.71, -4.6, 40.0)
	_model("plateHalf", -49.4, 0.71, 4.6); _model("mug", -49.1, 0.71, 6.1, -20.0)
	_model("bookOpenA", -49.3, 0.71, 5.6, 10.0)
	_prop("barrel", -50.25, -14.25); _prop("barrelDark", -49.25, -14.25)
	_prop("barrel", -50.25, -13.25, 90.0); _prop("bucket", -48.25, -14.25)
	_prop("crate", -50.25, 14.25); _prop("crateDark", -49.25, 14.25, 90.0)
	_model("crate", -50.2, 1.06, 14.2, 25.0)
	_prop("lootSackB", -48.25, 14.25)

	# --- Armory: x (-52, -36), z (-32, -16) ---
	var weapons := [
		"res://3D/Weapons/Sword/sword_3d.tscn", "res://3D/Weapons/Axe/axe_3d.tscn",
		"res://3D/Weapons/Hammer/hammer_3d.tscn", "res://3D/Weapons/Bow and Arrow/bow_3d.tscn",
		"res://3D/Weapons/Staff/staff_3d.tscn", "res://3D/Weapons/Dagger/dagger_3d.tscn",
	]
	for i in 6:
		@warning_ignore("integer_division")
		_stand(weapons[i], -48.0 + (i % 3) * 4.0, -27.0 + (i / 3) * 5.0)
	for x: float in [-49.0, -44.0, -39.0]:
		_prop("weaponRack", x, -30.75, 180.0)
	_model("quiver_full", -50.5, 0.0, -30.4, 180.0)
	_model("shield_rare", -41.0, 0.45, -30.9, 0.0)
	_prop("cratePlatform_medium", -50.25, -18.25)
	_prop("barrel", -37.75, -30.25); _prop("barrel", -37.75, -29.25, 90.0)
	_torch(-44.0, -31.1, 0.0); _torch(-51.1, -24.0, 90.0)
	_model("banner", -51.2, 3.7, -28.5, 90.0, true)

	# --- Library: x (-52, -36), z (16, 32) ---
	for x: float in [-49.25, -45.25, -41.25]:
		_prop("bookcaseWideFilled" if x != -45.25 else "bookcaseWideFilled_broken", x, 30.75, 180.0)
	_prop("bookcaseFilled", -50.75, 25.25, 90.0); _prop("bookcase", -50.75, 22.75, 90.0)
	_prop("tableMedium", -44.25, 24.25); _prop("chair", -44.25, 25.75, 180.0); _prop("stool", -42.25, 24.25)
	_model("spellBook", -44.4, 0.71, 24.2, 15.0); _model("potionSmall_blue", -43.6, 0.71, 24.0)
	_model("bookA", -45.0, 0.71, 24.4, 80.0)
	_prop("bookOpenB", -47.75, 27.75, 30.0); _prop("bookC", -47.25, 28.25, 70.0)
	_prop("potionLarge_green", -37.75, 30.75); _prop("potionMedium_red", -38.75, 30.75)
	_prop("pots", -37.75, 17.75)
	_torch(-51.1, 29.0, 90.0); _torch(-36.9, 27.5, -90.0)
	_orb(-44.0, 20.0, true)
	_dx = 0.0

	_treasure_hall()
	_guard_room()
	_crypt()

	# --- Vault behind the goal: x (-36, -20), z (-8, 8), sealed by a portcullis ---
	_prop("chest_rare", -29.25, 0.25, 90.0)
	
	_prop("coinsLarge", -26.25, -3.75); _prop("coinsMedium", -24.25, 3.25, 60.0)
	_prop("coinsSmall", -31.75, 4.75); _prop("coin", -27.75, 5.25)
	_prop("lootSackA", -22.25, -5.75); _prop("lootSackB", -23.25, -6.25, 45.0)
	_prop("artifact", -23.75, 0.25); _prop("potA_decorated", -33.75, -5.75); _prop("potB_decorated", -32.75, -6.25)
	_torch(-20.95, -4.0, -90.0); _torch(-20.95, 4.0, -90.0)

	# --- Corridors to the arena: x (-36, -20), z (-16, -8) and mirror ---
	for z_sign: float in [-1.0, 1.0]:
		_prop("barrel", -33.25, 15.0 * z_sign - 0.25); _prop("crateDark", -24.25, 9.25 * z_sign)
		_torch(-28.0, 15.1 * z_sign, 180.0 if z_sign > 0 else 0.0)
		_orb(-28.0, 12.0 * z_sign, false)

	# --- Flank passages: x (-36, -8), z (-24, -16) and mirror ---
	for z_sign: float in [-1.0, 1.0]:
		_prop("cratePlatform_small", -33.25, 23.25 * z_sign); _prop("crate", -31.75, 23.25 * z_sign)
		_prop("bricks", -17.25, 22.75 * z_sign, 30.0)
		_model("floorDecoration_shatteredBricks", -24.0, 0.01, 20.0 * z_sign, 40.0)
		_torch(-22.0, 23.1 * z_sign, 180.0 if z_sign > 0 else 0.0)
		_torch(-12.0, 23.1 * z_sign, 180.0 if z_sign > 0 else 0.0)
		_orb(-16.0, 20.0 * z_sign, false)


## x (-68, -36), z (-16, 16): straight ahead from the spawn hall, the way to
## both corridors. The team's chest sits in the middle among four pillars.
func _treasure_hall() -> void:
	_chest(-50.0, 0.0, -90.0)
	_model("floorDecoration_tilesLarge", -50.0, 0.01, 0.0)
	_prop("coinsSmall", -48.25, -2.25, 30.0); _prop("coin", -51.75, 2.75)
	_prop("coinsMedium", -47.25, 2.25, 110.0); _prop("lootSackA", -53.25, -2.75)
	for z_sign: float in [-1.0, 1.0]:
		_model("banner", -67.2, 3.7, 8.0 * z_sign, 90.0, true)
		_model("banner", -36.8, 3.7, 6.0 * z_sign, -90.0, true)
		_torch(-62.0, 15.1 * z_sign, 180.0 if z_sign > 0 else 0.0)
		_torch(-42.0, 15.1 * z_sign, 180.0 if z_sign > 0 else 0.0)
		_torch(-67.1, 12.0 * z_sign, 90.0)
		_prop("potB_decorated", -66.25, 14.25 * z_sign); _prop("potA", -65.25, 14.75 * z_sign)
		_prop("crateDark", -37.75, 14.75 * z_sign); _prop("barrel", -38.75, 14.75 * z_sign)
		_mob_spawn("TreasureHall", -57.0, 5.0 * z_sign)
		_mob_spawn("TreasureHall", -44.0, 4.0 * z_sign)


## x (-68, -36), z (-32, -16): the northern way round, armory to flank.
func _guard_room() -> void:
	_prop("tableMedium", -60.25, -27.75); _prop("stool", -60.25, -26.25); _prop("stool", -58.25, -27.75)
	_model("mug", -60.6, 0.71, -27.9, 30.0); _model("plate", -59.8, 0.71, -27.6)
	_prop("tableSmall", -55.25, -29.75); _prop("chair", -55.25, -28.25, 180.0)
	_model("bookOpenA", -55.3, 0.71, -29.8, -20.0)
	for x: float in [-48.0, -44.0]:
		_prop("weaponRack", x, -30.75, 180.0)
	_prop("cratePlatform_large", -65.75, -29.75); _prop("crate", -66.25, -26.75)
	_prop("barrel", -38.25, -30.25); _prop("barrelDark", -39.25, -30.25); _prop("barrel", -38.25, -29.25)
	_prop("bricks", -41.75, -18.25, 60.0)
	_model("floorDecoration_shatteredBricks", -47.0, 0.01, -22.0, 15.0)
	_model("banner", -56.0, 3.7, -31.2, 0.0, true)
	_torch(-62.0, -31.1, 0.0); _torch(-40.0, -31.1, 0.0); _torch(-58.0, -16.95, 180.0)
	_mob_spawn("GuardRoom", -56.0, -23.0)
	_mob_spawn("GuardRoom", -47.0, -26.0)
	_mob_spawn("GuardRoom", -42.0, -21.0)


## x (-68, -36), z (16, 32): the southern way round, library to flank.
## Crumbling pillars, broken shelves and a sickly green light.
func _crypt() -> void:
	_prop("bookcaseWide_broken", -48.25, 30.75, 180.0); _prop("bookcase_broken", -42.75, 30.75, 180.0)
	_prop("potC_decorated", -66.25, 30.25); _prop("potB", -65.25, 30.75); _prop("potA_decorated", -66.25, 29.25)
	_prop("pots", -38.25, 30.25); _prop("lootSackB", -39.75, 30.75)
	_prop("trapdoor", -55.75, 28.25, 90.0)
	_prop("coinsSmall", -61.25, 20.25); _prop("spellBook", -45.75, 19.25, 40.0)
	_prop("potionSmall_green", -41.25, 18.25); _prop("potionMedium_green", -40.25, 18.75)
	_prop("bricks", -63.25, 25.75, 200.0); _prop("bricks", -45.25, 27.25, 120.0)
	_model("floorDecoration_shatteredBricks", -52.0, 0.01, 22.0, 70.0)
	_model("floorDecoration_shatteredBricks", -58.0, 0.01, 27.0, 10.0)
	for team in 2:
		var eerie := OmniLight3D.new(); eerie.name = "CryptGlow%s" % ("Blue" if team == 0 else "Red")
		eerie.light_color = Color(0.45, 1.0, 0.55); eerie.light_energy = 1.6; eerie.omni_range = 12.0
		eerie.position = Vector3(_mx(team, -52.0), 3.0, 25.0)
		_add(decor, eerie)
	_torch(-62.0, 31.1, 180.0); _torch(-40.0, 16.95, 0.0)
	_mob_spawn("Crypt", -56.0, 22.0)
	_mob_spawn("Crypt", -48.0, 27.0)
	_mob_spawn("Crypt", -42.0, 22.0)


func _arena(ref: Node, walls_root: Node) -> void:
	# Goals in the middle of each end wall (Blue defends the west one).
	for team in 2:
		var goal: Node3D = _inst("res://3D/Game/goal.tscn", "Goal" if team == 1 else "Goal2")
		var ref_goal: Node3D = ref.get_node("Walls/Goal" if team == 1 else "Walls/Goal2")
		goal.transform = Transform3D(ref_goal.transform.basis, Vector3(_mx(team, -18.6), 1.75, 0))
		goal.set("owner_team", team)
		goal.set("scoring_team", 1 - team)
		_add(walls_root, goal)
		goal.add_to_group(NAV_GROUP, true)
	# Broken pillars for cover, a rune circle under the boss
	_prop("cratePlatform_small", -14.25, -12.25)
	_model("floorDecoration_tilesLarge", 0.0, 0.01, 0.0)
	for z_sign: float in [-1.0, 1.0]:
		walls_map.set_cell_item(Vector3i(-2, 0, int(2 * z_sign)), struct_lib.find_item_by_name("pillar_broken"))
		walls_map.set_cell_item(Vector3i(2, 0, int(2 * z_sign)), struct_lib.find_item_by_name("pillar_broken"))
		_torch(-6.0, 15.1 * z_sign, 180.0 if z_sign > 0 else 0.0)
		_torch(-16.0, 15.1 * z_sign, 180.0 if z_sign > 0 else 0.0)
		_torch(-19.1, 6.0 * z_sign, 90.0)
		_model("banner", -19.2, 3.7, 4.6 * z_sign, 90.0, true)
		_orb(-8.0, 11.0 * z_sign, false)

	# The boss stays in the arena: a tall invisible cage along the arena
	# walls that only it collides with (its stomp leap clears the walls).
	var barrier := StaticBody3D.new(); barrier.name = "BossCage"
	barrier.collision_layer = 32; barrier.collision_mask = 0
	_add(walls_root, barrier)
	for spec: Array in [
		["West", Vector3(-20, 20, 0), Vector3(1.5, 40, 33.5)], ["East", Vector3(20, 20, 0), Vector3(1.5, 40, 33.5)],
		["North", Vector3(0, 20, -16), Vector3(41.5, 40, 1.5)], ["South", Vector3(0, 20, 16), Vector3(41.5, 40, 1.5)],
	]:
		var cs := CollisionShape3D.new(); cs.name = spec[0]
		var b := BoxShape3D.new(); b.size = spec[2]; cs.shape = b
		cs.position = spec[1]
		_add(barrier, cs)
	# ...and can't perch on the broken pillars (the altars have their own).
	for px: float in [-8.0, 8.0]:
		for pz: float in [-8.0, 8.0]:
			var cs := CollisionShape3D.new(); cs.name = "Pillar%d" % barrier.get_child_count()
			var b := BoxShape3D.new(); b.size = Vector3(2.2, 40, 2.2); cs.shape = b
			cs.position = Vector3(px, 20, pz)
			_add(barrier, cs)

	# Nothing leaves the level: a tall invisible fence just outside the
	# outer walls (thrown weapons can sail over them).
	var bounds := StaticBody3D.new(); bounds.name = "LevelBounds"
	bounds.collision_mask = 0
	_add(walls_root, bounds)
	for spec: Array in [
		["West", Vector3(-86, 20, 0), Vector3(2, 40, 72)], ["East", Vector3(86, 20, 0), Vector3(2, 40, 72)],
		["North", Vector3(0, 20, -34), Vector3(174, 40, 2)], ["South", Vector3(0, 20, 34), Vector3(174, 40, 2)],
	]:
		var cs := CollisionShape3D.new(); cs.name = spec[0]
		var b := BoxShape3D.new(); b.size = spec[2]; cs.shape = b
		cs.position = spec[1]
		_add(bounds, cs)

	# Walking into the arena wakes the boss.
	var trigger := Area3D.new(); trigger.name = "BossTrigger"
	trigger.set_script(load("res://3D/Game/Level/boss_trigger.gd"))
	trigger.collision_layer = 0; trigger.collision_mask = 2; trigger.monitorable = false
	_add(walls_root, trigger)
	trigger.add_to_group("ArenaZone", true)  # The camera widens to show the fight in here
	var tcs := CollisionShape3D.new(); tcs.name = "CollisionShape3D"
	var tb := BoxShape3D.new(); tb.size = Vector3(38, 6, 30); tcs.shape = tb; tcs.position = Vector3(0, 3, 0)
	_add(trigger, tcs)


# ===== WALL TORCH SCENE =====

func _make_torch_scene() -> PackedScene:
	var t := Node3D.new(); t.name = "WallTorch"
	var model: Node3D = (load(GLB % "torchWall") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	model.name = "torchWall"
	t.add_child(model); model.owner = t
	var flame := MeshInstance3D.new(); flame.name = "Flame"
	var sphere := SphereMesh.new(); sphere.radius = 0.13; sphere.height = 0.34
	var hot := StandardMaterial3D.new()
	hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hot.albedo_color = Color(1.0, 0.55, 0.15)
	hot.emission_enabled = true; hot.emission = Color(1.0, 0.45, 0.1); hot.emission_energy_multiplier = 4.0
	sphere.material = hot
	flame.mesh = sphere
	flame.position = Vector3(0, 1.08, 0.72)
	t.add_child(flame); flame.owner = t
	var light := OmniLight3D.new(); light.name = "Light"
	light.set_script(load("res://3D/Game/Level/flicker_light.gd"))
	light.light_color = Color(1.0, 0.62, 0.3)
	light.light_energy = 2.2
	light.omni_range = 9.0
	light.omni_attenuation = 1.2
	light.position = Vector3(0, 1.3, 1.1)
	t.add_child(light); light.owner = t
	var packed := PackedScene.new()
	packed.pack(t)
	ResourceSaver.save(packed, TORCH_OUT)
	t.free()
	return load(TORCH_OUT)
