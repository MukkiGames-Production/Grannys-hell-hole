extends InteractionPoint

@export var tnt: RigidBody3D
@export var throw_force: float = 20.0
@export var basketball: Node3D
@onready var marker: Marker3D = $Marker3D

func _on_body_entered(body: Node3D) -> void:
	print("body entered: ", body.name)

	# Accept direct match OR child of basketball
	var is_basketball := body == basketball or basketball.is_ancestor_of(body)
	if not is_basketball:
		return

	if is_instance_valid(basketball):
		basketball.queue_free()

	# Wake + reset TNT movement
	tnt.sleeping = false
	tnt.linear_velocity = Vector3.ZERO
	tnt.angular_velocity = Vector3.ZERO

	# Throw toward marker (or swap marker with player node if needed)
	var dir := (marker.global_position - tnt.global_position).normalized()
	tnt.apply_central_impulse(dir * throw_force)
