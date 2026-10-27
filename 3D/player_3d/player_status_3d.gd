class_name PlayerStatus3D extends Node
## What's happening to a player for a while beyond their perks: frozen
## solid, burning, asleep, poisoned or chilled (see Kind). Also shows the wild items' status
## buffs on whoever has them (Frost Touch, Ablaze, Regen, see WildItem).
##
## The player's owner decides: apply() passes anyone else's request on to
## it, and it tells every machine, which each run the clock and show it.
## While frozen or asleep the player can't act (see held()); burning and
## poison hurt, and regen heals, on the owner only (HP is synced from there).
## Chilled players walk slower (see speed_multiplier).

enum Kind { FROZEN, BURNING, ASLEEP, POISONED, CHILLED }
## These stop the player where they stand.
const HOLDING: Array[Kind] = [Kind.FROZEN, Kind.ASLEEP]

const FREEZE_TIME := 1.5
## Can't be frozen again this soon after thawing, so nobody's locked for good.
const FREEZE_IMMUNITY := 2.5
const BURN_TIME := 3.0
const BURN_DPS := 6.0
const SLEEP_TIME := 4.0
## Can't be put back to sleep this soon after waking.
const SLEEP_IMMUNITY := 3.0
const POISON_DPS := 4.0
## A chilled player walks at this share of their speed.
const CHILL_SPEED := 0.55
## Regen heals this share of max HP a second.
const REGEN_RATE := 0.06
## How long an Ablaze player's touch sets the ball burning (see Ball3D).
const ABLAZE_BALL_BURN := 3.0

## How each status looks while it lasts: [Vfx.EFFECTS id, size, offset from
## the player's middle, Vfx.OVERLAYS id (empty = none)].
const LOOKS: Dictionary[Kind, Array] = {
	Kind.FROZEN: [&"frozen", 1.0, Vector3.ZERO, &"frozen"],
	Kind.BURNING: [&"burning", 0.7, Vector3(0.0, -0.9, 0.0), &"burning"],
	Kind.ASLEEP: [&"asleep", 1.8, Vector3(0.0, 1.0, 0.0), &""],
	Kind.POISONED: [&"poisoned", 1.5, Vector3.ZERO, &""],
	Kind.CHILLED: [&"frozen", 0.7, Vector3.ZERO, &""],
}
## The same for the wild items' buffs, by the perk stat they set.
const BUFF_LOOKS: Dictionary[StringName, Array] = {
	&"frost_touch": [&"frozen", 0.7, Vector3.ZERO, &""],
	&"ablaze": [&"burning", 0.9, Vector3(0.0, -0.9, 0.0), &"burning"],
	&"regen": [&"healing", 1.0, Vector3.ZERO, &""],
}
## Which overlay wins when several apply.
const OVERLAY_ORDER: Array[StringName] = [&"frozen", &"burning"]

var player: PlayerClass3D
## Seconds left of each status running, on every machine.
var _left: Dictionary[Kind, float] = {}
## Owner: seconds before each can start again.
var _immune: Dictionary[Kind, float] = {}
## What's shown for each running status (Kind) and buff (stat name).
var _fx: Dictionary[Variant, Node3D] = {}
var _overlay: StringName = &""


func _init(of: PlayerClass3D) -> void:
	player = of
	name = "Status"


func is_frozen() -> bool:
	return _left.has(Kind.FROZEN)


func is_asleep() -> bool:
	return _left.has(Kind.ASLEEP)


## Frozen or asleep: no moving, turning or attacking.
func held() -> bool:
	return is_frozen() or is_asleep()


## Seconds left of `kind` (0 = not running).
func time_left(kind: Kind) -> float:
	return _left.get(kind, 0.0)


## What their walking speed is multiplied by (chilled: slower).
func speed_multiplier() -> float:
	return CHILL_SPEED if _left.has(Kind.CHILLED) else 1.0


## Whether the player has a wild item's status buff (its perk stat).
func has_buff(stat: StringName) -> bool:
	return player.perk_stat(stat) > 1.0


## Start `kind` for `seconds` (or keep it going, if longer), caused by
## `source` (who gets the kill, if it finishes us). Any machine; it's
## decided on the player's owner.
func apply(kind: Kind, seconds: float, source: Node3D = null) -> void:
	if player.is_dead():
		return
	if not player._is_local():
		if Net.match_synced:
			_net_apply.rpc_id(player.get_multiplayer_authority(), kind, seconds,
				String(source.name) if source is PlayerClass3D else "")
		return
	if _immune.get(kind, 0.0) > 0.0:
		return
	if source is PlayerClass3D and source != player:
		player.blame(source)
	_start(kind, maxf(seconds, _left.get(kind, 0.0)))
	if Net.match_synced:
		_net_start.rpc(kind, _left[kind])


## Owner: a hit landed on us. It wakes us up.
func on_hit() -> void:
	if is_asleep():
		_stop(Kind.ASLEEP)
		if Net.match_synced:
			_net_stop.rpc(Kind.ASLEEP)


@rpc("any_peer", "reliable")
func _net_apply(kind: Kind, seconds: float, source_name: String) -> void:
	if player._is_local():
		apply(kind, seconds, Global.Game3D.player_named(source_name) if Global.Game3D else null)


@rpc("any_peer", "reliable")
func _net_start(kind: Kind, seconds: float) -> void:
	if multiplayer.get_remote_sender_id() == player.get_multiplayer_authority():
		_start(kind, seconds)


@rpc("any_peer", "reliable")
func _net_stop(kind: Kind) -> void:
	if multiplayer.get_remote_sender_id() == player.get_multiplayer_authority():
		_stop(kind)


func _start(kind: Kind, seconds: float) -> void:
	var fresh: bool = not _left.has(kind)
	_left[kind] = seconds
	if not fresh:
		return
	_show(kind, LOOKS[kind])
	match kind:
		Kind.FROZEN:
			Sfx.play(&"ice_bolt", player.global_position)
		Kind.BURNING:
			Sfx.play(&"ignite", player.global_position)
		Kind.POISONED:
			Sfx.play(&"spell_impact", player.global_position, 0.7)
		Kind.CHILLED:
			Sfx.play(&"ice_bolt", player.global_position, 1.3)
	if kind in HOLDING and player._is_local():
		player.stop_in_place()


## Every machine: `kind` is over (ran out, or ended early by the owner).
func _stop(kind: Kind) -> void:
	if not _left.has(kind):
		return
	_left.erase(kind)
	_hide(kind)
	match kind:
		Kind.FROZEN:
			Vfx.play(&"shatter", player.global_position, Vector3.FORWARD, false, 2.0, Color(0.8, 0.95, 1.0))
			Sfx.play(&"weapon_break", player.global_position)
			_immune[kind] = FREEZE_IMMUNITY
		Kind.ASLEEP:
			_immune[kind] = SLEEP_IMMUNITY
			if player._is_local() and not player.is_dead():
				player.get_up()


func _process(delta: float) -> void:
	if player.is_dead():
		for kind: Kind in _left.keys():
			_left.erase(kind)
			_hide(kind)
	for kind: Kind in _left.keys():
		_left[kind] -= delta
		if _left[kind] <= 0.0:
			_stop(kind)
	for kind: Kind in _immune.keys():
		_immune[kind] -= delta
		if _immune[kind] <= 0.0:
			_immune.erase(kind)
	if player._is_local() and not player.is_dead():
		if _left.has(Kind.BURNING):
			player.hurt(BURN_DPS * delta)
		if _left.has(Kind.POISONED):
			player.hurt(POISON_DPS * delta)
		if has_buff(&"regen"):
			player.heal(player.Entity.hp_max * REGEN_RATE * delta)
	for stat: StringName in BUFF_LOOKS:
		var on: bool = has_buff(stat) and not player.is_dead()
		if on != _fx.has(stat):
			if on:
				_show(stat, BUFF_LOOKS[stat])
			else:
				_hide(stat)
	_update_overlay()


func _show(key: Variant, look: Array) -> void:
	_hide(key)
	var fx: Node3D = Vfx.attach(look[0], player, look[2], 0.0, look[1])
	if fx:
		_fx[key] = fx


func _hide(key: Variant) -> void:
	if _fx.has(key):
		Vfx.release(_fx[key])
		_fx.erase(key)


## The body's overlay: the first in OVERLAY_ORDER any running status or
## buff calls for.
func _update_overlay() -> void:
	var wanted: Array[StringName] = []
	for kind: Kind in _left:
		wanted.append(LOOKS[kind][3])
	for stat: StringName in BUFF_LOOKS:
		if _fx.has(stat):
			wanted.append(BUFF_LOOKS[stat][3])
	var overlay: StringName = &""
	for id: StringName in OVERLAY_ORDER:
		if id in wanted:
			overlay = id
			break
	if overlay != _overlay:
		_overlay = overlay
		player.visual.set_status_overlay(Vfx.overlay(overlay) if overlay != &"" else null)
