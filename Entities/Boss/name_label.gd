extends Label

func _ready() -> void:
	text = get_parent().name
	
func _process(_delta: float) -> void:
	text = str(get_parent().name_display)
	global_position = get_parent().global_position - Vector2(50,82)
