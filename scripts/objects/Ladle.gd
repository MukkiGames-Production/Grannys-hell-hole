extends GrabbableObject

@export var Ladle: Mesh

func on_fast_hit(body: Node3D) -> void:
	replace_model(Ladle, "Ladle")
