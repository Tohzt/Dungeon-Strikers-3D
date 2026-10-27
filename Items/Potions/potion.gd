class_name Potion extends RefCounted
## The potions: small ones that pop out of chests (and item boxes) and are
## drunk the moment someone runs through them (see PotionPickup3D), and
## big flasks, held and thrown, that shatter in a splash (see Throwable3D).
##
## Potions are listed by index, which is what gets sent online, so only ever
## append to SMALL and LARGE.

## The flask models (Assets/Potions, from the Potions pack's red flasks):
## the glass is tinted each potion's color (see model).
const SHAPES: Dictionary[StringName, PackedScene] = {
	&"round": preload("res://Assets/Potions/potion_3.glb"),
	&"tall": preload("res://Assets/Potions/potion_1.glb"),
	&"flask": preload("res://Assets/Potions/potion_7.glb"),
	&"square": preload("res://Assets/Potions/potion_4.glb"),
	&"bulb": preload("res://Assets/Potions/potion_6.glb"),
	&"jug": preload("res://Assets/Potions/potion_9_handles.glb"),
}
## A small potion stands this tall (m); a big flask is about a bomb's size.
const SMALL_HEIGHT := 0.55
const LARGE_HEIGHT := 0.85

## Drunk on pickup. Each: title, blurb, color, flask shape, chance (relative),
## and what it does: `heal` (share of max HP, at once) and/or a timed perk
## (`mods` for `seconds`).
const SMALL: Array[Dictionary] = [
	{"title": "Health Potion", "blurb": "Heals a third of your health",
		"color": Color(1.0, 0.2, 0.3), "shape": &"round", "chance": 4.0,
		"heal": 0.35},
	{"title": "Swiftness", "blurb": "Run faster for a while",
		"color": Color(1.0, 0.85, 0.15), "shape": &"tall", "chance": 2.0,
		"seconds": 8.0, "mods": {&"move_speed": 0.45}},
	{"title": "Stoneskin", "blurb": "Take less damage and shoving",
		"color": Color(0.6, 0.65, 0.75), "shape": &"square", "chance": 2.0,
		"seconds": 10.0, "mods": {&"damage_taken": -0.4, &"knockback_taken": -0.6}},
	{"title": "Might", "blurb": "Hit harder for a while",
		"color": Color(1.0, 0.45, 0.1), "shape": &"flask", "chance": 2.0,
		"seconds": 10.0, "mods": {&"damage": 0.4, &"knockback": 0.4}},
	{"title": "Regen Tonic", "blurb": "Heal up over time",
		"color": Color(0.35, 1.0, 0.45), "shape": &"bulb", "chance": 2.0,
		"seconds": 6.0, "mods": {&"regen": 1.0}},
]

## Thrown, shattering in a SPLASH_RADIUS splash. Each: title, color, chance,
## who it hits (`allies`: the thrower's team, the thrower too; otherwise
## their enemies), and what it does to them: a `status` for `seconds`,
## `heal` (share of max HP), and/or a timed perk (`mods` for
## `perk_seconds`). With a `patch`, it leaves a puddle (GroundPatch3D).
const LARGE: Array[Dictionary] = [
	{"title": "Fire Flask", "color": Color(1.0, 0.4, 0.1), "chance": 2.0,
		"status": PlayerStatus3D.Kind.BURNING, "seconds": PlayerStatus3D.BURN_TIME,
		"patch": GroundPatch3D.Kind.FIRE},
	{"title": "Frost Flask", "color": Color(0.5, 0.85, 1.0), "chance": 2.0,
		"status": PlayerStatus3D.Kind.FROZEN, "seconds": PlayerStatus3D.FREEZE_TIME,
		"patch": GroundPatch3D.Kind.ICE},
	{"title": "Poison Flask", "color": Color(0.55, 0.95, 0.2), "chance": 2.0,
		"status": PlayerStatus3D.Kind.POISONED, "seconds": 6.0,
		"patch": GroundPatch3D.Kind.POISON},
	{"title": "Sleep Flask", "color": Color(0.75, 0.6, 1.0), "chance": 1.5,
		"status": PlayerStatus3D.Kind.ASLEEP, "seconds": PlayerStatus3D.SLEEP_TIME},
	{"title": "Shrink Flask", "color": Color(1.0, 0.5, 0.9), "chance": 1.5,
		"perk_seconds": 8.0, "mods": {&"size": -0.45, &"damage_taken": 0.25}},
	{"title": "Healing Flask", "color": Color(1.0, 0.3, 0.45), "chance": 1.5,
		"allies": true, "heal": 0.4},
]
const SPLASH_RADIUS := 4.0
## How long a flask's puddle lasts (s), and how wide it is (m).
const PUDDLE_TIME := 7.0
const PUDDLE_RADIUS := 2.8

## Each potion's timed perk, made once (the same object every time, so
## another of the same restarts it instead of stacking a copy).
static var _small_perks: Dictionary[int, Perk] = {}
static var _large_perks: Dictionary[int, Perk] = {}


static func roll_small() -> int:
	return _roll(SMALL)


static func roll_large() -> int:
	return _roll(LARGE)


static func _roll(list: Array[Dictionary]) -> int:
	var total: float = 0.0
	for potion: Dictionary in list:
		total += potion.chance
	var pick: float = randf() * total
	for i in list.size():
		pick -= list[i].chance
		if pick < 0.0:
			return i
	return 0


static func small(index: int) -> Dictionary:
	return SMALL[clampi(index, 0, SMALL.size() - 1)]


static func large(index: int) -> Dictionary:
	return LARGE[clampi(index, 0, LARGE.size() - 1)]


## A flask in `color`, `height` tall, standing on its base at the origin.
static func model(shape: StringName, color: Color, height: float) -> Node3D:
	var flask: Node3D = SHAPES.get(shape, SHAPES[&"round"]).instantiate()
	var glass := StandardMaterial3D.new()
	glass.albedo_color = color
	glass.roughness = 0.15
	glass.metallic_specular = 0.8
	glass.emission_enabled = true
	glass.emission = color
	glass.emission_energy_multiplier = 0.35
	var tall: float = 0.0
	for mesh: MeshInstance3D in flask.find_children("*", "MeshInstance3D", true, false):
		tall = maxf(tall, mesh.mesh.get_aabb().end.y)
		for i in mesh.mesh.get_surface_count():
			var material: Material = mesh.mesh.surface_get_material(i)
			if material and material.resource_name.begins_with("Glass"):
				mesh.set_surface_override_material(i, glass)
	flask.scale = Vector3.ONE * (height / maxf(tall, 0.01))
	return flask


## Every machine: `player` drinks small potion `index`. Timed perks go on
## everywhere; healing happens on their owner (HP is synced from there).
static func drink(player: PlayerClass3D, index: int) -> void:
	var potion: Dictionary = small(index)
	if potion.has("mods"):
		player.add_timed_perk(_perk(_small_perks, index, potion), potion.seconds)
	if potion.has("heal") and player._is_local():
		player.heal(player.Entity.hp_max * potion.heal)
	var fx: Node3D = Vfx.attach(&"healing", player, Vector3.ZERO, 0.0, 1.0, potion.color)
	if fx:
		player.get_tree().create_timer(1.0).timeout.connect(Vfx.release.bind(fx))
	Sfx.play(&"equip_small", player.global_position, 1.4)


## Every machine: flask `index` splashed `player`.
static func splash(player: PlayerClass3D, index: int, thrower: PlayerClass3D) -> void:
	var potion: Dictionary = large(index)
	if potion.has("mods"):
		player.add_timed_perk(_perk(_large_perks, index, potion), potion.perk_seconds)
	if not player._is_local() or player.is_dead():
		return
	if potion.has("status"):
		player.status.apply(potion.status, potion.seconds, thrower)
	if potion.has("heal"):
		player.heal(player.Entity.hp_max * potion.heal)


static func _perk(cache: Dictionary[int, Perk], index: int, potion: Dictionary) -> Perk:
	if not cache.has(index):
		var perk := Perk.new()
		perk.title = potion.title
		perk.description = potion.get("blurb", "")
		perk.mods.assign(potion.mods)
		cache[index] = perk
	return cache[index]
