extends GrabbableObject
@onready var Plunger:MeshInstance3D = $Plunger

func on_fast_hit(body: Node3D) -> void:
	replace_model(Plunger.mesh, "Plunger")
