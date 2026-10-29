class_name CardHand extends Control
## A player's cards, shown while they hold Use Item (G / D-pad Down, see
## PlayerInputHandler3D.hand_open): their perks peek up from the bottom of
## the screen, fanned out like a hand of cards, with their two consumable
## slots (PlayerClass3D.consumables) standing to the right. Picking a perk
## (mouse over it, or flick the right stick to it) lifts it up to read;
## picking a consumable and clicking it (or pressing Light / Interact) uses it.
## Each local player has their own, along the bottom of the screen.

## The canvas layer the hand is drawn on: over the HUD and the boss's
## health bar (layer 1), under the perk picker and pause menu (10).
const LAYER := 2
## How big cards are drawn (ItemCards.FRAMED_SIZE is full size): fanned in
## the hand, lifted out of it, and the consumable slots, picked or not.
const HAND_SCALE := 0.55
const PICKED_SCALE := 1.0
const SLOT_SCALE := 0.6
const SLOT_PICKED_SCALE := 0.8
## Share of a fanned card hidden below the bottom of the screen.
const PEEK := 0.4
## The fan: gap between cards (closer together once there are many), how
## far each tilts, the most it spreads out, and how much lower the cards
## toward its ends sit.
const FAN_STEP := 52.0
const FAN_MAX_WIDTH := 420.0
const FAN_TILT := 7.0
const FAN_MAX_TILT := 36.0
const FAN_ARC := 3.0
## Space between the fan and the slots, and between the two slots.
const SLOT_GAP := 36.0
const SLOT_SPACING := 12.0
const BOTTOM_MARGIN := 12.0
const OPEN_TIME := 0.15
const MOVE_TIME := 0.1
## A picked card is drawn over the rest.
const PICKED_Z := 10
## How big the hand is with this many players on this machine.
const SCALE_BY_PLAYERS: Array[float] = [1.0, 0.75, 0.6, 0.55]
## Flicking the right stick this far picks the next card; it has to come
## back under STICK_RESET before the next flick.
const STICK_FLICK := 0.6
const STICK_RESET := 0.3
## A consumable that can't be used right now (hands full) is dimmed.
const UNUSABLE_TINT := Color(0.5, 0.5, 0.5)
const HINT_COLOR := Color(0.95, 0.8, 0.4)

var player: PlayerClass3D
## This player's place among this machine's people (see HUD3D.setup).
var _place: int = 0
var _cards := ItemCards.new()
## Everything's laid out on this, its origin at the bottom middle of the hand.
var _root: Control
## The cards left to right: the perks, then the two consumable slots.
var _shown: Array[Control] = []
var _perks: Array[Perk] = []
## What the cards were built from, to tell when to build them again.
var _built_from: String = ""
## Which card is picked (-1 = none).
var _picked: int = -1
## 0 = tucked away below the screen, 1 = up.
var _open: float = 0.0
var _stick_held: bool = false
var _tweens: Dictionary[Control, Tween] = {}


func setup(p: PlayerClass3D, place: int) -> void:
	player = p
	_place = place


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	hide()


func _process(delta: float) -> void:
	var wanted: bool = _wanted()
	if wanted and not visible:
		show()
		_rebuild()
		_picked = -1 if _uses_mouse() else _first_pick()
		_layout(false)
	elif wanted and _source() != _built_from:
		_rebuild()
		_layout(false)
	_open = move_toward(_open, 1.0 if wanted else 0.0, delta / OPEN_TIME)
	if _open <= 0.0:
		hide()
		return
	_place_root()
	if wanted:
		_read_input()
		for i in _shown.size():
			if i >= _perks.size():
				_shown[i].modulate = Color.WHITE if player.can_use_consumable(i - _perks.size()) else UNUSABLE_TINT


## Showing while the player holds Use Item and can act.
func _wanted() -> bool:
	if not is_instance_valid(player) or not player.Input_Handler or not player.is_local_person():
		return false
	return player.Input_Handler.hand_open and not player.is_dead() and not player.is_perk_locked() \
		and not get_tree().paused


func _uses_mouse() -> bool:
	return player.slot == null or player.slot.uses_keyboard_mouse()


## Along the bottom of the screen, in this player's share of its width,
## sliding up as it opens.
func _place_root() -> void:
	var screen: Vector2 = get_viewport_rect().size
	var people: int = Global.Game3D.huds.size() if Global.Game3D else 1
	var ui_scale: float = SCALE_BY_PLAYERS[clampi(people, 1, SCALE_BY_PLAYERS.size()) - 1]
	_root.scale = Vector2.ONE * ui_scale
	var slide: float = (1.0 - ease(_open, 0.5)) * ItemCards.FRAMED_SIZE.y * ui_scale
	_root.position = Vector2(screen.x * (_place + 0.5) / maxi(people, 1), screen.y + slide)


# ===== CARDS =====

## What's in hand: the perks taken (not wild items' timed ones) and the slots.
func _source() -> String:
	return "%s|%d" % [player.consumables, player.perks.perks.size() - player.timed_perks.size()]


func _rebuild() -> void:
	_built_from = _source()
	for card: Control in _shown:
		card.queue_free()
	_shown.clear()
	_tweens.clear()
	_perks.clear()
	for perk: Perk in player.perks.perks:
		if not player.timed_perks.has(perk) and not _perks.has(perk):
			_perks.append(perk)
	for perk: Perk in _perks:
		_add(_perk_card(perk))
	for card: Vector2i in player.consumables:
		_add(_consumable_card(card))
	if _picked >= _shown.size() or (_picked >= 0 and not _can_pick(_picked)):
		_picked = -1 if _uses_mouse() else _first_pick()


func _add(card: Control) -> void:
	var index: int = _shown.size()
	_shown.append(card)
	_root.add_child(card)
	card.pivot_offset = Vector2(card.size.x / 2.0, card.size.y)  # Fans out from its bottom middle
	if _uses_mouse():
		card.mouse_entered.connect(_on_mouse_entered.bind(index))
		card.mouse_exited.connect(_on_mouse_exited.bind(index))
		card.gui_input.connect(_on_card_input.bind(index))
	else:
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _perk_card(perk: Perk) -> Control:
	var owned: int = player.perks.count(perk)
	var title: String = "%s x%d" % [perk.title, owned] if owned > 1 else perk.title
	var card: Control = _cards.make_framed_card(ItemCards.FRAME_PERK, title)
	var face: VBoxContainer = ItemCards.face_of(card)
	var width: float = ItemCards.face_width()
	face.add_child(_cards.label(perk.category_name().to_upper(), 12, perk.category_color(), width))
	_cards.add_rule(face, perk.category_color().darkened(0.3))
	face.add_child(_cards.label(perk.description, 13, _cards.muted_color, width))
	return card


func _consumable_card(item: Vector2i) -> Control:
	if item == PlayerClass3D.NO_ITEM:
		var back: Control = _cards.make_card_back()
		back.modulate = Color(1, 1, 1, 0.6)
		return back
	var color: Color = Consumable.color_of(item)
	var card: Control = _cards.make_framed_card(ItemCards.FRAME_ITEM, Consumable.title_of(item))
	var face: VBoxContainer = ItemCards.face_of(card)
	var width: float = ItemCards.face_width()
	face.add_child(_cards.label(Consumable.kind_name(item), 12, color.lightened(0.2), width))
	_cards.add_rule(face, color.darkened(0.3))
	face.add_child(_cards.label(Consumable.text_of(item), 13, _cards.muted_color, width))
	_cards.add_spacer(face)
	face.add_child(_cards.label("Click to use" if _uses_mouse() else "RB to use", 13, HINT_COLOR, width))
	return card


## Perks can always be picked (to read); slots only with something in them.
func _can_pick(index: int) -> bool:
	return index < _perks.size() or player.consumables[index - _perks.size()] != PlayerClass3D.NO_ITEM


## On a controller, opening picks the first consumable (ready to use), or
## else the last perk.
func _first_pick() -> int:
	var slot: int = player.first_consumable()
	return _perks.size() + slot if slot >= 0 else _perks.size() - 1


# ===== LAYOUT =====

## Fan the perks out on the left, stand the slots on the right, lifting the
## picked card. `animate` eases them there.
func _layout(animate: bool = true) -> void:
	var card_size: Vector2 = ItemCards.FRAMED_SIZE
	var count: int = _perks.size()
	var hand_width: float = card_size.x * HAND_SCALE
	var step: float = minf(FAN_STEP, (FAN_MAX_WIDTH - hand_width) / maxi(count - 1, 1))
	var tilt: float = minf(FAN_TILT, FAN_MAX_TILT / maxi(count - 1, 1))
	var fan_width: float = hand_width + step * (count - 1) if count > 0 else 0.0
	var slot_width: float = card_size.x * SLOT_SCALE
	var slots: int = player.consumables.size()
	var slots_width: float = slot_width * slots + SLOT_SPACING * (slots - 1)
	var left: float = -(fan_width + (SLOT_GAP if count > 0 else 0.0) + slots_width) / 2.0
	for i in _shown.size():
		var picked: bool = i == _picked
		var x: float
		var bottom: float
		var card_scale: float
		var tilt_degrees: float = 0.0
		if i < count:
			var from_middle: float = i - (count - 1) / 2.0
			x = left + fan_width / 2.0 + from_middle * step
			if picked:
				card_scale = PICKED_SCALE
				bottom = -BOTTOM_MARGIN
			else:
				card_scale = HAND_SCALE
				bottom = card_size.y * HAND_SCALE * PEEK + from_middle * from_middle * FAN_ARC
				tilt_degrees = from_middle * tilt
		else:
			var slot: int = i - count
			x = left + fan_width + (SLOT_GAP if count > 0 else 0.0) + slot_width / 2.0 + slot * (slot_width + SLOT_SPACING)
			card_scale = SLOT_PICKED_SCALE if picked else SLOT_SCALE
			bottom = -BOTTOM_MARGIN
		var card: Control = _shown[i]
		card.z_index = PICKED_Z if picked else 0
		var to_position := Vector2(x - card.size.x / 2.0, bottom - card.size.y)
		if _tweens.has(card):
			_tweens[card].kill()
		if not animate:
			card.position = to_position
			card.scale = Vector2.ONE * card_scale
			card.rotation_degrees = tilt_degrees
			continue
		var tween: Tween = create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, ^"position", to_position, MOVE_TIME)
		tween.tween_property(card, ^"scale", Vector2.ONE * card_scale, MOVE_TIME)
		tween.tween_property(card, ^"rotation_degrees", tilt_degrees, MOVE_TIME)
		_tweens[card] = tween


func _pick(index: int) -> void:
	if index == _picked or (index >= 0 and not _can_pick(index)):
		return
	_picked = index
	_layout()


# ===== INPUT =====

## A controller flicks the right stick to pick, and Light or Interact uses
## a picked consumable. The mouse picks by hovering (see _on_card_input).
func _read_input() -> void:
	if _uses_mouse():
		return
	var stick: float = player.Input_Handler.get_aim_stick().x
	if _stick_held:
		_stick_held = absf(stick) > STICK_RESET
	elif absf(stick) >= STICK_FLICK:
		_stick_held = true
		_step_pick(1 if stick > 0.0 else -1)
	if _just_pressed(&"attack_light") or _just_pressed(&"interact"):
		_use(_picked)


## The next card that can be picked that way, if there is one.
func _step_pick(direction: int) -> void:
	var index: int = _picked
	while true:
		index += direction
		if index < 0 or index >= _shown.size():
			return
		if _can_pick(index):
			_pick(index)
			return


func _just_pressed(base: StringName) -> bool:
	var input_action: StringName = player.slot.action(base) if player.slot else base
	return InputMap.has_action(input_action) and Input.is_action_just_pressed(input_action)


## Use the consumable at card `index`, if that's what it is.
func _use(index: int) -> void:
	if index >= _perks.size() and index < _shown.size():
		player.use_consumable(index - _perks.size())


func _on_mouse_entered(index: int) -> void:
	_pick(index)


func _on_mouse_exited(index: int) -> void:
	if _picked == index:
		_pick(-1)


func _on_card_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_use(index)
