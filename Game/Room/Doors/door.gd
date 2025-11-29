class_name DoorClass extends StaticBody2D
@export var invincible: bool = false

@onready var block_1: Sprite2D = $Blocks/Block1
@onready var block_2: Sprite2D = $Blocks/Block2
@onready var block_3: Sprite2D = $Blocks/Block3
@onready var block_4: Sprite2D = $Blocks/Block4
@onready var block_5: Sprite2D = $Blocks/Block5
@onready var block_6: Sprite2D = $Blocks/Block6

var durability_max: int = 3
var durability: int = durability_max
var under_attack: bool = false
var iframes_max_sec: float = 0.5
var iframes: float = iframes_max_sec

# Variables for rumble effect
var original_positions: Array = []
var rumble_intensity: float = 1.0
var is_rumbling: bool = false

var broken: CompressedTexture2D = preload("res://Game/Room/Doors/wall_demolished.png")

func _ready() -> void:
	# Store original positions of blocks
	original_positions = [
		block_1.position,
		block_2.position,
		block_3.position,
		block_4.position,
		block_5.position,
		block_6.position
	]

func _process(delta: float) -> void:
	
	if durability <= 0:
		destroy.rpc()
	
	if iframes > 0:
		iframes -= delta
		
		# Apply rumble effect during iframes
		if not is_rumbling:
			is_rumbling = true
		apply_rumble()
	else:
		# Reset positions when iframes end
		if is_rumbling:
			reset_block_positions()
			is_rumbling = false
	
	if under_attack:
		under_attack = false
		iframes = iframes_max_sec
		if !invincible:
			durability -= 1



func _physics_process(_delta: float) -> void:
	var collision: KinematicCollision2D = move_and_collide(Vector2.ZERO, true)
	if collision:
		if collision.get_collider().is_in_group("Weapon"):
			under_attack = true


func apply_rumble() -> void:
	# Apply random offset to each block
	block_1.position = original_positions[0] + Vector2(randf_range(-rumble_intensity, rumble_intensity), randf_range(-rumble_intensity, rumble_intensity))
	block_2.position = original_positions[1] + Vector2(randf_range(-rumble_intensity, rumble_intensity), randf_range(-rumble_intensity, rumble_intensity))
	block_3.position = original_positions[2] + Vector2(randf_range(-rumble_intensity, rumble_intensity), randf_range(-rumble_intensity, rumble_intensity))
	block_4.position = original_positions[3] + Vector2(randf_range(-rumble_intensity, rumble_intensity), randf_range(-rumble_intensity, rumble_intensity))
	block_5.position = original_positions[4] + Vector2(randf_range(-rumble_intensity, rumble_intensity), randf_range(-rumble_intensity, rumble_intensity))
	block_6.position = original_positions[5] + Vector2(randf_range(-rumble_intensity, rumble_intensity), randf_range(-rumble_intensity, rumble_intensity))

func reset_block_positions() -> void:
	# Reset blocks to original positions
	block_1.position = original_positions[0]
	block_2.position = original_positions[1]
	block_3.position = original_positions[2]
	block_4.position = original_positions[3]
	block_5.position = original_positions[4]
	block_6.position = original_positions[5]

@rpc("any_peer", "call_local", "reliable")
func destroy() -> void:
	#queue_free()
	self.set_collision_layer_value(1, false)
	self.set_process(false)
	#hide()
	#block_1.texture = broken
	#block_2.texture = broken
	#block_3.texture = broken
	block_1.hide()
	block_2.hide()
	block_3.hide()
	block_4.hide()
	block_5.hide()
	block_6.hide()
	$Broken.show()
