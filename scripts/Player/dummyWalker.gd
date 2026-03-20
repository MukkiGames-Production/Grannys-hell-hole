extends DummyPlayer
class_name DummyWalker

const SPEED = 5.0
const JUMP_VELOCITY = 4.5  # if you add jumping later
var is_walking: bool = false

@rpc("call_local", "any_peer")
func _physics_process(delta: float) -> void:
	#gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Move the character
	
	#set position to ragdoll if in ragdoll
	if ragdoll_state:
		global_position = stus_root_bone.global_position
		return

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
