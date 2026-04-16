extends GrabbableObject
class_name PhantomObject

@export var phantom_mesh: MeshInstance3D

var valid_placement := false
var valid_position = null

func _ready():
	super._ready()
	valid_placement = false

func _physics_process(delta):
	super._physics_process(delta)
	var hit := get_holder_look_hit(5.5)

	if _is_floor_hit(hit):
		valid_placement = true
		valid_position = hit.position
		phantom_mesh.global_position = hit.position
	else:
		valid_placement = false
		valid_position = null
		var hidden_pos := phantom_mesh.global_position
		hidden_pos.y -= 20.0
		phantom_mesh.global_position = hidden_pos
	
	phantom_mesh.global_rotation.x = 0.0
	phantom_mesh.global_rotation.z = 0.0

func special() -> void: #right click to place at the current phantom location
	if not valid_placement:
		return
	
	

func special_released():
	pass

func _is_floor_hit(hit: Dictionary) -> bool:
	if hit.is_empty():
		return false

	var collider = hit.get("collider")
	return collider is StaticBody3D and collider.name == "Floor"
