extends BasePlayer
class_name WalkingPlayer

const SPEED = 5.0
var is_walking: bool = false

func _handle_mouse_look(event: InputEventMouseMotion) -> void:
	rotate_y(-event.relative.x * mouse_sensitivity)
	stu_camera.root.rotate_x(-event.relative.y * mouse_sensitivity)

	if camera_mode == CameraMode.THIRD_PERSON:
		set_third_person_cam_pos()

	stu_camera.root.rotation.x = clamp(
		stu_camera.root.rotation.x,
		deg_to_rad(-80),
		deg_to_rad(80)
	)

@rpc("call_local", "any_peer")
func _physics_process(delta: float) -> void:
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	#gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Move the character

	#set position to ragdoll if in ragdoll
	if ragdoll_state:
		global_position = stus_root_bone.global_position
		return

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
	
func reach_ending():
	self.visible = false
	set_process_input(false)
	set_process_unhandled_input(false)
	set_physics_process(false)
	stu_camera.camera.current = false
	
	remove_from_group("players")
	
	spectator_camera.activate()
