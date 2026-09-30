@tool
class_name Altar3D extends WeaponStand3D
## A team's own weapon stand. Only its team can take from it. It holds up to
## `capacity` weapons: each new one (a restock after a take, or a tier-up)
## goes on top and pushes the oldest off once it's full. Stronger tiers make
## a new weapon sit "charging" for a while before it can be taken.
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
## The tier goes up once this many seconds pass with nobody taking a weapon
## (counting from the match start, then from each take). 0 = only upgrade()
## raises the tier (e.g. on a goal).
@export var seconds_per_tier: float = 0.0
## How many weapons the altar holds at once; a new one past this pushes off
## the oldest. Perks may raise it (e.g. to keep the last two).
@export_range(1, 4) var capacity: int = 1:
	set(value):
		capacity = value
		_trim_held()

@onready var base_mesh: MeshInstance3D = $MeshInstance3D
@onready var arming_ring: MeshInstance3D = $ArmingRing

## One weapon on display.
class HeldWeapon:
	var scene: PackedScene
	## Seconds until it can be taken, out of arming_total.
	var arming_left: float = 0.0
	var arming_total: float = 0.0
	## Spins the display copy; also placed side by side with the others.
	var pivot: Node3D

	func is_armed() -> bool:
		return arming_left <= 0.0


## Index into `tiers`. A tier-up stocks a weapon from the new tier at once.
var tier: int = 0
## What's on display, oldest first.
var _held: Array[HeldWeapon] = []
## A restock waiting out the respawn delay after a take: [tier, pick].
var _pending: Array[int] = []
## Server/offline: time since the last take (or tier-up), toward the next tier-up.
var _tier_timer: float = 0.0
## Gap between held weapons, side by side along the altar.
const HELD_SPACING := 1.2
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
	var first: AltarTier = _current_tier()
	var has_first: bool = first != null and not first.weapons.is_empty()
	if Engine.is_editor_hint():
		# Preview the first tier's weapon through the plain stand display
		if not weapon_scene and has_first:
			weapon_scene = first.weapons[0]
	else:
		# The altar shows its own stock (_held), even if the editor's
		# preview weapon got saved into the scene.
		weapon_scene = null
	super()
	_make_tier_pips()
	_apply_team_color()
	if not Engine.is_editor_hint():
		_make_perk_sign()
		if has_first:
			_add_held(0, 0)


func _process(delta: float) -> void:
	super(delta)
	if Engine.is_editor_hint():
		return
	if cooldown_left <= 0.0 and not _pending.is_empty():
		_add_held(_pending[0], _pending[1])
		_pending.clear()
	for item: HeldWeapon in _held:
		item.arming_left = max(item.arming_left - delta, 0.0)
		item.pivot.rotate_y(display_spin_speed * delta)
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


# ===== STOCK =====

## Something armed to hand out (older weapons stay takeable during a restock's
## respawn delay).
func _is_stocked() -> bool:
	return _newest_armed() != null


func _newest_armed() -> HeldWeapon:
	for i in range(_held.size() - 1, -1, -1):
		if _held[i].is_armed():
			return _held[i]
	return null


## Hands out the newest armed weapon. Falls back to the newest one, so a
## machine whose charge timer runs a touch behind still gives the same weapon.
func _take_stock() -> PackedScene:
	var item: HeldWeapon = _newest_armed()
	if not item:
		if _held.is_empty():
			return null
		item = _held.back()
	cooldown_left = _cooldown_after_take()
	_remove_held(item)
	return item.scene


## Put tiers[tier_index].weapons[pick] on top, charging for its arming time.
func _add_held(tier_index: int, pick: int) -> void:
	var stocked_tier: AltarTier = tiers[tier_index]
	var item := HeldWeapon.new()
	item.scene = stocked_tier.weapons[pick]
	item.arming_total = stocked_tier.arming_time
	item.arming_left = item.arming_total
	item.pivot = Node3D.new()
	item.pivot.add_child(_make_display_copy(item.scene))
	add_child(item.pivot)
	_held.append(item)
	_trim_held()


func _remove_held(item: HeldWeapon) -> void:
	_held.erase(item)
	item.pivot.queue_free()
	_layout_held()


## Push the oldest off past capacity, then line the rest up.
func _trim_held() -> void:
	while _held.size() > capacity:
		_remove_held(_held[0])
	_layout_held()


func _layout_held() -> void:
	if not is_node_ready():
		return
	for i in _held.size():
		var offset: float = (i - (_held.size() - 1) * 0.5) * HELD_SPACING
		_held[i].pivot.position = display_anchor.position + Vector3(offset, 0, 0)


func _may_take(player: PlayerClass3D) -> bool:
	return player.slot != null and player.slot.team == owner_team


func _cooldown_after_take() -> float:
	var current: AltarTier = _current_tier()
	return current.respawn_delay if current else cooldown


## A take restarts the wait for the next tier-up, and the server (or the
## offline game) picks what appears next.
func _after_given() -> void:
	_tier_timer = 0.0
	_restock()


## Server/offline: pick a weapon from the current tier and stock it everywhere.
func _restock() -> void:
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
## Right after a take it waits out the respawn delay (a newer pick replaces
## a waiting one); otherwise it goes on top at once. Either way it then
## charges for its arming time.
@rpc("authority", "call_local", "reliable")
func _stock(tier_index: int, pick: int) -> void:
	if cooldown_left > 0.0:
		_pending = [tier_index, pick]
	else:
		_add_held(tier_index, pick)


## Raise the altar's tier (e.g. its team scored) and stock a weapon from the
## new tier, replacing the oldest. Server/offline only.
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
	_restock()


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


## Ring grows while the newest weapon charges and glows fully once it's
## takeable. Each weapon is see-through until it's armed.
func _update_arming_visual() -> void:
	arming_ring.visible = not _held.is_empty()
	if _held.is_empty():
		return
	var newest: HeldWeapon = _held.back()
	var progress: float = 1.0 if newest.arming_total <= 0.0 else 1.0 - newest.arming_left / newest.arming_total
	arming_ring.scale = Vector3.ONE * lerpf(0.3, 1.0, progress)
	for item: HeldWeapon in _held:
		var see_through: float = 0.0 if item.is_armed() else 0.6
		for node: Node in item.pivot.find_children("*", "GeometryInstance3D", true, false):
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
