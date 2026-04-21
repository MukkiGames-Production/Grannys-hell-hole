extends InteractionPoint

@export var tnt: Node3D
@export var throw_force: float = 20.0
@export var basketball: Node3D
@export var marker: Marker3D

func _on_body_entered(body: Node3D) -> void:
	print("body entered: ", body.name)

	# Accept direct match OR child of basketball
	var is_basketball := body == basketball or basketball.is_ancestor_of(body)
	if not is_basketball:
		return

	if is_instance_valid(basketball):
		basketball.queue_free()

	# Wake + reset TNT movement
	var tnt_rigid := tnt.find_child("GrabbableObject", true)
	tnt_rigid.linear_velocity = Vector3.ZERO
	tnt_rigid.angular_velocity = Vector3.ZERO

	# Throw toward marker (or swap marker with player node if needed)
	var dir := (marker.global_position - tnt.global_position).normalized()
	tnt_rigid.apply_central_impulse(dir * throw_force)
