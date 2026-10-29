class_name PerkPicker3D extends CanvasLayer
## Perk cards, Rounds-style, for every player on this machine who's choosing
## at once: each gets their own hand, browsed with their own device. Remote
## players' cards are never shown. In the intermission the hands fill the
## (dimmed) screen side by side; a mid-round pick (a boss kill's reward)
## shows small at the bottom, so everyone else keeps playing.
## Also shows who still has to pick during the intermission.

## `player` took card `index` of the hand they were shown.
signal chosen(player: PlayerClass3D, index: int)

## Ignore input this long after opening, so the altar press doesn't also
## take a card.
const INPUT_DELAY := 0.35
const CARD_SIZE := Vector2(260, 340)
const CARD_PADDING := 18.0
## The chosen card grows, rises and glows in the player's color; the
## others shrink back into the dark.
const SELECTED_SCALE := 1.12
const UNSELECTED_SCALE := 0.92
const SELECTED_LIFT := 28.0
const UNSELECTED_DIM := Color(0.4, 0.4, 0.4)
const HIGHLIGHT_TIME := 0.12
## Room around each card for it to grow and rise into.
const CARD_MARGIN := Vector2(24, 48)
## How big the hands are drawn: one alone, two side by side, three or four
## in a 2x2 grid, and a mid-round pick at the bottom of the screen.
const SCALE_ONE := 1.0
const SCALE_TWO := 0.62
const SCALE_MANY := 0.48
const SCALE_COMPACT := 0.5
const HAND_GAP := 48.0
## A mid-round pick sits this far up from the bottom of the screen, or
## this far above the boss's health bar while it's showing.
const BOTTOM_MARGIN := 24.0
const ABOVE_BOSS_BAR := 12.0
## A hand's title, hint and spacing at scale 1, on top of its cards.
const HAND_CHROME_HEIGHT := 140.0
## Kept clear around the hands, plus room for the waiting line under them.
const SCREEN_MARGIN := 40.0
const WAITING_ROOM := 72.0
## A card's evolution hint (see PerkCatalog.evolution_hint).
const EVOLVE_COLOR := Color(1.0, 0.78, 0.25)

@onready var dim: ColorRect = $Dim
@onready var waiting_label: Label = $Waiting

## One player's open hand of cards.
class Hand:
	var player: PlayerClass3D
	var perks: Array[Perk] = []
	var selected: int = 0
	var input_delay: float = 0.0
	var ui_scale: float = 1.0
	var root: VBoxContainer
	var cards: Array[PanelContainer] = []
	var markers: Array[ColorRect] = []
	var tween: Tween

var _hands: Array[Hand] = []
## Intermission: hands fill the dimmed screen. Otherwise they're compact.
var _full_screen: bool = false
var _center: FitCenterContainer
var _grid: GridContainer
var _bottom: HBoxContainer
## The waiting line's place at the top of the screen, as laid out in the scene.
var _waiting_offsets: Vector2


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_center = FitCenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", int(HAND_GAP))
	_grid.add_theme_constant_override("v_separation", int(HAND_GAP))
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center.add_child(_grid)
	_bottom = HBoxContainer.new()
	_bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bottom.offset_bottom = -BOTTOM_MARGIN
	_bottom.add_theme_constant_override("separation", int(HAND_GAP))
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bottom)
	_waiting_offsets = Vector2(waiting_label.offset_top, waiting_label.offset_bottom)
	dim.hide()
	waiting_label.hide()


## Show `player` (on this machine) their cards.
func open(player: PlayerClass3D, perks: Array[Perk]) -> void:
	close(player)
	var hand := Hand.new()
	hand.player = player
	hand.perks = perks
	hand.selected = 1 if perks.size() > 2 else 0
	hand.input_delay = INPUT_DELAY
	_hands.append(hand)
	_relayout()


func close(player: PlayerClass3D) -> void:
	var hand: Hand = _hand_of(player)
	if not hand:
		return
	_hands.erase(hand)
	if hand.tween:
		hand.tween.kill()
	hand.root.queue_free()
	_relayout()


## Someone on this machine is looking at cards.
func is_open() -> bool:
	return not _hands.is_empty()


## Intermission (true): hands fill the dimmed screen. Otherwise (a mid-round
## pick) they sit small at the bottom.
func set_full_screen(full: bool) -> void:
	if _full_screen == full:
		return
	_full_screen = full
	_relayout()


## During the intermission or a draft, list who still has to pick under
## `heading` (empty = hide).
func show_waiting(players: Array[PlayerClass3D], heading: String = "Choose a perk at your altar") -> void:
	if players.is_empty():
		waiting_label.hide()
		return
	var names: PackedStringArray = []
	for waiting: PlayerClass3D in players:
		names.append(waiting.slot.label() if waiting.slot else String(waiting.name))
	waiting_label.text = "%s\nWaiting on: %s" % [heading, ", ".join(names)]
	waiting_label.show()


func _process(delta: float) -> void:
	_bottom.offset_bottom = -_bottom_clearance()
	for hand: Hand in _hands.duplicate():
		if not is_instance_valid(hand.player):
			continue
		if hand.input_delay > 0.0:
			hand.input_delay -= delta
			continue
		if _just_pressed(hand, &"move_left"):
			_select(hand, hand.selected - 1)
		elif _just_pressed(hand, &"move_right"):
			_select(hand, hand.selected + 1)
		elif _just_pressed(hand, &"interact") or _just_pressed(hand, &"attack") \
				or _just_pressed(hand, &"attack_light") or _just_pressed(hand, &"attack_heavy"):
			chosen.emit(hand.player, hand.selected)


## How far up from the bottom of the screen a mid-round pick sits: clear of
## the boss's health bar while it's showing.
func _bottom_clearance() -> float:
	var game: Game3D_Class = Global.Game3D
	var bar: Control = game.boss_health_bar.root if game and game.boss_health_bar else null
	if not bar or not bar.is_visible_in_tree():
		return BOTTOM_MARGIN
	var screen_height: float = get_viewport().get_visible_rect().size.y
	return maxf(screen_height - bar.get_global_rect().position.y + ABOVE_BOSS_BAR, BOTTOM_MARGIN)


func _just_pressed(hand: Hand, base: StringName) -> bool:
	var input_action: StringName = hand.player.slot.action(base) if hand.player.slot else base
	return InputMap.has_action(input_action) and Input.is_action_just_pressed(input_action)


func _hand_of(player: PlayerClass3D) -> Hand:
	for hand: Hand in _hands:
		if hand.player == player:
			return hand
	return null


func _select(hand: Hand, index: int) -> void:
	if hand.perks.is_empty():
		return
	var new_selected: int = wrapi(index, 0, hand.perks.size())
	if new_selected == hand.selected:
		return
	hand.selected = new_selected
	_highlight(hand)


# ===== LAYOUT =====

## Rebuild every hand at the size that fits how many are open.
func _relayout() -> void:
	var ui_scale: float = SCALE_COMPACT
	if _full_screen:
		ui_scale = SCALE_ONE if _hands.size() <= 1 else (SCALE_TWO if _hands.size() == 2 else SCALE_MANY)
	_grid.columns = 1 if _hands.size() <= 1 else 2
	ui_scale = minf(ui_scale, _fit_scale())
	_place_waiting_label()
	for hand: Hand in _hands:
		if hand.root:
			if hand.tween:
				hand.tween.kill()
			hand.root.queue_free()
		_build_hand(hand, ui_scale)
		(_grid as Container if _full_screen else _bottom as Container).add_child(hand.root)
		_highlight(hand)
		hand.tween.custom_step(HIGHLIGHT_TIME)  # Open already highlighted
	dim.visible = _full_screen and not _hands.is_empty()


## The biggest scale at which every open hand fits on screen (a big hand,
## like a draft's, would otherwise run off the sides), leaving room for
## the waiting line.
func _fit_scale() -> float:
	var most_cards: int = 1
	for hand: Hand in _hands:
		most_cards = maxi(most_cards, hand.perks.size())
	var columns: int = _grid.columns if _full_screen else maxi(_hands.size(), 1)
	var rows: int = ceili(_hands.size() / float(columns)) if _full_screen else 1
	# One hand at scale 1: its row of cards wide, and title + cards + hint tall
	var hand_size := Vector2(
		most_cards * (CARD_SIZE.x + CARD_MARGIN.x) + (most_cards - 1) * 36.0,
		CARD_SIZE.y + CARD_MARGIN.y + HAND_CHROME_HEIGHT)
	var room: Vector2 = get_viewport().get_visible_rect().size - Vector2(SCREEN_MARGIN * 2.0, SCREEN_MARGIN * 2.0 + WAITING_ROOM)
	room -= Vector2(columns - 1, rows - 1) * HAND_GAP
	return minf(room.x / (hand_size.x * columns), room.y / (hand_size.y * rows))


## The waiting line sits at the top of the screen, unless hands fill it;
## then it moves under them, clear of their titles.
func _place_waiting_label() -> void:
	var bottom: bool = _full_screen and not _hands.is_empty()
	waiting_label.anchor_top = 1.0 if bottom else 0.0
	waiting_label.anchor_bottom = 1.0 if bottom else 0.0
	waiting_label.offset_top = -WAITING_ROOM if bottom else _waiting_offsets.x
	waiting_label.offset_bottom = -12.0 if bottom else _waiting_offsets.y
	waiting_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM if bottom else VERTICAL_ALIGNMENT_TOP
	waiting_label.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END


func _build_hand(hand: Hand, ui_scale: float) -> void:
	var player: PlayerClass3D = hand.player
	var color: Color = player.slot.color if player.slot else Color.WHITE
	hand.ui_scale = ui_scale
	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", int(18 * ui_scale))
	hand.root = root

	var relic: bool = hand.perks.all(func(perk: Perk) -> bool: return perk.category == Perk.Category.RELIC)
	var title := _label("%s, choose a %s" % [player.slot.label() if player.slot else "Player 1", "relic" if relic else "perk"],
		int(44 * ui_scale), color, 0.0)
	title.add_theme_constant_override("outline_size", int(10 * ui_scale))
	root.add_child(title)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(36 * ui_scale))
	root.add_child(row)

	var uses_mouse: bool = player.Input_Handler and player.Input_Handler.uses_mouse()
	var hint_text: String = "A / D or point, click to take" if uses_mouse else "Left / Right to browse, Attack to take"
	if not _full_screen:
		hint_text += ", %s to put away" % ("R" if uses_mouse else "D-pad Up")
	var hint := _label(hint_text, int(20 * ui_scale), Color(0.8, 0.8, 0.8), 0.0)
	root.add_child(hint)

	hand.cards.clear()
	hand.markers.clear()
	var card_size: Vector2 = CARD_SIZE * ui_scale
	var margin: Vector2 = CARD_MARGIN * ui_scale
	for i in hand.perks.size():
		var holder := Control.new()
		holder.custom_minimum_size = card_size + margin
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(holder)
		var card: PanelContainer = _make_card(player, hand.perks[i], ui_scale)
		card.position = margin / 2.0
		card.size = card_size
		# It can grow while its text is still unwrapped; back to its own size
		card.reset_size.call_deferred()
		holder.add_child(card)
		hand.cards.append(card)
		# A bar under the chosen card, in the picker's color
		var marker := ColorRect.new()
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.size = Vector2(card_size.x * 0.5, 8 * ui_scale)
		marker.position = Vector2((holder.custom_minimum_size.x - marker.size.x) / 2.0, holder.custom_minimum_size.y + 4)
		marker.visible = false
		holder.add_child(marker)
		hand.markers.append(marker)
		# Keyboard/mouse players can also just point and click
		if uses_mouse:
			card.mouse_entered.connect(_select.bind(hand, i))
			card.gui_input.connect(_on_card_input.bind(hand, i))
		else:
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _highlight(hand: Hand) -> void:
	var player_color: Color = hand.player.slot.color if hand.player.slot else Color.WHITE
	if hand.tween:
		hand.tween.kill()
	hand.tween = create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var ui_scale: float = hand.ui_scale
	for i in hand.cards.size():
		var card: PanelContainer = hand.cards[i]
		var on: bool = i == hand.selected
		card.pivot_offset = card.size / 2.0
		var rest: Vector2 = CARD_MARGIN * ui_scale / 2.0
		hand.tween.tween_property(card, "scale", Vector2.ONE * (SELECTED_SCALE if on else UNSELECTED_SCALE), HIGHLIGHT_TIME)
		hand.tween.tween_property(card, "position", rest - Vector2(0, SELECTED_LIFT * ui_scale if on else 0.0), HIGHLIGHT_TIME)
		hand.tween.tween_property(card, "modulate", Color.WHITE if on else UNSELECTED_DIM, HIGHLIGHT_TIME)
		var style: StyleBoxFlat = card.get_theme_stylebox("panel") as StyleBoxFlat
		style.border_color = player_color.lightened(0.25) if on else hand.perks[i].category_color().darkened(0.2)
		style.set_border_width_all(maxi(1, int((8 if on else 3) * ui_scale)))
		style.shadow_color = Color(player_color, 0.6) if on else Color(0, 0, 0, 0)
		style.shadow_size = int(24 * ui_scale) if on else 0
		hand.markers[i].color = player_color.lightened(0.25)
		hand.markers[i].visible = on


func _on_card_input(event: InputEvent, hand: Hand, index: int) -> void:
	if hand.input_delay <= 0.0 and event is InputEventMouseButton \
			and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hand.selected = index
		chosen.emit(hand.player, index)


func _make_card(player: PlayerClass3D, perk: Perk, ui_scale: float) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE * ui_scale
	var padding: float = CARD_PADDING * ui_scale
	var wrap_width: float = CARD_SIZE.x * ui_scale - padding * 2.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.13, 0.96)
	style.border_color = perk.category_color()
	style.set_border_width_all(maxi(1, int(3 * ui_scale)))
	style.set_corner_radius_all(int(6 * ui_scale))
	style.set_content_margin_all(padding)
	card.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(14 * ui_scale))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)

	column.add_child(_label(perk.category_name().to_upper(), int(16 * ui_scale), perk.category_color(), wrap_width))
	column.add_child(_label(perk.title, int(30 * ui_scale), Color.WHITE, wrap_width))
	var rule := ColorRect.new()
	rule.color = perk.category_color().darkened(0.3)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	var description := _label(perk.description, int(20 * ui_scale), Color(0.85, 0.85, 0.85), wrap_width)
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(description)
	var catalog: PerkCatalog = Global.Game3D.perks.catalog if Global.Game3D else null
	var evolution: String = catalog.evolution_hint(perk) if catalog else ""
	if evolution != "":
		column.add_child(_label("Evolves:\n" + evolution, int(16 * ui_scale), EVOLVE_COLOR, wrap_width))
	var owned: int = player.perks.count(perk)
	if owned > 0:
		column.add_child(_label("Owned x%d" % owned, int(16 * ui_scale), Color(0.95, 0.8, 0.4), wrap_width))
	return card


## `wrap_width` > 0 wraps the text at that width (without one, a wrapping
## label sizes itself as if it were one letter wide).
func _label(text: String, size: int, color: Color, wrap_width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if wrap_width > 0.0:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = wrap_width
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", maxi(size, 8))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", maxi(1, int(4 * size / 20.0)))
	return label
