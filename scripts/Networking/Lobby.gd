extends Control

const PACKET_READ_LIMIT: int = 32

var lobby_data
var lobby_id: int = 0
var lobby_members: Array = []
var lobby_members_max: int = 10
var lobby_vote_kick: bool = false
var steam_id: int = 0
var steam_username: String = ""

# UI Node references
@onready var player_name_label: Label = %PlayerName
@onready var lobbies_list: VBoxContainer = %List
@onready var no_lobbies_label: Label = %NoLobbiesLabel
@onready var current_lobby_panel: PanelContainer = %CurrentLobbyPanel
@onready var lobby_name_label: Label = %LobbyName
@onready var members_list: VBoxContainer = %MembersList
@onready var status_label: Label = %StatusLabel
@onready var start_game_button: Button = %StartGameButton

func _ready() -> void:
	# Get your Steam ID and username
	steam_id = Steam.getSteamID()
	steam_username = Steam.getPersonaName()

	# Update player name in UI (with null check)
	if player_name_label:
		player_name_label.text = steam_username

	# Connect lobby signals
	Steam.join_requested.connect(_on_lobby_join_requested)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_data_update.connect(_on_lobby_data_update)
	Steam.lobby_invite.connect(_on_lobby_invite)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_message.connect(_on_lobby_message)

	# Connect P2P signals
	Steam.p2p_session_request.connect(_on_p2p_session_request)
	Steam.p2p_session_connect_fail.connect(_on_p2p_session_connect_fail)

	# Check for command line arguments
	check_command_line()

	# Initial lobby list request (deferred to ensure UI is ready)
	call_deferred("_on_open_lobby_list_pressed")

func _process(_delta: float) -> void:
	# If connected to a lobby, read any incoming P2P packets
	if lobby_id > 0:
		read_all_p2p_packets()

func check_command_line() -> void:
	var these_arguments: Array = OS.get_cmdline_args()

	# There are arguments to process
	if these_arguments.size() > 0:
		# A Steam connection argument exists
		if these_arguments[0] == "+connect_lobby":
			# Lobby invite exists so try to connect to it
			if int(these_arguments[1]) > 0:
				print("Command line lobby ID: %s" % these_arguments[1])
				join_lobby(int(these_arguments[1]))

func create_lobby() -> void:
	# Make sure a lobby is not already set
	if lobby_id == 0:
		if status_label:
			status_label.text = "Status: Creating lobby..."
		print("Creating lobby with max members: %s" % lobby_members_max)
		Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, lobby_members_max)

func _on_lobby_created(connect: int, this_lobby_id: int) -> void:
	if connect == 1:
		# Set the lobby ID
		lobby_id = this_lobby_id
		print("Created a lobby: %s" % lobby_id)

		# Set this lobby as joinable
		Steam.setLobbyJoinable(lobby_id, true)

		# Set some lobby data
		Steam.setLobbyData(lobby_id, "name", "%s's Lobby" % steam_username)
		Steam.setLobbyData(lobby_id, "mode", "GodotSteam test")

		# Allow P2P connections to fallback to being relayed through Steam if needed
		var set_relay: bool = Steam.allowP2PPacketRelay(true)
		print("Allowing Steam to be relay backup: %s" % set_relay)

		# Update UI
		if status_label:
			status_label.text = "Status: Lobby created!"
		get_lobby_members()
		update_lobby_ui()
	else:
		if status_label:
			status_label.text = "Status: Failed to create lobby"

func _on_open_lobby_list_pressed() -> void:
	# Clear previous lobby buttons
	clear_lobby_list()
	if no_lobbies_label:
		no_lobbies_label.visible = true
		no_lobbies_label.text = "Searching for lobbies..."

	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	print("Requesting a lobby list")
	Steam.requestLobbyList()

func clear_lobby_list() -> void:
	# Remove all lobby buttons except the no lobbies label
	if not lobbies_list:
		return
	for child in lobbies_list.get_children():
		if child != no_lobbies_label:
			child.queue_free()

func _on_lobby_match_list(these_lobbies: Array) -> void:
	clear_lobby_list()

	if these_lobbies.size() == 0:
		if no_lobbies_label:
			no_lobbies_label.visible = true
			no_lobbies_label.text = "No lobbies found. Click 'Refresh Lobbies' or create your own!"
		return

	if no_lobbies_label:
		no_lobbies_label.visible = false

	if not lobbies_list:
		return

	for this_lobby in these_lobbies:
		var lobby_name: String = Steam.getLobbyData(this_lobby, "name")
		var lobby_mode: String = Steam.getLobbyData(this_lobby, "mode")
		var lobby_num_members: int = Steam.getNumLobbyMembers(this_lobby)
		var lobby_max_members: int = Steam.getLobbyMemberLimit(this_lobby)

		var lobby_button: Button = Button.new()
		lobby_button.text = "%s [%s] - %s/%s Players" % [lobby_name, lobby_mode, lobby_num_members, lobby_max_members]
		lobby_button.custom_minimum_size = Vector2(0, 50)
		lobby_button.name = "lobby_%s" % this_lobby
		lobby_button.pressed.connect(join_lobby.bind(this_lobby))

		lobbies_list.add_child(lobby_button)

func join_lobby(this_lobby_id: int) -> void:
	print("Attempting to join lobby %s" % this_lobby_id)
	if status_label:
		status_label.text = "Status: Joining lobby..."

	# Clear any previous lobby members lists
	lobby_members.clear()

	# Make the lobby join request to Steam
	Steam.joinLobby(this_lobby_id)

func _on_lobby_joined(this_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	# If joining was successful
	if response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		# Set this lobby ID as your lobby ID
		lobby_id = this_lobby_id

		# Get the lobby members
		get_lobby_members()

		# Make the initial handshake
		make_p2p_handshake()

		# Update UI
		if status_label:
			status_label.text = "Status: Connected to lobby!"
		update_lobby_ui()

	else:
		# Get the failure reason
		var fail_reason: String

		match response:
			Steam.CHAT_ROOM_ENTER_RESPONSE_DOESNT_EXIST: fail_reason = "This lobby no longer exists."
			Steam.CHAT_ROOM_ENTER_RESPONSE_NOT_ALLOWED: fail_reason = "You don't have permission to join this lobby."
			Steam.CHAT_ROOM_ENTER_RESPONSE_FULL: fail_reason = "The lobby is now full."
			Steam.CHAT_ROOM_ENTER_RESPONSE_ERROR: fail_reason = "Uh... something unexpected happened!"
			Steam.CHAT_ROOM_ENTER_RESPONSE_BANNED: fail_reason = "You are banned from this lobby."
			Steam.CHAT_ROOM_ENTER_RESPONSE_LIMITED: fail_reason = "You cannot join due to having a limited account."
			Steam.CHAT_ROOM_ENTER_RESPONSE_CLAN_DISABLED: fail_reason = "This lobby is locked or disabled."
			Steam.CHAT_ROOM_ENTER_RESPONSE_COMMUNITY_BAN: fail_reason = "This lobby is community locked."
			Steam.CHAT_ROOM_ENTER_RESPONSE_MEMBER_BLOCKED_YOU: fail_reason = "A user in the lobby has blocked you from joining."
			Steam.CHAT_ROOM_ENTER_RESPONSE_YOU_BLOCKED_MEMBER: fail_reason = "A user you have blocked is in the lobby."

		print("Failed to join this chat room: %s" % fail_reason)
		if status_label:
			status_label.text = "Status: %s" % fail_reason

		# Refresh the lobby list
		_on_open_lobby_list_pressed()

func _on_lobby_join_requested(this_lobby_id: int, friend_id: int) -> void:
	var owner_name: String = Steam.getFriendPersonaName(friend_id)
	print("Joining %s's lobby..." % owner_name)
	join_lobby(this_lobby_id)

func get_lobby_members() -> void:
	lobby_members.clear()
	var num_members: int = Steam.getNumLobbyMembers(lobby_id)
	for i in range(num_members):
		var member_id: int = Steam.getLobbyMemberByIndex(lobby_id, i)
		var member_name: String = Steam.getFriendPersonaName(member_id)
		lobby_members.append({
			"steam_id": member_id,
			"steam_name": member_name
		})

func update_lobby_ui() -> void:
	if not current_lobby_panel:
		return

	if lobby_id == 0:
		current_lobby_panel.visible = false
		return

	current_lobby_panel.visible = true

	# Update lobby name
	var current_lobby_name: String = Steam.getLobbyData(lobby_id, "name")
	if lobby_name_label:
		lobby_name_label.text = "Lobby: %s" % current_lobby_name

	# Clear and update members list
	if members_list:
		for child in members_list.get_children():
			child.queue_free()

		for member in lobby_members:
			var member_label: Label = Label.new()
			var is_host: bool = Steam.getLobbyOwner(lobby_id) == member["steam_id"]
			var host_text: String = " (Host)" if is_host else ""
			var you_text: String = " (You)" if member["steam_id"] == steam_id else ""
			member_label.text = "• %s%s%s" % [member["steam_name"], host_text, you_text]
			members_list.add_child(member_label)

	# Show/hide start button based on if we're the host
	if start_game_button:
		start_game_button.visible = Steam.getLobbyOwner(lobby_id) == steam_id

func leave_lobby() -> void:
	if lobby_id != 0:
		# Close P2P sessions with all members
		for member in lobby_members:
			if member["steam_id"] != steam_id:
				Steam.closeP2PSessionWithUser(member["steam_id"])

		# Leave the lobby
		Steam.leaveLobby(lobby_id)

		# Reset lobby data
		lobby_id = 0
		lobby_members.clear()

		# Update UI
		if status_label:
			status_label.text = "Status: Left the lobby"
		update_lobby_ui()

		# Refresh lobby list
		_on_open_lobby_list_pressed()

		print("Left the lobby")

# ---- P2P NETWORKING ----

func make_p2p_handshake() -> void:
	print("Making P2P handshake with lobby members...")
	send_p2p_packet(0, {"message": "handshake", "from": steam_id})

func read_all_p2p_packets(read_count: int = 0) -> void:
	if read_count >= PACKET_READ_LIMIT:
		return

	if Steam.getAvailableP2PPacketSize(0) > 0:
		read_p2p_packet()
		read_all_p2p_packets(read_count + 1)

func read_p2p_packet() -> void:
	var packet_size: int = Steam.getAvailableP2PPacketSize(0)

	if packet_size > 0:
		var this_packet: Dictionary = Steam.readP2PPacket(packet_size, 0)

		if this_packet.is_empty() or this_packet == null:
			print("WARNING: read an empty packet with non-zero size!")
			return

		var packet_sender: int = this_packet['steam_id_remote']
		var packet_code: PackedByteArray = this_packet['data']
		var readable_data: Dictionary = bytes_to_var(packet_code)

		process_p2p_packet(packet_sender, readable_data)

func process_p2p_packet(sender_id: int, data: Dictionary) -> void:
	var message_type: String = data.get("message", "")

	match message_type:
		"handshake":
			print("Received handshake from: %s" % sender_id)
		"player_update":
			print("Received player update from: %s" % sender_id)
		"chat":
			var chat_message: String = data.get("text", "")
			print("Chat from %s: %s" % [sender_id, chat_message])
		_:
			print("Unknown message type: %s from %s" % [message_type, sender_id])

func send_p2p_packet(target_id: int, data: Dictionary, send_type: int = Steam.P2P_SEND_RELIABLE) -> void:
	var packet_data: PackedByteArray = var_to_bytes(data)

	if target_id == 0:
		# Send to all members except ourselves
		for member in lobby_members:
			if member["steam_id"] != steam_id:
				Steam.sendP2PPacket(member["steam_id"], packet_data, send_type, 0)
	else:
		Steam.sendP2PPacket(target_id, packet_data, send_type, 0)

# ---- P2P SESSION CALLBACKS ----

func _on_p2p_session_request(remote_id: int) -> void:
	var requester_name: String = Steam.getFriendPersonaName(remote_id)
	print("P2P session request from: %s (%s)" % [requester_name, remote_id])

	var is_in_lobby: bool = false
	for member in lobby_members:
		if member["steam_id"] == remote_id:
			is_in_lobby = true
			break

	if is_in_lobby:
		Steam.acceptP2PSessionWithUser(remote_id)
		print("Accepted P2P session with %s" % requester_name)
	else:
		print("Rejected P2P session - user not in lobby")

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

	print("P2P session connect fail with %s: %s" % [steam_id_remote, error_message])

# ---- LOBBY SIGNAL CALLBACKS ----

func _on_lobby_chat_update(this_lobby_id: int, changed_id: int, making_change_id: int, chat_state: int) -> void:
	var changer_name: String = Steam.getFriendPersonaName(making_change_id)
	var changed_name: String = Steam.getFriendPersonaName(changed_id)

	match chat_state:
		Steam.CHAT_MEMBER_STATE_CHANGE_ENTERED:
			print("%s has joined the lobby" % changed_name)
			if status_label:
				status_label.text = "Status: %s joined" % changed_name
		Steam.CHAT_MEMBER_STATE_CHANGE_LEFT:
			print("%s has left the lobby" % changed_name)
			if status_label:
				status_label.text = "Status: %s left" % changed_name
		Steam.CHAT_MEMBER_STATE_CHANGE_DISCONNECTED:
			print("%s has been disconnected" % changed_name)
			if status_label:
				status_label.text = "Status: %s disconnected" % changed_name
		Steam.CHAT_MEMBER_STATE_CHANGE_KICKED:
			print("%s was kicked by %s" % [changed_name, changer_name])
			if status_label:
				status_label.text = "Status: %s was kicked" % changed_name
		Steam.CHAT_MEMBER_STATE_CHANGE_BANNED:
			print("%s was banned by %s" % [changed_name, changer_name])
			if status_label:
				status_label.text = "Status: %s was banned" % changed_name

	# Refresh the lobby members list
	get_lobby_members()
	update_lobby_ui()

func _on_lobby_data_update(this_lobby_id: int, member_id: int, key: int) -> void:
	print("Lobby data updated for lobby %s" % this_lobby_id)

func _on_lobby_invite(inviter_id: int, this_lobby_id: int, game_id: int) -> void:
	var inviter_name: String = Steam.getFriendPersonaName(inviter_id)
	print("Received lobby invite from %s for lobby %s" % [inviter_name, this_lobby_id])
	if status_label:
		status_label.text = "Status: Invite from %s" % inviter_name

func _on_lobby_message(this_lobby_id: int, sender_id: int, message: String, chat_type: int) -> void:
	var sender_name: String = Steam.getFriendPersonaName(sender_id)
	print("[Lobby Chat] %s: %s" % [sender_name, message])

# ---- NAVIGATION ----

func _on_back_button_pressed() -> void:
	# Leave lobby if in one
	if lobby_id != 0:
		leave_lobby()

	# Go back to main menu
	get_tree().change_scene_to_file("res://world.tscn")

func start_game() -> void:
	# Only the host can start the game
	if Steam.getLobbyOwner(lobby_id) == steam_id:
		print("Starting game...")
		# Send start game message to all players
		send_p2p_packet(0, {"message": "start_game"})
		# Load your game scene
		get_tree().change_scene_to_file("res://scenes/main.tscn")
