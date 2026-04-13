extends Node3D

var is_active := true

func _on_area_3d_body_entered(body: Node3D) -> void:
	if is_active:
		if body is BasePlayer or body is DummyPlayer:
			body.snap_trap()
			print("TRAP applied!")
			body.connect("trap_free", Callable(self, "_on_body_freed"))
			is_active = false

func _on_body_freed():
	queue_free()
