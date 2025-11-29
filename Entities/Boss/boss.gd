class_name BossClass extends CharacterBody2D

var color: Color = Color.TRANSPARENT
@onready var Sprite: Sprite2D = $"Sprite Inner"
@export var Hands: Node2D
@export var Attack_Origin: Marker2D
@export var State_Handler: StateHandlerClass
@export var Attack_List: Array[PackedScene]

var hp_max: float = 1000.0
var hp: float = hp_max
@export var healthbar: TextureProgressBar

var name_display: String
const SPEED: float = 5000.0  
const SPEED_MULTIPLIER: float = 1.0
var ATTACK: float = 400.0 
var ATTACK_RANGE: float = 0.0
@onready var ATTACK_COOLDOWN: float = 0.0
var DEFENSE: float = 100.0

var spawn_pos: Vector2 = Vector2.ZERO
var spawn_rot: float = 0.0
var current_room: RoomClass

var is_in_iframes: bool = false
var iframes_duration: float = 0.5

@export var _Target: Node2D
@onready var ray_target := $RayCast2D
var target: Node2D
var target_locked: bool = false
var enemy: Node2D

func _enter_tree() -> void:
	if multiplayer.is_server():
		set_multiplayer_authority(1)

func _ready() -> void:
	z_index = Global.Layers.ENEMIES
	target = _Target
	healthbar.max_value = hp_max
	healthbar.value = hp_max


func _process(delta: float) -> void:
	_update_hp(delta)
	_update_position(delta)
	_update_cooldowns(delta)
	_update_current_room()
	#if !is_multiplayer_authority(): return
	
func _physics_process(_delta: float) -> void:
	if !Server.OFFLINE and !multiplayer.is_server(): return
	move_and_slide()


func _update_hp(delta: float) -> void:
	healthbar.global_position = global_position - Vector2(70,80)
	healthbar.value = lerp(healthbar.value, float(hp/hp_max)*hp_max, delta*10)

func _update_position(delta: float) -> void:
	if !target: return
	var target_angle := position.direction_to(target.global_position).angle()
	var _offset := deg_to_rad(90)
	ray_target.global_rotation = target_angle + _offset
	var ray_collider: Node2D = ray_target.get_collider()
	target_locked = ray_collider == target
	var direction: Vector2 = (target.global_position - global_position).normalized()
	velocity = direction * SPEED * SPEED_MULTIPLIER * delta
	rotation = lerp_angle(rotation, direction.angle() + PI/2, delta*5)

func _update_cooldowns(delta: float) -> void:
	if ATTACK_COOLDOWN > 0.0:
		ATTACK_COOLDOWN -= delta
		if ATTACK_COOLDOWN <= 0.0:
			ATTACK_COOLDOWN = 0.0

func reset_position(pos: Vector2) -> void:
	spawn_pos = pos
	global_position = spawn_pos

func _update_current_room() -> void:
	##NOTE: Update via enter/exit room's area2D
	for room in get_tree().get_nodes_in_group("Room"):
		if room.current_room:
			current_room = room

@rpc("any_peer", "call_local")
func set_color(col: Color) -> void:
	color = col
	healthbar.tint_progress = col
	healthbar.tint_under = col.darkened(0.5)
	Sprite.modulate = color
	set_hand_color(col)

func set_hand_color(col: Color) -> void:
	var hands: Array = Hands.get_children()
	for hand: BossHandClass in hands:
		hand.hand.modulate = col
		hand.particle.modulate = col

func under_attack(atk: float, dir: Vector2) -> void:
	apply_knockback.rpc(dir, atk*100)

@rpc("any_peer", "call_local")
func take_damage(dmg: float, dir: Vector2) -> void:
	if is_in_iframes: return
	if hp > 0:
		hp -= int(dmg)
	apply_knockback(dir, dmg*10)

@rpc("any_peer")
func apply_knockback(_direction: Vector2, _force: float) -> void:
	if is_in_iframes: return
	is_in_iframes = true
	#NOTE: Removing Handlers 
	#Input_Handler.velocity += direction * force
	
	modulate.a = 0.5
	var timer: SceneTreeTimer = get_tree().create_timer(iframes_duration)
	timer.timeout.connect(_end_iframes)

func _end_iframes() -> void:
	is_in_iframes = false
	modulate.a = 1.0
