extends StateClass


func _ready() -> void:
	super._ready()

func enter_state() -> void:
	super.enter_state()
	exit_to("wander_state")
