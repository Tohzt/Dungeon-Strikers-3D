class_name HUD3D extends CanvasLayer
@export var player: PlayerClass3D

@onready var panel:       PanelContainer = $Panel
## The player's name, filled in their team color as far as their health
## goes (see NameTag).
@onready var name_tag:    NameTag        = $Panel/Row/Bars/NameTag
## The blue bar: the player's carry meter (see PlayerClass3D.carry).
@onready var carry_bar:   ProgressBar    = $Panel/Row/Bars/CarryBar
@onready var player_icon: TextureRect    = $Panel/Row/PlayerIcon

## Gap between the HUD panel and the screen edges.
const MARGIN := 16
const NAME_FONT_SIZE := 30
const NAME_BORDER := 9

var signals_connected: bool = false
## "Knocked out: 7s" under the bars while the player is down (knockout modes).
var _down_label: Label
## While a killed player is down: who they'll get back up as (see
## PlayerClass3D.next_character), stepped through with their own left/right
## (or clicked, on keyboard & mouse). Made the first time it's needed.
var _picker: CharacterSelectPanel
const PICKER_STAGE_SIZE := Vector2(240, 190)
var _corner: Control.LayoutPreset = Control.PRESET_TOP_LEFT


## Binds this HUD to a player and moves it to `corner` (the player's place
## among this machine's humans): top-left, top-right, bottom-left,
## bottom-right. Anchored, so it stays in the corner whatever shape the
## window is.
func setup(p: PlayerClass3D, slot: PlayerSlot, corner: int) -> void:
	player = p
	var corners: Array[Control.LayoutPreset] = [Control.PRESET_TOP_LEFT, Control.PRESET_TOP_RIGHT,
		Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT]
	_corner = corners[corner % corners.size()]
	panel.set_anchors_and_offsets_preset(_corner, Control.PRESET_MODE_MINSIZE, MARGIN)
	player_icon.modulate = slot.color
	name_tag.font_size = NAME_FONT_SIZE
	name_tag.border = NAME_BORDER
	name_tag.color = slot.color
	name_tag.text = slot.label()
	if not _down_label:
		_down_label = Label.new()
		_down_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		_down_label.hide()
		$Panel/Row/Bars.add_child(_down_label)

func _process(_delta: float) -> void:
	if _down_label and player:
		_down_label.visible = player.is_dead()
		if player.is_dead():
			var what: String = "Knocked out" if player.is_knocked_out else "Respawning"
			_down_label.text = "%s: %ds" % [what, ceili(player.dead_time)]
	if player:
		_update_picker()
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
	name_tag.fraction = new_hp / max_hp if max_hp > 0.0 else 0.0

func _on_carry_changed(new_carry: float, max_carry: float) -> void:
	carry_bar.max_value = max_carry
	carry_bar.value = new_carry


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


func _step_pick(step: int) -> void:
	_show_pick(Roster.step(_picker.character, player.slot.team, step))


func _show_pick(character: int) -> void:
	if not Roster.fits_team(character, player.slot.team):
		return
	player.next_character = character
	_picker.show_choice(player.slot.team, character)
