class_name AutoBakeNavigation3D extends NavigationRegion3D
## Bakes this region's navigation mesh when the level loads, from whatever
## is in its source group (by default the level's walls, floor and props),
## so editing the level never leaves bots walking into new walls.


func _ready() -> void:
	if navigation_mesh:
		bake_navigation_mesh(false)
