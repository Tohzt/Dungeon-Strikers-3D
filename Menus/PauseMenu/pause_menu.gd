extends CanvasLayer
## In-match pause overlay. Start (controller) or Esc (keyboard) toggles it;
## B also resumes. Runs while the tree is paused (process_mode = Always).

const MAIN_MENU := "res://Menus/MainMenu/main_menu.tscn"

@onready var resume_button: Button = %Resume


func _ready() -> void:
	hide()
	resume_button.pressed.connect(resume)
	%ResetBall.pressed.connect(_on_reset_ball)
	%ResetGame.pressed.connect(_on_reset_game)
	%MainMenu.pressed.connect(_on_main_menu)
	%ExitGame.pressed.connect(get_tree().quit)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if visible:
			resume()
		else:
			pause()
	elif visible and event.is_action_pressed("ui_cancel"):
		resume()
	else:
		return
	get_viewport().set_input_as_handled()


func pause() -> void:
	show()
	get_tree().paused = true
	resume_button.grab_focus()


func resume() -> void:
	hide()
	get_tree().paused = false


func _on_reset_ball() -> void:
	if Global.Game3D:
		Global.Game3D.reset_ball()
	resume()


## Restart the match with the same players (they stay joined in Players).
func _on_reset_game() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU)
