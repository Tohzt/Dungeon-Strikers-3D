extends Label

@onready var wander_state := get_parent().get_node("State Handler/Boss_Wander")

func _ready() -> void:
	if wander_state:
		wander_state.target_position_changed.connect(_on_target_position_changed)
	else:
		push_error("Could not find wander state node")

func _on_target_position_changed(new_position: Vector2) -> void:
	global_position = new_position
