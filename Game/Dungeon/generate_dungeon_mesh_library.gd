@tool
extends EditorScript
## Rebuilds the dungeon GridMap palettes from res://Assets/BetterDungeon/glb/:
##
## - dungeon_mesh_library.tres  Walls, pillars, stairs, scaffolds. 4m grid,
##                              cell_center_y off; walls run through cell centers.
## - dungeon_floor_library.tres Floor tiles, shifted so their top is at y=0.
##                              4m grid (medium tiles fill one cell). No collision:
##                              levels put one flat floor body underneath instead,
##                              so balls and players never catch on tile seams.
## - dungeon_props_library.tres Furniture and clutter, shifted to sit on y=0.
##                              Meant for a 0.5m grid. Big pieces get a box
##                              collider; small clutter has none.
##
## Run it from the Script Editor with this file open (File > Run, or Ctrl+Shift+X),
## or headlessly from a SceneTree script that calls
##   load("res://Game/Dungeon/generate_dungeon_mesh_library.gd").build()
## (EditorScript itself can only be instantiated inside the editor).
##
## GridMap cells store the item ID, which is the index in each list, so only
## ever append new pieces to the end of a list. Reordering scrambles levels.

const SOURCE_DIR := "res://Assets/BetterDungeon/glb/"
const STRUCTURE_PATH := "res://Game/Dungeon/dungeon_mesh_library.tres"
const FLOOR_PATH := "res://Game/Dungeon/dungeon_floor_library.tres"
const PROPS_PATH := "res://Game/Dungeon/dungeon_props_library.tres"

enum Collision { NONE, TRIMESH, BOX, WALL }
enum Align { AS_IS, FLOOR_TOP, SIT_ON_FLOOR }

## Props that animate or need scripted behavior (doors, gates) are placed by
## hand as separate scenes instead of being baked into a GridMap.
const STRUCTURE : Array[String] = [
	"pillar", "pillar_broken", "wall", "wallCorner", "wallDecorationA",
	"wallDecorationB", "wallIntersection", "wallSingle", "wallSingle_broken",
	"wallSingle_corner", "wallSingle_decorationA", "wallSingle_decorationB",
	"wallSingle_door", "wallSingle_split", "wallSingle_window",
	"wallSingle_windowGate", "wallSplit", "wall_broken", "wall_door",
	"wall_end", "wall_end_broken", "wall_gate", "wall_gateCorner",
	"wall_gateDoor", "wall_window", "wall_windowGate",
	"stairs", "stairs_wide", "scaffold_stairs",
	"scaffold_low", "scaffold_low_railing", "scaffold_low_cornerLeft",
	"scaffold_low_cornerRight", "scaffold_low_cornerBoth",
	"scaffold_medium", "scaffold_medium_railing", "scaffold_medium_cornerLeft",
	"scaffold_medium_cornerRight", "scaffold_medium_cornerBoth",
	"scaffold_high", "scaffold_high_railing", "scaffold_high_cornerLeft",
	"scaffold_high_cornerRight", "scaffold_high_cornerBoth",
	"scaffold_small_low", "scaffold_small_low_long", "scaffold_small_low_railing",
	"scaffold_small_low_railing_long", "scaffold_small_low_cornerLeft",
	"scaffold_small_low_cornerRight",
	"scaffold_small_medium", "scaffold_small_medium_long",
	"scaffold_small_medium_railing", "scaffold_small_medium_railing_long",
	"scaffold_small_medium_cornerLeft", "scaffold_small_medium_cornerRight",
	"scaffold_small_high", "scaffold_small_high_long",
	"scaffold_small_high_railing", "scaffold_small_high_railing_long",
	"scaffold_small_high_cornerLeft", "scaffold_small_high_cornerRight",
]

## Solid wall pieces get simple box colliders (a center post plus one box
## per arm) rather than their bumpy trimesh, so balls bounce cleanly and
## held weapons can't wedge into a concave corner and get flung. Arms point
## +x (E), -x (W), +z (S), -z (N) as the piece is modelled. Pieces with
## openings (doors, windows, scaffolds) keep their trimesh.
const WALL_ARMS : Dictionary[String, Array] = {
	"wall": [Vector3.LEFT, Vector3.RIGHT],
	"wall_broken": [Vector3.LEFT, Vector3.RIGHT],
	"wallDecorationA": [Vector3.LEFT, Vector3.RIGHT],
	"wallDecorationB": [Vector3.LEFT, Vector3.RIGHT],
	"wall_gate": [Vector3.LEFT, Vector3.RIGHT],
	"wallCorner": [Vector3.LEFT, Vector3.BACK],
	"wall_gateCorner": [Vector3.LEFT, Vector3.BACK],
	"wallSplit": [Vector3.LEFT, Vector3.RIGHT, Vector3.BACK],
	"wallIntersection": [Vector3.LEFT, Vector3.RIGHT, Vector3.BACK, Vector3.FORWARD],
	"wall_end": [Vector3.RIGHT],
	"wall_end_broken": [Vector3.RIGHT],
	"pillar": [],
	"pillar_broken": [],
}
## Wall half-thickness and height (4m grid, 1.5m thick walls).
const WALL_HALF := 0.75
const WALL_HEIGHT := 4.0

const FLOORS : Array[String] = [
	"tileBrickB_medium", "tileBrickA_medium",
	"tileBrickB_small", "tileBrickA_small",
	"tileBrickB_large", "tileBrickB_largeCrackedA", "tileBrickB_largeCrackedB",
	"tileBrickA_large",
	"tileSpikes", "tileSpikes_large", "tileSpikes_shallow",
]

## Big enough to block movement (and bots path around them).
const PROPS_SOLID : Array[String] = [
	"barrel", "barrelDark", "crate", "crateDark",
	"cratePlatform_small", "cratePlatform_medium", "cratePlatform_large",
	"tableSmall", "tableMedium", "tableLarge", "bench",
	"bookcase", "bookcaseFilled", "bookcase_broken", "bookcaseFilled_broken",
	"bookcaseWide", "bookcaseWideFilled", "bookcaseWide_broken",
	"bookcaseWideFilled_broken",
	"chest_common", "chest_common_empty", "chest_uncommon", "chest_uncommon_mimic",
	"chest_rare", "chest_rare_mimic",
	"pots", "potA", "potA_decorated", "potB", "potB_decorated", "potC",
	"potC_decorated", "lootSackA", "lootSackB",
	"potionLarge_blue", "potionLarge_green", "potionLarge_red",
	"coinsLarge", "weaponRack", "artifact",
]
## Clutter you walk through (or that sits on top of other props).
const PROPS_CLUTTER : Array[String] = [
	"chair", "stool", "bucket", "bricks",
	"bookA", "bookB", "bookC", "bookD", "bookE", "bookF", "bookOpenA",
	"bookOpenB", "spellBook",
	"plate", "plateFull", "plateHalf", "mug",
	"potionMedium_blue", "potionMedium_green", "potionMedium_red",
	"potionSmall_blue", "potionSmall_green", "potionSmall_red",
	"coin", "coinsSmall", "coinsMedium",
	"quiver_empty", "quiver_half_full", "quiver_full",
	"chestTop_common", "chestTop_common_empty", "chestTop_uncommon",
	"chestTop_uncommon_mimic", "chestTop_rare", "chestTop_rare_mimic",
	"floorDecoration_tilesSmall", "floorDecoration_tilesLarge",
	"floorDecoration_wood", "floorDecoration_woodLeft",
	"floorDecoration_woodRight", "floorDecoration_shatteredBricks",
	"trapdoor",
]
## Hung on walls: kept at their modelled height (a banner hangs down from
## its pivot), so paint them one cell layer up or more.
const PROPS_WALL : Array[String] = ["banner", "torchWall"]


func _run() -> void:
	build()


static func build() -> void:
	var structure := MeshLibrary.new()
	for piece_name in STRUCTURE:
		var collision: Collision = Collision.WALL if WALL_ARMS.has(piece_name) else Collision.TRIMESH
		if not _add(structure, piece_name, collision, Align.AS_IS):
			return
	_save(structure, STRUCTURE_PATH)

	var floors := MeshLibrary.new()
	for piece_name in FLOORS:
		if not _add(floors, piece_name, Collision.NONE, Align.FLOOR_TOP):
			return
	_save(floors, FLOOR_PATH)

	var props := MeshLibrary.new()
	for piece_name in PROPS_SOLID:
		if not _add(props, piece_name, Collision.BOX, Align.SIT_ON_FLOOR):
			return
	for piece_name in PROPS_CLUTTER:
		if not _add(props, piece_name, Collision.NONE, Align.SIT_ON_FLOOR):
			return
	for piece_name in PROPS_WALL:
		if not _add(props, piece_name, Collision.NONE, Align.AS_IS):
			return
	_save(props, PROPS_PATH)


## Adds `piece_name` as the library's next item. False (and an error) if
## it couldn't, since skipping one would shift every later ID.
static func _add(library: MeshLibrary, piece_name: String, collision: Collision, align: Align) -> bool:
	var packed : PackedScene = load(SOURCE_DIR + piece_name + ".glb")
	if packed == null:
		push_error("Missing %s; IDs would shift, aborting" % piece_name)
		return false
	var instance := packed.instantiate()
	var mesh_instance := _find_mesh_instance(instance)
	if mesh_instance == null:
		push_error("No MeshInstance3D found in %s; IDs would shift, aborting" % piece_name)
		instance.free()
		return false

	var mesh := mesh_instance.mesh
	var xform := _transform_to_root(mesh_instance, instance)
	var bounds : AABB = xform * mesh.get_aabb()
	match align:
		Align.FLOOR_TOP:
			# Tiles are 1m slabs with their top at y=1; sink them so it's at 0.
			xform.origin.y -= 1.0
		Align.SIT_ON_FLOOR:
			xform.origin.y -= bounds.position.y
	bounds = xform * mesh.get_aabb()

	var id := library.get_last_unused_item_id()
	library.create_item(id)
	library.set_item_name(id, piece_name)
	library.set_item_mesh(id, mesh)
	library.set_item_mesh_transform(id, xform)
	match collision:
		Collision.TRIMESH:
			var shape := mesh.create_trimesh_shape()
			if shape != null:
				library.set_item_shapes(id, [shape, xform])
		Collision.WALL:
			library.set_item_shapes(id, _wall_shapes(piece_name, bounds))
		Collision.BOX:
			var box := BoxShape3D.new()
			box.size = bounds.size
			library.set_item_shapes(id, [box, Transform3D(Basis(), bounds.get_center())])
	instance.free()
	return true


## A post in the middle plus a box out to the cell edge for each arm.
## Pillars (no arms) just use their bounds.
static func _wall_shapes(piece_name: String, bounds: AABB) -> Array:
	var shapes: Array = []
	var arms: Array = WALL_ARMS[piece_name]
	if arms.is_empty():
		var box := BoxShape3D.new()
		box.size = bounds.size
		return [box, Transform3D(Basis(), bounds.get_center())]
	# A wall end stops flush at the cell center; everything else has a post there.
	var start: float = 0.0 if arms.size() == 1 else WALL_HALF
	if start > 0.0:
		var post := BoxShape3D.new()
		post.size = Vector3(WALL_HALF * 2.0, WALL_HEIGHT, WALL_HALF * 2.0)
		shapes.append_array([post, Transform3D(Basis(), Vector3(0, WALL_HEIGHT / 2.0, 0))])
	for arm: Vector3 in arms:
		var length: float = 2.0 - start
		var arm_box := BoxShape3D.new()
		arm_box.size = Vector3(
				length if arm.x != 0.0 else WALL_HALF * 2.0, WALL_HEIGHT,
				length if arm.z != 0.0 else WALL_HALF * 2.0)
		var center: Vector3 = arm * (start + length / 2.0) + Vector3(0, WALL_HEIGHT / 2.0, 0)
		shapes.append_array([arm_box, Transform3D(Basis(), center)])
	return shapes


static func _save(library: MeshLibrary, path: String) -> void:
	# Saving a fresh resource drops the UID that scenes reference it by.
	var uid := ResourceLoader.get_resource_uid(path) if ResourceLoader.exists(path) else ResourceUID.INVALID_ID
	var err := ResourceSaver.save(library, path)
	if err != OK:
		push_error("Failed to save %s: %s" % [path, err])
		return
	if uid == ResourceUID.INVALID_ID:
		uid = ResourceUID.create_id()
	ResourceSaver.set_uid(path, uid)
	print("Saved %d pieces to %s" % [library.get_item_list().size(), path])


static func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found != null:
			return found
	return null

## FBX-sourced models carry an axis-fix rotation on the mesh node (and possibly
## its parents), so bake the whole chain up to the scene root.
static func _transform_to_root(node: Node3D, root: Node) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current : Node = node
	while current != root and current is Node3D:
		xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform
