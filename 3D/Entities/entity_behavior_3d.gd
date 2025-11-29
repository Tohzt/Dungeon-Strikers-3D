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
var stamina_regen_rate: float = 2.0
var stamina_cost: float = 1.0
var stamina_cost_default: float = 1.0
var stamina_regen_timer: Timer
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
		# Restart stamina regeneration if we're below max
		if value < stamina_max and stamina_regen_timer and stamina_regen_timer.is_stopped():
			stamina_regen_timer.start()

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
	_setup_stamina_regen_timer()


func _setup_stat_properties() -> void:
	hp = hp_max
	mana = mana_max
	stamina = stamina_max


# ===== HEALTH SYSTEM FUNCTIONS =====
func _setup_stamina_regen_timer() -> void:
	stamina_regen_timer = Timer.new()
	stamina_regen_timer.wait_time = 1.0 / stamina_regen_rate  # Convert rate to interval
	stamina_regen_timer.timeout.connect(_on_stamina_regen_tick)
	add_child(stamina_regen_timer)
	stamina_regen_timer.start()

func _on_stamina_regen_tick() -> void:
	if stamina < stamina_max:
		stamina = min(stamina + 1.0, stamina_max)
		# Stop timer if we're at max stamina
		if stamina >= stamina_max:
			stamina_regen_timer.stop()
	# Restart timer if we're below max stamina
	elif stamina < stamina_max and stamina_regen_timer.is_stopped():
		stamina_regen_timer.start()


@rpc("any_peer", "call_local")
func take_damage(dmg: float, dir: Vector3) -> void:
	if is_in_iframes: return
	if hp > 0:
		hp -= int(dmg)
	apply_knockback(dir, dmg*10)

@rpc("any_peer")
func apply_knockback(direction: Vector3, force: float) -> void:
	if is_in_iframes: return
	is_in_iframes = true
	# Apply knockback to the CharacterBody3D's velocity
	if Master is CharacterBody3D:
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
	if Master.has("mesh_instance_3d") and Master.mesh_instance_3d:
		for mesh_instance: MeshInstance3D in Master.mesh_instance_3d:
			if not mesh_instance:
				continue
			
			var material: StandardMaterial3D = mesh_instance.get_surface_override_material(0)
			if not material:
				# Get or duplicate base material
				var base_material: Material = mesh_instance.get_surface_material(0)
				if base_material:
					material = base_material.duplicate() as StandardMaterial3D
				else:
					material = StandardMaterial3D.new()
				mesh_instance.set_surface_override_material(0, material)
			
			if material is StandardMaterial3D:
				material.albedo_color.a = 0.5
	
	var timer: SceneTreeTimer = get_tree().create_timer(iframes_duration)
	timer.timeout.connect(end_iframes)


func set_color(color: Color = Color.WHITE) -> void:
	# Apply color to all meshes in the player's mesh array
	if Master.has("mesh_instance_3d") and Master.mesh_instance_3d:
		for mesh_instance: MeshInstance3D in Master.mesh_instance_3d:
			if not mesh_instance:
				continue
			
			# Get or create material
			var material: StandardMaterial3D = mesh_instance.get_surface_override_material(0)
			if not material:
				# If no override material, duplicate the existing one or create new
				var base_material: Material = mesh_instance.get_surface_material(0)
				if base_material:
					material = base_material.duplicate() as StandardMaterial3D
				else:
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
	if Master.has("Properties") and Master.Properties:
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
	
	if stamina_regen_timer:
		stamina_regen_timer.stop()
		stamina_regen_timer.start()
	
	Master.global_position = spawn_pos


func end_iframes() -> void:
	is_in_iframes = false
	# Restore visual feedback - restore full alpha to mesh materials
	if Master.has("mesh_instance_3d") and Master.mesh_instance_3d:
		for mesh_instance: MeshInstance3D in Master.mesh_instance_3d:
			if not mesh_instance:
				continue
			
			var material: StandardMaterial3D = mesh_instance.get_surface_override_material(0)
			if material is StandardMaterial3D:
				material.albedo_color.a = 1.0


func set_target() -> void:
	print("setting target from EB")
