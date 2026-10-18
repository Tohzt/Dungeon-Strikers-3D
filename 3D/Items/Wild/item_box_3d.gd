class_name ItemBox3D extends Area3D
## A floating "?" box, Mario Kart style: run through it to grab a random
## WildItem, and it comes back a few seconds later. Players further behind
## get the wilder items (Game3D.item_luck).
##
## The server (or offline game) decides who grabbed it and what they got,
## then tells every machine (_grabbed). Boxes are found by name online, so
## every machine must name them the same.

## Seconds before a grabbed box comes back.
@export var respawn_time: float = 8.0

const SIZE := 0.9
const HOVER_HEIGHT := 1.3
const SPIN_SPEED := 1.6
const HUE_SPEED := 0.25

var is_available: bool = true
var _visual: Node3D
var _material: StandardMaterial3D
var _light: OmniLight3D
var _time: float = 0.0
## Names giant weapons it hands out, the same on every machine.
var _weapons_made: int = 0
## Each giant weapon scene's grip, worked out once.
static var _grips: Dictionary[PackedScene, Weapon3D.Grip] = {}


func _ready() -> void:
	add_to_group("ItemBox")
	collision_layer = 0
	collision_mask = 2  # Players
	monitorable = false
	var reach := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.1
	reach.shape = sphere
	reach.position.y = HOVER_HEIGHT
	add_child(reach)
	_build_visual()
	_time = randf() * TAU  # So a row of them doesn't bob in step


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.position.y = HOVER_HEIGHT
	add_child(_visual)
	var cube := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * SIZE
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.emission_enabled = true
	_material.emission_energy_multiplier = 1.2
	_material.roughness = 0.2
	mesh.material = _material
	cube.mesh = mesh
	cube.rotation = Vector3(PI / 4.0, 0.0, PI / 4.0)  # Stood on a corner
	_visual.add_child(cube)
	var mark := Label3D.new()
	mark.text = "?"
	mark.font_size = 160
	mark.outline_size = 24
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = false
	mark.pixel_size = 0.005
	_visual.add_child(mark)
	_light = OmniLight3D.new()
	_light.light_energy = 0.8
	_light.omni_range = 4.0
	_visual.add_child(_light)


func _process(delta: float) -> void:
	_time += delta
	_visual.rotation.y += SPIN_SPEED * delta
	_visual.position.y = HOVER_HEIGHT + sin(_time * 2.2) * 0.15
	var hue: Color = Color.from_hsv(fmod(_time * HUE_SPEED, 1.0), 0.65, 1.0, 0.85)
	_material.albedo_color = hue
	_material.emission = hue
	_light.light_color = hue


# ===== GRABBING =====

func _physics_process(_delta: float) -> void:
	if not is_available or not Net.decides() or not Global.Game3D:
		return
	for body: Node3D in get_overlapping_bodies():
		var player: PlayerClass3D = body as PlayerClass3D
		if player and not player.is_dead():
			_grab(player)
			return


## Server/offline: `player` ran into it. Roll their item and tell everyone.
func _grab(player: PlayerClass3D) -> void:
	is_available = false
	var luck: float = Global.Game3D.item_luck(player)
	var fitting: Array[int] = []  # Giant weapons that'd fit a free hand
	for i in WildItem.GIANT_WEAPONS.size():
		if player.free_hand_for(_grip_of(WildItem.GIANT_WEAPONS[i])) != null:
			fitting.append(i)
	var item: int = WildItem.roll(luck, func(i: int) -> bool:
		return WildItem.kind(i) != WildItem.Kind.WEAPON or not fitting.is_empty())
	var weapon_pick: int = -1
	var is_left: bool = false
	if WildItem.kind(item) == WildItem.Kind.WEAPON:
		weapon_pick = fitting.pick_random()
		is_left = player.free_hand_for(_grip_of(WildItem.GIANT_WEAPONS[weapon_pick]))
	Net.everywhere(_grabbed, String(player.name), item, weapon_pick, is_left)


## Every machine: the box pops, and `player_name` gets `item`.
@rpc("authority", "call_local", "reliable")
func _grabbed(player_name: String, item: int, weapon_pick: int, is_left: bool) -> void:
	is_available = false
	_pop()
	var player: PlayerClass3D = Global.Game3D.player_named(player_name) if Global.Game3D else null
	if player:
		_apply(player, item, weapon_pick, is_left)
		Global.Game3D.scoreboard.announce("%s got %s" % [_label(player), WildItem.title(item)], WildItem.color(item))
	get_tree().create_timer(respawn_time).timeout.connect(_restock)


func _apply(player: PlayerClass3D, item: int, weapon_pick: int, is_left: bool) -> void:
	var owned: bool = not Net.in_session() or player.is_multiplayer_authority()
	match WildItem.kind(item):
		WildItem.Kind.BUFF:
			var perk: Perk = WildItem.perk_of(item)
			if perk.mods.has(&"size"):  # Giant and Pipsqueak replace each other
				for other: Perk in player.timed_perks:
					if other != perk and other.mods.has(&"size"):
						player.timed_perks[other] = 0.0  # Wears off next frame
			player.add_timed_perk(perk, WildItem.seconds(item))
		WildItem.Kind.WEAPON:
			_hand_giant_weapon(player, weapon_pick, is_left)
		WildItem.Kind.INSTANT:
			match item:
				WildItem.SNACK:
					_flourish(&"healing", player, 1.2)
					if owned:
						player.Entity.hp = player.Entity.hp_max
				WildItem.THUNDERCLAP:
					_thunderclap(player, owned)
				WildItem.WARP:
					_warp(player, owned)
				WildItem.LULLABY:
					_lullaby(player, owned)


func _hand_giant_weapon(player: PlayerClass3D, pick: int, is_left: bool) -> void:
	if pick < 0 or pick >= WildItem.GIANT_WEAPONS.size():
		return
	_weapons_made += 1
	var weapon_name: String = "%s_Wild%d" % [name, _weapons_made]
	var weapon: Weapon3D = WildItem.GIANT_WEAPONS[pick].instantiate()
	weapon.name = weapon_name
	Global.Game3D.add_weapon(weapon)
	weapon.name = weapon_name  # Its _ready renames it after its Properties
	weapon.set_rarity(WeaponRarity.Tier.LEGENDARY)
	weapon.make_giant(WildItem.GIANT_WEAPON_SIZE, WildItem.GIANT_WEAPON_POWER)
	weapon.global_position = _visual.global_position
	weapon.hand_to(player, is_left)


## Show `id` (a HELD Vfx) on `player` for `seconds`.
func _flourish(id: StringName, player: PlayerClass3D, seconds: float) -> void:
	var fx: Node3D = Vfx.attach(id, player)
	if fx:
		get_tree().create_timer(seconds).timeout.connect(Vfx.release.bind(fx))


## Seconds a warp's portals take to open, and stay open.
const PORTAL_OPEN := 0.35
const PORTAL_HOLD := 0.7
const PORTAL_SIZE := 1.7


## `player` steps into a portal and out of another by the ball (see
## _warp_spot). Every machine shows both; the owner moves them.
func _warp(player: PlayerClass3D, owned: bool) -> void:
	var to: Vector3 = _warp_spot(player)
	_portal(player.global_position)
	_portal(to)
	Sfx.play(&"spell_impact", player.global_position)
	Sfx.play(&"spell_impact", to)
	if owned:
		player.global_position = to
		player.velocity = Vector3.ZERO


## Just behind the nearest ball, on `player`'s side of it. With no ball
## about, up to WildItem.WARP_DISTANCE toward where the mode wants them
## (a race's next stretch, see Game3D.bot_goal), or the middle of the field.
func _warp_spot(player: PlayerClass3D) -> Vector3:
	var from: Vector3 = player.global_position
	var ball: Ball3D = null
	for b: Ball3D in Global.Game3D.balls:
		if is_instance_valid(b) and b.is_inside_tree() and b.is_visible_in_tree() \
				and (not ball or from.distance_to(b.global_position) < from.distance_to(ball.global_position)):
			ball = b
	if not ball:
		var goal: Node3D = Global.Game3D.bot_goal(player)
		var target: Vector3 = goal.global_position if goal else Global.Game3D.ball_reset_point
		var toward: Vector3 = target - from
		toward.y = 0.0
		if toward.length() < 0.1:
			return from
		return _clear_to(from, from + toward.limit_length(WildItem.WARP_DISTANCE))
	var at := Vector3(ball.global_position.x, from.y, ball.global_position.z)
	var back: Vector3 = from - at
	back.y = 0.0
	back = back.normalized() if back.length() > 0.1 else Vector3.BACK
	return _clear_to(at, at + back * WildItem.WARP_BALL_GAP)


## `to`, or short of the first wall between `from` and it.
func _clear_to(from: Vector3, to: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(from, to, Combat.WORLD_MASK)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return to
	return hit.position - (to - from).normalized() * 0.6


## A portal standing at `at`, facing the camera, open a moment.
func _portal(at: Vector3) -> void:
	var portal: Node3D = Vfx.attach(&"portal", Global.Game3D, Vector3.ZERO, PORTAL_OPEN, 1.0,
		WildItem.color(WildItem.WARP))
	if not portal:
		return
	portal.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * PORTAL_SIZE), at)
	get_tree().create_timer(PORTAL_HOLD).timeout.connect(Vfx.release.bind(portal))


## A wave of sleep from `player`: every foe within WildItem.LULLABY_RADIUS
## nods off (decided on the machine that owns `player`, passed on to theirs).
func _lullaby(player: PlayerClass3D, owned: bool) -> void:
	var center: Vector3 = player.global_position
	Vfx.play(&"impact", center + Vector3.DOWN * 0.9, Vector3.FORWARD, false, 2.5, WildItem.color(WildItem.LULLABY))
	Sfx.play(&"altar_reward", center)
	if not owned:
		return
	for other: PlayerClass3D in Global.Game3D.players:
		if other == player or other.is_dead() or Combat.are_teammates(other, player):
			continue
		var away: Vector3 = other.global_position - center
		away.y = 0.0
		if away.length() <= WildItem.LULLABY_RADIUS:
			other.status.apply(PlayerStatus3D.Kind.ASLEEP, PlayerStatus3D.SLEEP_TIME, player)


## A shockwave from `player`: a ring everyone sees, and (on the machine
## that owns them, which decides their hits) a blast for everyone nearby.
func _thunderclap(player: PlayerClass3D, owned: bool) -> void:
	var center: Vector3 = player.global_position
	Sfx.play(&"boss_stomp", center)
	Vfx.play(&"impact", center + Vector3.DOWN * 0.9, Vector3.FORWARD, false, 2.5, WildItem.color(WildItem.THUNDERCLAP))
	CameraShake.add(CameraShake.HEAVY, center)
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.8
	mesh.outer_radius = 1.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = WildItem.color(WildItem.THUNDERCLAP)
	mesh.material = material
	ring.mesh = mesh
	ring.top_level = true
	add_child(ring)
	ring.global_position = center + Vector3.UP * 0.3
	var tween: Tween = ring.create_tween().set_parallel()
	tween.tween_property(ring, ^"scale", Vector3.ONE * WildItem.THUNDERCLAP_RADIUS, 0.35)
	tween.tween_property(material, ^"albedo_color:a", 0.0, 0.35)
	tween.chain().tween_callback(ring.queue_free)
	if not owned:
		return
	var targets: Array[Node] = get_tree().get_nodes_in_group("Boss")
	targets.append_array(Global.Game3D.players)
	for target: Node in targets:
		var body: Node3D = target as Node3D
		if body == player or not is_instance_valid(body) or (body is PlayerClass3D and body.is_dead()) \
				or (body is Boss3D and body.wait_for_players):  # Don't wake one through a wall
			continue
		var away: Vector3 = body.global_position - center
		away.y = 0.0
		if away.length() <= WildItem.THUNDERCLAP_RADIUS:
			Combat.strike(body, away, WildItem.THUNDERCLAP_DAMAGE, WildItem.THUNDERCLAP_KNOCKBACK,
				WildItem.THUNDERCLAP_POP, -1.0, player)


func _pop() -> void:
	Sfx.play(&"spell_impact", _visual.global_position)
	var tween: Tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(_visual, ^"scale", Vector3.ONE * 0.01, 0.2)
	tween.tween_callback(_visual.hide)


func _restock() -> void:
	is_available = true
	_visual.show()
	var tween: Tween = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_visual, ^"scale", Vector3.ONE, 0.6)


static func _grip_of(scene: PackedScene) -> Weapon3D.Grip:
	if not _grips.has(scene):
		var probe: Weapon3D = scene.instantiate()
		_grips[scene] = probe.grip
		probe.free()
	return _grips[scene]


func _label(player: PlayerClass3D) -> String:
	return player.slot.label() if player.slot else String(player.name)
