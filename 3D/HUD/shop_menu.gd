class_name ShopMenu3D extends CanvasLayer
## A shop altar's wares (see Altar3D.shop), as a popup in the middle of the
## screen for every player on this machine who's browsing one (side by
## side when several are; FitCenterContainer shrinks them to fit). Each is
## browsed with its owner's own device while everyone else keeps playing.
## Each section of offers (ShopOffer.SECTION_TITLES) is a row: the buyer's
## own kit upgrade and a breakable weapon, perks, bombs and flasks, a tower
## repair. Weapons, kits, bombs and flasks show a spinning preview, perks
## their card, a repair the tower's health. Browsing holds the player still
## (PlayerClass3D.is_perk_locked), so only this machine needs to know who's
## shopping; a buy goes to the server (Altar3D.buy). Game3D makes one.

## Ignore input this long after opening, so the interact press that opened
## it doesn't also close it.
const INPUT_DELAY := 0.3
const WEAPON_CARD_SIZE := Vector2(240, 290)
const PREVIEW_SIZE := Vector2i(180, 130)
const PERK_CARD_SIZE := Vector2(210, 250)
const THROWABLE_CARD_SIZE := Vector2(220, 290)
const UPGRADE_COLOR := Color(0.55, 1.0, 0.5)
const CARD_TINT := Color(0.62, 0.55, 0.52)
const WELL_COLOR := Color(0.07, 0.04, 0.03, 0.75)
const CARD_GAP := 14
const SHOP_GAP := 40
const UNAFFORDABLE := Color(1.0, 0.35, 0.3)
const SECTION_COLOR := Color(0.95, 0.8, 0.45)
## Cards that aren't picked fade back (more so if you can't afford them).
const UNSELECTED_DIM := 0.85
const UNAFFORDABLE_DIM := 0.75
const PREVIEW_SPIN := 1.2
const PREVIEW_FOV := 35.0
const COIN_ICON := preload("res://Assets/UI/icon_coin.png")
const GRIP_NAMES: Dictionary[Weapon3D.Grip, String] = {
	Weapon3D.Grip.MAIN_HAND: "One-handed",
	Weapon3D.Grip.OFF_HAND: "Off hand",
	Weapon3D.Grip.EITHER_HAND: "Either hand",
	Weapon3D.Grip.TWO_HANDED: "Two-handed",
}

## One drawn offer.
class Card:
	var panel: PanelContainer
	var price_label: Label
	var price: int
	## A weapon's spinning preview, if it has one.
	var spinner: Node3D
	## A repair's line on how its tower is doing, kept up to date.
	var tower_status: Label
	## The picked card (it draws the focus corners).
	var selected: bool = false

## One player's open shop.
class Stall:
	var player: PlayerClass3D
	var altar: Altar3D
	## Index into altar.offers.
	var selected: int = 0
	var input_delay: float = INPUT_DELAY
	var root: PanelContainer
	var coin_label: Label
	## altar.offers indices, one array per row (a kind of offer).
	var rows: Array[PackedInt32Array] = []
	## By offer index.
	var cards: Array[Card] = []
	## What it was last drawn from: the stock and the coins.
	var drawn_version: int = -1
	var drawn_coins: int = -1

var _stalls: Array[Stall] = []
var _row: HBoxContainer
## Looks come from the project theme (Assets/default_theme.tres), like the
## rest of the UI: the wooden panel, the focus corners round the picked
## card, and the theme's text colors (cards: see _card_style).
var _theme: Theme
var _text_color: Color
var _muted_color: Color
## Cards are dark against the wooden panel (the theme's dark inset, a text
## box's, darker still), and previews sit in a darker well inside them.
var _card_style: StyleBoxTexture
var _well_style: StyleBoxFlat


func _ready() -> void:
	layer = 9  # Under the perk cards
	_theme = ThemeDB.get_project_theme()
	if not _theme:
		_theme = ThemeDB.get_default_theme()
	_text_color = _theme.get_color(&"font_color", &"Label")
	_muted_color = _text_color.darkened(0.12)
	_card_style = (_theme.get_stylebox(&"normal", &"LineEdit") as StyleBoxTexture).duplicate() as StyleBoxTexture
	_card_style.modulate_color = CARD_TINT
	_card_style.content_margin_left = 12.0
	_card_style.content_margin_right = 12.0
	_card_style.content_margin_top = 10.0
	_card_style.content_margin_bottom = 12.0
	_well_style = StyleBoxFlat.new()
	_well_style.bg_color = WELL_COLOR
	_well_style.set_corner_radius_all(6)
	_well_style.set_content_margin_all(4.0)
	# Shrinks the popups if enough players are shopping to run them off screen
	var fit := FitCenterContainer.new()
	fit.set_anchors_preset(Control.PRESET_FULL_RECT)
	fit.margin = 24.0
	fit.vertical = 1  # Center
	fit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fit)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", SHOP_GAP)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fit.add_child(_row)


## Show `player` (on this machine) what `altar` sells.
func open(player: PlayerClass3D, altar: Altar3D) -> void:
	close(player)
	var stall := Stall.new()
	stall.player = player
	stall.altar = altar
	_stalls.append(stall)
	_redraw(stall)
	stall.selected = _first_affordable(stall)
	_highlight(stall)


func close(player: PlayerClass3D) -> void:
	var stall: Stall = _stall_of(player)
	if not stall:
		return
	_stalls.erase(stall)
	stall.root.queue_free()
	# The button that closed it (or bought the last thing) shouldn't also act
	if is_instance_valid(player) and player.Input_Handler:
		player.Input_Handler.release_all()


## `player` is browsing a shop on this machine.
func is_shopping(player: PlayerClass3D) -> bool:
	return _stall_of(player) != null


func _stall_of(player: PlayerClass3D) -> Stall:
	for stall: Stall in _stalls:
		if stall.player == player:
			return stall
	return null


func _process(delta: float) -> void:
	for stall: Stall in _stalls.duplicate():
		var player: PlayerClass3D = stall.player
		if not is_instance_valid(player) or not is_instance_valid(stall.altar) \
				or not stall.altar.can_shop(player) or stall.altar.offers.is_empty() \
				or player.holds_throwable() \
				or (Global.Game3D and Global.Game3D.perks.is_picking(player)):
			close(player)
			continue
		if stall.drawn_version != stall.altar.shop_version:
			_redraw(stall)
		elif stall.drawn_coins != player.coins_shown():
			_update_prices(stall)
		for card: Card in stall.cards:
			if card.spinner:
				card.spinner.rotate_y(PREVIEW_SPIN * delta)
			if card.tower_status:
				card.tower_status.text = _tower_status(stall.altar)
		if stall.input_delay > 0.0:
			stall.input_delay -= delta
			continue
		if _just_pressed(stall, &"move_left"):
			_step(stall, -1, 0)
		elif _just_pressed(stall, &"move_right"):
			_step(stall, 1, 0)
		elif _just_pressed(stall, &"move_up"):
			_step(stall, 0, -1)
		elif _just_pressed(stall, &"move_down"):
			_step(stall, 0, 1)
		elif _just_pressed(stall, &"interact") or _just_pressed(stall, &"open_perks"):
			close(player)
		elif _just_pressed(stall, &"attack") or _just_pressed(stall, &"attack_light") \
				or _just_pressed(stall, &"attack_heavy"):
			_buy(stall)


## Pause (Esc, or Start on a controller) leaves the shop instead of pausing.
## The pause menu listens in _unhandled_input, so taking it here stops it.
func _input(event: InputEvent) -> void:
	for stall: Stall in _stalls.duplicate():
		var pause_action: StringName = stall.player.slot.action(&"pause") if stall.player.slot else &"pause"
		if InputMap.has_action(pause_action) and event.is_action_pressed(pause_action):
			close(stall.player)
			get_viewport().set_input_as_handled()
			return


func _just_pressed(stall: Stall, base: StringName) -> bool:
	var input_action: StringName = stall.player.slot.action(base) if stall.player.slot else base
	return InputMap.has_action(input_action) and Input.is_action_just_pressed(input_action)


## Move the selection `across` within its row, or `down` to the next row
## (to about the same place along it).
func _step(stall: Stall, across: int, down: int) -> void:
	var at: Vector2i = _place_of(stall, stall.selected)
	if at.x < 0:
		return
	if down != 0:
		var row_index: int = wrapi(at.x + down, 0, stall.rows.size())
		var row: PackedInt32Array = stall.rows[row_index]
		var along: float = at.y / maxf(stall.rows[at.x].size() - 1, 1.0)
		stall.selected = row[roundi(along * (row.size() - 1))]
	else:
		var row: PackedInt32Array = stall.rows[at.x]
		stall.selected = row[wrapi(at.y + across, 0, row.size())]
	_highlight(stall)


## [row, place in row] of offer `index`, or (-1, -1).
func _place_of(stall: Stall, index: int) -> Vector2i:
	for r in stall.rows.size():
		var place: int = stall.rows[r].find(index)
		if place >= 0:
			return Vector2i(r, place)
	return Vector2i(-1, -1)


func _first_affordable(stall: Stall) -> int:
	for i in stall.altar.offers.size():
		if _can_buy(stall, stall.altar.offers[i]):
			return i
	return 0


## Whether the player in `stall` can pay for `offer` and has a use for it.
func _can_buy(stall: Stall, offer: ShopOffer) -> bool:
	return stall.player.coins >= stall.altar.price_of(offer, stall.player) \
		and stall.altar.is_useful_to(stall.player, offer)


func _select(stall: Stall, index: int) -> void:
	stall.selected = index
	_highlight(stall)


func _buy(stall: Stall) -> void:
	var offers: Array[ShopOffer] = stall.altar.offers
	if stall.selected >= offers.size():
		return
	if not _can_buy(stall, offers[stall.selected]):
		Sfx.play(&"hit_wall", stall.player.global_position)  # Can't afford it (or no use)
		return
	stall.altar.buy(stall.player, stall.selected)


# ===== DRAWING =====

func _redraw(stall: Stall) -> void:
	if stall.root:
		stall.root.queue_free()
	stall.drawn_version = stall.altar.shop_version
	stall.drawn_coins = stall.player.coins_shown()
	stall.cards.clear()
	stall.rows.clear()
	var player: PlayerClass3D = stall.player
	var color: Color = player.slot.color if player.slot else Color.WHITE
	var uses_mouse: bool = player.Input_Handler and player.Input_Handler.uses_mouse()

	stall.root = PanelContainer.new()  # The theme's wooden panel
	stall.root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(stall.root)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 12)
	stall.root.add_child(column)

	# Header: whose shop, and their coins
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)
	var who: String = player.slot.label() if player.slot else "Player 1"
	var title := _label("%s - Shop" % who, 30, color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_coin_icon())
	stall.coin_label = _label("%d" % stall.drawn_coins, 30, FlyingCoin3D.GOLD)
	header.add_child(stall.coin_label)

	# A row per section, in ShopOffer.ORDER (offers come grouped that way)
	var offers: Array[ShopOffer] = stall.altar.offers
	stall.cards.resize(offers.size())
	var i: int = 0
	while i < offers.size():
		var section: String = ShopOffer.SECTION_TITLES.get(offers[i].kind, "")
		column.add_child(_label(section.to_upper(), 22, SECTION_COLOR, 0.0, true))
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", CARD_GAP)
		column.add_child(row)
		var indices := PackedInt32Array()
		while i < offers.size() and ShopOffer.SECTION_TITLES.get(offers[i].kind, "") == section:
			var card: Card = _make_card(stall, offers[i])
			row.add_child(card.panel)
			stall.cards[i] = card
			indices.append(i)
			if uses_mouse:
				card.panel.mouse_entered.connect(_select.bind(stall, i))
				card.panel.gui_input.connect(_on_card_input.bind(stall, i))
			else:
				card.panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			i += 1
		stall.rows.append(indices)

	var hint: String = "WASD or point, click to buy, F or Esc to leave" if uses_mouse \
		else "D-pad to browse, Attack to buy, Interact to leave"
	column.add_child(_label(hint, 18, _text_color))
	stall.selected = clampi(stall.selected, 0, maxi(offers.size() - 1, 0))
	_update_prices(stall)


## The coins went up or down: recolor what's (un)affordable.
func _update_prices(stall: Stall) -> void:
	stall.drawn_coins = stall.player.coins_shown()
	stall.coin_label.text = "%d" % stall.drawn_coins
	for i in stall.cards.size():
		var card: Card = stall.cards[i]
		if card:
			card.price_label.add_theme_color_override("font_color",
				FlyingCoin3D.GOLD if _can_buy(stall, stall.altar.offers[i]) else UNAFFORDABLE)
	_highlight(stall)


## The picked card gets the theme's focus corners; the rest fade back.
func _highlight(stall: Stall) -> void:
	for i in stall.cards.size():
		var card: Card = stall.cards[i]
		if not card:
			continue
		card.selected = i == stall.selected
		var dim: float = 1.0 if card.selected else UNSELECTED_DIM
		if i >= stall.altar.offers.size() or not _can_buy(stall, stall.altar.offers[i]):
			dim *= UNAFFORDABLE_DIM
		card.panel.modulate = Color(dim, dim, dim)
		card.panel.queue_redraw()


## Drawn under the card's contents, but its corners sit outside the card.
func _draw_focus(card: Card) -> void:
	if card.selected:
		_theme.get_stylebox(&"focus", &"Button").draw(card.panel.get_canvas_item(), Rect2(Vector2.ZERO, card.panel.size))


func _on_card_input(event: InputEvent, stall: Stall, index: int) -> void:
	if stall.input_delay <= 0.0 and event is InputEventMouseButton \
			and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		stall.selected = index
		_buy(stall)


func _make_card(stall: Stall, offer: ShopOffer) -> Card:
	var card := Card.new()
	card.price = stall.altar.price_of(offer, stall.player)
	card.panel = PanelContainer.new()
	card.panel.add_theme_stylebox_override(&"panel", _card_style)
	card.panel.draw.connect(_draw_focus.bind(card))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	card.panel.add_child(column)
	match offer.kind:
		ShopOffer.Kind.WEAPON:
			card.panel.custom_minimum_size = WEAPON_CARD_SIZE
			_fill_weapon_card(card, column, stall.player, stall.altar, offer)
		ShopOffer.Kind.KIT:
			card.panel.custom_minimum_size = WEAPON_CARD_SIZE
			_fill_kit_card(card, column, stall.player, stall.altar, offer)
		ShopOffer.Kind.THROWABLE:
			card.panel.custom_minimum_size = THROWABLE_CARD_SIZE
			_fill_throwable_card(card, column, stall.player, stall.altar, offer)
		ShopOffer.Kind.PERK:
			card.panel.custom_minimum_size = PERK_CARD_SIZE
			_fill_perk_card(column, stall.player, stall.altar, offer)
		ShopOffer.Kind.REPAIR:
			card.panel.custom_minimum_size = PERK_CARD_SIZE
			_fill_repair_card(card, column, stall.altar)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var price_row := HBoxContainer.new()
	price_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_row.alignment = BoxContainer.ALIGNMENT_CENTER
	price_row.add_theme_constant_override("separation", 6)
	price_row.add_child(_coin_icon())
	card.price_label = _label("%d" % card.price, 26, FlyingCoin3D.GOLD)
	price_row.add_child(card.price_label)
	column.add_child(price_row)
	return card


func _fill_weapon_card(card: Card, column: VBoxContainer, player: PlayerClass3D, altar: Altar3D, offer: ShopOffer) -> void:
	var info: Array = Altar3D.weapon_info(offer.scene)
	_add_preview(card, column, player, altar, offer)
	column.add_child(_label(WeaponRarity.NAMES[offer.rarity].to_upper(), 16, _rarity_color(offer.rarity)))
	column.add_child(_label(info[0], 24, _text_color, WEAPON_CARD_SIZE.x - 24))
	var details: String = GRIP_NAMES.get(info[1], "")
	if info[2] != "":
		details += "  -  Heavy: %s" % info[2]
	column.add_child(_label(details, 16, _muted_color, WEAPON_CARD_SIZE.x - 24))
	column.add_child(_label("Breaks with use", 16, UNAFFORDABLE.lightened(0.3), WEAPON_CARD_SIZE.x - 24))


## The buyer's own kit, one or two rarities up: it never breaks, and each
## rarity hits harder (WeaponRarity.KIT_POWER).
func _fill_kit_card(card: Card, column: VBoxContainer, player: PlayerClass3D, altar: Altar3D, offer: ShopOffer) -> void:
	var text_width: float = WEAPON_CARD_SIZE.x - 24
	_add_preview(card, column, player, altar, offer)
	var kit_name: String = Roster.kit_name_of(player.slot.character if player.slot else 0)
	if not player.can_upgrade_kit():
		column.add_child(_label("YOUR KIT", 16, _rarity_color(player.kit_rarity)))
		column.add_child(_label(kit_name, 24, _text_color, text_width))
		column.add_child(_label("Fully upgraded", 16, _muted_color, text_width))
		return
	var after: int = altar.kit_rarity_after(offer, player)
	var jump: String = "  x2!" if after - player.kit_rarity > 1 else ""
	column.add_child(_label("%s -> %s%s" % [WeaponRarity.NAMES[player.kit_rarity].to_upper(),
		WeaponRarity.NAMES[after].to_upper(), jump], 16, _rarity_color(after)))
	column.add_child(_label(kit_name, 24, _text_color, text_width))
	var bonus: int = roundi((WeaponRarity.KIT_POWER[after] - 1.0) * 100.0)
	column.add_child(_label("Yours for good  -  +%d%% damage" % bonus, 16, UPGRADE_COLOR, text_width))


func _fill_throwable_card(card: Card, column: VBoxContainer, player: PlayerClass3D, altar: Altar3D, offer: ShopOffer) -> void:
	var text_width: float = THROWABLE_CARD_SIZE.x - 24
	_add_preview(card, column, player, altar, offer)
	var is_bomb: bool = offer.throwable_kind == Throwable3D.Kind.BOMB
	column.add_child(_label("BOMB" if is_bomb else "FLASK", 16, Altar3D.throwable_color(offer).lightened(0.2)))
	column.add_child(_label(Altar3D.throwable_title(offer), 22, _text_color, text_width))
	column.add_child(_label(_throwable_text(offer), 16, _muted_color, text_width))


## What a bomb or flask does, in a line.
func _throwable_text(offer: ShopOffer) -> String:
	if offer.throwable_kind == Throwable3D.Kind.BOMB:
		var fuse: String = "Throw it within %ds!" % roundi(Throwable3D.BOMB_FUSE)
		match offer.variant:
			Bomb3D.Type.FIRE:
				return "Sets the blast on fire. " + fuse
			Bomb3D.Type.POISON:
				return "Poisons the blast. " + fuse
			Bomb3D.Type.ICE:
				return "Chills the blast. " + fuse
		return fuse
	var flask: Dictionary = Potion.large(offer.variant)
	if flask.get("allies", false):
		return "Shatters where it lands, healing your team."
	return "Shatters where it lands, splashing enemies%s." % (" and leaving a puddle" if flask.has("patch") else "")


## An offer's model spinning in the card, sunk into a dark well.
func _add_preview(card: Card, column: VBoxContainer, player: PlayerClass3D, altar: Altar3D, offer: ShopOffer) -> void:
	var preview: SubViewportContainer = _make_preview(card, player, altar, offer)
	if not preview:
		return
	var inset := PanelContainer.new()
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_theme_stylebox_override(&"panel", _well_style)
	inset.add_child(preview)
	column.add_child(inset)


func _rarity_color(rarity: int) -> Color:
	return Color.WHITE if rarity <= WeaponRarity.Tier.COMMON \
		else Color(WeaponRarity.COLORS[rarity], 1.0).lightened(0.2)


func _fill_perk_card(column: VBoxContainer, player: PlayerClass3D, altar: Altar3D, offer: ShopOffer) -> void:
	var perk: Perk = altar.perk_of(offer)
	if not perk:
		return
	var text_width: float = PERK_CARD_SIZE.x - 24
	column.add_child(_label(perk.category_name().to_upper(), 16, perk.category_color(), text_width))
	column.add_child(_label(perk.title, 22, _text_color, text_width))
	var rule := ColorRect.new()
	rule.color = perk.category_color().darkened(0.3)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	column.add_child(_label(perk.description, 17, _muted_color, text_width))
	var owned: int = player.perks.count(perk)
	if owned > 0:
		column.add_child(_label("Owned x%d" % owned, 16, Color(0.95, 0.8, 0.4), text_width))


func _fill_repair_card(card: Card, column: VBoxContainer, altar: Altar3D) -> void:
	var text_width: float = PERK_CARD_SIZE.x - 24
	var color: Color = Players.TEAM_COLORS[altar.owner_team % Players.TEAM_COLORS.size()] if altar.owner_team >= 0 else Color.WHITE
	column.add_child(_label("TOWER", 16, color, text_width))
	column.add_child(_label(altar.offer_title(ShopOffer.repair()), 22, _text_color, text_width))
	var rule := ColorRect.new()
	rule.color = color.darkened(0.3)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	column.add_child(_label("Puts back %d%% of your most damaged tower's health." % roundi(altar.repair_share * 100.0),
		15, _muted_color, text_width))
	card.tower_status = _label(_tower_status(altar), 17, Color(0.95, 0.8, 0.4), text_width)
	column.add_child(card.tower_status)


## How the tower a repair at `altar` would fix is doing.
func _tower_status(altar: Altar3D) -> String:
	var tower: Tower3D = altar.tower_to_repair()
	if not tower:
		return "Your towers are at full health"
	return "%s: %d / %d" % [Tower3D.NAMES[tower.kind], ceili(tower.hp), roundi(tower.max_hp)]


## The offer, spinning in a little world of its own, framed to fit.
func _make_preview(card: Card, player: PlayerClass3D, altar: Altar3D, offer: ShopOffer) -> SubViewportContainer:
	var model: Node3D = altar.make_preview(offer, player)
	if not model:
		return null
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = PREVIEW_SIZE
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.size = PREVIEW_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.9, 0.85, 0.8)
	environment.ambient_light_energy = 0.6
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(30.0), 0.0)
	light.light_energy = 1.4
	viewport.add_child(light)
	card.spinner = Node3D.new()
	viewport.add_child(card.spinner)
	card.spinner.add_child(model)
	# Center it on the spinner and back the camera off until it all fits
	var box: AABB = _bounds(model)
	model.position = -box.get_center()
	var camera := Camera3D.new()
	camera.fov = PREVIEW_FOV
	var radius: float = maxf(box.size.length() / 2.0, 0.1)
	var distance: float = radius / tan(deg_to_rad(PREVIEW_FOV) / 2.0) * 1.05
	var eye := Vector3(0, radius * 0.25, distance)
	camera.transform = Transform3D(Basis.looking_at(-eye), eye)
	viewport.add_child(camera)
	return container


## Everything `root` draws, in its own space.
func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first: bool = true
	for node: Node in root.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		var local: Transform3D = _transform_to(root, visual)
		var part: AABB = local * visual.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box if not first else AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)


## `node`'s transform in `root`'s space (works outside the tree too).
func _transform_to(root: Node3D, node: Node3D) -> Transform3D:
	var xform: Transform3D = Transform3D.IDENTITY
	var current: Node = node
	while current and current != root:
		if current is Node3D:
			xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform


func _coin_icon() -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = COIN_ICON
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


## `wrap_width` > 0 wraps the text at that width; `left` aligns it left.
func _label(text: String, size: int, color: Color, wrap_width: float = 0.0, left: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_CENTER
	if wrap_width > 0.0:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = wrap_width
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	# The theme's dark-brown outline, a little thicker on big text
	label.add_theme_constant_override("outline_size", maxi(4, int(size / 5.0)))
	return label
