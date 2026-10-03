class_name PerkPicker3D extends CanvasLayer
## Full-screen perk cards, Rounds-style: the game is paused while one player
## picks from their three. Only that player's device (or, online, only their
## machine) can move between cards and take one; everyone else watches.
## Also shows who still has to visit their altar during the intermission.

## The picking player took card `index` of the hand they were shown.
signal chosen(index: int)

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

@onready var dim: ColorRect = $Dim
@onready var title: Label = $Dim/Layout/Title
@onready var hint: Label = $Dim/Layout/Hint
@onready var cards_row: HBoxContainer = $Dim/Layout/Cards
@onready var waiting_label: Label = $Waiting

var player: PlayerClass3D = null
var hand: Array[Perk] = []
var selected: int = 0
## Whether this machine controls the picking player (and so takes input).
var is_local: bool = false
var _cards: Array[PanelContainer] = []
## Each card sits in a plain holder: the row lays out the holders, so it
## doesn't undo the cards' scale and lift.
var _holders: Array[Control] = []
## The bar under the chosen card.
var _markers: Array[ColorRect] = []
var _input_delay: float = 0.0
var _highlight_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	dim.hide()
	waiting_label.hide()


func open(picking_player: PlayerClass3D, perks: Array[Perk], local: bool) -> void:
	player = picking_player
	hand = perks
	is_local = local
	selected = 1 if hand.size() > 2 else 0
	_input_delay = INPUT_DELAY
	var color: Color = player.slot.color if player.slot else Color.WHITE
	title.text = "Player %d, choose a perk" % (player.slot.index + 1 if player.slot else 1)
	title.add_theme_color_override("font_color", color)
	hint.text = "Left / Right to browse, Interact or Attack to take" if is_local \
			else "Waiting for them to choose..."
	_build_cards()
	_highlight()
	_highlight_tween.custom_step(HIGHLIGHT_TIME)  # Open already highlighted
	waiting_label.hide()
	dim.show()


## Showing a hand of cards to pick from.
func is_open() -> bool:
	return dim.visible


func close() -> void:
	player = null
	hand.clear()
	dim.hide()


## During the intermission, list who still has to pick (empty = hide).
func show_waiting(players: Array[PlayerClass3D]) -> void:
	if players.is_empty():
		waiting_label.hide()
		return
	var names: PackedStringArray = []
	for waiting: PlayerClass3D in players:
		names.append("P%d" % (waiting.slot.index + 1) if waiting.slot else String(waiting.name))
	waiting_label.text = "Visit your altar to choose a perk\nWaiting on: %s" % ", ".join(names)
	waiting_label.visible = not dim.visible


func _process(delta: float) -> void:
	if not dim.visible or not is_local or not player:
		return
	if _input_delay > 0.0:
		_input_delay -= delta
		return
	if _just_pressed(&"move_left"):
		_select(selected - 1)
	elif _just_pressed(&"move_right"):
		_select(selected + 1)
	elif _just_pressed(&"interact") or _just_pressed(&"attack") or _just_pressed(&"attack_left") or _just_pressed(&"attack_right"):
		chosen.emit(selected)


func _just_pressed(base: StringName) -> bool:
	var input_action: StringName = player.slot.action(base) if player.slot else base
	return InputMap.has_action(input_action) and Input.is_action_just_pressed(input_action)


func _select(index: int) -> void:
	if hand.is_empty():
		return
	var new_selected: int = wrapi(index, 0, hand.size())
	if new_selected == selected:
		return
	selected = new_selected
	_highlight()


func _highlight() -> void:
	var player_color: Color = player.slot.color if player and player.slot else Color.WHITE
	if _highlight_tween:
		_highlight_tween.kill()
	_highlight_tween = create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in _cards.size():
		var card: PanelContainer = _cards[i]
		var on: bool = i == selected
		card.pivot_offset = card.size / 2.0
		var rest: Vector2 = CARD_MARGIN / 2.0
		_highlight_tween.tween_property(card, "scale", Vector2.ONE * (SELECTED_SCALE if on else UNSELECTED_SCALE), HIGHLIGHT_TIME)
		_highlight_tween.tween_property(card, "position", rest - Vector2(0, SELECTED_LIFT if on else 0.0), HIGHLIGHT_TIME)
		_highlight_tween.tween_property(card, "modulate", Color.WHITE if on else UNSELECTED_DIM, HIGHLIGHT_TIME)
		var style: StyleBoxFlat = card.get_theme_stylebox("panel") as StyleBoxFlat
		style.border_color = player_color.lightened(0.25) if on else hand[i].category_color().darkened(0.2)
		style.set_border_width_all(8 if on else 3)
		style.shadow_color = Color(player_color, 0.6) if on else Color(0, 0, 0, 0)
		style.shadow_size = 24 if on else 0
		_markers[i].color = player_color.lightened(0.25)
		_markers[i].visible = on


func _build_cards() -> void:
	for holder: Control in _holders:
		holder.queue_free()
	_holders.clear()
	_cards.clear()
	_markers.clear()
	for i in hand.size():
		var holder := Control.new()
		holder.custom_minimum_size = CARD_SIZE + CARD_MARGIN
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cards_row.add_child(holder)
		_holders.append(holder)
		var card: PanelContainer = _make_card(hand[i])
		card.position = CARD_MARGIN / 2.0
		card.size = CARD_SIZE
		holder.add_child(card)
		_cards.append(card)
		# A bar under the chosen card, in the picker's color
		var marker := ColorRect.new()
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.size = Vector2(CARD_SIZE.x * 0.5, 8)
		marker.position = Vector2((holder.custom_minimum_size.x - marker.size.x) / 2.0, holder.custom_minimum_size.y + 4)
		marker.visible = false
		holder.add_child(marker)
		_markers.append(marker)
		# Keyboard/mouse players can also just point and click
		if is_local and player.Input_Handler and player.Input_Handler.uses_mouse():
			card.mouse_entered.connect(_select.bind(i))
			card.gui_input.connect(_on_card_input.bind(i))
		else:
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_card_input(event: InputEvent, index: int) -> void:
	if _input_delay <= 0.0 and event is InputEventMouseButton \
			and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected = index
		chosen.emit(index)


func _make_card(perk: Perk) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.1, 0.95)
	style.border_color = perk.category_color()
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(CARD_PADDING)
	card.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)

	var category := _label(perk.category_name().to_upper(), 16, perk.category_color())
	column.add_child(category)
	var name_label := _label(perk.title, 30, Color.WHITE)
	column.add_child(name_label)
	var rule := ColorRect.new()
	rule.color = perk.category_color().darkened(0.3)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	var description := _label(perk.description, 20, Color(0.85, 0.85, 0.85))
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(description)
	var owned: int = player.perks.count(perk)
	if owned > 0:
		column.add_child(_label("Owned x%d" % owned, 16, Color(0.95, 0.8, 0.4)))
	return card


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A fixed wrap width, or the label sizes itself as if it were one letter wide
	label.custom_minimum_size.x = CARD_SIZE.x - CARD_PADDING * 2.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	return label
