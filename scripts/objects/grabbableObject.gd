extends RigidBody3D
class_name GrabbableObject

@export var item_id: String = ""  # unique identifier for this object
@export var hold_distance := 1.0
@export var follow_speed := 15.0
@export var hold_offset := Vector3(0.6, -0.4, -2.0)
@export var is_grabbable := true

var is_held := false
var holder: Node3D = null

func _physics_process(delta):
	if not is_held or holder == null:
		return

	# Desired position in front of the holder (camera)
	var target_pos = holder.global_transform.origin + holder.global_transform.basis.z * -hold_distance + holder.global_transform.basis.x * 0.6 + holder.global_transform.basis.y * -0.3

	# Smooth follow
	global_position = global_position.lerp(target_pos, follow_speed * delta)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

#grab helper
func grab(camera: Node3D):
	is_held = true
	holder = camera
	freeze = true

func release():
	is_held = false
	holder = null
	freeze = false
