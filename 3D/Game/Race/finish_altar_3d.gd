class_name FinishAltar3D extends Area3D
## The race's goal: a glowing relic on a plinth. The first player standing
## (not knocked out) to touch it wins the race for their team. Whatever
## guards it (a boss, a locked door) is up to the level.

const ARTIFACT := preload("res://Assets/BetterDungeon/glb/artifact.glb")
## How close counts as touching it, from its center.
const REACH := 1.8
const PLINTH_RADIUS := 0.8
const PLINTH_HEIGHT := 1.0
const SPIN_SPEED := 0.8
const GOLD := Color(1.0, 0.8, 0.35)

var _relic: Node3D
var _time: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # Players
	monitorable = false
	var reach := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = REACH
	reach.shape = sphere
	reach.position.y = 1.0
	add_child(reach)
	_build_visuals()


func _build_visuals() -> void:
	var plinth := StaticBody3D.new()
	plinth.name = "Plinth"
	plinth.collision_mask = 0
	plinth.add_to_group("dungeon_nav")
	add_child(plinth)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = PLINTH_RADIUS
	cylinder.height = PLINTH_HEIGHT
	shape.shape = cylinder
	shape.position.y = PLINTH_HEIGHT / 2.0
	plinth.add_child(shape)
	var stone := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = PLINTH_RADIUS * 0.85
	mesh.bottom_radius = PLINTH_RADIUS
	mesh.height = PLINTH_HEIGHT
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.33, 0.36)
	material.roughness = 0.9
	mesh.material = material
	stone.mesh = mesh
	stone.position.y = PLINTH_HEIGHT / 2.0
	plinth.add_child(stone)

	_relic = ARTIFACT.instantiate()
	_relic.scale = Vector3.ONE * 1.5
	_relic.position.y = PLINTH_HEIGHT + 0.3
	add_child(_relic)

	var light := OmniLight3D.new()
	light.light_color = GOLD
	light.light_energy = 3.0
	light.omni_range = 10.0
	light.position.y = 2.5
	add_child(light)


func _process(delta: float) -> void:
	_time += delta
	_relic.rotation.y += SPIN_SPEED * delta
	_relic.position.y = PLINTH_HEIGHT + 0.3 + sin(_time * 2.0) * 0.1


func _physics_process(_delta: float) -> void:
	if not Net.decides() or not Global.Game3D or Global.Game3D.match_over:
		return
	for body: Node3D in get_overlapping_bodies():
		var player: PlayerClass3D = body as PlayerClass3D
		if player and not player.is_dead() and Global.Game3D.has_method(&"reach_finish"):
			Global.Game3D.reach_finish(player)
			return
