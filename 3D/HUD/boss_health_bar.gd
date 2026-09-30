class_name BossHealthBar3D extends CanvasLayer
## Souls-style boss bar along the bottom of the screen: the boss's name over
## a long red bar, with a pale strip that lingers where the HP just was and
## then drains down to it. Appears when the fight starts; says so when the
## boss falls. Game3D binds each new boss to it.

@export var boss: Boss3D

## How long the lingering strip waits after a hit before it drains.
const TRAIL_DELAY := 0.7
## Share of max HP the strip drains per second.
const TRAIL_DRAIN_RATE := 0.6
const FADE_TIME := 0.6
## How long the "felled" banner stays up (fading in and out included).
const BANNER_TIME := 4.0

@onready var root: Control = $Root
@onready var name_label: Label = $Root/Name
@onready var trail_bar: ProgressBar = $Root/Bars/Trail
@onready var health_bar: ProgressBar = $Root/Bars/Health
@onready var banner: Label = $Banner

var _trail_wait: float = 0.0
var _tween: Tween


func _ready() -> void:
	root.modulate.a = 0.0
	root.visible = false
	banner.modulate.a = 0.0
	if boss:
		bind(boss)


## Follow `new_boss` from now on (hidden until it wakes up).
func bind(new_boss: Boss3D) -> void:
	if boss and boss != new_boss and is_instance_valid(boss):
		boss.hp_changed.disconnect(_on_hp_changed)
		boss.awakened.disconnect(_show)
		boss.defeated.disconnect(_on_defeated)
	if boss == new_boss and boss.hp_changed.is_connected(_on_hp_changed):
		return
	boss = new_boss
	name_label.text = boss.display_name
	for bar: ProgressBar in [trail_bar, health_bar]:
		bar.max_value = boss.max_hp
		bar.value = boss.hp
	boss.hp_changed.connect(_on_hp_changed)
	boss.awakened.connect(_show)
	boss.defeated.connect(_on_defeated)
	if boss.is_awake:
		_show()


func _process(delta: float) -> void:
	if trail_bar.value <= health_bar.value:
		trail_bar.value = health_bar.value
		return
	if _trail_wait > 0.0:
		_trail_wait -= delta
		return
	trail_bar.value = move_toward(trail_bar.value, health_bar.value,
			trail_bar.max_value * TRAIL_DRAIN_RATE * delta)


func _on_hp_changed(hp: float, max_hp: float) -> void:
	health_bar.max_value = max_hp
	trail_bar.max_value = max_hp
	if hp < health_bar.value:
		_trail_wait = TRAIL_DELAY  # Each new hit holds the strip a little longer
	health_bar.value = hp


func _show() -> void:
	root.visible = true
	_fade(root, 1.0)


func _on_defeated(_killer: PlayerClass3D) -> void:
	health_bar.value = 0.0
	_trail_wait = 0.0
	var tween: Tween = _fade(root, 0.0, 1.5)
	tween.tween_callback(root.hide)
	var banner_tween: Tween = create_tween()
	banner_tween.tween_interval(0.8)
	banner_tween.tween_property(banner, "modulate:a", 1.0, FADE_TIME)
	banner_tween.tween_interval(BANNER_TIME - FADE_TIME * 2.0)
	banner_tween.tween_property(banner, "modulate:a", 0.0, FADE_TIME)


func _fade(node: CanvasItem, alpha: float, delay: float = 0.0) -> Tween:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_interval(delay)
	_tween.tween_property(node, "modulate:a", alpha, FADE_TIME)
	return _tween
