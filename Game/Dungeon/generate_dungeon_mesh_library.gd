@tool
extends EditorScript
## Rebuilds res://Game/Dungeon/dungeon_mesh_library.tres from every .glb in
## res://Assets/Dungeon/, so the GridMap palette stays in sync when new
## pieces are dropped into that folder.
##
## Run it from the Script Editor with this file open (File > Run, or Ctrl+Shift+X),
## or headlessly:
##   godot --headless --script res://Game/Dungeon/generate_dungeon_mesh_library.gd

const SOURCE_DIR := "res://Assets/Dungeon/"
const OUTPUT_PATH := "res://Game/Dungeon/dungeon_mesh_library.tres"

## Props that animate or need scripted behavior (doors, gates) are placed by
## hand as separate scenes instead of being baked into the static GridMap.
const EXCLUDE := ["door", "door_gate"]

func _run() -> void:
	var library := MeshLibrary.new()
	var dir := DirAccess.open(SOURCE_DIR)
	if dir == null:
		push_error("Could not open %s" % SOURCE_DIR)
		return

	var names : Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".gltf.glb"):
			names.append(file_name.trim_suffix(".gltf.glb"))
		file_name = dir.get_next()
	dir.list_dir_end()
	names.sort()

	var id := 0
	for piece_name in names:
		if EXCLUDE.has(piece_name):
			continue

		var packed : PackedScene = load(SOURCE_DIR + piece_name + ".gltf.glb")
		var instance := packed.instantiate()
		var mesh_instance := _find_mesh_instance(instance)
		if mesh_instance == null:
			push_warning("No MeshInstance3D found in %s, skipping" % piece_name)
			instance.free()
			continue

		var mesh := mesh_instance.mesh
		library.create_item(id)
		library.set_item_name(id, piece_name)
		library.set_item_mesh(id, mesh)
		library.set_item_mesh_transform(id, mesh_instance.transform)

		var shape := mesh.create_trimesh_shape()
		if shape != null:
			library.set_item_shapes(id, [shape, mesh_instance.transform])

		instance.free()
		id += 1

	var err := ResourceSaver.save(library, OUTPUT_PATH)
	if err != OK:
		push_error("Failed to save mesh library: %s" % err)
	else:
		print("Saved %d pieces to %s" % [id, OUTPUT_PATH])

func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found != null:
			return found
	return null
