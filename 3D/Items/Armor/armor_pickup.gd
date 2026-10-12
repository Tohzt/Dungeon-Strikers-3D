@tool
class_name ArmorPickup3D extends Pickup3D
## A floating helmet. Running through it puts on armor: less damage taken
## and the character's helmet/hat and cape, until they next die (see
## PlayerClass3D.armored). Anyone already armored passes through.

## The Knight's helmet, borrowed for the pickup's look. Its meshes sit at
## head height in the model, so they're lowered by HELMET_HEIGHT.
const HELMET_SOURCE: PackedScene = preload("res://Assets/Characters/Adventurers/Knight.glb")
const HELMET_MESHES: Array[String] = ["Knight_Helmet", "Knight_HelmetVisor"]
const HELMET_HEIGHT := 1.8

@onready var helmet: Node3D = $Helmet


func _ready() -> void:
	_build_helmet()
	super._ready()


## Copy the helmet meshes out of the Knight. Unskinned, they keep the
## model's rest pose.
func _build_helmet() -> void:
	var source: Node = HELMET_SOURCE.instantiate()
	for mesh_name: String in HELMET_MESHES:
		var from := source.find_child(mesh_name, true, false) as MeshInstance3D
		if not from:
			continue
		var mesh := MeshInstance3D.new()
		mesh.name = mesh_name
		mesh.mesh = from.mesh
		mesh.position.y = -HELMET_HEIGHT
		helmet.add_child(mesh)
	source.free()


func _model() -> Node3D:
	return helmet


func _can_take(player: PlayerClass3D) -> bool:
	return player.can_take_armor()


func _give(player: PlayerClass3D) -> void:
	player.put_on_armor()
