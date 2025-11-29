extends Node3D
@onready var ball: RigidBody3D = $Ball_3D
@onready var Player: CharacterBody3D = $CharacterBody3D
@onready var HUD: HUD3D = $HUD


func _ready() -> void:
	# Connect HUD to player if available
	if HUD and Player:
		HUD.game = self
		# HUD will connect signals in its _process
	
	# Ensure player has Entity node (renamed from EntityBehavior)
	if Player and not Player.has_node("Entity"):
		print_debug("WARNING: Player3D missing Entity child node!")


func _process(_delta: float) -> void: 
	pass


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if ball:
			ball.global_position = ball.starting_position
