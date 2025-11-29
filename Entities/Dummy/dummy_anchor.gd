extends Node2D
@export var chain_scene: PackedScene
@export var ball_scene: PackedScene
@export var chain_segments: int = 5
@export var segment_distance: float = 40.0
@export var joint_stiffness: float = 0.0
@export var joint_damping: float = 1.0

func _ready() -> void:
	call_deferred("create_chain")

func create_chain() -> void:
	# Create Anchor
	var anchor := StaticBody2D.new()
	anchor.name = "Anchor"
	anchor.collision_layer = 0
	anchor.collision_mask = 0
	var anchor_collision := CollisionShape2D.new()
	var anchor_shape := RectangleShape2D.new()
	anchor_shape.size = Vector2(16, 16)
	anchor_collision.shape = anchor_shape
	anchor.add_child(anchor_collision)
	add_child(anchor)
	anchor.position = Vector2.ZERO
	
	var previous_link: Node2D = anchor
	var chain_links := []
	
	for i in range(chain_segments):
		if not chain_scene: return
		var chain_link := chain_scene.instantiate()
		chain_link.name = "Chain_" + str(i)
		chain_link.position = Vector2(0, (i + 1) * segment_distance)
		add_child(chain_link)
		chain_links.append(chain_link)
		
		var joint := PinJoint2D.new()
		joint.name = "Joint_" + str(i)
		add_child(joint)
		
		if i == 0: joint.position = Vector2(0, segment_distance / 2)
		else: joint.position = Vector2(0, (i + 0.5) * segment_distance)
		
		joint.softness = 1.0 - joint_stiffness
		joint.bias = joint_damping
		
		joint.node_a = joint.get_path_to(previous_link)
		joint.node_b = joint.get_path_to(chain_link)
		
		previous_link = chain_link
	
	if ball_scene:
		var ball := ball_scene.instantiate()
		ball.name = "Ball"
		ball.position = Vector2(0, (chain_segments + 1) * segment_distance)
		add_child(ball)
		
		var final_joint := PinJoint2D.new()
		final_joint.name = "BallJoint"
		add_child(final_joint)
		
		final_joint.position = ball.position
		
		final_joint.softness = 1.0 - joint_stiffness
		final_joint.bias = joint_damping
		
		final_joint.node_a = final_joint.get_path_to(previous_link)
		final_joint.node_b = final_joint.get_path_to(ball) 
