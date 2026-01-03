class_name Game3D_Class extends Node3D

signal set_camera_active(TorF: bool)

@onready var ball: RigidBody3D = $Ball_3D
@onready var Player: CharacterBody3D = $CharacterBody3D
@onready var HUD: HUD3D = $HUD

func _enter_tree() -> void: Global.Game3D = self

func _ready() -> void:
	if HUD and Player:
		HUD.game = self
	
	await get_tree().create_timer(3.0).timeout
	set_camera_active.emit(true)


func _process(_delta: float) -> void: pass


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if ball:
			ball.global_position = ball.starting_position
