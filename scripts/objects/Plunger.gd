extends GrabbableObject
@export var Plunger: Mesh

func on_fast_hit(body: Node3D) -> void:
	replace_model(Plunger, "Plunger")
