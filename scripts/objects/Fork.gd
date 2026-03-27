extends GrabbableObject

@export var lockpick: Mesh


func on_fast_hit(body: Node3D) -> void:
	replace_model(lockpick, "Lockpick")
