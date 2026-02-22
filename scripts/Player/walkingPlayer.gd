extends BasePlayer
class_name WalkingPlayer

const SPEED = 5.0
const JUMP_VELOCITY = 4.5  # if you add jumping later

func _handle_mouse_look(event: InputEventMouseMotion) -> void:
	# Yaw: rotate whole body
	rotate_y(-event.relative.x * mouse_sensitivity)
	# Pitch: rotate camera pivot only
	camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
	camera_pivot.rotation.x = clamp(
		camera_pivot.rotation.x,
		deg_to_rad(-80),
		deg_to_rad(80)
	)

func _physics_process(delta: float) -> void:
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
