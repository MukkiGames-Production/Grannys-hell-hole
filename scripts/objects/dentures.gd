extends PhantomObject
class_name Dentures

const DENTURES_MESH = preload("res://Assets/objects/Dentures/test_dentures_mesh.tres")  #I literally have no idea what is going on here
const DENTURES_SCENE = preload("res://scenes/ActiveDentures.tscn")

@onready var dentures_in_hand_mesh: MeshInstance3D = $MeshInstance3D

@export var reparent_target: Node3D

func _ready() -> void:
	super._ready()
	var parent := get_parent_node_3d()
	reparent_target = parent.get_parent_node_3d()
	
	# Optional: hide the in-hand mesh preview if you want the phantom to show the real trap
	# trap_in_hand_mesh.visible = false

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	# No line preview needed for a bear trap

# Right-click to place
func special() -> void:
	if not valid_placement:
		return
	
	# Instantiate the real trap
	var dentures = DENTURES_SCENE.instantiate()
	
	dentures.global_transform = phantom_mesh.global_transform
	dentures.global_position = valid_position + Vector3(0, 0.3, 0)
	
	# Add it to the world
	get_tree().current_scene.add_child(dentures)
	
	# Remove from player's hand
	consume([], reparent_target)
