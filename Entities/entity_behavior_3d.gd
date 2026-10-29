class_name EntityBehavior3D extends Node
## A player's health, hit reactions (knockback and the brief invulnerability
## after a hit) and where they spawn.

@export var spawn_pos: Vector3
## Seconds of invulnerability after a hit.
@export var iframes_duration: float = 0.5

@onready var Master := get_parent()

# ===== CONSTANTS =====
const SPEED: float = 6.5

# ===== HEALTH SYSTEM =====
# Base stats
var strength: int = 0

# Max Values
## Max HP per point of strength. Players start at 10 strength = 250 HP, so a
## sword (40) kills in 7 hits: kills win the match, so fights should end
## before the ball has moved on without them.
const HP_PER_STRENGTH := 25
## Strength everyone starts with, before their Properties' bonus.
const BASE_STRENGTH := 10
var hp_max: float = 1000.0
var stat_values: Dictionary = {}

# Stat properties with automatic signal emission
var hp: float:
	get: return stat_values.get("hp", hp_max)
	set(value): 
		stat_values["hp"] = value
		hp_changed.emit(value, hp_max)

# ===== STATE VARIABLES =====
var is_in_iframes: bool = false

# ===== SIGNALS =====
signal hp_changed(new_hp: float, max_hp: float)


func _ready() -> void:
	hp = hp_max


# ===== HEALTH SYSTEM FUNCTIONS =====

## Damage plus a shove given directly as a velocity (horizontal slide +
## upward pop), for hits that want exact control over the knockback.
func take_hit(dmg: float, knockback_velocity: Vector3) -> void:
	if is_in_iframes: return
	if hp > 0:
		hp -= dmg
	apply_knockback(knockback_velocity, knockback_velocity.length())


func apply_knockback(direction: Vector3, force: float) -> void:
	if is_in_iframes: return
	# Players keep shoves in their own knockback velocity (movement would
	# overwrite a plain velocity change on the next frame)
	if Master is PlayerClass3D:
		Master.add_knockback(direction.normalized() * force)
	# Apply knockback to the CharacterBody3D's velocity
	elif Master is CharacterBody3D:
		# Convert 3D direction to horizontal (X/Z) and apply force
		var horizontal_dir: Vector3 = Vector3(direction.x, 0, direction.z).normalized()
		Master.velocity += horizontal_dir * force
		# Also apply vertical component if needed
		if direction.y != 0:
			Master.velocity.y += direction.y * force
	else:
		# Fallback for other body types
		if Master.has_method("get") and Master.get("Input_Handler"):
			Master.Input_Handler.velocity += direction * force
	start_iframes()


## Brief invulnerability after a hit, shown by flashing the player red.
## Online, other machines call this on their copy to show the same flash.
func start_iframes() -> void:
	is_in_iframes = true
	if Master is PlayerClass3D and Master.visual:
		Master.visual.set_iframe_fade(true)
	
	var timer: SceneTreeTimer = get_tree().create_timer(iframes_duration)
	timer.timeout.connect(end_iframes)


## The player's team color, shown by the ring at their feet.
func set_color(color: Color = Color.WHITE) -> void:
	if Master is PlayerClass3D and Master.visual:
		Master.visual.set_team_color(color)


## Full health (with the stats from the player's Properties) and back to
## spawn_pos.
func reset() -> void:
	if Master is PlayerClass3D and Master.Properties:
		var props: PlayerResource = Master.Properties
		strength = props.player_strength + BASE_STRENGTH
		set_color(props.player_color)
	else:
		strength = BASE_STRENGTH
	_update_max_stats()
	hp = hp_max

	Master.global_position = spawn_pos


## Max values from base stats and perks.
func _update_max_stats() -> void:
	hp_max = float(strength * HP_PER_STRENGTH) * _perk_stat(&"max_hp")


## Perks changed the max values: resize them, keeping HP just as full as
## it was.
func refresh_max_stats() -> void:
	var hp_ratio: float = hp / hp_max if hp_max > 0.0 else 1.0
	_update_max_stats()
	hp = hp_max * hp_ratio


func _perk_stat(stat_name: StringName) -> float:
	return Master.perk_stat(stat_name) if Master is PlayerClass3D else 1.0


func end_iframes() -> void:
	is_in_iframes = false
	if Master is PlayerClass3D and Master.visual:
		Master.visual.set_iframe_fade(false)

