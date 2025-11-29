class_name MenuClass extends Node
@onready var Menu_UI: CanvasLayer = $"Menu UI"
@onready var Room: RoomClass = $"Rooms/Room Center"
@onready var Player: PlayerClass = $Player
@onready var Player_Name: LineEdit = $"Menu UI/Multiplayer/MarginContainer/VBoxContainer/Character Select/VBoxContainer/DisplayName"
@onready var Strength: StatOptionClass = $"Menu UI/Multiplayer/MarginContainer/VBoxContainer/Character Select/VBoxContainer/Strength"
@onready var Endurance: StatOptionClass = $"Menu UI/Multiplayer/MarginContainer/VBoxContainer/Character Select/VBoxContainer/Endurance"
@onready var Intelligence: StatOptionClass = $"Menu UI/Multiplayer/MarginContainer/VBoxContainer/Character Select/VBoxContainer/Intelligence"
var Player_Color: Color

@export var STAT_POINTS_MAX: int = 5
var STAT_POINTS: int = STAT_POINTS_MAX
var character_select: bool = false

func _on_host_pressed() -> void: Server.Create()
func _on_join_pressed() -> void: Server.Join()
func _on_quit_pressed() -> void: get_tree().quit()
func _on_quick_play_pressed() -> void:
	#enter_character_select(!character_select)
	hide_UI()
	
	# Create a new PlayerResource instance instead of modifying the shared one
	var new_properties := PlayerResource.new()
	new_properties.player_name = Player_Name.text
	new_properties.player_id = multiplayer.get_unique_id()
	new_properties.player_color = Player_Color
	new_properties.player_strength = int(Strength.stat_value.value)
	new_properties.player_endurance = int(Endurance.stat_value.value)
	new_properties.player_intelligence = int(Intelligence.stat_value.value)
	#Player.Properties.player_name = Player_Name.text
	#Player.Properties.player_id = multiplayer.get_unique_id()
	#Player.Properties.player_color = Player_Color
	#Player.Properties.player_strength = int(Strength.stat_value.value)
	#Player.Properties.player_endurance = int(Endurance.stat_value.value)
	#Player.Properties.player_intelligence = int(Intelligence.stat_value.value)
	
	Global.resources_to_load.append(new_properties)
	Server.Offline()

#func _ready() -> void:
	#Player.EB.spawn_pos = Player.global_position
	#Player.EB.set_color()
	#update_points(0)

func _process(_delta: float) -> void:
	var bodies := Room.area.get_overlapping_bodies()
	if bodies.is_empty():
		# Save player's weapons before transitioning
		Global.save_player_weapons(Player)
		get_tree().change_scene_to_file(Global.GAME)
	pass


func _on_display_name_text_changed(new_text: String) -> void:
	Global.player_display_name = new_text

func enter_character_select(TorF: bool) -> void:
	character_select = TorF
	#$CanvasLayer/Multiplayer/VBoxContainer.visible = !TorF
	#$CanvasLayer/Multiplayer/HBoxContainer.visible = TorF

func update_points(amt: int) -> void:
	var _str := Strength.stat_value.value/STAT_POINTS_MAX
	var _end := Endurance.stat_value.value/STAT_POINTS_MAX
	var _int := Intelligence.stat_value.value/STAT_POINTS_MAX
	var _red   := 1 - _end - _int
	var _green := 1 - _str - _int
	var _blue  := 1 - _str - _end
	Player_Color = Color(_red, _green, _blue)
	Player.EB.set_color(Player_Color)
	
	# Update player stats and max values in real-time
	var strength_value: int = int(Strength.stat_value.value) + 10
	var intelligence_value: int = int(Intelligence.stat_value.value) + 10
	var endurance_value: int = int(Endurance.stat_value.value) + 10
	
	Player.EB.strength = strength_value
	Player.EB.intelligence = intelligence_value
	Player.EB.endurance = endurance_value
	
	##TODO: Confirm these are correct
	# Update max values based on stats
	Player.EB.hp_max = float(strength_value * 50)  # Scale strength to HP
	Player.EB.mana_max = float(intelligence_value * 10)  # Scale intelligence to mana
	Player.EB.stamina_max = float(endurance_value)
	
	# Update current values to match new max values
	Player.EB.hp = Player.EB.hp_max
	Player.EB.mana = Player.EB.mana_max
	Player.EB.stamina = Player.EB.stamina_max
	
	STAT_POINTS += amt
	var display: Label = $"Menu UI/Multiplayer/MarginContainer/VBoxContainer/Character Select/VBoxContainer/Points Remaining"
	display.text = "(%d) points remaining" % STAT_POINTS

func hide_UI() -> void:
	Menu_UI.hide()
