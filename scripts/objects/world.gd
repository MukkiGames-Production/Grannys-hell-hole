extends Node3D
@onready var player = preload("res://scenes/Player.tscn")
@onready var Voip = preload("res://scripts/Networking/Voip.gd")
@onready var voip_instance = Voip.new()
## Dictionary mapping remote steam_id -> their CharacterBody3D node
var remote_players: Dictionary = {}

## Reference to the local player node (inside the instanced main.tscn, which is "Node3D")
@onready var local_player: CharacterBody3D = $Main/Player

func _ready() -> void:


	# Initialize Steam if not already done
	var init_steam_node = InitSteam.new()
	add_child(init_steam_node)

	# Connect to the persistent GameNetwork autoload for incoming packets
	GameNetwork.p2p_packet_received.connect(_on_p2p_packet_received)
	GameNetwork.player_joined.connect(_on_player_joined)
	GameNetwork.player_left.connect(_on_player_left)

	# Spawn remote player nodes for everyone already in the lobby (except us)
	if GameNetwork.lobby_id > 0:
		print("[World] Game started with %s players in lobby" % GameNetwork.lobby_members.size())
		for member in GameNetwork.lobby_members:
			if member["steam_id"] != GameNetwork.steam_id and member["steam_id"] != Steam.getSteamID() and member["steam_name"] != Steam.getPersonaName():
				_spawn_remote_player(member["steam_id"], member["steam_name"])
	else:
		print("[World] No active lobby — running in single-player mode")

	voip_instance.voice_data_ready.connect(_on_voice_data_ready)
	$Main.add_child(voip_instance)
@rpc("call_local", "any_peer")
func _on_voice_data_ready(buffer: PackedByteArray) -> void:
	GameNetwork.send_p2p_packet(0, {
		"message": "voice_data",
		"buffer": buffer,
		"id": Steam.getSteamID(),
	}, Steam.P2P_SEND_RELIABLE)
	if voip_instance.has_loopback:
		# Also play locally if loopback is enabled
		voip_instance.process_voice_data(buffer,"local")

func _physics_process(_delta: float) -> void:
	if GameNetwork.lobby_id <= 0:
		return
	if not is_instance_valid(local_player):
		return

	# Broadcast our position + rotation to all peers every physics tick
	GameNetwork.send_p2p_packet(0, {
		"message": "player_update",
		"px": local_player.global_position.x,
		"py": local_player.global_position.y,
		"pz": local_player.global_position.z,
		"rx": local_player.global_rotation.x,
		"ry": local_player.global_rotation.y,
		"rz": local_player.global_rotation.z,
	}, Steam.P2P_SEND_RELIABLE)

# ---- Packet handling ----

func _on_p2p_packet_received(sender_id: int, data: Dictionary) -> void:
	var msg: String = data.get("message", "")

	match msg:

		"player_update":
			_handle_player_update(sender_id, data)
		"voice_data":
			_handle_voice_data(data)
		"player_action":
			_handle_player_action(sender_id, data)
		_:
			print("[World] Unhandled packet type '%s' from %s" % [msg, sender_id])

func _handle_player_update(sender_id: int, data: Dictionary) -> void:
	# Make sure we have a node for this remote player
	var sender_name: String = Steam.getFriendPersonaName(sender_id)
	if sender_id not in remote_players:

		_spawn_remote_player(sender_id, sender_name)
		return
	var remote: Node3D = remote_players[sender_id]
	if not is_instance_valid(remote):
		return

	var target_pos := Vector3(
		data.get("px", 0.0),
		data.get("py", 0.0),
		data.get("pz", 0.0),
	)
	var target_rot := Vector3(
		data.get("rx", 0.0),
		data.get("ry", 0.0),
		data.get("rz", 0.0),
	)

	# Lerp for smooth movement instead of snapping
	remote.global_position = remote.global_position.lerp(target_pos, 0.5)
	remote.global_rotation = target_rot
	remote.set_physics_process(true) # Disable physics for remote players to prevent jitter/collisions
	print("[World] Updated player %s position to %s" % [sender_name, target_pos])

func _handle_voice_data(data: Dictionary) -> void:
	var voice_buffer: PackedByteArray = data.get("buffer", PackedByteArray())
	if voice_buffer.size() > 0:
		# Forward to the Voip node inside the instanced main scene
		var voip_node = $Main as Node
		if voip_instance.has_method("receive_voice_data"):
			voip_instance.receive_voice_data(voice_buffer)

func _handle_player_action(sender_id: int, data: Dictionary) -> void:
	var action: String = data.get("action", "")
	print("[World] Player %s performed action: %s" % [sender_id, action])
	# TODO: Handle remote player interactions (grab, drop, interact, etc.)
	if action  == "interact":
		var remote: Node3D = remote_players.get(sender_id, null)
		if remote and is_instance_valid(remote):
			# now need to find the object they interacted with and trigger it locally

			GameNetwork.send_p2p_packet(0, {
				"message": "player_action_response",
				"action": "interact_response",
				"result": "success",
			}, Steam.P2P_SEND_RELIABLE)


# ---- Remote player management ----
# FIXME - the player spawns however no connection betweens the remote player nodes and the actual player updates, so they just sit at the spawn point and do not move. Need to debug why the position updates are not applying to the remote nodes.
func _spawn_remote_player(peer_steam_id: int, peer_name: String) -> void:
	if peer_steam_id in remote_players:
		return

	var remote := player.instantiate() as CharacterBody3D
	remote.name = "RemotePlayer_%s" % peer_steam_id



	# Name label above head
	var label_3d := Label3D.new()
	label_3d.text = peer_name
	label_3d.position = Vector3(0, 1.2, 0)
	label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_3d.font_size = 32
	label_3d.no_depth_test = true
	remote.add_child(label_3d)

	# Default spawn position (same as local player start)
	remote.call_deferred("set_global_transform", Transform3D(Basis(), Vector3(0, 0, 0)))
	remote.connect("ready", func():
		remote.set_physics_process(true)
		remote.set_physics_process_priority(1)
	)
	if (peer_steam_id == Steam.getSteamID() or peer_name == Steam.getPersonaName()):
		# print("[World] WARNING: Attempted to spawn remote player for ourselves (steam_id: %s)" % peer_steam_id)
		return
	$Main.add_child(remote,true)
	remote_players[peer_steam_id] = remote

	print("[World] Spawned remote player: %s (steam_id: %s)" % [peer_name, peer_steam_id])

func _remove_remote_player(peer_steam_id: int) -> void:
	if peer_steam_id in remote_players:
		var node: Node = remote_players[peer_steam_id]
		if is_instance_valid(node):
			node.queue_free()
		remote_players.erase(peer_steam_id)
		print("[World] Removed remote player: %s" % peer_steam_id)
func _update_remote_player_position(peer_steam_id: int, position: Vector3, rotation: Vector3) -> void:
	if peer_steam_id in remote_players:
		var remote: Node3D = remote_players[peer_steam_id]
		if is_instance_valid(remote):
			remote.global_position = position
			remote.global_rotation = rotation
func _update_remote_player_action(peer_steam_id: int, action: String) -> void:
	print("[World] Received action '%s' from player %s" % [action, peer_steam_id])
# ---- Lobby change callbacks ----

func _on_player_joined(peer_steam_id: int, player_name: String) -> void:
	print("[World] Player joined mid-game: %s (%s)" % [player_name, peer_steam_id])
	_spawn_remote_player(peer_steam_id, player_name)

func _on_player_left(peer_steam_id: int) -> void:
	print("[World] Player left: %s" % peer_steam_id)
	_remove_remote_player(peer_steam_id)

func _exit_tree() -> void:
	# Disconnect signals when leaving this scene
	if GameNetwork.p2p_packet_received.is_connected(_on_p2p_packet_received):
		GameNetwork.p2p_packet_received.disconnect(_on_p2p_packet_received)
	if GameNetwork.player_joined.is_connected(_on_player_joined):
		GameNetwork.player_joined.disconnect(_on_player_joined)
	if GameNetwork.player_left.is_connected(_on_player_left):
		GameNetwork.player_left.disconnect(_on_player_left)
