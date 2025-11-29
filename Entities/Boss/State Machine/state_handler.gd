class_name StateHandlerClass extends Node
@export var Master: CharacterBody2D
@export var state_init: StateClass

var state_current: StateClass
var state_next: StateClass

func _ready() -> void:
	if state_init:
		state_current = state_init
		state_current.enter_state()

func change_state(new_state: StateClass) -> void:
	if state_current == new_state: return
		
	state_next = new_state
	_handle_state_transition()

func _handle_state_transition() -> void:
	if state_next and state_next != state_current:
		state_current = state_next
		state_current.enter_state()
		state_next = null
