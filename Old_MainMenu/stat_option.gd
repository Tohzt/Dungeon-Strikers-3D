class_name StatOptionClass extends HBoxContainer

enum StatType { STRENGTH, ENDURANCE, INTELLIGENCE }
@export var Stat_Type: StatType
@export var Stat_Color: Color

@onready var Menu: MenuClass = get_tree().get_first_node_in_group("Main Menu")
@onready var stat_value: ProgressBar = $"Control/Stat Value"

func _ready() -> void:
	stat_value.max_value = Menu.STAT_POINTS_MAX
	stat_value.modulate = Stat_Color
	match Stat_Type:
		StatType.STRENGTH: 
			$"Control/Stat Name".text = "  STRENGTH  "
		StatType.ENDURANCE: 
			$"Control/Stat Name".text = "  ENDURANCE  "
		StatType.INTELLIGENCE: 
			$"Control/Stat Name".text = "  INTELLIGENCE  "

func _on_decrement_pressed() -> void: 
	if stat_value.value > 0:
		if Menu.STAT_POINTS < Menu.STAT_POINTS_MAX:
			stat_value.value = stat_value.value-1
			Menu.update_points(1)

func _on_increment_pressed() -> void: 
	if stat_value.value < Menu.STAT_POINTS_MAX:
		if Menu.STAT_POINTS > 0:
			stat_value.value = stat_value.value+1
			Menu.update_points(-1)
