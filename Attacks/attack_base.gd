class_name AttackBaseClass extends Area2D
@onready var Collision: CollisionShape2D = $CollisionShape2D
@onready var Sprite: TextureRect = $TextureRect

##FIX: Get Master better
var Master: Node2D
@onready var spawn_position: Vector2 = global_position
@export var attack_data: AttackResource

var is_casting: bool = false
var can_attack: bool = true
var telegraph_instance: Node2D = null
var attack_instance: Node2D = null


func _ready() -> void:
	if !attack_data:
		push_error("Attack data not set for " + name)
		return
	z_index = Global.Layers.GROUND_EFFECTS
	_activate_TorF(false)

func start_cast() -> void:
	if !can_attack: return
	is_casting = true
	can_attack = false
	
	# Spawn telegraph from resource
	if attack_data.attack_telegraph_scene:
		telegraph_instance = attack_data.attack_telegraph_scene.instantiate()
		add_child(telegraph_instance)
		telegraph_instance.global_position = get_parent().get_parent().get_parent().target.global_position
		telegraph_instance.initialize(attack_data.attack_cast_time)
	
	var cast_timer: SceneTreeTimer = get_tree().create_timer(attack_data.attack_cast_time)
	cast_timer.timeout.connect(_start_attack)

func _start_attack() -> void:
	_activate_TorF(true)
	is_casting = false
	
	if telegraph_instance:
		telegraph_instance.queue_free()
	
	# Start duration timer
	var cast_timer: SceneTreeTimer = get_tree().create_timer(attack_data.attack_duration)
	cast_timer.timeout.connect(_end_attack)

func _end_attack() -> void:
	can_attack = true 
	queue_free()


func _activate_TorF(TorF: bool) -> void:
	##HACK: Multiplayer Needed
	set_collision_layer_value(2, TorF)
	set_collision_mask_value(1, TorF)
	Sprite.visible = TorF
