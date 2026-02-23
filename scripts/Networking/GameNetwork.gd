extends Node

## Persistent networking singleton (autoload) that survives scene changes.
## Holds lobby/P2P state so the game scene can read it after leaving the lobby UI.

const PACKET_READ_LIMIT: int = 32
var peer: SteamMultiplayerPeer = null
# Lobby state
var lobby_id: int = 0
var lobby_members: Array = []
var lobby_members_max: int = 10
var steam_id: int = 0
var steam_username: String = ""
var is_host: bool = false

# Signals for game scenes to connect to
signal player_joined(peer_steam_id: int, player_name: String)
signal player_left(peer_steam_id: int)
signal game_started()
signal p2p_packet_received(sender_id: int, data: Dictionary)

func _ready() -> void:
	Steam.p2p_session_request.connect(_on_p2p_session_request)
	Steam.p2p_session_connect_fail.connect(_on_p2p_session_connect_fail)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)

	steam_id = Steam.getSteamID()
	steam_username = Steam.getPersonaName()

func _process(_delta: float) -> void:
	if lobby_id > 0:
		read_all_p2p_packets()

# ---- Lobby State Management ----

## Call this from Lobby.gd right before changing scene, so the data persists.
func set_lobby(id: int, members: Array, host: bool) -> void:
	lobby_id = id
	lobby_members = members
	is_host = host
	print("[GameNetwork] Lobby state saved — id:%s  host:%s  members:%s" % [id, host, members.size()])

## Tears down all P2P sessions and resets state (e.g. returning to menu).
func clear_lobby() -> void:
	for member in lobby_members:
		if member["steam_id"] != steam_id:
			Steam.closeP2PSessionWithUser(member["steam_id"])
	if lobby_id != 0:
		Steam.leaveLobby(lobby_id)
	lobby_id = 0
	lobby_members.clear()
	is_host = false
	print("[GameNetwork] Lobby state cleared")

# ---- P2P Sending ----

## Send a packet to a specific steam user, or to everyone in the lobby (target_id == 0).
func send_p2p_packet(target_id: int, data: Dictionary, send_type: int = Steam.P2P_SEND_RELIABLE) -> void:
	var packet_data: PackedByteArray = var_to_bytes(data)

	if target_id == 0:
		# Broadcast to all lobby members except ourselves
		for member in lobby_members:
			if member["steam_id"] != steam_id:
				Steam.sendP2PPacket(member["steam_id"], packet_data, send_type, 0)
	else:
		Steam.sendP2PPacket(target_id, packet_data, send_type, 0)


# ---- P2P Updating ----
@rpc("call_local", "any_peer")
func process_player_update(data: Dictionary) ->void:
	if data.get("message", "") != "player_update":
		return
	var remote_id = data.get("id",0)
	if remote_id:
		var member_info = get_member_by_id(remote_id)
		if member_info:
			# Update the member's data in our lobby_members list
			member_info["px"] = data.get("px", 0)
			member_info["py"] = data.get("py", 0)
			member_info["pz"] = data.get("pz", 0)
			member_info["rx"] = data.get("rx", 0)
			member_info["ry"] = data.get("ry", 0)
			member_info["rz"] = data.get("rz", 0)
			member_info["vx"] = data.get("vx", 0)
			member_info["vy"] = data.get("vy", 0)
			member_info["vz"] = data.get("vz", 0)
	print("[GameNetwork] Processed player update from %s: pos=(%s, %s, %s) rot=(%s, %s, %s) vel=(%s, %s, %s)" %
		[remote_id, data.get("px", 0), data.get("py", 0), data.get("pz", 0),
			data.get("rx", 0), data.get("ry", 0), data.get("rz", 0),
			data.get("vx", 0), data.get("vy", 0), data.get("vz", 0)])

# ---- P2P Reading ----

func read_all_p2p_packets(read_count: int = 0) -> void:
	if read_count >= PACKET_READ_LIMIT:
		return
	if Steam.getAvailableP2PPacketSize(0) > 0:
		read_p2p_packet()
		read_all_p2p_packets(read_count + 1)

func read_p2p_packet() -> void:
	var packet_size: int = Steam.getAvailableP2PPacketSize(0)
	if packet_size <= 0:
		return

	var this_packet: Dictionary = Steam.readP2PPacket(packet_size, 0)
	if this_packet.is_empty():
		print("[GameNetwork] WARNING: read an empty packet with non-zero size!")
		return

	var packet_sender: int = this_packet["remote_steam_id"]
	var packet_code: PackedByteArray = this_packet["data"]
	var readable_data: Dictionary = bytes_to_var(packet_code)

	# Emit for any connected listener (Lobby UI, game world, etc.)
	p2p_packet_received.emit(packet_sender, readable_data)

# ---- P2P Session Callbacks ----

func _on_p2p_session_request(remote_id: int) -> void:
	var requester_name: String = Steam.getFriendPersonaName(remote_id)
	print("[GameNetwork] P2P session request from: %s (%s)" % [requester_name, remote_id])

	# Only accept if the requester is in our lobby
	for member in lobby_members:
		if member["steam_id"] == remote_id:
			Steam.acceptP2PSessionWithUser(remote_id)
			print("[GameNetwork] Accepted P2P session with %s" % requester_name)
			return

	print("[GameNetwork] Rejected P2P session — user not in lobby")

func _on_p2p_session_connect_fail(steam_id_remote: int, session_error: int) -> void:
	var error_message: String
	match session_error:
		Steam.P2P_SESSION_ERROR_NONE:
			error_message = "No error"
		Steam.P2P_SESSION_ERROR_NOT_RUNNING_APP:
			error_message = "Target user not running the same game"
		Steam.P2P_SESSION_ERROR_NO_RIGHTS_TO_APP:
			error_message = "Local user doesn't own the app"
		Steam.P2P_SESSION_ERROR_DESTINATION_NOT_LOGGED_ON:
			error_message = "Target user isn't connected to Steam"
		Steam.P2P_SESSION_ERROR_TIMEOUT:
			error_message = "Connection timed out"
		_:
			error_message = "Unknown error"

	print("[GameNetwork] P2P session connect fail with %s: %s" % [steam_id_remote, error_message])

# ---- Lobby Chat Update (member join/leave while in lobby) ----

func _on_lobby_chat_update(this_lobby_id: int, changed_id: int, _making_change_id: int, chat_state: int) -> void:
	if this_lobby_id != lobby_id:
		return

	var changer_name: String = Steam.getFriendPersonaName(changed_id)

	# Someone joined
	if chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_ENTERED:
		print("[GameNetwork] %s joined the lobby" % changer_name)
		# Add to our members list if not already present
		var already_exists: bool = false
		for member in lobby_members:
			if member["steam_id"] == changed_id:
				already_exists = true
				break
		if not already_exists:
			lobby_members.append({"steam_id": changed_id, "steam_name": changer_name})
		player_joined.emit(changed_id, changer_name)

	# Someone left / disconnected / kicked / banned
	elif chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_LEFT \
		or chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_DISCONNECTED \
		or chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_KICKED \
		or chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_BANNED:
		print("[GameNetwork] %s left the lobby" % changer_name)
		# Remove from our members list
		for i in range(lobby_members.size() - 1, -1, -1):
			if lobby_members[i]["steam_id"] == changed_id:
				lobby_members.remove_at(i)
				break
		# Close P2P session with the departed user
		Steam.closeP2PSessionWithUser(changed_id)
		player_left.emit(changed_id)


# ---- P2P session management ----
#
func create_steam_socket()->void:

	peer = SteamMultiplayerPeer.new()
	peer.create_host(0)
	multiplayer.multiplayer_peer = peer
func connect_to_host(host_id: int)->void:
	peer = SteamMultiplayerPeer.new()
	peer.create_client(host_id)
	multiplayer.multiplayer_peer = peer

# ---- Helpers ---- #

## Returns the member dict for a given steam_id, or an empty dict if not found.
func get_member_by_id(member_steam_id: int) -> Dictionary:
	for member in lobby_members:
		if member["steam_id"] == member_steam_id:
			return member
	return {}

## Convenience: get just the display names.
func get_member_names() -> Array[String]:
	var names: Array[String] = []
	for member in lobby_members:
		names.append(member.get("steam_name", "Unknown"))
	return names
