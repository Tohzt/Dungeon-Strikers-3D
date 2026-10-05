@tool
class_name Altar3D extends WeaponStand3D
## A team's own weapon stand. Only its team can take from it, unless every
## one of its players is dead: then it's unguarded and anyone can. It holds up to
## `capacity` weapons: each new one (a restock after a take, or a tier-up)
## goes on top and pushes the oldest off once it's full. Stronger tiers make
## a new weapon sit "charging" for a while before it can be taken.
## Online the server picks every restock and every tier change.
## During the intermission between rounds it's also where each of its
## team's players picks a perk (see PerkDirector): interact opens the cards.
## A boss's skull brought here (see Skull3D) becomes a reward after
## a random 10-20s (see reward_time_min/max): a strong weapon, or a perk
## relic (pick one of two Relic perks, stronger than the usual cards). It floats above the altar and is taken
## like the weapons. Play goes on meanwhile, so the other team has a chance
## to wipe this one out and steal it; the round only ends once it's claimed.

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

@export_group("Skull Reward")
## Seconds a skull brought home takes to become its reward: a random time
## in this range, picked by the server.
@export var reward_time_min: float = 10.0
@export var reward_time_max: float = 20.0
## Chance the reward is a weapon; otherwise it's a perk relic.
@export_range(0.0, 1.0) var reward_weapon_chance: float = 0.5
## Weapons a skull can become, and their rarity odds (its arming_time and
## respawn_delay aren't used; the wait is reward_time_min/max).
@export var reward_weapons: AltarTier
## Relic cards (Perk.Category.RELIC, stronger than the rest) a perk relic
## offers; its taker picks one.
@export_range(1, 5) var relic_hand_size: int = 2
@export_group("")

@onready var base_mesh: MeshInstance3D = $MeshInstance3D
@onready var arming_ring: MeshInstance3D = $ArmingRing

## One weapon on display.
class HeldWeapon:
	var scene: PackedScene
	var rarity: int = WeaponRarity.Tier.COMMON
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
## A restock waiting out the respawn delay after a take: [tier, pick, rarity].
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

enum Reward { NONE, WEAPON, PERK }
## What a delivered skull turned (or is turning) into. Set on every machine.
var reward: Reward = Reward.NONE
var _reward_scene: PackedScene = null
var _reward_rarity: int = WeaponRarity.Tier.COMMON
## Seconds until the reward can be taken.
var _reward_left: float = 0.0
## Holds the reward's display copy, above the stock.
var _reward_pivot: Node3D = null
var _reward_sign: Label3D = null
const REWARD_HEIGHT := 1.2  # Above the weapon display
const REWARD_SIGN_HEIGHT := 4.9
const RELIC_COLOR := Color(1.0, 0.8, 0.3)
const UNGUARDED_COLOR := Color(1.0, 0.25, 0.2)


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
		_make_reward_sign()
		if has_first:
			_add_held(0, 0, WeaponRarity.Tier.COMMON)


func _process(delta: float) -> void:
	super(delta)
	if Engine.is_editor_hint():
		return
	if cooldown_left <= 0.0 and not _pending.is_empty():
		_add_held(_pending[0], _pending[1], _pending[2])
		_pending.clear()
	for item: HeldWeapon in _held:
		item.arming_left = max(item.arming_left - delta, 0.0)
		item.pivot.rotate_y(display_spin_speed * delta)
	_update_arming_visual()
	_update_perk_sign()
	_update_reward(delta)
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
	if has_reward_for(player) and reach.overlaps_body(player):
		_take_reward(player)
		return true
	return super(player)


## The skull's reward comes first, then the stock.
func has_weapon_for(player: PlayerClass3D) -> bool:
	return has_reward_for(player) or super(player)


func _has_perks_for(player: PlayerClass3D) -> bool:
	var perks: PerkDirector = Global.Game3D.perks if Global.Game3D else null
	# Bots take their cards on their own (BotInputHandler3D); opening them
	# here would leave a bot stuck looking at them.
	if player.slot and player.slot.is_bot:
		return false
	return perks != null and perks.can_open(player) and _is_ours(player) and reach.overlaps_body(player)


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


## The weapon _take_stock() would hand out: the newest armed one, or else
## the newest one, so a machine whose charge timer runs a touch behind still
## gives the same weapon.
func _next_given() -> HeldWeapon:
	var item: HeldWeapon = _newest_armed()
	if not item and not _held.is_empty():
		item = _held.back()
	return item


func _stock_grip() -> Weapon3D.Grip:
	var item: HeldWeapon = _next_given()
	var weapon: Weapon3D = item.pivot.get_child(0) as Weapon3D if item else null
	return weapon.grip if weapon else super()


## Hands out the next weapon (see _next_given).
func _take_stock() -> PackedScene:
	var item: HeldWeapon = _next_given()
	if not item:
		return null
	cooldown_left = _cooldown_after_take()
	_remove_held(item)
	_given_rarity = item.rarity
	return item.scene


## Put tiers[tier_index].weapons[pick] on top, charging for its arming time.
func _add_held(tier_index: int, pick: int, tier_rarity: int) -> void:
	var stocked_tier: AltarTier = tiers[tier_index]
	var item := HeldWeapon.new()
	item.scene = stocked_tier.weapons[pick]
	item.rarity = tier_rarity
	item.arming_total = stocked_tier.arming_time
	item.arming_left = item.arming_total
	item.pivot = Node3D.new()
	item.pivot.add_child(_make_display_copy(item.scene, item.rarity))
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


## Our own team always may; anyone else only while the altar is unguarded.
func _may_take(player: PlayerClass3D) -> bool:
	return _is_ours(player) or (player.slot != null and is_unguarded())


func _is_ours(player: PlayerClass3D) -> bool:
	return player.slot != null and player.slot.team == owner_team


## Every player on our team is dead right now (and there is one), so
## enemies may take from us.
func is_unguarded() -> bool:
	var game: Game3D_Class = Global.Game3D
	if not game:
		return false
	var guarded: bool = false
	var anyone: bool = false
	for player: PlayerClass3D in game.players:
		if is_instance_valid(player) and _is_ours(player):
			anyone = true
			guarded = guarded or not player.is_dead()
	return anyone and not guarded


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
	var pick_rarity: int = WeaponRarity.roll(current.rarity_weights)
	if Net.in_session():
		_stock.rpc(tier, pick, pick_rarity)
	else:
		_stock(tier, pick, pick_rarity)


## Server -> everyone: the next weapon is tiers[tier_index].weapons[pick],
## of rarity `pick_rarity`.
## Right after a take it waits out the respawn delay (a newer pick replaces
## a waiting one); otherwise it goes on top at once. Either way it then
## charges for its arming time.
@rpc("authority", "call_local", "reliable")
func _stock(tier_index: int, pick: int, pick_rarity: int) -> void:
	if cooldown_left > 0.0:
		_pending = [tier_index, pick, pick_rarity]
	else:
		_add_held(tier_index, pick, pick_rarity)


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


# ===== SKULL REWARD =====

## Server/offline: what a skull brought here becomes, as
## [Reward, weapon pick, rarity, seconds to charge], for start_reward on
## every machine.
func roll_reward() -> PackedInt32Array:
	var seconds: int = roundi(randf_range(reward_time_min, maxf(reward_time_min, reward_time_max)))
	if reward_weapons and not reward_weapons.weapons.is_empty() and randf() < reward_weapon_chance:
		return PackedInt32Array([Reward.WEAPON, randi() % reward_weapons.weapons.size(),
			WeaponRarity.roll(reward_weapons.rarity_weights), seconds])
	return PackedInt32Array([Reward.PERK, 0, 0, seconds])


## Every machine: a skull came home; start turning it into `roll` (see
## roll_reward). An unclaimed earlier reward is replaced.
func start_reward(roll: PackedInt32Array) -> void:
	_clear_reward()
	reward = roll[0] as Reward
	_reward_left = roll[3]
	_reward_pivot = Node3D.new()
	_reward_pivot.position = display_anchor.position + Vector3.UP * REWARD_HEIGHT
	if reward == Reward.WEAPON:
		_reward_scene = reward_weapons.weapons[roll[1]]
		_reward_rarity = roll[2]
		_reward_pivot.add_child(_make_display_copy(_reward_scene, _reward_rarity))
	else:
		_reward_pivot.add_child(_make_relic())
	add_child(_reward_pivot)


func _clear_reward() -> void:
	reward = Reward.NONE
	_reward_scene = null
	if _reward_pivot:
		_reward_pivot.queue_free()
		_reward_pivot = null


func _reward_ready() -> bool:
	return reward != Reward.NONE and _reward_left <= 0.0


## Whether `player` could take the reward now, once in reach.
func has_reward_for(player: PlayerClass3D) -> bool:
	if not _reward_ready() or not _may_take(player):
		return false
	return reward == Reward.PERK or player.free_hand_for(_reward_grip()) != null


func _reward_grip() -> Weapon3D.Grip:
	var weapon: Weapon3D = _reward_pivot.get_child(0) as Weapon3D if _reward_pivot else null
	return weapon.grip if weapon else Weapon3D.Grip.EITHER_HAND


func _take_reward(player: PlayerClass3D) -> void:
	var is_left: bool = reward == Reward.WEAPON and player.free_hand_for(_reward_grip())
	if not Net.in_session():
		_reward_given(player.name, is_left, _next_weapon_name())
	else:
		_request_reward.rpc_id(Net.SERVER_ID, is_left)


@rpc("any_peer", "reliable")
func _request_reward(is_left: bool) -> void:
	if not Net.is_server or not _reward_ready():
		return
	var player: PlayerClass3D = Global.Game3D.player_of_peer(multiplayer.get_remote_sender_id())
	if player and _may_take(player) and (reward == Reward.PERK or player.can_hold_grip(_reward_grip(), is_left)):
		_reward_given.rpc(player.name, is_left, _next_weapon_name())


## Offline, or server -> everyone: `player_name` takes the reward.
@rpc("authority", "call_local", "reliable")
func _reward_given(player_name: String, is_left: bool, weapon_name: String) -> void:
	var game: Game3D_Class = Global.Game3D
	var player: PlayerClass3D = game.get_node_or_null(player_name) as PlayerClass3D
	var kind: Reward = reward
	var scene: PackedScene = _reward_scene
	var from: Transform3D = _reward_pivot.global_transform if _reward_pivot else display_anchor.global_transform
	_clear_reward()
	if player and kind == Reward.WEAPON and scene:
		_hand_weapon(scene, _reward_rarity, player, is_left, weapon_name, from)
	elif player and kind == Reward.PERK:
		game.perks.grant_bonus_hand(player, relic_hand_size, true)  # Server/offline deals
	game.check_round_over()  # The reward may have been the last thing the round waited on
	if not player:
		return
	if not _is_ours(player):
		var label: String = "P%d" % (player.slot.index + 1) if player.slot else player_name
		game.scoreboard.announce("%s raided %s's altar!" % [label, Players.team_name(owner_team)],
			player.slot.color if player.slot else Color.WHITE)


## The perk relic's looks: a glowing gem.
func _make_relic() -> Node3D:
	var gem := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.5, 0.7, 0.5)
	var material := StandardMaterial3D.new()
	material.albedo_color = RELIC_COLOR
	material.emission_enabled = true
	material.emission = RELIC_COLOR
	material.emission_energy_multiplier = 2.5
	mesh.material = material
	gem.mesh = mesh
	var light := OmniLight3D.new()
	light.light_color = RELIC_COLOR
	light.omni_range = 4.0
	gem.add_child(light)
	return gem


func _make_reward_sign() -> void:
	_reward_sign = Label3D.new()
	_reward_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_reward_sign.no_depth_test = true
	_reward_sign.pixel_size = 0.01
	_reward_sign.font_size = 72
	_reward_sign.outline_size = 18
	_reward_sign.position = Vector3(0, REWARD_SIGN_HEIGHT, 0)
	_reward_sign.visible = false
	add_child(_reward_sign)


## Count the reward down, spin it, and say what it is (and when it's
## up for grabs to everyone).
func _update_reward(delta: float) -> void:
	_reward_sign.visible = reward != Reward.NONE
	if reward == Reward.NONE:
		return
	_reward_left = max(_reward_left - delta, 0.0)
	_reward_pivot.rotate_y(display_spin_speed * 1.5 * delta)
	var t: float = Time.get_ticks_msec() / 1000.0
	_reward_pivot.position.y = display_anchor.position.y + REWARD_HEIGHT + sin(t * 2.0) * 0.12
	var see_through: float = 0.0 if _reward_ready() else 0.6
	for node: Node in _reward_pivot.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).transparency = see_through
	var what: String = "WEAPON" if reward == Reward.WEAPON else "RELIC PERK"
	if not _reward_ready():
		_reward_sign.text = "%s  %ds" % [what, ceili(_reward_left)]
		_reward_sign.modulate = Color(0.85, 0.85, 0.85)
	elif is_unguarded():
		_reward_sign.text = "UNGUARDED %s!" % what
		_reward_sign.modulate = UNGUARDED_COLOR
	else:
		_reward_sign.text = "%s READY" % what
		_reward_sign.modulate = RELIC_COLOR


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
