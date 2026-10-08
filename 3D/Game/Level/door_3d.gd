class_name Door3D extends StaticBody3D
## A gate that blocks a doorway until it's opened, then swings open for
## good. Made to sit in BetterDungeon's wall_gateDoor wall piece: the
## doorway runs along local X, centered on the door's origin.
##
## Something has to open it: set key_boss and it opens once that boss
## falls, or call open() (e.g. the race opens every start gate at once).
## Either way it happens on every machine together: a boss falls on every
## machine, and open() is meant to be called from an Net.everywhere RPC.

## The door swung open. On every machine.
signal opened

## Opens when this boss is defeated. Set before the door enters the tree.
@export var key_boss: Boss3D
## Seconds the swing takes.
@export var open_time: float = 0.9
## How far the gate swings (away from the side it's seen from, +Z).
@export var swing_degrees: float = 100.0
## Shown on the scoreboard as it opens (empty = nothing).
@export var message: String = ""

## Turns about the hinge (the doorway's -X edge); holds the gate model.
@onready var leaf: Node3D = $Leaf
@onready var shape: CollisionShape3D = $CollisionShape3D

var is_open: bool = false


func _ready() -> void:
	add_to_group("Door")
	if key_boss:
		key_boss.defeated.connect(_on_key_boss_defeated, CONNECT_ONE_SHOT)


func _on_key_boss_defeated(_killer: PlayerClass3D) -> void:
	open()


## Swing open and stop blocking the way (on this machine).
func open() -> void:
	if is_open:
		return
	is_open = true
	shape.set_deferred(&"disabled", true)  # May be mid physics step (a boss's death)
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(leaf, ^"rotation_degrees:y", -swing_degrees, open_time)
	Sfx.play(&"chest_open", global_position)
	if message != "" and Global.Game3D:
		Global.Game3D.scoreboard.announce(message, Color(1.0, 0.85, 0.4))
	opened.emit()
