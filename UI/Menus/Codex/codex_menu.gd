class_name CodexMenu extends Control
## The Codex, opened from the title screen: every weapon, perk, bomb, flask
## and potion in the game on shop-style cards (ItemCards), a tab per kind.
## Only the open tab's cards are built, so there are never more spinning
## previews than one page's worth.
##
## Browse with the mouse, or a controller / the keyboard: the arrows move
## between cards, LB / RB (or Q / E) switch tab, B or Esc goes back.

const MAIN_MENU := "res://UI/Menus/MainMenu/main_menu.tscn"
## What altars stock comes from here (its tiers and skull rewards).
const ALTAR_SCENE := "res://Items/Altar/Altar.tscn"
const CARD_GAP := 14
## Room the page keeps either side of the card grid.
const SIDE_ROOM := 120.0
const SIGNATURE_COLOR := Color(0.95, 0.8, 0.45)
const RELIC_NOTE_COLOR := Color(1.0, 0.78, 0.25)
const EVOLVE_COLOR := Color(0.95, 0.8, 0.4)
const POTION_COLOR := Color(1.0, 0.55, 0.65)

enum Tab { WEAPONS, PERKS, THROWABLES, POTIONS }
const TAB_TITLES: Dictionary[Tab, String] = {
	Tab.WEAPONS: "Weapons",
	Tab.PERKS: "Perks",
	Tab.THROWABLES: "Bombs & Flasks",
	Tab.POTIONS: "Potions",
}
const TAB_BLURBS: Dictionary[Tab, String] = {
	Tab.WEAPONS: "Every character's signature kit, and the weapons found on altars and sold in shops (those break with use).",
	Tab.PERKS: "Bought at shop altars, they last the rest of the match. Two of the right ones evolve into something stronger.",
	Tab.THROWABLES: "Bought at shops or found in item boxes. They go in your consumable slots, to throw when you need them.",
	Tab.POTIONS: "Spilled by chests and item boxes: run through one to drink it.",
}

@onready var _tab_row: HBoxContainer = %Tabs
@onready var _blurb: Label = %Blurb
@onready var _scroll: ScrollContainer = %Scroll
@onready var _grid: GridContainer = %Grid
@onready var _back: Button = %Back

var _cards := ItemCards.new()
var _tab: Tab = Tab.WEAPONS
var _tab_buttons: Array[Button] = []
var _spinners: Array[Node3D] = []


func _ready() -> void:
	_grid.add_theme_constant_override("h_separation", CARD_GAP)
	_grid.add_theme_constant_override("v_separation", CARD_GAP)
	var group := ButtonGroup.new()
	for tab: Tab in TAB_TITLES:
		var button := Button.new()
		button.text = TAB_TITLES[tab]
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(200, 44)
		button.add_theme_font_size_override("font_size", 20)
		button.pressed.connect(_open.bind(tab))
		_tab_row.add_child(button)
		_tab_buttons.append(button)
	_back.pressed.connect(_leave)
	get_viewport().size_changed.connect(_fit_columns)
	_open(Tab.WEAPONS)
	_tab_buttons[0].grab_focus()


func _process(delta: float) -> void:
	for spinner: Node3D in _spinners:
		spinner.rotate_y(ItemCards.PREVIEW_SPIN * delta)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if Players.is_back_press(event):
		_leave()
	elif _tab_step(event) != 0:
		_open(posmod(_tab + _tab_step(event), Tab.size()) as Tab)
	else:
		return
	accept_event()


## LB / RB, or Q / E: the tab before or after.
func _tab_step(event: InputEvent) -> int:
	if event is InputEventJoypadButton:
		match event.button_index:
			JOY_BUTTON_LEFT_SHOULDER: return -1
			JOY_BUTTON_RIGHT_SHOULDER: return 1
	elif event is InputEventKey:
		match event.physical_keycode:
			KEY_Q: return -1
			KEY_E: return 1
	return 0


func _leave() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)


func _open(tab: Tab) -> void:
	_tab = tab
	_tab_buttons[tab].set_pressed_no_signal(true)
	_blurb.text = TAB_BLURBS[tab]
	_spinners.clear()
	for child: Node in _grid.get_children():
		child.queue_free()
	match tab:
		Tab.WEAPONS:
			for scene: PackedScene in _all_weapons():
				_add_weapon(scene)
		Tab.PERKS:
			var catalog: PerkCatalog = PerkDirector.CATALOG
			for category: Perk.Category in Perk.CATEGORY_NAMES:
				for perk: Perk in catalog.in_category(category):
					_add_perk(catalog, perk)
		Tab.THROWABLES:
			for type: int in Bomb3D.Type.size():
				_add_throwable(ShopOffer.throwable(Throwable3D.Kind.BOMB, type))
			for flask in Potion.LARGE.size():
				_add_throwable(ShopOffer.throwable(Throwable3D.Kind.FLASK, flask))
		Tab.POTIONS:
			for potion in Potion.SMALL.size():
				_add_potion(Potion.small(potion))
	_fit_columns()
	_scroll.scroll_vertical = 0


## As many columns of cards as fit across the window.
func _fit_columns() -> void:
	var room: float = get_viewport_rect().size.x - SIDE_ROOM * 2.0
	_grid.columns = maxi(2, floori((room + CARD_GAP) / (ItemCards.CARD_SIZE.x + CARD_GAP)))


## A card in the grid. It takes focus (from the keyboard, a controller, or
## the mouse passing over it), which draws the theme's focus frame round it.
func _new_card() -> VBoxContainer:
	var card: PanelContainer = _cards.make_card()
	card.focus_mode = Control.FOCUS_ALL
	card.draw.connect(func() -> void:
		if card.has_focus():
			_cards.draw_focus(card))
	card.focus_entered.connect(card.queue_redraw)
	card.focus_exited.connect(card.queue_redraw)
	card.mouse_entered.connect(card.grab_focus)
	_grid.add_child(card)
	return ItemCards.column_of(card)


func _add_spinner(column: VBoxContainer, model: Node3D) -> void:
	var spinner: Node3D = _cards.add_preview(column, model)
	if spinner:
		_spinners.append(spinner)


func _add_weapon(scene: PackedScene) -> void:
	var column: VBoxContainer = _new_card()
	_add_spinner(column, WeaponStand3D.make_display_copy(scene, WeaponRarity.Tier.COMMON))
	var owners: Array[String] = _kit_owners(scene)
	if owners.is_empty():
		_cards.fill_weapon(column, scene, "WEAPON", _cards.muted_color)
	else:
		_cards.fill_weapon(column, scene, "SIGNATURE WEAPON", SIGNATURE_COLOR)
		column.add_child(_cards.label("Kit of " + ", ".join(owners), 16, SIGNATURE_COLOR, ItemCards.CARD_TEXT_WIDTH))


func _add_perk(catalog: PerkCatalog, perk: Perk) -> void:
	var column: VBoxContainer = _new_card()
	_cards.fill_perk(column, perk)
	_cards.add_spacer(column)
	if perk.category == Perk.Category.RELIC:
		column.add_child(_cards.label("Only from a skull's altar reward", 15, RELIC_NOTE_COLOR, ItemCards.CARD_TEXT_WIDTH))
	var hint: String = catalog.evolution_hint(perk)
	if hint != "":
		column.add_child(_cards.label(hint, 15, EVOLVE_COLOR, ItemCards.CARD_TEXT_WIDTH))


func _add_throwable(offer: ShopOffer) -> void:
	var column: VBoxContainer = _new_card()
	_add_spinner(column, Altar3D.throwable_preview(offer))
	_cards.fill_throwable(column, offer)


func _add_potion(potion: Dictionary) -> void:
	var column: VBoxContainer = _new_card()
	# Wrapped, so the preview's framing counts the model's own scale
	var holder := Node3D.new()
	holder.add_child(Potion.model(potion.shape, potion.color, Potion.SMALL_HEIGHT))
	_add_spinner(column, holder)
	column.add_child(_cards.label("POTION", 16, (potion.color as Color).lightened(0.2)))
	column.add_child(_cards.label(potion.title, 22, _cards.text_color, ItemCards.CARD_TEXT_WIDTH))
	column.add_child(_cards.label(potion.blurb, 16, _cards.muted_color, ItemCards.CARD_TEXT_WIDTH))


## Every weapon in the game, by name: the characters' kits, and everything
## the altars stock (their tiers and skull rewards, see Altar.tscn).
func _all_weapons() -> Array[PackedScene]:
	var found: Dictionary[String, PackedScene] = {}
	for character in Roster.count():
		for scene: PackedScene in Roster.kit_of(character):
			if scene:
				found[scene.resource_path] = scene
	var altar: Altar3D = (load(ALTAR_SCENE) as PackedScene).instantiate() as Altar3D
	var tiers: Array[AltarTier] = altar.tiers.duplicate()
	if altar.reward_weapons:
		tiers.append(altar.reward_weapons)
	altar.free()
	for tier: AltarTier in tiers:
		for scene: PackedScene in tier.weapons:
			if scene:
				found[scene.resource_path] = scene
	var weapons: Array[PackedScene] = found.values()
	weapons.sort_custom(func(a: PackedScene, b: PackedScene) -> bool:
		return Altar3D.weapon_info(a)[0] < Altar3D.weapon_info(b)[0])
	return weapons


## The characters whose signature kit includes `scene`.
func _kit_owners(scene: PackedScene) -> Array[String]:
	var owners: Array[String] = []
	for character in Roster.count():
		for kit_scene: PackedScene in Roster.kit_of(character):
			if kit_scene and kit_scene.resource_path == scene.resource_path:
				owners.append(Roster.name_of(character))
				break
	return owners
