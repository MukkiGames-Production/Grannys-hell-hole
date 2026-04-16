extends PhantomObject
class_name Tripwire

const TEST_ARMED_TRIPWIRE_MESH = preload("res://Assets/objects/Tripwire/test_armed_tripwire_mesh.tres")
const TEST_OTHER_TRIPWIRE_MESH = preload("res://Assets/objects/Tripwire/test_other_tripwire_mesh.tres")

@onready var tripwire_in_hand_mesh: MeshInstance3D = $MeshInstance3D
@export var reparent_target : Node3D
@onready var sides_node: Node3D = $"../Sides"
@onready var line_drawer: MeshInstance3D = $"../LineDrawer"

enum PlacePhase {
	PLACE_ARMED,
	PLACE_OTHER
}

var place_phase := PlacePhase.PLACE_ARMED
var armed_side_instance: MeshInstance3D = null

func _ready():
	super._ready()
	var parent := get_parent_node_3d()
	_clear_preview_line()
	
	reparent_target = parent.get_parent_node_3d()

func _physics_process(delta):
	super._physics_process(delta)

	if place_phase == PlacePhase.PLACE_OTHER and armed_side_instance != null and valid_placement:
		var start := armed_side_instance.global_position
		start.y += 0.1

		var end = valid_position
		_draw_preview_line(start, end)
	else:
		_clear_preview_line()

func special() -> void: # right click to place at the current phantom location
	if not valid_placement:
		return

	if place_phase == PlacePhase.PLACE_ARMED:
		var armed_side := MeshInstance3D.new()
		armed_side.mesh = TEST_ARMED_TRIPWIRE_MESH
		sides_node.add_child(armed_side)
		armed_side.global_position = valid_position
		armed_side.global_rotation = phantom_mesh.global_rotation

		armed_side_instance = armed_side
		place_phase = PlacePhase.PLACE_OTHER

	elif place_phase == PlacePhase.PLACE_OTHER:
		var other_side := MeshInstance3D.new()
		other_side.mesh = TEST_OTHER_TRIPWIRE_MESH
		sides_node.add_child(other_side)
		other_side.global_position = valid_position
		other_side.global_rotation = phantom_mesh.global_rotation
		consume([sides_node, line_drawer], reparent_target)
		
		#_clear_preview_line()

func _draw_preview_line(world_start: Vector3, world_end: Vector3) -> void:
	if line_drawer == null:
		return

	var immediate_mesh := line_drawer.mesh as ImmediateMesh
	if immediate_mesh == null:
		return

	immediate_mesh.clear_surfaces()

	var local_start := line_drawer.to_local(world_start)
	var local_end := line_drawer.to_local(world_end)

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_add_vertex(local_start)
	immediate_mesh.surface_add_vertex(local_end)
	immediate_mesh.surface_end()

func _clear_preview_line() -> void:
	if line_drawer == null:
		return

	var immediate_mesh := line_drawer.mesh as ImmediateMesh
	if immediate_mesh == null:
		return

	immediate_mesh.clear_surfaces()
