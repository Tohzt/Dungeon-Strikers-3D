@tool
class_name GameTools3D extends Node
## Editor tools for the arena. Settings here take effect when the match
## starts; in the editor they also show a preview of what they'll add
## (preview nodes aren't saved into the scene).

## Stocks the middle of the arena with weapon stands, two of each weapon
## in `test_weapons` (one per side of the halfway line), for trying them out.
@export var testing_mode: bool = false:
	set(value):
		testing_mode = value
		if is_node_ready():
			_refresh_test_stands()

@export_group("Testing Mode")
@export var stand_scene: PackedScene = preload("res://3D/Weapons/weapon_stand.tscn")
## One stand on each side of the arena for every weapon listed here.
@export var test_weapons: Array[PackedScene] = [
	preload("res://3D/Weapons/Sword/sword_3d.tscn"),
	preload("res://3D/Weapons/Bow and Arrow/bow_3d.tscn"),
	preload("res://3D/Weapons/Shield/Shield_3D.tscn"),
]
## How far each row of stands sits from the middle, towards the side walls.
@export var row_offset: float = 11.5
## Gap between neighbouring stands in a row.
@export var stand_spacing: float = 6.0

var _test_stands: Array[WeaponStand3D] = []


func _ready() -> void:
	_refresh_test_stands()


## Clears out the testing stands, then puts them back if testing mode is on.
## Names are fixed so they match on every machine online.
func _refresh_test_stands() -> void:
	for stand: WeaponStand3D in _test_stands:
		if is_instance_valid(stand):
			stand.get_parent().remove_child(stand)
			stand.queue_free()
	_test_stands.clear()

	if not testing_mode or not stand_scene:
		return
	var weapons_root: Node = get_parent().get_node_or_null("Weapons")
	if not weapons_root:
		push_warning("Tools: no Weapons node to put the testing stands in.")
		return

	var count: int = test_weapons.size()
	for row: int in 2:
		var z: float = row_offset * (-1.0 if row == 0 else 1.0)
		for i: int in count:
			if not test_weapons[i]:
				continue
			var stand: WeaponStand3D = stand_scene.instantiate()
			stand.name = "TestStand_%d_%d" % [row, i]
			stand.weapon_scene = test_weapons[i]
			stand.position = Vector3((i - (count - 1) / 2.0) * stand_spacing, 0.0, z)
			weapons_root.add_child(stand)
			_test_stands.append(stand)
