extends StateClass


@export var attack_resources: Array[AttackResource]
var current_attack: AttackBaseClass

func enter_state() -> void:
	##TODO: Get nearest target.. or whatever should take the agro
	## Get all in range and calculate agro deltas
	Master.target = Global.get_nearest(Master.global_position, "Entity", INF)["inst"]
	super.enter_state()

func update(_delta: float) -> void:
	if !Master.target_locked:
		exit_to("wander_state")
		return
	
	# Clear current_attack if it's been destroyed
	if current_attack and !is_instance_valid(current_attack):
		current_attack = null
	
	# Check if we should start a new attack
	if !current_attack and Master.ATTACK_COOLDOWN <= 0:
		_decide_attack()
	
	# Only move if not casting
	if current_attack and current_attack.is_casting:
		Master.velocity = Vector2.ZERO
		return

func _decide_attack() -> void:
	var attack_list: Array = Master.Attack_List
	var attack_node: AttackBaseClass = attack_list.pick_random().instantiate()
	if attack_node:
		attack_node.global_position = Master.target.global_position
		add_child(attack_node)
		Master.ATTACK_COOLDOWN = attack_node.attack_data.attack_cooldown
		current_attack = attack_node
		attack_node.start_cast()
