##TODO: Set up an isActive to overwrite multiplayer status
class_name EntityBehavior3D extends Node

# ===== EXPORT VARIABLES =====
@export_category("Core Components")
@export var Attack_Origin: Marker3D

@export_category("Spawn & State")
@export var spawn_pos: Vector3
@export var is_active: bool = false

@onready var Master := get_parent()

# ===== CONSTANTS =====
const SPEED: float = 5.0

# ===== HEALTH SYSTEM =====
# Base stats
var strength: int = 0
var intelligence: int = 0
var endurance: int = 0

# Max Values
var hp_max: float = 1000.0
var mana_max: float = 100.0
var stamina_max: float = 5.0

# Costs and Regens
var mana_cost: float = 0.0
var mana_cost_default: float = 0.0
var stamina_regen_rate: float = 3.0  # Stamina per second once regen kicks in
var stamina_regen_delay: float = 1.0  # Seconds after last use before regen starts
var stamina_cost: float = 1.0
var stamina_cost_default: float = 1.0
var _stamina_regen_wait: float = 0.0
var stat_values: Dictionary = {}

# Stat properties with automatic signal emission
var hp: float:
	get: return stat_values.get("hp", hp_max)
	set(value): 
		stat_values["hp"] = value
		hp_changed.emit(value, hp_max)

var mana: float:
	get: return stat_values.get("mana", mana_max)
	set(value): 
		stat_values["mana"] = value
		mana_changed.emit(value, mana_max)

var stamina: float:
	get: return stat_values.get("stamina", stamina_max)
	set(value): 
		stat_values["stamina"] = value
		stamina_changed.emit(value, stamina_max)

# ===== COMBAT & MOVEMENT =====
var atk_pwr: float = 400.0  
var def_base: float = 100.0
var target: Node3D = null

# ===== STATE VARIABLES =====
var name_display: String
var spawn_rot: float = 0.0
var is_in_iframes: bool = false
var iframes_duration: float = 0.5
var has_control: bool = false

# ===== SIGNALS =====
signal hp_changed(new_hp: float, max_hp: float)
signal mana_changed(new_mana: float, max_mana: float)
signal stamina_changed(new_stamina: float, max_stamina: float)


# ===== MULTIPLAYER & NETWORKING =====
##TODO: All Multiplayer/Offline authentication should alter this. 
func _is_active(TorF: bool) -> void:
	is_active = TorF


func _ready() -> void:
	_setup_stat_properties()


func _setup_stat_properties() -> void:
	hp = hp_max
	mana = mana_max
	stamina = stamina_max


# ===== HEALTH SYSTEM FUNCTIONS =====
func _process(delta: float) -> void:
	_regen_stamina(delta)


## Spend stamina for an action. Returns false (spending nothing) if there
## isn't enough.
func use_stamina(amount: float) -> bool:
	if stamina < amount:
		return false
	drain_stamina(amount)
	return true


## Drain stamina without needing the full amount (e.g. per-frame sprinting).
func drain_stamina(amount: float) -> void:
	stamina = max(stamina - amount, 0.0)
	_stamina_regen_wait = stamina_regen_delay


func _regen_stamina(delta: float) -> void:
	if _stamina_regen_wait > 0.0:
		_stamina_regen_wait -= delta
	elif stamina < stamina_max:
		stamina = min(stamina + stamina_regen_rate * delta, stamina_max)


@rpc("any_peer", "call_local")
func take_damage(dmg: float, dir: Vector3) -> void:
	if is_in_iframes: return
	if hp > 0:
		hp -= int(dmg)
	apply_knockback(dir, dmg*10)


## Damage plus a shove given directly as a velocity (horizontal slide +
## upward pop), for hits that want exact control over the knockback.
func take_hit(dmg: float, knockback_velocity: Vector3) -> void:
	if is_in_iframes: return
	if hp > 0:
		hp -= int(dmg)
	apply_knockback(knockback_velocity, knockback_velocity.length())

@rpc("any_peer")
func apply_knockback(direction: Vector3, force: float) -> void:
	if is_in_iframes: return
	is_in_iframes = true
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
	
	# Visual feedback for iframes - apply alpha to mesh materials
	if Master is PlayerClass3D and Master.mesh_instance_3d:
		for mesh_instance: MeshInstance3D in Master.mesh_instance_3d:
			if not mesh_instance:
				continue
			
			var material: StandardMaterial3D = mesh_instance.get_surface_override_material(0)
			if not material:
				# Create new material if no override exists
				material = StandardMaterial3D.new()
				mesh_instance.set_surface_override_material(0, material)
			
			if material is StandardMaterial3D:
				material.albedo_color.a = 0.5
	
	var timer: SceneTreeTimer = get_tree().create_timer(iframes_duration)
	timer.timeout.connect(end_iframes)


func set_color(color: Color = Color.WHITE) -> void:
	# Apply color to all meshes in the player's mesh array
	if Master is PlayerClass3D and Master.mesh_instance_3d:
		for mesh_instance: MeshInstance3D in Master.mesh_instance_3d:
			if not mesh_instance:
				continue
			
			# Get or create material
			var material: StandardMaterial3D = mesh_instance.get_surface_override_material(0)
			if not material:
				# Create new material if no override exists
				material = StandardMaterial3D.new()
				mesh_instance.set_surface_override_material(0, material)
			
			# Apply color to material
			if material is StandardMaterial3D:
				material.albedo_color = color


@rpc("any_peer")
func reset(active_status: bool = true) -> void:
	is_active = active_status
	has_control = active_status
	
	# Set stats from Properties if available
	if Master is PlayerClass3D and Master.Properties:
		var props: Resource = Master.Properties
		strength = props.player_strength + 10
		intelligence = props.player_intelligence + 10
		endurance = props.player_endurance + 10
		set_color(props.player_color)
	else:
		# Default values if no Properties
		strength = 10
		intelligence = 10
		endurance = 10
	
	# Update max values based on stats
	hp_max = float(strength * 50)  # Scale strength to HP
	mana_max = float(intelligence * 10)  # Scale intelligence to mana
	stamina_max = float(endurance)
	
	# Update current values to match new max values
	hp = hp_max
	mana = mana_max
	stamina = stamina_max
	_stamina_regen_wait = 0.0
	
	Master.global_position = spawn_pos


func end_iframes() -> void:
	is_in_iframes = false
	# Restore visual feedback - restore full alpha to mesh materials
	if Master is PlayerClass3D and Master.mesh_instance_3d:
		for mesh_instance: MeshInstance3D in Master.mesh_instance_3d:
			if not mesh_instance:
				continue
			
			var material: StandardMaterial3D = mesh_instance.get_surface_override_material(0)
			if material is StandardMaterial3D:
				material.albedo_color.a = 1.0


func set_target() -> void:
	print("setting target from EB")
