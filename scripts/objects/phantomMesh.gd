extends MeshInstance3D
class_name PhantomMesh

var father : MeshInstance3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	father = self.get_parent()
	self.mesh = father.mesh


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
