class_name PlayerInputHandler extends Node
@onready var Master: PlayerClass = get_parent()

var move_dir: Vector2
var look_dir: Vector2 = Vector2.ZERO
var action_left: bool = false
var action_right: bool = false
var dodge: bool = false
var interact: bool = false
var interact_held: bool = false
var target_toggle: bool = false
var target_scroll: bool = false

# Mouse movement tracking
var last_mouse_pos: Vector2
var mouse_movement_timer: float = 0.0
const MOUSE_MOVEMENT_COOLDOWN: float = 0.5
const MOUSE_LOOK_STRENGTH: float = 15.0


func _ready() -> void:
	last_mouse_pos = Master.get_global_mouse_position()


func _process(delta: float) -> void:
	move_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_handle_look_input(delta)


func _handle_look_input(delta: float) -> void:
	if Global.input_type == "Keyboard":
		var current_mouse_pos: Vector2 = Master.get_global_mouse_position()
		if current_mouse_pos != last_mouse_pos:
			look_dir = (current_mouse_pos - Master.global_position).normalized()
			mouse_movement_timer = MOUSE_MOVEMENT_COOLDOWN
		else:
			mouse_movement_timer -= delta
			if mouse_movement_timer <= 0:
				look_dir = Vector2.ZERO
	
	elif Global.input_type == "Controller":
		var controller_input: Vector2 = Input.get_vector("aim_left","aim_right","aim_up","aim_down")
		if controller_input:
			look_dir = controller_input
			mouse_movement_timer = MOUSE_MOVEMENT_COOLDOWN
		else:
			mouse_movement_timer -= delta
			if mouse_movement_timer <= 0:
				look_dir = Vector2.ZERO


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		last_mouse_pos = Master.get_global_mouse_position()
		mouse_movement_timer = MOUSE_MOVEMENT_COOLDOWN
		look_dir = (last_mouse_pos - Master.global_position).normalized()
	
	if event.is_action("attack_left"):
		action_left = event.is_action_pressed("attack_left")
	
	if event.is_action("attack_right"):
		action_right = event.is_action_pressed("attack_right")
	
	if event.is_action("dodge"):
		dodge = event.is_action_pressed("dodge")
	
	if event.is_action("interact"):
		interact =  event.is_action_pressed("interact")
	
	if event.is_action("target"):
		target_toggle = event.is_action_pressed("target")
	
	if event.is_action("target_scroll"):
		if event.is_action_pressed("target_scroll"):
			target_scroll = true
