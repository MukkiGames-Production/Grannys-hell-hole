extends GrabbableObject

@export var force: float = 10.0
var rocket_scene: PackedScene = preload("res://scenes/Objects/rocket.tscn")

func _ready() -> void:
	super._ready()
	# Rotate 90 degrees around X or Y axis so it points forward instead of horizontal
	hold_rotation_offset = Vector3(-PI/2, PI/2, 0)

func use() -> void:
	print("RPG use() called")
	fire()

func fire() -> void:
	print("RPG fire() called.")
	if not rocket_scene:
		print("Error: rocket_scene not loaded.")
		return

	# Instantiate a new rocket from the scene
	var rocket_instance = rocket_scene.instantiate()
	get_tree().current_scene.add_child(rocket_instance)

	# Determine the forward direction
	var forward_dir = -global_transform.basis.z.normalized()
	if holder:
		forward_dir = -holder.global_transform.basis.z.normalized()

	var rocket_velocity = forward_dir * force * 5.0
	print("Firing rocket with velocity ", rocket_velocity)

	# Match the launcher's position and rotation without non-uniform scale
	var spawn_xform = global_transform
	spawn_xform.basis = spawn_xform.basis.orthonormalized()
	rocket_instance.global_transform = spawn_xform
	rocket_instance.scale = Vector3(0.05, 0.05, 0.05)

	# Since the new rocket scene uses a RigidBody3D child for physics,
	# we can just apply velocity to it directly so it flies naturally!
	var rb = rocket_instance.get_node_or_null("RigidBody3D")
	if rb is RigidBody3D:
		rb.linear_velocity = rocket_velocity
