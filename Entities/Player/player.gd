class_name PlayerClass extends CharacterBody2D

@export_category("Handlers")
@export var Hands: Node2D
@export var Properties: PlayerResource
@export var Input_Handler: PlayerInputHandler
@export var Action_Handler: PlayerActionHandler

@onready var EB: EntityBehaviorClass = $EntityBehavior


# ===== GODOT ENGINE FUNCTIONS =====
#func _enter_tree() -> void:
	#if multiplayer.has_multiplayer_peer():
		#var peer_id := int(str(name))
		#EB.name_display = Global.player_display_name
		#if EB.name_display.is_empty(): EB.name_display = name
		#set_multiplayer_authority(peer_id)

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	##HACK: Waiting for update to multiplayer/offline
	#if !Server.OFFLINE and !is_multiplayer_authority(): return
	_handle_target()
	_handle_rotation(delta)

func _physics_process(delta: float) -> void:
	##HACK: Waiting for update to multiplayer/offline
	#if !Server.OFFLINE and !is_multiplayer_authority(): return
	
	if EB.is_active and EB.has_control:
		var move_dir: Vector2 = Input_Handler.move_dir
		if move_dir:
			var prev_dir: Vector2 = velocity.normalized()
			velocity.x = lerp(prev_dir.x, move_dir.x, delta*10) * EB.SPEED
			velocity.y = lerp(prev_dir.y, move_dir.y, delta*10) * EB.SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, EB.SPEED)
			velocity.y = move_toward(velocity.y, 0, EB.SPEED)
		
		move_and_slide()


func _handle_target() -> void:
	# Handle target scrolling (cycle through targets)
	if Input_Handler.target_scroll:
		print("DEBUG: target_scroll input detected - EB.target exists: ", EB.target != null)
	if EB.target and Input_Handler.target_scroll:
		var current_target_name: String = String(EB.target.name) if is_instance_valid(EB.target) else "null"
		print("DEBUG: Scroll detected - Current target: ", current_target_name)
		Input_Handler.target_scroll = false
		# Get nearest entity, excluding the current target if it's still valid
		var exclude_target: Node2D = EB.target if is_instance_valid(EB.target) else null
		var exclude_name: String = String(exclude_target.name) if exclude_target else "null"
		print("DEBUG: Excluding target: ", exclude_name)
		var nearest := Global.get_nearest(global_position, "Entity", INF, exclude_target)
		print("DEBUG: get_nearest result - found: ", nearest.get("found", false), ", dist: ", nearest.get("dist", INF), ", inst: ", nearest.get("inst", null))
		if nearest.get("found", false):
			EB.target = nearest["inst"]
			var new_target_name: String = String(EB.target.name) if is_instance_valid(EB.target) else "null"
			print("DEBUG: Target updated to: ", new_target_name)
		else:
			print("DEBUG: No new target found, keeping current target")
	
	# Handle target toggle (target nearest or clear current)
	if Input_Handler.target_toggle:
		Input_Handler.target_toggle = false
		if EB.target and is_instance_valid(EB.target):
			# Clear current target
			EB.target = null
		else:
			# Find nearest entity
			var nearest := Global.get_nearest(global_position, "Entity", INF)
			if nearest.get("found", false):
				EB.target = nearest["inst"]


func _handle_rotation(delta: float) -> void:
	if EB.target and is_instance_valid(EB.target):
		var direction: Vector2 = (EB.target.global_position - global_position).normalized()
		rotation = lerp_angle(rotation, direction.angle() + PI/2, delta * Input_Handler.MOUSE_LOOK_STRENGTH)
	elif !Input_Handler.look_dir.is_zero_approx():
		rotation = lerp_angle(rotation, Input_Handler.look_dir.angle() + PI/2, delta * Input_Handler.MOUSE_LOOK_STRENGTH)
	elif !velocity.is_zero_approx():
		rotation = lerp_angle(rotation, velocity.angle() + PI/2, delta * 10)


# ===== COMBAT FUNCTIONS =====
@rpc("any_peer", "call_local")
func attack(_atk_dir: float, atk_side: String) -> void:
	var hand: int = 0 if atk_side == "left" else 1
	var target_hand: PlayerHandClass = Hands.get_child(hand)
	
	# Only set is_attacking if no weapon is equipped (legacy attack system)
	if !target_hand.held_weapon:
		target_hand.is_attacking = true
	
	if multiplayer.get_unique_id() != 1: return
	
	var entities_node: Node2D = get_tree().get_first_node_in_group("Entities")
	if !entities_node: return


# ===== PLAYER STATE MANAGEMENT =====
@rpc("any_peer", "call_remote", "reliable")
func set_pos_and_sprite(pos: Vector2, rot: float, color: Color) -> void:
	if Server.OFFLINE or multiplayer.get_unique_id() == int(name):
		##TODO: You know...
		get_parent().get_parent().HUD.set_hud(color, EB.hp_max)
		$Label.hide()

	EB.spawn_pos = pos
	rotation = rot
	EB.reset()


# ===== UTILITY FUNCTIONS =====
func get_left_weapon() -> WeaponClass:
	return Hands.Left.held_weapon

func get_right_weapon() -> WeaponClass:
	return Hands.Right.held_weapon
