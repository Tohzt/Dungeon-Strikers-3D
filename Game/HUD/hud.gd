class_name HUDClass extends CanvasLayer
@export var game: Node2D

@onready var health_bar:  TextureProgressBar = $HealthBar
@onready var stamina_bar: TextureProgressBar = $StaminaBar
@onready var mana_bar:    TextureProgressBar = $ManaBar
@onready var player_icon: TextureRect        = $PlayerIcon

var signals_connected: bool = false

func _process(_delta: float) -> void:
	if game.Player and !signals_connected:
		signals_connected = true
		_connect_signals()

func _connect_signals() -> void:
	game.Player.EB.hp_changed.connect(_on_hp_changed)
	game.Player.EB.mana_changed.connect(_on_mana_changed)
	game.Player.EB.stamina_changed.connect(_on_stamina_changed)
	
	# Get initial values immediately after connecting
	_on_hp_changed(game.Player.EB.hp, game.Player.EB.hp_max)
	_on_mana_changed(game.Player.EB.mana, game.Player.EB.mana_max)
	_on_stamina_changed(game.Player.EB.stamina, game.Player.EB.stamina_max)

func _on_hp_changed(new_hp: float, max_hp: float) -> void:
	health_bar.max_value = max_hp
	health_bar.value = new_hp

func _on_mana_changed(new_mana: float, max_mana: float) -> void:
	mana_bar.max_value = max_mana
	mana_bar.value = new_mana

func _on_stamina_changed(new_stamina: float, max_stamina: float) -> void:
	stamina_bar.max_value = max_stamina
	stamina_bar.value = new_stamina
	
