class_name HUD3D extends CanvasLayer
@export var player: PlayerClass3D

@onready var health_bar:  TextureProgressBar = $HealthBar
@onready var stamina_bar: TextureProgressBar = $StaminaBar
@onready var mana_bar:    TextureProgressBar = $ManaBar
@onready var player_icon: TextureRect        = $PlayerIcon

## Screen space the HUD art occupies, including its margin from the edge.
const PANEL_SIZE := Vector2(304, 112)

var signals_connected: bool = false


## Binds this HUD to a player and moves it to that player's corner:
## P1 top-left, P2 top-right, P3 bottom-left, P4 bottom-right.
func setup(p: PlayerClass3D, slot: PlayerSlot) -> void:
	player = p
	var screen := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))
	offset = Vector2(
		screen.x - PANEL_SIZE.x if slot.index % 2 == 1 else 0.0,
		screen.y - PANEL_SIZE.y if slot.index >= 2 else 0.0)
	player_icon.modulate = slot.color

func _process(_delta: float) -> void:
	if player and player.Entity and !signals_connected:
		signals_connected = true
		_connect_signals(player.Entity)

func _connect_signals(eb: Node) -> void:
	# eb should be EntityBehavior3D, but using Node type to avoid class loading issues
	if not eb:
		return
	eb.hp_changed.connect(_on_hp_changed)
	eb.mana_changed.connect(_on_mana_changed)
	eb.stamina_changed.connect(_on_stamina_changed)

	# Get initial values immediately after connecting
	_on_hp_changed(eb.hp, eb.hp_max)
	_on_mana_changed(eb.mana, eb.mana_max)
	_on_stamina_changed(eb.stamina, eb.stamina_max)

func _on_hp_changed(new_hp: float, max_hp: float) -> void:
	health_bar.max_value = max_hp
	health_bar.value = new_hp

func _on_mana_changed(new_mana: float, max_mana: float) -> void:
	mana_bar.max_value = max_mana
	mana_bar.value = new_mana

func _on_stamina_changed(new_stamina: float, max_stamina: float) -> void:
	stamina_bar.max_value = max_stamina
	stamina_bar.value = new_stamina
