class_name CoinPile3D extends Node3D
## Coins lying loose: half of what a dead player held, or what spilled out
## of a chest (see Game3D_Class.drop_coins). Stand by it and the coins fly
## into you one at a time (FlyingCoin3D), each a little sooner than the
## last. The nearest living player in reach gets them; anyone can, enemies
## included, so a fallen player's coins are worth fighting over.
##
## The server (or the offline game) decides who each coin goes to and tells
## every machine (_coin_taken). Piles are found by name online, so Game3D
## names them the same everywhere.

## How close a player has to be to start taking coins.
const REACH := 2.6
## Seconds before the first coin of a run flies, then each next one comes
## GAP_SHRINK times as long after the last, down to MIN_GAP.
const FIRST_GAP := 0.14
const GAP_SHRINK := 0.86
const MIN_GAP := 0.035
## Spilled coins can't be taken until they've landed.
const SETTLE_TIME := 0.6
## Seconds the spill takes, from where the coins came from to the floor.
const SPILL_TIME := 0.45
## Most coins drawn; past this, the pile looks full until it's below it.
const MAX_SHOWN := 40
## The heap's radius: grows with the coins in it, up to the max.
const HEAP_RADIUS := Vector2(0.45, 1.3)
const HEAP_HEIGHT := 0.22
const COUNT_HEIGHT := 1.1

## Coins left. Set before it enters the tree.
var count: int = 0
## Where the coins spilled out from (a body, a chest), set before it enters
## the tree. Null = they're just there.
var spill_from: Variant = null

var _shown: Array[MeshInstance3D] = []
var _settle: float = SETTLE_TIME
var _count_label: Label3D
## Server/offline: who's taking coins right now, and when the next goes.
var _collector: PlayerClass3D = null
var _gap: float = FIRST_GAP
var _gap_left: float = 0.0


func _ready() -> void:
	add_to_group("CoinPile")
	_settle_on_floor()
	_build_heap()
	_count_label = Label3D.new()
	_count_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_count_label.pixel_size = 0.01
	_count_label.font_size = 48
	_count_label.outline_size = 12
	_count_label.modulate = FlyingCoin3D.GOLD
	_count_label.position.y = COUNT_HEIGHT
	add_child(_count_label)
	var glint := OmniLight3D.new()
	glint.light_color = FlyingCoin3D.GOLD
	glint.light_energy = 0.8
	glint.omni_range = 3.0
	glint.position.y = 0.6
	add_child(glint)
	_update_label()
	Sfx.play(&"coin_spill", global_position)


## Down onto whatever's below (a player can die in the air). The same on
## every machine: it's the level's own geometry.
func _settle_on_floor() -> void:
	var from: Vector3 = global_position + Vector3.UP
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 20.0, 1)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit.position


## A mound of coins, each spilling out from spill_from to its spot.
func _build_heap() -> void:
	var shown: int = mini(count, MAX_SHOWN)
	var radius: float = lerpf(HEAP_RADIUS.x, HEAP_RADIUS.y, shown / float(MAX_SHOWN))
	var from_local: Vector3 = to_local(spill_from) if spill_from is Vector3 else Vector3.ZERO
	for i in shown:
		var coin: MeshInstance3D = FlyingCoin3D.make_mesh()
		var dist: float = sqrt(randf()) * radius
		var angle: float = randf() * TAU
		var spot := Vector3(cos(angle) * dist, 0.03 + (1.0 - dist / radius) * HEAP_HEIGHT * randf(), sin(angle) * dist)
		coin.rotation = Vector3(randf_range(-0.35, 0.35), randf() * TAU, randf_range(-0.35, 0.35))
		add_child(coin)
		_shown.append(coin)
		if spill_from is Vector3:
			coin.position = from_local
			var hop: Vector3 = (from_local + spot) / 2.0 + Vector3.UP * randf_range(0.8, 1.6)
			var tween: Tween = coin.create_tween()
			tween.tween_method(func(t: float) -> void:
				coin.position = from_local.lerp(hop, t).lerp(hop.lerp(spot, t), t),
				0.0, 1.0, SPILL_TIME * randf_range(0.7, 1.2)).set_delay(randf() * 0.15)
		else:
			coin.position = spot


func _update_label() -> void:
	_count_label.text = "x%d" % count
	_count_label.visible = count > 1


# ===== TAKING =====

func _physics_process(delta: float) -> void:
	if _settle > 0.0:
		_settle -= delta
		return
	if count <= 0 or not Net.decides() or Net.waiting_for_load():
		return
	var nearest: PlayerClass3D = _nearest_player()
	if nearest != _collector:
		# Someone new: their run starts slow
		_collector = nearest
		_gap = FIRST_GAP
		_gap_left = FIRST_GAP * 0.5
	if not _collector:
		return
	_gap_left -= delta
	if _gap_left > 0.0:
		return
	_gap = maxf(_gap * GAP_SHRINK, MIN_GAP)
	_gap_left = _gap
	Net.everywhere(_coin_taken, String(_collector.name))


func _nearest_player() -> PlayerClass3D:
	var game: Game3D_Class = Global.Game3D
	if not game:
		return null
	var best: PlayerClass3D = null
	var best_dist: float = REACH
	for player: PlayerClass3D in game.players:
		if not is_instance_valid(player) or player.is_dead():
			continue
		var to: Vector3 = player.global_position - global_position
		var dist: float = Vector2(to.x, to.z).length()
		if dist < best_dist and absf(to.y) < 2.5:
			best = player
			best_dist = dist
	return best


## Every machine: a coin flies from the pile into `player_name`.
@rpc("authority", "call_local", "reliable")
func _coin_taken(player_name: String) -> void:
	var player: PlayerClass3D = Global.Game3D.player_named(player_name) if Global.Game3D else null
	count -= 1
	var from: Vector3 = global_position + Vector3.UP * 0.1
	if _shown.size() > count and not _shown.is_empty():
		# Fewer coins than drawn: one of them is the one that goes
		var coin: MeshInstance3D = _shown.pop_back()
		from = coin.global_position
		coin.queue_free()
	elif not _shown.is_empty():
		from = _shown.pick_random().global_position
	if player:
		player.add_coins(1)
		FlyingCoin3D.launch(get_parent(), from, player)
	_update_label()
	if count <= 0:
		queue_free()
