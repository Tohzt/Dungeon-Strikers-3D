@tool
class_name Altar3D extends WeaponStand3D
## A team's own weapon stand. Only its team can take from it, unless every
## one of its players is dead: then it's unguarded and anyone can. A
## NEUTRAL altar belongs to nobody, and anyone may take from it any time. It holds up to
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
## An altar can also cycle its stock (see cycle_time): a weapon nobody
## takes in a while shatters and another takes its place. Any restock may
## be a perk instead of a weapon (see perk_chance): taking it deals a hand
## of perk cards to open whenever you like (the HUD's open_perks button).
## A shop altar (see `shop`) shows nothing on top: interact opens its shop
## (ShopMenu3D), where coins buy an upgrade for the buyer's own kit, a
## breakable weapon (rolled from the current tier, so the stock gets better
## as the tier goes up), perk cards, and bombs and flasks. Every player has
## their own stock, rolled afresh every shop_restock_time. All it shows
## is a quiet hint: its ring glows gold while someone here can afford
## something, and a coin floats over it while they're in reach.

const PLAYERS_SCRIPT := preload("res://Autoloads/players.gd")
## owner_team value: nobody's, so anyone may take from it.
const NEUTRAL := -1
## Color of a neutral altar.
const NEUTRAL_COLOR := Color(0.85, 0.75, 0.5)

## Which team (PlayerSlot.team) may take from this altar, or NEUTRAL.
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

@export_group("Cycling")
## Seconds the newest stock may sit untaken (once charged) before it
## shatters and the altar stocks another. 0 = it stays until taken.
@export var cycle_time: float = 0.0
## Chance each restock is a perk instead of a weapon.
@export_range(0.0, 1.0) var perk_chance: float = 0.0
## The hand a perk deals its taker: a card from each category.
@export var perk_categories: Array[Perk.Category] = [Perk.Category.OFFENSE, Perk.Category.MOBILITY, Perk.Category.GENERAL]
## Interact opens the cards of a teammate with a hand waiting (for maps
## whose perks are picked at the altars, at intermission). Off where hands
## are opened from the HUD, so taking from the altar isn't blocked.
@export var opens_perks: bool = true

@export_group("Shop")
## Sells its stock for coins instead of handing it out (see ShopMenu3D).
@export var shop: bool = false
## Seconds between restocks: every player's stock is rolled afresh. A
## tier-up restocks at once too.
@export var shop_restock_time: float = 45.0
## Sells an upgrade for each buyer's own signature kit (see
## PlayerClass3D.upgrade_kit), first in the weapons row: one rarity up, or
## with kit_jump_chance two. There's always another once one's bought.
@export var shop_kit_slot: bool = true
@export_range(0.0, 1.0) var kit_jump_chance: float = 0.2
## Breakable weapons (any kind) in each stock, from the current tier.
## Everything but the kit upgrade sells out until the next restock.
@export_range(0, 4) var shop_weapon_slots: int = 1
## Perk cards in each stock (never relics), each taken on the spot.
@export_range(0, 4) var shop_perk_slots: int = 2
## Bombs and big flasks on sale at once (see Throwable3D), put in the
## buyer's item slot (PlayerClass3D.stored_item). Each is a bomb at bomb_chance, else a
## flask, and no two alike.
@export_range(0, 4) var shop_throwable_slots: int = 3
@export_range(0.0, 1.0) var bomb_chance: float = 0.6
## Coins a weapon costs, by rarity (Common, Uncommon, Rare, Legendary).
@export var weapon_prices: Array[int] = [10, 18, 30, 50]
## Coins a kit upgrade costs, by the rarity it takes the kit to.
@export var kit_prices: Array[int] = [0, 20, 35, 55]
@export var perk_price: int = 25
@export var bomb_price: int = 12
@export var flask_price: int = 10
## What a tower repair costs (see set_repair_offer), and the share of the
## tower's max HP it puts back.
@export var repair_price: int = 20
@export_range(0.0, 1.0) var repair_share: float = 0.4
@export_group("")

@onready var base_mesh: MeshInstance3D = $MeshInstance3D
@onready var arming_ring: MeshInstance3D = $ArmingRing

## One weapon on display.
class HeldWeapon:
	var scene: PackedScene
	## A perk instead of a weapon (scene is null).
	var is_perk: bool = false
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
## Seconds the newest stock has sat charged and untaken, toward cycle_time.
var _idle_time: float = 0.0
## _stock's pick for a perk instead of a weapon.
const PERK_PICK := -1
const PERK_COLOR := Color(0.55, 0.85, 1.0)
## The stock about to cycle out flickers for this long first.
const CYCLE_WARNING := 3.0
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

## Shop: each player's own stock (Array[ShopOffer]), by player name,
## grouped in ShopOffer.ORDER (the menu's rows). The same on every machine.
var _stocks: Dictionary[String, Array] = {}
## Shop: goes up whenever a player's stock changes (their menu redraws, and
## a buy meant for older stock is turned down), by player name.
var _stock_versions: Dictionary[String, int] = {}
## Shop: seconds until the next restock, counted on every machine (for the
## menu); the server's (or the offline game's) count is the one that acts.
var restock_left: float = 0.0
## Server/offline: the first stock has been rolled.
var _shop_rolled: bool = false
## Shop: a repair is on sale (our team has a tower up), after the stock.
var _repair_offered: bool = false
## The shop's hint (see the class notes): a coin over the altar, and the
## ring's own material, to glow without lighting the tier pips too.
var _shop_coin: Sprite3D = null
var _shop_ring: StandardMaterial3D = null
var _shop_glow: float = 0.0
const SHOP_COIN_HEIGHT := 2.6
const SHOP_GLOW_SPEED := 4.0
## Gap between a two-piece kit's weapons in the menu's preview.
const KIT_PREVIEW_SPACING := 0.7
## [name, grip, heavy move's name] of each weapon scene, worked out once.
static var _weapon_info: Dictionary[PackedScene, Array] = {}


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
		if shop:
			_make_shop_hint()
		elif has_first:
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
	_tick_cycle(delta)
	_update_perk_sign()
	_update_reward(delta)
	_update_pip_pop(delta)
	_tick_tier_timer(delta)
	if shop:
		_update_shop(delta)


# ===== PERKS =====

## Perk cards come first: if `player` has some waiting, interact opens them.
func can_give_to(player: PlayerClass3D) -> bool:
	if _has_perks_for(player):
		return true
	if shop and can_shop(player) and not offers_for(player).is_empty():
		return not player.slot or not player.slot.is_bot or bot_buy_index(player) >= 0 \
			or (has_reward_for(player))
	return super(player)


func request_take(player: PlayerClass3D) -> bool:
	if _has_perks_for(player):
		Global.Game3D.perks.open_for(player)
		return true
	if has_reward_for(player) and reach.overlaps_body(player):
		_take_reward(player)
		return true
	if shop:
		return _open_shop(player)
	return super(player)


## The skull's reward comes first, then the stock (a shop's: for a bot,
## something it can afford).
func has_weapon_for(player: PlayerClass3D) -> bool:
	if has_reward_for(player):
		return true
	if shop:
		return player.slot != null and player.slot.is_bot and bot_buy_index(player) >= 0
	return super(player)


func _has_perks_for(player: PlayerClass3D) -> bool:
	var perks: PerkDirector = Global.Game3D.perks if Global.Game3D else null
	# Bots take their cards on their own (BotInputHandler3D); opening them
	# here would leave a bot stuck looking at them.
	if not opens_perks or (player.slot and player.slot.is_bot):
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
	_perk_sign.visible = opens_perks and perks != null and perks.team_has_offer(owner_team)
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


## A perk is taken with no hand free.
func _stock_needs_hand() -> bool:
	var item: HeldWeapon = _next_given()
	return not item or not item.is_perk


## Hands out the next weapon (see _next_given).
func _take_stock() -> PackedScene:
	var item: HeldWeapon = _next_given()
	if not item:
		return null
	cooldown_left = _cooldown_after_take()
	_remove_held(item)
	_given_rarity = item.rarity
	return item.scene  # Null for a perk: see _hand_other


## Every machine: `player` took a perk. The server (or the offline game)
## deals them its hand, which waits for them to open it.
func _hand_other(player: PlayerClass3D) -> void:
	Sfx.play(&"altar_reward", global_position)
	var perks: PerkDirector = Global.Game3D.perks if Global.Game3D else null
	if perks:
		perks.grant_hand(player, perk_categories)


## Put tiers[tier_index].weapons[pick] (or a perk, for PERK_PICK) on top,
## charging for its arming time.
func _add_held(tier_index: int, pick: int, tier_rarity: int) -> void:
	var stocked_tier: AltarTier = tiers[tier_index]
	var item := HeldWeapon.new()
	item.is_perk = pick == PERK_PICK
	item.scene = null if item.is_perk else stocked_tier.weapons[pick]
	item.rarity = tier_rarity
	item.arming_total = stocked_tier.arming_time
	item.arming_left = item.arming_total
	item.pivot = Node3D.new()
	if item.is_perk:
		item.pivot.add_child(_make_gem(PERK_COLOR))
	else:
		item.pivot.add_child(_make_display_copy(item.scene, item.rarity))
	add_child(item.pivot)
	_held.append(item)
	_idle_time = 0.0
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


## Our own team always may; anyone else only while the altar is unguarded
## (a neutral altar: anyone, always).
func _may_take(player: PlayerClass3D) -> bool:
	if owner_team == NEUTRAL:
		return player.slot != null
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


## Server/offline: pick a weapon (or a perk) from the current tier and
## stock it everywhere. A shop restocks all its weapons instead.
func _restock() -> void:
	if not Net.decides():
		return
	if shop:
		_restock_shop()
		return
	var roll: PackedInt32Array = _roll_stock()
	if not roll.is_empty():
		Net.everywhere(_stock, roll[0], roll[1], roll[2])


## Server/offline: what to stock next, as [tier, pick, rarity] (pick is
## PERK_PICK for a perk), or empty if the tier has nothing.
func _roll_stock() -> PackedInt32Array:
	var current: AltarTier = _current_tier()
	if not current or current.weapons.is_empty():
		return PackedInt32Array()
	var perks_on: bool = Global.Game3D != null and Global.Game3D.perks != null
	var pick: int = PERK_PICK if perks_on and randf() < perk_chance else randi() % current.weapons.size()
	return PackedInt32Array([tier, pick, WeaponRarity.roll(current.rarity_weights)])


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
	if not Net.decides():
		return
	var new_tier: int = clampi(tier + levels, 0, tiers.size() - 1)
	if new_tier == tier:
		return
	Net.everywhere(_set_tier, new_tier)
	_restock()


@rpc("authority", "call_local", "reliable")
func _set_tier(new_tier: int) -> void:
	tier = new_tier
	_update_tier_pips()
	_pip_pop = PIP_POP_TIME
	Sfx.play(&"altar_tier", global_position)


func _tick_tier_timer(delta: float) -> void:
	if seconds_per_tier <= 0.0 or tier >= tiers.size() - 1:
		return
	if Net.in_session() and not (Net.is_server and Net.match_synced):
		return
	_tier_timer += delta
	if _tier_timer >= seconds_per_tier:
		_tier_timer = 0.0
		upgrade()


# ===== CYCLING =====

## Count how long the newest stock has sat charged and untaken; the server
## (or the offline game) swaps it out at cycle_time. Paused during a draft.
func _tick_cycle(delta: float) -> void:
	if cycle_time <= 0.0 or _held.is_empty():
		return
	var counting: bool = _held.back().is_armed() and _pending.is_empty() \
		and cooldown_left <= 0.0 and not PerkDirector.halted()
	if counting:
		_idle_time += delta
	# The oldest is the one that goes: it blinks for a moment first
	_flicker(_held[0], counting and cycle_time - _idle_time < CYCLE_WARNING)
	if not counting or _idle_time < cycle_time or not Net.decides():
		return
	if Net.in_session() and not Net.match_synced:
		return
	_idle_time = 0.0
	var roll: PackedInt32Array = _roll_stock()
	if not roll.is_empty():
		Net.everywhere(_cycle_stock, roll[0], roll[1], roll[2])


## Blink `item` while it's about to shatter (`on`), else show it.
func _flicker(item: HeldWeapon, on: bool) -> void:
	item.pivot.visible = not on or fmod(Time.get_ticks_msec() / 1000.0 * 8.0, 1.0) < 0.6


## Server -> everyone: the oldest stock shatters, and tiers[tier_index].
## weapons[pick] (or a perk) takes its place.
@rpc("authority", "call_local", "reliable")
func _cycle_stock(tier_index: int, pick: int, pick_rarity: int) -> void:
	if not _held.is_empty():
		_shatter(_held[0])
	_add_held(tier_index, pick, pick_rarity)


func _shatter(item: HeldWeapon) -> void:
	var at: Vector3 = item.pivot.global_position
	var color: Color = PERK_COLOR if item.is_perk else WeaponRarity.effect_color(item.rarity)
	Sfx.play(&"weapon_break", at)
	Vfx.play(&"shatter", at, Vector3.FORWARD, false, 1.0, color)
	_remove_held(item)


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
	Sfx.play(&"altar_reward", global_position)
	reward = roll[0] as Reward
	_reward_left = roll[3]
	_reward_pivot = Node3D.new()
	_reward_pivot.position = display_anchor.position + Vector3.UP * REWARD_HEIGHT
	if reward == Reward.WEAPON:
		_reward_scene = reward_weapons.weapons[roll[1]]
		_reward_rarity = roll[2]
		_reward_pivot.add_child(_make_display_copy(_reward_scene, _reward_rarity))
	else:
		_reward_pivot.add_child(_make_gem(RELIC_COLOR))
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
	elif Net.is_server:
		_decide_reward(player, is_left)  # A bot
	else:
		_request_reward.rpc_id(Net.SERVER_ID, is_left)


@rpc("any_peer", "reliable")
func _request_reward(is_left: bool) -> void:
	if Net.is_server:
		_decide_reward(Global.Game3D.rpc_sender(), is_left)


## Server: give `player` the reward if it's still there for them.
func _decide_reward(player: PlayerClass3D, is_left: bool) -> void:
	if not _reward_ready() or not player or not _may_take(player):
		return
	if reward == Reward.PERK or player.can_hold_grip(_reward_grip(), is_left):
		_reward_given.rpc(player.name, is_left, _next_weapon_name())


## Offline, or server -> everyone: `player_name` takes the reward.
@rpc("authority", "call_local", "reliable")
func _reward_given(player_name: String, is_left: bool, weapon_name: String) -> void:
	var game: Game3D_Class = Global.Game3D
	var player: PlayerClass3D = game.player_named(player_name)
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
		var label: String = player.slot.label() if player.slot else player_name
		game.scoreboard.announce("%s raided %s's altar!" % [label, Players.team_name(owner_team)],
			player.slot.color if player.slot else Color.WHITE)


## A perk's looks (a relic's, or a stocked one's): a glowing gem.
func _make_gem(color: Color) -> Node3D:
	var gem := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.5, 0.7, 0.5)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.5
	mesh.material = material
	gem.mesh = mesh
	var light := OmniLight3D.new()
	light.light_color = color
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
## up for grabs to everyone). Without one, the sign names a stocked perk.
func _update_reward(delta: float) -> void:
	if reward == Reward.NONE:
		_update_perk_stock_sign()
		return
	_reward_sign.visible = true
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


func _update_perk_stock_sign() -> void:
	var item: HeldWeapon = _next_given()
	_reward_sign.visible = item != null and item.is_perk
	if not _reward_sign.visible:
		return
	_reward_sign.text = "PERK" if item.is_armed() else "PERK  %ds" % ceili(item.arming_left)
	_reward_sign.modulate = PERK_COLOR


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
	if shop:
		arming_ring.scale = Vector3.ONE
		arming_ring.visible = true
		return
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
	var color: Color = NEUTRAL_COLOR if owner_team == NEUTRAL else team_colors[owner_team % team_colors.size()]
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


# ===== SHOP =====

## What `offer` costs `player` (a kit upgrade costs more the rarer it
## makes their kit).
func price_of(offer: ShopOffer, player: PlayerClass3D) -> int:
	match offer.kind:
		ShopOffer.Kind.WEAPON:
			return weapon_prices[clampi(offer.rarity, 0, weapon_prices.size() - 1)] if not weapon_prices.is_empty() else 0
		ShopOffer.Kind.PERK:
			return perk_price
		ShopOffer.Kind.REPAIR:
			return repair_price
		ShopOffer.Kind.KIT:
			return kit_prices[clampi(kit_rarity_after(offer, player), 0, kit_prices.size() - 1)] if not kit_prices.is_empty() else 0
		ShopOffer.Kind.THROWABLE:
			return bomb_price if offer.throwable_kind == Throwable3D.Kind.BOMB else flask_price
	return 0


## The rarity a kit offer would take `player`'s kit to.
func kit_rarity_after(offer: ShopOffer, player: PlayerClass3D) -> int:
	var from: int = player.kit_rarity if player else WeaponRarity.Tier.COMMON
	return mini(from + offer.steps, WeaponRarity.Tier.LEGENDARY)


## What the menu calls `offer`.
func offer_title(offer: ShopOffer) -> String:
	match offer.kind:
		ShopOffer.Kind.WEAPON:
			return weapon_info(offer.scene)[0]
		ShopOffer.Kind.PERK:
			var perk: Perk = perk_of(offer)
			return perk.title if perk else "Perk"
		ShopOffer.Kind.REPAIR:
			return "Repair Tower"
		ShopOffer.Kind.KIT:
			return "Kit Upgrade"
		ShopOffer.Kind.THROWABLE:
			return throwable_title(offer)
	return ""


## A throwable offer's name and color, as Throwable3D names it.
static func throwable_title(offer: ShopOffer) -> String:
	if offer.throwable_kind == Throwable3D.Kind.FLASK:
		return Potion.large(offer.variant).title
	return "%s Bomb" % Bomb3D.NAMES.get(offer.variant as Bomb3D.Type, "")


static func throwable_color(offer: ShopOffer) -> Color:
	if offer.throwable_kind == Throwable3D.Kind.FLASK:
		return Potion.large(offer.variant).color
	return Bomb3D.COLORS.get(offer.variant as Bomb3D.Type, Color.WHITE)


## A perk offer's card.
func perk_of(offer: ShopOffer) -> Perk:
	var perks: PerkDirector = Global.Game3D.perks if Global.Game3D else null
	if offer.kind != ShopOffer.Kind.PERK or not perks or offer.perk_index < 0 or offer.perk_index >= perks.catalog.perks.size():
		return null
	return perks.catalog.perks[offer.perk_index]


## [name, grip, heavy move's name ("" = none)] of the weapon `scene` makes.
static func weapon_info(scene: PackedScene) -> Array:
	if not scene:
		return ["Weapon", Weapon3D.Grip.EITHER_HAND, ""]
	if not _weapon_info.has(scene):
		var weapon: Weapon3D = scene.instantiate() as Weapon3D
		var weapon_name: String = weapon.Properties.weapon_name if weapon and weapon.Properties else "Weapon"
		var heavy: String = ""
		if weapon and weapon.heavy_move and weapon.heavy_move.resource_path != "":
			heavy = weapon.heavy_move.resource_path.get_file().get_basename().trim_prefix("heavy_").replace("_", " ").capitalize()
		_weapon_info[scene] = [weapon_name, weapon.grip if weapon else Weapon3D.Grip.EITHER_HAND, heavy]
		if weapon:
			weapon.free()
	return _weapon_info[scene]


## A copy of an offer for looks only (the menu's preview): the weapon, the
## upgraded kit of `player` (side by side, if it's two), or the bomb or flask.
func make_preview(offer: ShopOffer, player: PlayerClass3D) -> Node3D:
	match offer.kind:
		ShopOffer.Kind.WEAPON:
			return _make_display_copy(offer.scene, offer.rarity) if offer.scene else null
		ShopOffer.Kind.KIT:
			var scenes: Array[PackedScene] = Roster.kit_of(player.slot.character if player.slot else 0)
			var shown: Array[PackedScene] = []
			for scene: PackedScene in scenes:
				if scene:
					shown.append(scene)
			if shown.is_empty():
				return null
			var group := Node3D.new()
			for i in shown.size():
				var copy: Node3D = _make_display_copy(shown[i], kit_rarity_after(offer, player))
				copy.position.x = (i - (shown.size() - 1) * 0.5) * KIT_PREVIEW_SPACING
				group.add_child(copy)
			return group
		ShopOffer.Kind.THROWABLE:
			if offer.throwable_kind == Throwable3D.Kind.FLASK:
				# Wrapped, so the menu's framing counts the model's own scale
				var holder := Node3D.new()
				holder.add_child(Potion.model(&"jug", throwable_color(offer), Potion.LARGE_HEIGHT))
				return holder
			var bomb := BombModel3D.new()
			bomb.set_color(throwable_color(offer))
			return bomb
	return null


## Whether `player` may shop here and is in reach of it.
func can_shop(player: PlayerClass3D) -> bool:
	return shop and not player.is_dead() and _may_take(player) and reach.overlaps_body(player)


## `player`'s own stock here (empty until the server rolls it).
func offers_for(player: PlayerClass3D) -> Array[ShopOffer]:
	var stock: Array[ShopOffer] = []
	if player:
		stock.assign(_stocks.get(String(player.name), []))
	return stock


## Goes up whenever `player`'s stock changes.
func stock_version(player: PlayerClass3D) -> int:
	return _stock_versions.get(String(player.name), 0) if player else 0


func _stock_changed(player_name: String) -> void:
	_stock_versions[player_name] = _stock_versions.get(player_name, 0) + 1


## Whether `player` has the coins for anything on sale.
func can_afford_any(player: PlayerClass3D) -> bool:
	for offer: ShopOffer in offers_for(player):
		if price_of(offer, player) <= player.coins and is_useful_to(player, offer):
			return true
	return false


## Whether `offer` would do `player` any good: not once it's sold, a repair
## only when it's our team's altar and one of our towers is hurt, a kit
## upgrade until their kit's Legendary, a bomb or flask while their item
## slot is empty.
func is_useful_to(player: PlayerClass3D, offer: ShopOffer) -> bool:
	if offer.sold:
		return false
	match offer.kind:
		ShopOffer.Kind.REPAIR:
			return _is_ours(player) and tower_to_repair() != null
		ShopOffer.Kind.KIT:
			return player.can_upgrade_kit()
		ShopOffer.Kind.THROWABLE:
			return not player.has_stored_item()  # It goes in the item slot
	return true


## The tower a repair here would fix: our team's most hurt one.
func tower_to_repair() -> Tower3D:
	return Tower3D.most_damaged_of(get_tree(), owner_team) if owner_team != NEUTRAL else null


## Every machine, in the same order: sell repairs (or stop) while our team
## has a tower up.
func set_repair_offer(on: bool) -> void:
	if not shop or on == _repair_offered:
		return
	_repair_offered = on
	for player_name: String in _stocks:
		var stock: Array = _stocks[player_name]
		if on:
			stock.append(ShopOffer.repair())
		else:
			for i in range(stock.size() - 1, -1, -1):
				if stock[i].kind == ShopOffer.Kind.REPAIR:
					stock.remove_at(i)
		_stock_changed(player_name)


## A person opens the shop on their own machine; a bot (server/offline)
## just buys the priciest thing it can afford (or a repair, see
## bot_buy_index).
func _open_shop(player: PlayerClass3D) -> bool:
	if not can_shop(player) or offers_for(player).is_empty():
		return false
	if player.slot and player.slot.is_bot:
		var index: int = bot_buy_index(player)
		if index >= 0:
			buy(player, index)
		return index >= 0
	var menu: ShopMenu3D = Global.Game3D.shop_menu if Global.Game3D else null
	if menu:
		menu.open(player, self)
	return menu != null


## The offer a bot would buy, or -1: a repair if one of its team's towers
## is down to half, else a kit upgrade, else the dearest weapon it can
## afford if it's holding nothing it found, else the dearest perk. Bots
## leave the bombs and flasks alone.
func bot_buy_index(player: PlayerClass3D) -> int:
	var best: int = -1
	var wants_weapon: bool = not player.holds_found_weapon()
	var offers: Array[ShopOffer] = offers_for(player)
	for i in offers.size():
		var offer: ShopOffer = offers[i]
		if price_of(offer, player) > player.coins or not is_useful_to(player, offer):
			continue
		match offer.kind:
			ShopOffer.Kind.REPAIR:
				# A badly hurt tower comes first
				if tower_to_repair().damage_share() >= 0.5:
					return i
				continue
			ShopOffer.Kind.KIT:
				return i
			ShopOffer.Kind.THROWABLE:
				continue
		if (offer.kind == ShopOffer.Kind.WEAPON) != wants_weapon:
			continue
		if best < 0 or price_of(offer, player) > price_of(offers[best], player):
			best = i
	return best


## `player` (on the machine that controls them) buys their offers[index].
## The server (or the offline game) checks they still can.
func buy(player: PlayerClass3D, index: int) -> void:
	if Net.decides():
		_decide_buy(player, index)
	else:
		_request_buy.rpc_id(Net.SERVER_ID, index, stock_version(player))


@rpc("any_peer", "reliable")
func _request_buy(index: int, version: int) -> void:
	if not Net.is_server:
		return
	# A buy meant for stock that's changed since (a restock, a tier-up)
	# could be something else now
	var player: PlayerClass3D = Global.Game3D.rpc_sender()
	if player and version == stock_version(player):
		_decide_buy(player, index)


## Server/offline: sell `player` their offers[index] if it's still there,
## they're still here and they can pay for it. It sells out until the next
## restock, but a kit upgrade is followed by the next one.
func _decide_buy(player: PlayerClass3D, index: int) -> void:
	var offers: Array[ShopOffer] = offers_for(player)
	if not player or index < 0 or index >= offers.size() or not can_shop(player):
		return
	var offer: ShopOffer = offers[index]
	if player.coins < price_of(offer, player) or not is_useful_to(player, offer):
		return
	var is_left: bool = false
	var replacement := PackedInt32Array()
	match offer.kind:
		ShopOffer.Kind.WEAPON:
			is_left = player.free_hand_for(weapon_info(offer.scene)[1])
		ShopOffer.Kind.KIT:
			replacement = _roll_kit_offer()
		ShopOffer.Kind.REPAIR:
			var tower: Tower3D = tower_to_repair()
			tower.repair(tower.max_hp * repair_share)
			replacement = offer.encode()  # Still on sale
	Net.everywhere(_sold, String(player.name), index, is_left, _next_weapon_name(), replacement)


## Every machine: `player_name` paid for their offers[index] and gets it (a
## weapon in hand, a perk at once; a repair was done by the server). It's
## sold out, unless `replacement` (an encoded ShopOffer) takes its place.
@rpc("authority", "call_local", "reliable")
func _sold(player_name: String, index: int, is_left: bool, weapon_name: String, replacement: PackedInt32Array) -> void:
	var offers: Array = _stocks.get(player_name, [])
	if index < 0 or index >= offers.size():
		return
	var offer: ShopOffer = offers[index]
	var game: Game3D_Class = Global.Game3D
	var player: PlayerClass3D = game.player_named(player_name) if game else null
	Sfx.play(&"shop_buy", global_position)
	if player:
		player.add_coins(-price_of(offer, player))
		# Out of the shop, so they see what they got (open it again for more)
		if game.shop_menu:
			game.shop_menu.close(player)
		match offer.kind:
			ShopOffer.Kind.WEAPON:
				_hand_weapon(offer.scene, offer.rarity, player, is_left, weapon_name, display_anchor.global_transform)
			ShopOffer.Kind.PERK:
				var perk: Perk = perk_of(offer)
				if perk:
					player.add_perk(perk)
					game.perks.perk_taken.emit(player, perk)
			ShopOffer.Kind.KIT:
				player.upgrade_kit(offer.steps)
				Vfx.play(&"shatter", player.global_position + Vector3.UP, Vector3.UP, false, 1.0,
					WeaponRarity.effect_color(player.kit_rarity))
			ShopOffer.Kind.THROWABLE:
				player.store_item(offer.throwable_kind as Throwable3D.Kind, offer.variant)
	var next: ShopOffer = _decode_offer(replacement)
	if next:
		offers[index] = next
	else:
		offer.sold = true
	_stock_changed(player_name)
	if player and not _is_ours(player) and owner_team != NEUTRAL and game:
		game.scoreboard.announce("%s raided %s's shop!" % [player.slot.label() if player.slot else player_name,
			Players.team_name(owner_team)], player.slot.color if player.slot else Color.WHITE)


## Server/offline: a weapon from the current tier, encoded (empty if the
## tier has none).
func _roll_weapon_offer() -> PackedInt32Array:
	var current: AltarTier = _current_tier()
	if not current or current.weapons.is_empty():
		return PackedInt32Array()
	return ShopOffer.weapon(tier, randi() % current.weapons.size(), WeaponRarity.roll(current.rarity_weights)).encode()


## Server/offline: a perk card that isn't in `taken`, encoded (empty if
## none's left). Never a relic.
func _roll_perk_offer(taken: Array[int]) -> PackedInt32Array:
	var perks: PerkDirector = Global.Game3D.perks if Global.Game3D else null
	if not perks:
		return PackedInt32Array()
	var choices: Array[int] = []
	for i in perks.catalog.perks.size():
		if perks.catalog.perks[i].category != Perk.Category.RELIC and not taken.has(i):
			choices.append(i)
	return ShopOffer.perk(choices.pick_random()).encode() if not choices.is_empty() else PackedInt32Array()


## Server/offline: a kit upgrade, encoded: one rarity up, sometimes two.
func _roll_kit_offer() -> PackedInt32Array:
	return ShopOffer.kit(2 if randf() < kit_jump_chance else 1).encode()


## Server/offline: a bomb (at bomb_chance) or a big flask that isn't in
## `taken` ([kind, variant] pairs, back to back), encoded (empty if none's left).
func _roll_throwable_offer(taken: PackedInt32Array) -> PackedInt32Array:
	var bomb: bool = randf() < bomb_chance
	for attempt in 2:  # The kind rolled, else the other one
		var of_kind: int = Throwable3D.Kind.BOMB if bomb else Throwable3D.Kind.FLASK
		var count: int = Bomb3D.Type.size() if bomb else Potion.LARGE.size()
		var choices: Array[int] = []
		for which in count:
			if not _pair_in(taken, of_kind, which):
				choices.append(which)
		if not choices.is_empty():
			return ShopOffer.throwable(of_kind, choices.pick_random()).encode()
		bomb = not bomb
	return PackedInt32Array()


func _pair_in(pairs: PackedInt32Array, a: int, b: int) -> bool:
	for i in range(0, pairs.size() - 1, 2):
		if pairs[i] == a and pairs[i + 1] == b:
			return true
	return false


## Server/offline: roll every player's stock afresh, and start the wait for
## the next restock.
func _restock_shop() -> void:
	var game: Game3D_Class = Global.Game3D
	if not game:
		return
	for player: PlayerClass3D in game.players:
		if is_instance_valid(player):
			_restock_for(player)
	Net.everywhere(_set_restock_left, shop_restock_time)


@rpc("authority", "call_local", "reliable")
func _set_restock_left(seconds: float) -> void:
	restock_left = seconds


## Server/offline: roll `player` a fresh stock, for everyone.
func _restock_for(player: PlayerClass3D) -> void:
	var rolls := PackedInt32Array()
	if shop_kit_slot:
		rolls.append_array(_roll_kit_offer())
	for i in shop_weapon_slots:
		rolls.append_array(_roll_weapon_offer())
	var taken: Array[int] = []
	for i in shop_perk_slots:
		var roll: PackedInt32Array = _roll_perk_offer(taken)
		if not roll.is_empty():
			taken.append(roll[1])
			rolls.append_array(roll)
	var thrown_taken := PackedInt32Array()
	for i in shop_throwable_slots:
		var roll: PackedInt32Array = _roll_throwable_offer(thrown_taken)
		if not roll.is_empty():
			thrown_taken.append_array([roll[1], roll[2]])
			rolls.append_array(roll)
	Net.everywhere(_set_stock, String(player.name), tier, rolls)


## Every machine: `player_name` can now buy `rolls` here (encoded
## ShopOffers, back to back), with tiers[tier_index] as the shop's tier.
@rpc("authority", "call_local", "reliable")
func _set_stock(player_name: String, tier_index: int, rolls: PackedInt32Array) -> void:
	tier = tier_index
	var offers: Array[ShopOffer] = []
	for i in range(0, rolls.size() - ShopOffer.ENCODED_SIZE + 1, ShopOffer.ENCODED_SIZE):
		var offer: ShopOffer = _decode_offer(rolls.slice(i, i + ShopOffer.ENCODED_SIZE))
		if offer:
			offers.append(offer)
	if _repair_offered:
		offers.append(ShopOffer.repair())
	# Grouped by kind in the menu's order (see ShopOffer.ORDER), for its rows
	offers.sort_custom(func(a: ShopOffer, b: ShopOffer) -> bool:
		return ShopOffer.order_of(a.kind) < ShopOffer.order_of(b.kind))
	_stocks[player_name] = offers
	_stock_changed(player_name)


## An encoded ShopOffer (see ShopOffer.encode) back as an offer, or null.
func _decode_offer(code: PackedInt32Array) -> ShopOffer:
	if code.size() < ShopOffer.ENCODED_SIZE:
		return null
	match code[0]:
		ShopOffer.Kind.WEAPON:
			if code[1] < 0 or code[1] >= tiers.size() or code[2] < 0 or code[2] >= tiers[code[1]].weapons.size():
				return null
			var offer := ShopOffer.weapon(code[1], code[2], code[3])
			offer.scene = tiers[code[1]].weapons[code[2]]
			return offer
		ShopOffer.Kind.PERK:
			return ShopOffer.perk(code[1])
		ShopOffer.Kind.REPAIR:
			return ShopOffer.repair()
		ShopOffer.Kind.KIT:
			return ShopOffer.kit(code[1])
		ShopOffer.Kind.THROWABLE:
			var max_variant: int = Bomb3D.Type.size() if code[1] == Throwable3D.Kind.BOMB else Potion.LARGE.size()
			if code[1] < 0 or code[1] >= Throwable3D.Kind.size() or code[2] < 0 or code[2] >= max_variant:
				return null
			return ShopOffer.throwable(code[1], code[2])
	return null


func _make_shop_hint() -> void:
	_shop_ring = (arming_ring.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	arming_ring.material_override = _shop_ring
	_shop_coin = Sprite3D.new()
	_shop_coin.texture = ShopMenu3D.COIN_ICON
	_shop_coin.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_shop_coin.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_shop_coin.pixel_size = 0.02
	_shop_coin.no_depth_test = true
	_shop_coin.position.y = SHOP_COIN_HEIGHT
	_shop_coin.visible = false
	add_child(_shop_coin)


## Roll the first stock once everyone's in the match (and anyone who turns
## up later), restock on time, and show the hint for the players on this
## machine.
func _update_shop(delta: float) -> void:
	restock_left = maxf(restock_left - delta, 0.0)
	if Net.decides() and not Net.waiting_for_load():
		if not _shop_rolled or (shop_restock_time > 0.0 and restock_left <= 0.0):
			_shop_rolled = true
			_restock_shop()
		elif Global.Game3D:
			for player: PlayerClass3D in Global.Game3D.players:
				if is_instance_valid(player) and not _stocks.has(String(player.name)):
					_restock_for(player)
	var game: Game3D_Class = Global.Game3D
	var affordable: bool = false
	var in_reach: bool = false
	var in_reach_affordable: bool = false
	if game:
		for player: PlayerClass3D in game.huds:
			if not is_instance_valid(player) or player.is_dead() or not _may_take(player) \
					or game.shop_menu.is_shopping(player):
				continue
			var rich: bool = can_afford_any(player)
			affordable = affordable or rich
			if reach.overlaps_body(player):
				in_reach = true
				in_reach_affordable = in_reach_affordable or rich
	# The ring eases into a slow gold pulse while someone could buy something
	_shop_glow = move_toward(_shop_glow, 1.0 if affordable else 0.0, delta * 2.0)
	var t: float = Time.get_ticks_msec() / 1000.0
	var team_color: Color = (_pip_lit.emission if _pip_lit else NEUTRAL_COLOR)
	_shop_ring.emission = team_color.lerp(FlyingCoin3D.GOLD, _shop_glow)
	_shop_ring.albedo_color = _shop_ring.emission
	_shop_ring.emission_energy_multiplier = 2.0 + _shop_glow * (0.6 + 0.6 * sin(t * SHOP_GLOW_SPEED))
	# A coin over it while someone's close enough to open it
	_shop_coin.visible = in_reach
	if in_reach:
		_shop_coin.modulate = Color.WHITE if in_reach_affordable else Color(0.6, 0.6, 0.6, 0.6)
		_shop_coin.position.y = SHOP_COIN_HEIGHT + sin(t * 3.0) * 0.12
