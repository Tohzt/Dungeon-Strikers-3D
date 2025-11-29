class_name ChestClass extends StaticBody2D

@export var has_items: bool
@export var items: Array[Resource]
var nearby: Array[Node2D]


func open_chest() -> void:
	if items:
		for item in items:
			var _item: WeaponClass = Global.WEAPON.instantiate()
			_item.Properties = item
			var _offset := Vector2(randi_range(-20, 20), randi_range(-20, 20))
			_item.global_position = global_position + _offset
			get_parent().add_child(_item)
	queue_free()


func _on_area_2d_body_entered(body: Node2D) -> void:
	nearby.append(body)


func _on_area_2d_body_exited(body: Node2D) -> void:
	if nearby.has(body):
		nearby.remove_at(nearby.find(body))
