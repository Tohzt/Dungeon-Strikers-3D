class_name AutoBakeNavigation3D extends NavigationRegion3D
## Bakes this region's navigation mesh when the level loads, from whatever
## is in its source group (by default the level's walls, floor and props),
## so editing the level never leaves bots walking into new walls.

## Most physics frames to wait for the level's collision to settle.
const MAX_SETTLE_FRAMES := 10


func _ready() -> void:
	if not navigation_mesh:
		return
	# A GridMap filled at runtime (RaceLevel3D's walls) only gets its
	# collision a couple of physics frames later, and baking before that
	# leaves every wall out, so bots walk straight into them. Wait until the
	# source geometry stops changing.
	var count: int = _source_vertex_count()
	for i in MAX_SETTLE_FRAMES:
		await get_tree().physics_frame
		var next: int = _source_vertex_count()
		if next == count and i >= 1:
			break
		count = next
	bake_navigation_mesh(false)


func _source_vertex_count() -> int:
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navigation_mesh, source, self)
	return source.get_vertices().size()
