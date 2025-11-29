##NOTE: Keeping for networking references
class_name BossAttackClass extends Area2D
@export var mesh: MeshInstance2D
@export var attack: CollisionShape2D

var Attacker: BossClass
var spawn_position: Vector2
var attack_type: String
var attack_power: float
var attack_direction: Vector2 = Vector2.ZERO
var attack_distance: float = INF
var attack_duration: float = INF

var velocity := Vector2.ZERO

func _ready() -> void:
	_activate_TorF(false)
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if !multiplayer.is_server(): return
	
	attack_duration -= delta
	if attack_duration <= 0:
		trigger_destroy()
		return
	
	if attack_type == "melee":
		global_position = Attacker.Attack_Origin.global_position
	
	if abs((global_position-spawn_position).length()) > attack_distance:
		trigger_destroy()

func _physics_process(_delta: float) -> void:
	if !multiplayer.is_server(): return
	if attack_type == "ranged": 
		velocity = attack_direction * attack_power
		position += velocity

func set_props(atk_type: String, atk_pow: int, atk_dir: Vector2, atk_dur: float = INF, atk_dist: float = INF) -> void:
	attack_type = atk_type
	if atk_type == "melee":
		mesh.hide()
		attack.scale = Vector2(2,2)
	attack_power = atk_pow
	attack_direction = atk_dir
	attack_duration = atk_dur
	attack_distance = atk_dist
	_activate_TorF(true)

func _activate_TorF(TorF: bool) -> void:
	if multiplayer.is_server():
		set_collision_layer_value(2, TorF)
		set_collision_mask_value(1, TorF)
		set_process(TorF)
		set_physics_process(TorF)

func _on_body_entered(body: Node2D) -> void:
	if body == Attacker: return
	
	if body is PlayerClass:
		body.take_damage.rpc(attack_power,attack_direction)
	
	if body is BallClass:
		body.color_cur = Attacker.Sprite.modulate
		var _dir := (body.global_position - global_position).normalized()
		body.apply_central_force(_dir * attack_power * 100)
	
	if body is DoorClass:
		body.under_attack = true
	
	trigger_destroy()

func trigger_destroy() -> void:
	queue_free()
