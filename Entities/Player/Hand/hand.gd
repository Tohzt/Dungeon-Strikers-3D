class_name PlayerHandClass extends Node2D
@onready var arm: RayCast2D = $Arm
@onready var hand: Sprite2D = $Arm/Hand
@onready var particles: GPUParticles2D = $Arm/Hand/GPUParticles2D

@export_enum("left", "right") var handedness: String
@export var hand_offset: Vector2 = Vector2(0,-16)
var default_hand_distance: float
@export var particle: GPUParticles2D

var is_attacking: bool = false
var attack_dur := 0.1
var attack_dur_max := 0.1
var def_arm_rot: float
var def_arm_length: float
var held_weapon: WeaponClass = null

func _ready() -> void:
	def_arm_rot = arm.rotation
	def_arm_length = arm.target_position.length()
	hand_offset = Vector2(0,-16)

func _physics_process(delta: float) -> void:
	# If a weapon is equipped, let the weapon controller handle arm movement
	if held_weapon:
		# Only handle hand positioning, not arm rotation
		sprint_arm(delta)
	else:
		# Original attack system when no weapon is equipped
		if is_attacking: 
			particles.emitting = true
			attack(delta)
		else: 
			particles.emitting = false
			arm.rotation = lerp_angle(arm.rotation, def_arm_rot, delta*10)
			sprint_arm(delta)

func attack(delta: float) -> void:
	var rot_amt := 5
	match handedness:
		"left":
			rot_amt *= 1
		"right":
			rot_amt *= -1
	arm.rotation += rot_amt * delta*3
	attack_dur -= delta
	if attack_dur <= 0:
		attack_dur = attack_dur_max
		is_attacking = false

func sprint_arm(delta: float) -> void:
	var default_position: Vector2 = arm.target_position
	
	if arm.is_colliding():
		var collision_point: Vector2 = arm.to_local(arm.get_collision_point())
		var new_pos: Vector2 = collision_point + hand_offset
		hand.position = lerp(hand.position, new_pos, delta*10)
	else:
		hand.position = lerp(hand.position, default_position, delta*10)
