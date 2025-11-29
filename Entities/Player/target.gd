extends TextureRect
@onready var Master: PlayerClass = get_parent()
var offset: Vector2 = Vector2(-64,-64)

func _ready() -> void:
	hide()

func _process(_delta: float) -> void:
	##HACK: This just feels weird... 
	if !Master.EB.Sprite: return
	modulate = Master.EB.Sprite.modulate
	if Master.EB.target:
		global_position = Master.EB.target.global_position + offset
		if !visible: show()
	else:
		position = Vector2.ZERO
		if visible: hide()
