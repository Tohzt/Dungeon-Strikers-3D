class_name ShopMenu3D extends CanvasLayer
## A shop altar's wares for one player (each has their own stock, see
## Altar3D.offers_for), as a popup in the middle of the
## screen for every player on this machine who's browsing one (side by
## side when several are; FitCenterContainer shrinks them to fit). Each is
## browsed with its owner's own device while everyone else keeps playing.
## Each section of offers (ShopOffer.SECTION_TITLES) is a tab, one shown at
## a time so the cards stay big: the buyer's own kit upgrade and a
## breakable weapon, perks, bombs and flasks, a tower repair. Left/right
## browses a tab, up/down switches tabs. A strip under the title shows how
## far the buyer's kit is upgraded. Weapons, kits, bombs and flasks show a
## spinning preview, perks
## their card, a repair the tower's health. Browsing holds the player still
## (PlayerClass3D.is_perk_locked), so only this machine needs to know who's
## shopping; a buy goes to the server (Altar3D.buy), and once it's sold
## (Altar3D._sold) the shop closes. Game3D makes one.

## Ignore input this long after opening, so the interact press that opened
## it doesn't also close it.
const INPUT_DELAY := 0.3
## Every card is this size, so switching tabs doesn't resize the shop.
const CARD_SIZE := ItemCards.CARD_SIZE
const CARD_TEXT_WIDTH := ItemCards.CARD_TEXT_WIDTH
const UPGRADE_COLOR := Color(0.55, 1.0, 0.5)
const CARD_GAP := 14
const SHOP_GAP := 40
const UNAFFORDABLE := ItemCards.WARNING_COLOR
const SECTION_COLOR := Color(0.95, 0.8, 0.45)
## What each tab (ShopOffer.SECTION_TITLES) is for, under the tabs.
const SECTION_BLURBS: Dictionary[String, String] = {
	"Weapons": "Upgrade your own kit for good, or buy a weapon that breaks with use.",
	"Perks": "Boosts that last for the rest of the match. Pick one per restock.",
	"Bombs & Flasks": "Goes in a consumable slot, to throw when you need it (hold G / D-pad Down).",
	"Towers": "Patch up your team's towers.",
}
## The kit strip's rarity pips.
const PIP_SIZE := Vector2(16, 16)
const EMPTY_PIP := Color(1, 1, 1, 0.15)
## An unpicked tab's text.
const TAB_DIM := 0.6
## Cards that aren't picked fade back (more so if you can't afford them).
const UNSELECTED_DIM := 0.85
const UNAFFORDABLE_DIM := 0.75
const COIN_ICON := preload("res://Assets/UI/coin.png")
## How big the coin icon is drawn in the UI (the texture is twice that, so
## it stays sharp in 3D and on big windows).
const COIN_ICON_SIZE := Vector2(26, 28)
## One drawn offer.
class Card:
	var panel: PanelContainer
	var price_label: Label
	var price: int
	## A weapon's spinning preview, if it has one.
	var spinner: Node3D
	## A repair's line on how its tower is doing, kept up to date.
	var tower_status: Label
	## The picked card (it draws the focus frame).
	var selected: bool = false

## One player's open shop.
class Stall:
	var player: PlayerClass3D
	var altar: Altar3D
	## The player's own stock at the altar, as last drawn.
	var offers: Array[ShopOffer] = []
	## Index into offers.
	var selected: int = 0
	var input_delay: float = INPUT_DELAY
	var root: PanelContainer
	var coin_label: Label
	var restock_label: Label
	## offers indices, one array per tab (a section).
	var rows: Array[PackedInt32Array] = []
	## Per tab: its button, its row of cards, its section title.
	var tabs: Array[PanelContainer] = []
	var pages: Array[HBoxContainer] = []
	var sections: Array[String] = []
	var blurb: Label
	## By offer index.
	var cards: Array[Card] = []
	## What it was last drawn from: the stock and the coins.
	var drawn_version: int = -1
	var drawn_coins: int = -1

var _stalls: Array[Stall] = []
var _row: HBoxContainer
## Draws the cards, in the project theme's look (see ItemCards).
var _cards := ItemCards.new()
var _theme: Theme = _cards.theme
var _text_color: Color = _cards.text_color
var _muted_color: Color = _cards.muted_color


func _ready() -> void:
	layer = 9  # Under the perk cards
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
				or not stall.altar.can_shop(player) or stall.altar.offers_for(player).is_empty() \
				or player.holds_throwable() \
				or (Global.Game3D and Global.Game3D.perks.is_picking(player)):
			close(player)
			continue
		if stall.drawn_version != stall.altar.stock_version(player):
			_redraw(stall)
		elif stall.drawn_coins != player.coins_shown():
			_update_prices(stall)
		stall.restock_label.text = _restock_text(stall.altar)
		for card: Card in stall.cards:
			if card.spinner:
				card.spinner.rotate_y(ItemCards.PREVIEW_SPIN * delta)
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


## Move the selection `across` within its tab, or `down` to the next tab
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
	for i in stall.offers.size():
		if _can_buy(stall, stall.offers[i]):
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
	var offers: Array[ShopOffer] = stall.offers
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
	stall.drawn_version = stall.altar.stock_version(stall.player)
	stall.offers = stall.altar.offers_for(stall.player)
	stall.drawn_coins = stall.player.coins_shown()
	stall.cards.clear()
	stall.rows.clear()
	var player: PlayerClass3D = stall.player
	var color: Color = player.slot.color if player.slot else Color.WHITE
	var uses_mouse: bool = player.Input_Handler and player.Input_Handler.uses_mouse()

	stall.root = PanelContainer.new()  # The theme's stone panel
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
	stall.restock_label = _label(_restock_text(stall.altar), 18, _muted_color)
	header.add_child(stall.restock_label)
	header.add_child(coin_icon())
	stall.coin_label = _label("%d" % stall.drawn_coins, 30, FlyingCoin3D.GOLD)
	header.add_child(stall.coin_label)

	column.add_child(_kit_strip(player))

	# A tab per section, in ShopOffer.ORDER (offers come grouped that way)
	var tab_bar := HBoxContainer.new()
	tab_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab_bar.add_theme_constant_override("separation", 6)
	column.add_child(tab_bar)
	stall.blurb = _label("", 18, _muted_color)
	column.add_child(stall.blurb)
	var page_holder := VBoxContainer.new()  # Only the open tab's row shows
	page_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(page_holder)
	stall.tabs.clear()
	stall.pages.clear()
	stall.sections.clear()
	var offers: Array[ShopOffer] = stall.offers
	stall.cards.resize(offers.size())
	var most_cards: int = 1
	var i: int = 0
	while i < offers.size():
		var section: String = ShopOffer.SECTION_TITLES.get(offers[i].kind, "")
		var tab_index: int = stall.tabs.size()
		var tab: PanelContainer = _make_tab(section)
		tab_bar.add_child(tab)
		if uses_mouse:
			tab.gui_input.connect(_on_tab_input.bind(stall, tab_index))
		else:
			tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var page := HBoxContainer.new()
		page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.alignment = BoxContainer.ALIGNMENT_CENTER
		page.add_theme_constant_override("separation", CARD_GAP)
		page_holder.add_child(page)
		var indices := PackedInt32Array()
		while i < offers.size() and ShopOffer.SECTION_TITLES.get(offers[i].kind, "") == section:
			var card: Card = _make_card(stall, offers[i])
			page.add_child(card.panel)
			stall.cards[i] = card
			indices.append(i)
			if uses_mouse:
				card.panel.mouse_entered.connect(_select.bind(stall, i))
				card.panel.gui_input.connect(_on_card_input.bind(stall, i))
			else:
				card.panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			i += 1
		most_cards = maxi(most_cards, indices.size())
		stall.rows.append(indices)
		stall.tabs.append(tab)
		stall.pages.append(page)
		stall.sections.append(section)
	# As big as the fullest tab, so switching tabs doesn't resize the shop
	var tallest: float = CARD_SIZE.y
	for page: HBoxContainer in stall.pages:
		tallest = maxf(tallest, page.get_combined_minimum_size().y)
	page_holder.custom_minimum_size = Vector2(most_cards * CARD_SIZE.x + (most_cards - 1) * CARD_GAP, tallest)
	stall.blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stall.blurb.custom_minimum_size.x = page_holder.custom_minimum_size.x

	var hint: String = "A/D or point to browse, W/S or click a tab to switch, click to buy, F or Esc to leave" if uses_mouse \
		else "D-pad left/right to browse, up/down to switch tab, Attack to buy, Interact to leave"
	column.add_child(_label(hint, 16, _muted_color, page_holder.custom_minimum_size.x))
	stall.selected = clampi(stall.selected, 0, maxi(offers.size() - 1, 0))
	_update_prices(stall)


## When the altar restocks next (every player's stock at once).
func _restock_text(altar: Altar3D) -> String:
	return "New stock in %ds" % ceili(altar.restock_left) if altar.shop_restock_time > 0.0 else ""


## The coins went up or down: recolor what's (un)affordable.
func _update_prices(stall: Stall) -> void:
	stall.drawn_coins = stall.player.coins_shown()
	stall.coin_label.text = "%d" % stall.drawn_coins
	for i in stall.cards.size():
		var card: Card = stall.cards[i]
		if card and not stall.offers[i].locked:  # "Next restock" stays muted
			card.price_label.add_theme_color_override("font_color",
				FlyingCoin3D.GOLD if _can_buy(stall, stall.offers[i]) else UNAFFORDABLE)
	_highlight(stall)


## The picked card gets the theme's focus frame; the rest fade back. Only
## the picked card's tab is open.
func _highlight(stall: Stall) -> void:
	var open_tab: int = maxi(_place_of(stall, stall.selected).x, 0)
	for t in stall.tabs.size():
		var is_open: bool = t == open_tab
		stall.pages[t].visible = is_open
		stall.tabs[t].add_theme_stylebox_override(&"panel", _theme.get_stylebox(&"normal" if is_open else &"disabled", &"Button"))
		var dim: float = 1.0 if is_open else TAB_DIM
		stall.tabs[t].modulate = Color(dim, dim, dim)
	if open_tab < stall.sections.size():
		stall.blurb.text = SECTION_BLURBS.get(stall.sections[open_tab], "")
	for i in stall.cards.size():
		var card: Card = stall.cards[i]
		if not card:
			continue
		card.selected = i == stall.selected
		var dim: float = 1.0 if card.selected else UNSELECTED_DIM
		if i >= stall.offers.size() or not _can_buy(stall, stall.offers[i]):
			dim *= UNAFFORDABLE_DIM
		card.panel.modulate = Color(dim, dim, dim)
		card.panel.queue_redraw()


## Drawn under the card's contents, but its corners sit outside the card.
func _draw_focus(card: Card) -> void:
	if card.selected:
		_cards.draw_focus(card.panel)


## Clicking a tab opens it, picking the first thing in it.
func _on_tab_input(event: InputEvent, stall: Stall, tab_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and tab_index < stall.rows.size() and not stall.rows[tab_index].is_empty():
		_select(stall, stall.rows[tab_index][0])


## A tab's button: the section's name, with how many offers it holds.
func _make_tab(section: String) -> PanelContainer:
	var tab := PanelContainer.new()
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_child(_label(section.to_upper(), 20, SECTION_COLOR))
	return tab


## "Your kit: Sword" with a pip per rarity (lit up to the kit's), and what
## the upgrades so far are worth.
func _kit_strip(player: PlayerClass3D) -> Control:
	var strip := HBoxContainer.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_theme_constant_override("separation", 8)
	var kit_name: String = Roster.kit_name_of(player.slot.character if player.slot else 0)
	strip.add_child(_label("Your kit: %s" % kit_name, 18, _text_color))
	var pips := HBoxContainer.new()
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.add_theme_constant_override("separation", 4)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for tier in WeaponRarity.Tier.size():
		var pip := ColorRect.new()
		pip.custom_minimum_size = PIP_SIZE
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.color = _rarity_color(tier) if tier <= player.kit_rarity else EMPTY_PIP
		pips.add_child(pip)
	strip.add_child(pips)
	var rarity: int = player.kit_rarity
	var status: String = WeaponRarity.NAMES[rarity]
	if rarity > WeaponRarity.Tier.COMMON:
		status += "  +%d%% damage" % roundi((WeaponRarity.KIT_POWER[rarity] - 1.0) * 100.0)
	if rarity >= WeaponRarity.Tier.LEGENDARY:
		status += "  (max)"
	strip.add_child(_label(status, 18, _rarity_color(rarity)))
	return strip


func _on_card_input(event: InputEvent, stall: Stall, index: int) -> void:
	if stall.input_delay <= 0.0 and event is InputEventMouseButton \
			and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		stall.selected = index
		_buy(stall)


func _make_card(stall: Stall, offer: ShopOffer) -> Card:
	var card := Card.new()
	card.price = stall.altar.price_of(offer, stall.player)
	card.panel = _cards.make_card()
	card.panel.draw.connect(_draw_focus.bind(card))
	var column: VBoxContainer = ItemCards.column_of(card.panel)
	match offer.kind:
		ShopOffer.Kind.WEAPON:
			_fill_weapon_card(card, column, stall.player, stall.altar, offer)
		ShopOffer.Kind.KIT:
			_fill_kit_card(card, column, stall.player, stall.altar, offer)
		ShopOffer.Kind.THROWABLE:
			_fill_throwable_card(card, column, stall.player, stall.altar, offer)
		ShopOffer.Kind.PERK:
			_fill_perk_card(column, stall.player, stall.altar, offer)
		ShopOffer.Kind.REPAIR:
			_fill_repair_card(card, column, stall.altar)
	_cards.add_spacer(column)
	var price_row := HBoxContainer.new()
	price_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_row.alignment = BoxContainer.ALIGNMENT_CENTER
	price_row.add_theme_constant_override("separation", 6)
	if offer.sold:
		card.price_label = _label("SOLD", 26, UNAFFORDABLE)
	elif offer.locked:
		card.price_label = _label("Next restock", 22, _muted_color)
	else:
		price_row.add_child(coin_icon())
		card.price_label = _label("%d" % card.price, 26, FlyingCoin3D.GOLD)
	price_row.add_child(card.price_label)
	column.add_child(price_row)
	return card


func _fill_weapon_card(card: Card, column: VBoxContainer, player: PlayerClass3D, altar: Altar3D, offer: ShopOffer) -> void:
	_add_preview(card, column, player, altar, offer)
	_cards.fill_weapon(column, offer.scene, "NEW WEAPON  -  %s" % WeaponRarity.NAMES[offer.rarity].to_upper(),
		_rarity_color(offer.rarity))
	column.add_child(_label("Breaks with use", 16, UNAFFORDABLE.lightened(0.3), CARD_TEXT_WIDTH))


## The buyer's own kit, one or two rarities up: it never breaks, and each
## rarity hits harder (WeaponRarity.KIT_POWER).
func _fill_kit_card(card: Card, column: VBoxContainer, player: PlayerClass3D, altar: Altar3D, offer: ShopOffer) -> void:
	var text_width: float = CARD_TEXT_WIDTH
	_add_preview(card, column, player, altar, offer)
	var kit_name: String = Roster.kit_name_of(player.slot.character if player.slot else 0)
	if not player.can_upgrade_kit():
		column.add_child(_label("YOUR KIT", 16, _rarity_color(player.kit_rarity)))
		column.add_child(_label(kit_name, 24, _text_color, text_width))
		column.add_child(_label("Fully upgraded", 16, _muted_color, text_width))
		return
	var after: int = altar.kit_rarity_after(offer, player)
	var jump: String = "  x2!" if after - player.kit_rarity > 1 else ""
	column.add_child(_label("KIT UPGRADE%s" % jump, 16, UPGRADE_COLOR))
	column.add_child(_label("%s -> %s" % [WeaponRarity.NAMES[player.kit_rarity].to_upper(),
		WeaponRarity.NAMES[after].to_upper()], 16, _rarity_color(after)))
	column.add_child(_label(kit_name, 24, _text_color, text_width))
	var bonus: int = roundi((WeaponRarity.KIT_POWER[after] - 1.0) * 100.0)
	column.add_child(_label("+%d%% damage, for good" % bonus, 16, UPGRADE_COLOR, text_width))


func _fill_throwable_card(card: Card, column: VBoxContainer, player: PlayerClass3D, altar: Altar3D, offer: ShopOffer) -> void:
	_add_preview(card, column, player, altar, offer)
	_cards.fill_throwable(column, offer)


## An offer's model spinning in the card, sunk into a dark well.
func _add_preview(card: Card, column: VBoxContainer, player: PlayerClass3D, altar: Altar3D, offer: ShopOffer) -> void:
	card.spinner = _cards.add_preview(column, altar.make_preview(offer, player))


func _rarity_color(rarity: int) -> Color:
	return ItemCards.rarity_color(rarity)


func _fill_perk_card(column: VBoxContainer, player: PlayerClass3D, altar: Altar3D, offer: ShopOffer) -> void:
	var perk: Perk = altar.perk_of(offer)
	if not perk:
		return
	_cards.fill_perk(column, perk)
	var owned: int = player.perks.count(perk)
	if owned > 0:
		column.add_child(_label("Owned x%d" % owned, 16, Color(0.95, 0.8, 0.4), CARD_TEXT_WIDTH))


func _fill_repair_card(card: Card, column: VBoxContainer, altar: Altar3D) -> void:
	var text_width: float = CARD_TEXT_WIDTH
	var color: Color = Players.TEAM_COLORS[altar.owner_team % Players.TEAM_COLORS.size()] if altar.owner_team >= 0 else Color.WHITE
	column.add_child(_label("TOWER", 16, color, text_width))
	column.add_child(_label(altar.offer_title(ShopOffer.repair()), 22, _text_color, text_width))
	_cards.add_rule(column, color.darkened(0.3))
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


## A coin icon for a row of UI (the shop's prices, the HUD's coin count).
static func coin_icon() -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = COIN_ICON
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = COIN_ICON_SIZE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _label(text: String, size: int, color: Color, wrap_width: float = 0.0, left: bool = false) -> Label:
	return _cards.label(text, size, color, wrap_width, left)
