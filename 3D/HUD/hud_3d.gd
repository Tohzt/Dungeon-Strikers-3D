class_name HUD3D extends CanvasLayer
@export var player: PlayerClass3D

@onready var panel:       PanelContainer = $Panel
@onready var health_bar:  ProgressBar    = $Panel/Row/Bars/HealthBar
## The blue bar: the player's carry meter (see PlayerClass3D.carry).
@onready var carry_bar:   ProgressBar    = $Panel/Row/Bars/CarryBar
@onready var player_icon: TextureRect    = $Panel/Row/PlayerIcon

## Gap between the HUD panel and the screen edges.
const MARGIN := 16

var signals_connected: bool = false
## "Knocked out: 7s" under the bars while the player is down (knockout modes).
var _down_label: Label


## Binds this HUD to a player and moves it to `corner` (the player's place
## among this machine's humans): top-left, top-right, bottom-left,
## bottom-right. Anchored, so it stays in the corner whatever shape the
## window is.
func setup(p: PlayerClass3D, slot: PlayerSlot, corner: int) -> void:
	player = p
	var corners: Array[Control.LayoutPreset] = [Control.PRESET_TOP_LEFT, Control.PRESET_TOP_RIGHT,
		Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT]
	panel.set_anchors_and_offsets_preset(corners[corner % corners.size()], Control.PRESET_MODE_MINSIZE, MARGIN)
	player_icon.modulate = slot.color
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
