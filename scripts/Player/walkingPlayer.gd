extends BasePlayer
class_name WalkingPlayer

const SPEED = 5.0
const JUMP_VELOCITY = 4.5  # if you add jumping later
var is_walking: bool = false
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
@rpc("call_local", "any_peer")
func _physics_process(delta: float) -> void:
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
		move_and_slide()
		return

	# Move the character

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	# Determine walking state ONCE based on whether we have movement
	is_walking = not is_zero_approx(velocity.x) or not is_zero_approx(velocity.z)

	# Handle animation based on the resolved state
	if is_walking:
		if not animation.is_playing():
			animation.play("Walk")
	else:
		if animation.is_playing():
			animation.stop()

	move_and_slide()

	# Send network data AFTER all state is resolved
	var player_data := {
		"message": "player_update",
		"id": Steam.getSteamID(),
		"px": global_position.x,
		"py": global_position.y,
		"pz": global_position.z,
		"rx": global_rotation.x,
		"ry": global_rotation.y,
		"rz": global_rotation.z,
		"is_walking": is_walking
	}
	GameNetwork.send_p2p_packet(0, player_data, Steam.P2P_SEND_RELIABLE)
