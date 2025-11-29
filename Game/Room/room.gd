extends RoomClass

func _ready() -> void:
	z_index = Global.Layers.FLOOR

func _on_body_entered(body: Node2D) -> void:
	##TODO: Rewrite so mult.get_ yadda yada can be called from Server
	if !Server.OFFLINE and multiplayer.get_unique_id() != int(body.name): return
	Global.is_current_room(self, true)
