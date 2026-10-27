class_name HUD3D extends CanvasLayer
@export var player: PlayerClass3D

## Coins on the left (on levels with a shop), then the bars: red for
## health, blue for the carry meter. The player's name is only over their
## head (Nameplates3D).
@onready var panel:       PanelContainer = $Panel
## The red bar: the player's health.
@onready var health_bar:  ProgressBar    = $Panel/Row/Bars/HealthBar
## The blue bar: the player's carry meter (see PlayerClass3D.carry).
@onready var carry_bar:   ProgressBar    = $Panel/Row/Bars/CarryBar

## Gap between the HUD panel and the screen edges.
const MARGIN := 16

var signals_connected: bool = false
## "PERK READY (R)" under the bars while the player has a hand waiting
## (see PerkDirector.grant_hand); their open_perks button opens it, and
## puts it away again.
var _perk_label: Label
const PERK_READY_COLOR := Color(1.0, 0.8, 0.3)
## "Knocked out: 7s" under the bars while the player is down (knockout modes).
var _down_label: Label
## While a killed player is down: who they'll get back up as (see
## PlayerClass3D.next_character), stepped through with their own left/right
## (or clicked, on keyboard & mouse). Made the first time it's needed.
var _picker: CharacterSelectPanel
const PICKER_STAGE_SIZE := Vector2(240, 190)
var _corner: Control.LayoutPreset = Control.PRESET_TOP_LEFT
## The player's coins (see PlayerClass3D.coins), on levels with a shop.
var _coin_row: HBoxContainer
var _coin_label: Label
var _coins_drawn: int = -1
const COIN_POP_SCALE := 1.35


## Binds this HUD to a player and moves it to `corner` (the player's place
## among this machine's humans): top-left, top-right, bottom-left,
## bottom-right. Anchored, so it stays in the corner whatever shape the
## window is.
func setup(p: PlayerClass3D, _slot: PlayerSlot, corner: int) -> void:
	player = p
	var corners: Array[Control.LayoutPreset] = [Control.PRESET_TOP_LEFT, Control.PRESET_TOP_RIGHT,
		Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT]
	_corner = corners[corner % corners.size()]
	panel.set_anchors_and_offsets_preset(_corner, Control.PRESET_MODE_MINSIZE, MARGIN)
	if not _down_label:
		_down_label = Label.new()
		_down_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		_down_label.hide()
		$Panel/Row/Bars.add_child(_down_label)
	if not _perk_label:
		_perk_label = Label.new()
		_perk_label.add_theme_color_override("font_color", PERK_READY_COLOR)
		_perk_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_perk_label.add_theme_constant_override("outline_size", 6)
		_perk_label.add_theme_font_size_override("font_size", 20)
		_perk_label.hide()
		$Panel/Row/Bars.add_child(_perk_label)
	if not _coin_row:
		_coin_row = HBoxContainer.new()
		_coin_row.add_theme_constant_override("separation", 6)
		_coin_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := TextureRect.new()
		icon.texture = ShopMenu3D.COIN_ICON
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_coin_row.add_child(icon)
		_coin_label = Label.new()
		_coin_label.add_theme_color_override("font_color", FlyingCoin3D.GOLD)
		_coin_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_coin_label.add_theme_constant_override("outline_size", 6)
		_coin_label.add_theme_font_size_override("font_size", 30)
		_coin_label.custom_minimum_size.x = 44  # Room for 3 digits, so the bars don't shift
		_coin_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_coin_row.add_child(_coin_label)
		_coin_row.visible = Global.Game3D != null and Global.Game3D.has_shops()
		$Panel/Row.add_child(_coin_row)
		$Panel/Row.move_child(_coin_row, 0)

func _process(_delta: float) -> void:
	if _down_label and player:
		_down_label.visible = player.is_dead()
		if player.is_dead():
			var what: String = "Knocked out" if player.is_knocked_out else "Respawning"
			_down_label.text = "%s: %ds" % [what, ceili(player.dead_time)]
	if player:
		_update_picker()
		_update_perk_button()
		_update_coins()
	if player and player.Entity and !signals_connected:
		signals_connected = true
		_connect_signals(player.Entity)

func _connect_signals(eb: Node) -> void:
	# eb should be EntityBehavior3D, but using Node type to avoid class loading issues
	if not eb:
		return
	eb.hp_changed.connect(_on_hp_changed)
	player.carry_changed.connect(_on_carry_changed)
	_on_carry_changed(player.carry, PlayerClass3D.CARRY_MAX)

	# Get initial values immediately after connecting
	_on_hp_changed(eb.hp, eb.hp_max)

func _on_hp_changed(new_hp: float, max_hp: float) -> void:
	health_bar.max_value = max_hp
	health_bar.value = new_hp

func _on_carry_changed(new_carry: float, max_carry: float) -> void:
	carry_bar.max_value = max_carry
	carry_bar.value = new_carry


# ===== PERKS =====

## Show when a hand is waiting, and open (or put away) the cards on the
## player's open_perks press. Not during a draft or intermission: those
## open the cards themselves.
func _update_perk_button() -> void:
	var perks: PerkDirector = Global.Game3D.perks if Global.Game3D else null
	var usable: bool = perks != null and player.slot != null and player.is_local_person() \
			and not player.is_dead() and not perks.in_draft and not perks.in_intermission
	var waiting: int = perks.hands_waiting(player) if usable else 0
	_perk_label.visible = waiting > 0 and not perks.is_picking(player)
	if _perk_label.visible:
		var button: String = "R" if player.slot.uses_keyboard_mouse() else "D-pad Up"
		_perk_label.text = "PERK READY%s (%s)" % [" x%d" % waiting if waiting > 1 else "", button]
		_perk_label.modulate.a = 0.65 + 0.35 * sin(Time.get_ticks_msec() / 1000.0 * 5.0)
	if not usable or not Input.is_action_just_pressed(player.slot.action(&"open_perks")):
		return
	if perks.is_picking(player):
		perks.close_for(player)
	elif perks.can_open(player):
		perks.open_for(player)


# ===== COINS =====

## The count, with a pop each time a coin lands.
func _update_coins() -> void:
	if not _coin_row:
		return
	var shown: int = player.coins_shown()
	if shown == _coins_drawn:
		return
	var gained: bool = shown > _coins_drawn and _coins_drawn >= 0
	_coins_drawn = shown
	_coin_label.text = "%d" % shown
	_coin_row.visible = _coin_row.visible or shown > 0
	if gained:
		_coin_label.pivot_offset = _coin_label.size / 2.0
		_coin_label.scale = Vector2.ONE * COIN_POP_SCALE
		create_tween().tween_property(_coin_label, "scale", Vector2.ONE, 0.15)


# ===== CHARACTER PICK WHILE DOWN =====

func _update_picker() -> void:
	var picking: bool = player.is_dead() and player.slot and player.is_local_person() \
			and player.dead_time > PlayerClass3D.RESPAWN_HIDE_TIME
	if not picking:
		if _picker:
			_picker.hide()
		return
	if not _picker:
		_make_picker()
	if not _picker.visible:
		_picker.show()
		_show_pick(player.slot.character)
	var slot: PlayerSlot = player.slot
	if Input.is_action_just_pressed(slot.action(&"move_left")):
		_step_pick(-1)
	elif Input.is_action_just_pressed(slot.action(&"move_right")):
		_step_pick(1)


func _make_picker() -> void:
	_picker = CharacterSelectPanel.new(PICKER_STAGE_SIZE)
	_picker.teams_shown = false
	_picker.names_shown = false
	_picker.focusable = false
	_picker.interactive = player.slot.uses_keyboard_mouse()
	_picker.set_header("Get back up as...")
	_picker.character_picked.connect(_show_pick)
	_picker.character_stepped.connect(_step_pick)
	add_child(_picker)
	# Beside the HUD panel: below it at the top of the screen, above it at the bottom
	_picker.set_anchors_and_offsets_preset(_corner, Control.PRESET_MODE_MINSIZE, MARGIN)
	var shift: float = panel.get_combined_minimum_size().y + MARGIN
	if _corner in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT]:
		shift = -shift
	_picker.offset_top += shift
	_picker.offset_bottom += shift
	# Hidden until _update_picker shows it, filled with the current pick
	_picker.hide()


func _step_pick(step: int) -> void:
	_show_pick(Roster.step(_picker.character, player.slot.team, step))


func _show_pick(character: int) -> void:
	if not Roster.fits_team(character, player.slot.team):
		return
	player.next_character = character
	_picker.show_choice(player.slot.team, character)
