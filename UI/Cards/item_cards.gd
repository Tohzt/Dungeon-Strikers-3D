class_name ItemCards extends RefCounted
## Draws the cards for weapons, perks, bombs and potions, shared by the shop
## (ShopMenu3D) and the Codex (CodexMenu), so both look the same. Looks come
## from the project theme (Assets/default_theme.tres), like the rest of the
## UI: cards are dark against the stone panel (the theme's dark inset, a
## text box's, darker still), and previews spin in a well of the stone
## panel, dimmed, so dark models still stand out.

## Every card is this size, so a row of them lines up.
const CARD_SIZE := Vector2(240, 300)
## Room for text on a card (its width less the card's margins).
const CARD_TEXT_WIDTH := CARD_SIZE.x - 24.0
const PREVIEW_SIZE := Vector2i(180, 130)
const CARD_TINT := Color(0.8, 0.8, 0.85)
## How bright a preview's well is, against the theme's stone panel.
const WELL_TINT := Color(0.55, 0.55, 0.6)
const WARNING_COLOR := Color(1.0, 0.35, 0.3)
const PREVIEW_SPIN := 1.2
const PREVIEW_FOV := 35.0
const GRIP_NAMES: Dictionary[Weapon3D.Grip, String] = {
	Weapon3D.Grip.MAIN_HAND: "One-handed",
	Weapon3D.Grip.OFF_HAND: "Off hand",
	Weapon3D.Grip.EITHER_HAND: "Either hand",
	Weapon3D.Grip.TWO_HANDED: "Two-handed",
}

var theme: Theme
var text_color: Color
var muted_color: Color
var _card_style: StyleBoxTexture
var _well_style: StyleBox


func _init() -> void:
	theme = ThemeDB.get_project_theme()
	if not theme:
		theme = ThemeDB.get_default_theme()
	text_color = theme.get_color(&"font_color", &"Label")
	muted_color = text_color.darkened(0.12)
	_card_style = (theme.get_stylebox(&"normal", &"LineEdit") as StyleBoxTexture).duplicate() as StyleBoxTexture
	_card_style.modulate_color = CARD_TINT
	_card_style.content_margin_left = 12.0
	_card_style.content_margin_right = 12.0
	_card_style.content_margin_top = 10.0
	_card_style.content_margin_bottom = 12.0
	_well_style = theme.get_stylebox(&"panel", &"PanelContainer").duplicate() as StyleBox
	if _well_style is StyleBoxTexture:
		var stone := _well_style as StyleBoxTexture
		stone.modulate_color = stone.modulate_color * WELL_TINT
	_well_style.set_content_margin_all(4.0)


## An empty card; fill the column it holds (column_of).
func make_card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", _card_style)
	panel.custom_minimum_size = CARD_SIZE
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	return panel


static func column_of(card: PanelContainer) -> VBoxContainer:
	return card.get_child(0) as VBoxContainer


## Pushes whatever's added after it to the bottom of the card.
func add_spacer(column: VBoxContainer) -> void:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)


## The theme's focus frame round `card`; call from its draw signal.
func draw_focus(card: Control) -> void:
	theme.get_stylebox(&"focus", &"Button").draw(card.get_canvas_item(), Rect2(Vector2.ZERO, card.size))


## `model` spinning in a dark well on the card. Returns what to turn (by
## PREVIEW_SPIN a second), or null if there's no model.
func add_preview(column: VBoxContainer, model: Node3D) -> Node3D:
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
	var spinner := Node3D.new()
	viewport.add_child(spinner)
	spinner.add_child(model)
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
	var inset := PanelContainer.new()
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_theme_stylebox_override(&"panel", _well_style)
	inset.add_child(container)
	column.add_child(inset)
	return spinner


## A weapon's name, and how it's held and its heavy attack, under a header
## line (e.g. its rarity) in `header_color`.
func fill_weapon(column: VBoxContainer, scene: PackedScene, header: String, header_color: Color) -> void:
	var info: Array = Altar3D.weapon_info(scene)
	column.add_child(label(header, 16, header_color))
	column.add_child(label(info[0], 24, text_color, CARD_TEXT_WIDTH))
	var details: String = GRIP_NAMES.get(info[1], "")
	if info[2] != "":
		details += "  -  Heavy: %s" % info[2]
	column.add_child(label(details, 16, muted_color, CARD_TEXT_WIDTH))


## A perk's category, name and what it does.
func fill_perk(column: VBoxContainer, perk: Perk) -> void:
	column.add_child(label(perk.category_name().to_upper(), 16, perk.category_color(), CARD_TEXT_WIDTH))
	column.add_child(label(perk.title, 22, text_color, CARD_TEXT_WIDTH))
	add_rule(column, perk.category_color().darkened(0.3))
	column.add_child(label(perk.description, 17, muted_color, CARD_TEXT_WIDTH))


## A bomb or big flask (a THROWABLE offer): what it is and what it does.
func fill_throwable(column: VBoxContainer, offer: ShopOffer) -> void:
	var is_bomb: bool = offer.throwable_kind == Throwable3D.Kind.BOMB
	column.add_child(label("BOMB" if is_bomb else "FLASK", 16, Altar3D.throwable_color(offer).lightened(0.2)))
	column.add_child(label(Altar3D.throwable_title(offer), 22, text_color, CARD_TEXT_WIDTH))
	column.add_child(label(throwable_text(offer), 16, muted_color, CARD_TEXT_WIDTH))


## A thin colored line across the card.
func add_rule(column: VBoxContainer, color: Color) -> void:
	var rule := ColorRect.new()
	rule.color = color
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)


## What a bomb or flask does, in a line.
static func throwable_text(offer: ShopOffer) -> String:
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


static func rarity_color(rarity: int) -> Color:
	return Color.WHITE if rarity <= WeaponRarity.Tier.COMMON \
		else Color(WeaponRarity.COLORS[rarity], 1.0).lightened(0.2)


## `wrap_width` > 0 wraps the text at that width; `left` aligns it left.
func label(text: String, size: int, color: Color, wrap_width: float = 0.0, left: bool = false) -> Label:
	var new_label := Label.new()
	new_label.text = text
	new_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_CENTER
	if wrap_width > 0.0:
		new_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		new_label.custom_minimum_size.x = wrap_width
	new_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	new_label.add_theme_font_size_override("font_size", size)
	new_label.add_theme_color_override("font_color", color)
	# The theme's dark outline, a little thicker on big text
	new_label.add_theme_constant_override("outline_size", maxi(4, int(size / 5.0)))
	return new_label


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
