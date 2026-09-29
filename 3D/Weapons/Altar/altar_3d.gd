@tool
class_name Altar3D extends WeaponStand3D
## A team's own weapon stand. Only its team can take from it. It holds one
## weapon at a time and restocks only once that one is taken; stronger tiers
## make the new weapon sit "charging" for a while before it can be taken.
## Online the server picks every restock and every tier change.
## During the intermission between rounds it's also where each of its
## team's players picks a perk (see PerkDirector): interact opens the cards.

const PLAYERS_SCRIPT := preload("res://players.gd")

## Which team (PlayerSlot.team) may take from this altar.
@export var owner_team: int = 0:
	set(value):
		owner_team = value
		if is_node_ready():
			_apply_team_color()
## The altar's power curve, weakest first.
@export var tiers: Array[AltarTier] = []
## Seconds between automatic tier-ups over the match. 0 = only upgrade()
## raises the tier (e.g. on a goal).
@export var seconds_per_tier: float = 0.0

@onready var base_mesh: MeshInstance3D = $MeshInstance3D
@onready var arming_ring: MeshInstance3D = $ArmingRing

## Index into `tiers`. Changes what the next restock can be, not the weapon
## already on the altar.
var tier: int = 0
## Seconds until the weapon on display can be taken.
var arming_left: float = 0.0
## Arming time of the weapon on display, for the charging visual.
var _arming_total: float = 0.0
## Server/offline: time toward the next automatic tier-up.
var _tier_timer: float = 0.0
## Floats over the altar while one of its team has perk cards waiting.
var _perk_sign: Label3D = null
const PERK_SIGN_HEIGHT := 4.0
## Tier pips: a column at each end of the altar's top, one pip per tier,
## lit in the team's color up to the current tier.
var _tier_pips: Array[MeshInstance3D] = []
var _pip_lit: StandardMaterial3D
var _pip_unlit: StandardMaterial3D
const PIP_SIZE := Vector3(0.3, 0.08, 0.22)
const PIP_SPACING := 0.3
const PIP_END_X := 1.2  # Clear of the arming ring in the middle
const PIP_TOP_Y := 1.54
## A tier-up makes the pips pop this much bigger, easing back over PIP_POP_TIME.
const PIP_POP_SCALE := 1.8
const PIP_POP_TIME := 0.5
var _pip_pop: float = 0.0


func _ready() -> void:
	# In game, always start from the first tier, even if the editor's preview
	# weapon got saved into the scene.
	if not weapon_scene or not Engine.is_editor_hint():
		var first: AltarTier = _current_tier()
		if first and not first.weapons.is_empty():
			weapon_scene = first.weapons[0]
			_arming_total = first.arming_time
			arming_left = _arming_total
	super()
	_make_tier_pips()
	_apply_team_color()
	if not Engine.is_editor_hint():
		_make_perk_sign()


func _process(delta: float) -> void:
	super(delta)
	if Engine.is_editor_hint():
		return
	if cooldown_left <= 0.0 and arming_left > 0.0:
		arming_left = max(arming_left - delta, 0.0)
	_update_arming_visual()
	_update_perk_sign()
	_update_pip_pop(delta)
	_tick_tier_timer(delta)


# ===== PERKS =====

## Perk cards come first: if `player` has some waiting, interact opens them.
func can_give_to(player: PlayerClass3D) -> bool:
	return _has_perks_for(player) or super(player)


func request_take(player: PlayerClass3D) -> bool:
	if _has_perks_for(player):
		Global.Game3D.perks.open_for(player)
		return true
	return super(player)


func _has_perks_for(player: PlayerClass3D) -> bool:
	var perks: PerkDirector = Global.Game3D.perks if Global.Game3D else null
	return perks != null and perks.can_open(player) and _may_take(player) and reach.overlaps_body(player)


func _make_perk_sign() -> void:
	_perk_sign = Label3D.new()
	_perk_sign.text = "CHOOSE A PERK"
	_perk_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_perk_sign.no_depth_test = true
	# Big enough to read from the zoomed-out match camera
	_perk_sign.pixel_size = 0.01
	_perk_sign.font_size = 96
	_perk_sign.outline_size = 24
	_perk_sign.modulate = Color(0.95, 0.8, 0.4)
	_perk_sign.position = Vector3(0, PERK_SIGN_HEIGHT, 0)
	_perk_sign.visible = false
	add_child(_perk_sign)


func _update_perk_sign() -> void:
	var perks: PerkDirector = Global.Game3D.perks if Global.Game3D else null
	_perk_sign.visible = perks != null and perks.team_has_offer(owner_team)
	if _perk_sign.visible:
		var t: float = Time.get_ticks_msec() / 1000.0
		_perk_sign.position.y = PERK_SIGN_HEIGHT + sin(t * 3.0) * 0.15


func _is_stocked() -> bool:
	return super() and arming_left <= 0.0


func _may_take(player: PlayerClass3D) -> bool:
	return player.slot != null and player.slot.team == owner_team


func _cooldown_after_take() -> float:
	var current: AltarTier = _current_tier()
	return current.respawn_delay if current else cooldown


## The server (or the offline game) picks what appears next.
func _after_given() -> void:
	if Net.in_session() and not Net.is_server:
		return
	var current: AltarTier = _current_tier()
	if not current or current.weapons.is_empty():
		return
	var pick: int = randi() % current.weapons.size()
	if Net.in_session():
		_stock.rpc(tier, pick)
	else:
		_stock(tier, pick)


## Server -> everyone: the next weapon is tiers[tier_index].weapons[pick].
## It shows once the respawn delay is over, then charges for its arming time.
@rpc("authority", "call_local", "reliable")
func _stock(tier_index: int, pick: int) -> void:
	var stocked_tier: AltarTier = tiers[tier_index]
	_arming_total = stocked_tier.arming_time
	arming_left = _arming_total
	weapon_scene = stocked_tier.weapons[pick]


## Raise the altar's tier (e.g. its team scored). Server/offline only; the
## new tier applies from the next restock.
func upgrade(levels: int = 1) -> void:
	if Net.in_session() and not Net.is_server:
		return
	var new_tier: int = clampi(tier + levels, 0, tiers.size() - 1)
	if new_tier == tier:
		return
	if Net.in_session():
		_set_tier.rpc(new_tier)
	else:
		_set_tier(new_tier)


@rpc("authority", "call_local", "reliable")
func _set_tier(new_tier: int) -> void:
	tier = new_tier
	_update_tier_pips()
	_pip_pop = PIP_POP_TIME


func _tick_tier_timer(delta: float) -> void:
	if seconds_per_tier <= 0.0 or tier >= tiers.size() - 1:
		return
	if Net.in_session() and not (Net.is_server and Net.match_synced):
		return
	_tier_timer += delta
	if _tier_timer >= seconds_per_tier:
		_tier_timer = 0.0
		upgrade()


func _current_tier() -> AltarTier:
	if tiers.is_empty():
		return null
	return tiers[clampi(tier, 0, tiers.size() - 1)]


# ===== TIER PIPS =====

func _make_tier_pips() -> void:
	for pip: MeshInstance3D in _tier_pips:
		pip.queue_free()
	_tier_pips.clear()
	var mesh := BoxMesh.new()
	mesh.size = PIP_SIZE
	for end_x: float in [-PIP_END_X, PIP_END_X]:
		for i in tiers.size():
			var pip := MeshInstance3D.new()
			pip.mesh = mesh
			pip.position = Vector3(end_x, PIP_TOP_Y, (i - (tiers.size() - 1) * 0.5) * PIP_SPACING)
			add_child(pip)
			_tier_pips.append(pip)


func _update_tier_pips() -> void:
	if not _pip_lit:
		return
	for i in _tier_pips.size():
		var pip_tier: int = i % tiers.size()
		_tier_pips[i].material_override = _pip_lit if pip_tier <= tier else _pip_unlit


func _update_pip_pop(delta: float) -> void:
	if _pip_pop <= 0.0:
		return
	_pip_pop = max(_pip_pop - delta, 0.0)
	var pop: float = lerpf(1.0, PIP_POP_SCALE, _pip_pop / PIP_POP_TIME)
	for pip: MeshInstance3D in _tier_pips:
		pip.scale = Vector3.ONE * pop


## Ring grows while the weapon charges and glows fully once it's takeable.
## The weapon itself is see-through until then.
func _update_arming_visual() -> void:
	var showing: bool = _display != null and _display.visible
	arming_ring.visible = showing
	if not showing:
		return
	var progress: float = 1.0 if _arming_total <= 0.0 else 1.0 - arming_left / _arming_total
	arming_ring.scale = Vector3.ONE * lerpf(0.3, 1.0, progress)
	var see_through: float = 0.0 if arming_left <= 0.0 else 0.6
	for node: Node in _display.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).transparency = see_through


func _apply_team_color() -> void:
	# Read from the script, not the Players autoload, so it also works in the editor.
	var team_colors: Array[Color] = PLAYERS_SCRIPT.TEAM_COLORS
	var color: Color = team_colors[owner_team % team_colors.size()]
	var base_material := StandardMaterial3D.new()
	base_material.albedo_color = color.darkened(0.4)
	base_mesh.material_override = base_material
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = color
	ring_material.emission_enabled = true
	ring_material.emission = color
	ring_material.emission_energy_multiplier = 2.0
	arming_ring.material_override = ring_material
	_pip_lit = ring_material
	_pip_unlit = StandardMaterial3D.new()
	_pip_unlit.albedo_color = color.darkened(0.8)
	_update_tier_pips()
