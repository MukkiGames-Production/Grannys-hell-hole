extends Control

const PACKET_READ_LIMIT: int = 32

var lobby_data
var lobby_id: int = 0
var lobby_members: Array = []
var lobby_members_max: int = 10
var lobby_vote_kick: bool = false
var steam_id: int = 0
var steam_username: String = ""
@export var ReturnScene: PackedScene = null
# UI Node references
@onready var player_name_label: Label = %PlayerName
@onready var lobbies_list: VBoxContainer = %List
@onready var no_lobbies_label: Label = %NoLobbiesLabel
@onready var current_lobby_panel: PanelContainer = %CurrentLobbyPanel
@onready var lobby_name_label: Label = %LobbyName
@onready var members_list: VBoxContainer = %MembersList
@onready var status_label: Label = %StatusLabel
@onready var start_game_button: Button = %StartGameButton
@onready var record_voice_button: Button = %RecordVoiceButton
@onready var voip: Node = $Voip

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

	# Listen for P2P packets via the GameNetwork autoload (it handles reading & session callbacks)
	GameNetwork.p2p_packet_received.connect(process_p2p_packet)


	# Check for command line arguments
	check_command_line()

	# Connect Voip signal for sending voice data over P2P
	if voip:
		voip.voice_data_ready.connect(_on_voice_data_ready)

	# Initial lobby list request (deferred to ensure UI is ready)
	call_deferred("_on_open_lobby_list_pressed")

func _process(_delta: float) -> void:
	pass

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
		GameNetwork.create_steam_socket()
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
@rpc("call_local", "any_peer")
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

	# Keep the GameNetwork autoload in sync so it can accept P2P sessions
	# and persist member data across scene changes
	GameNetwork.lobby_id = lobby_id
	GameNetwork.lobby_members = lobby_members.duplicate(true)

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

func invite_friend() -> void:
	# Only allow inviting if we're in a lobby
	if lobby_id == 0:
		if status_label:
			status_label.text = "Status: Create or join a lobby first!"
		return

	# Check if Steam overlay is enabled
	var overlay_enabled: bool = Steam.isOverlayEnabled()
	print("Steam overlay enabled: %s" % overlay_enabled)

	if not overlay_enabled:
		# Overlay not available, try inviting all online friends directly
		if status_label:
			status_label.text = "Status: Overlay disabled, showing friend list..."
		print("Steam overlay not enabled, using direct invite method")
		show_friends_list_for_invite()
		return

	# Open the Steam overlay with the friend invite dialog
	# This lets the user pick a friend from their Steam friends list
	print("Attempting to open Steam invite dialog for lobby: %s" % lobby_id)
	Steam.activateGameOverlayInviteDialog(lobby_id)
	print("Called activateGameOverlayInviteDialog")

# Direct invite method when overlay is not available
func show_friends_list_for_invite() -> void:
	# Get the list of friends
	var friend_count: int = Steam.getFriendCount(Steam.FRIEND_FLAG_IMMEDIATE)
	print("Found %s Steam friends" % friend_count)

	if friend_count == 0:
		if status_label:
			status_label.text = "Status: No Steam friends found"
		return

	# Create a popup to show friends
	var popup = PopupPanel.new()
	popup.name = "FriendInvitePopup"

	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(300, 400)

	var title_label = Label.new()
	title_label.text = "Invite a Friend"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(280, 300)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var friend_list = VBoxContainer.new()
	friend_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var online_friends_count: int = 0
	for i in range(friend_count):
		var friend_id: int = Steam.getFriendByIndex(i, Steam.FRIEND_FLAG_IMMEDIATE)
		var friend_name: String = Steam.getFriendPersonaName(friend_id)
		var friend_state: int = Steam.getFriendPersonaState(friend_id)

		# Only show online friends (state > 0 means not offline)
		if friend_state > 0:
			online_friends_count += 1
			var friend_button = Button.new()
			friend_button.text = friend_name
			friend_button.custom_minimum_size = Vector2(0, 40)
			friend_button.pressed.connect(_on_invite_friend_selected.bind(friend_id, popup))
			friend_list.add_child(friend_button)

	if online_friends_count == 0:
		var no_friends_label = Label.new()
		no_friends_label.text = "No online friends found"
		no_friends_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		friend_list.add_child(no_friends_label)

	scroll.add_child(friend_list)
	vbox.add_child(scroll)

	var close_button = Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(0, 40)
	close_button.pressed.connect(popup.queue_free)
	vbox.add_child(close_button)

	popup.add_child(vbox)
	add_child(popup)
	popup.popup_centered()

func _on_invite_friend_selected(friend_id: int, popup: PopupPanel) -> void:
	invite_user_to_lobby(friend_id)
	popup.queue_free()

func invite_user_to_lobby(friend_steam_id: int) -> void:
	if lobby_id == 0:
		print("Cannot invite: not in a lobby")
		return

	var friend_name: String = Steam.getFriendPersonaName(friend_steam_id)
	print("Inviting %s (ID: %s) to lobby %s" % [friend_name, friend_steam_id, lobby_id])

	# Send the lobby invite
	var success: bool = Steam.inviteUserToLobby(lobby_id, friend_steam_id)

	if success:
		if status_label:
			status_label.text = "Status: Invite sent to %s!" % friend_name
		print("Successfully sent invite to %s" % friend_name)
	else:
		if status_label:
			status_label.text = "Status: Failed to invite %s" % friend_name
		print("Failed to send invite to %s" % friend_name)

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

		# Reset voice recording state
		if voip:
			voip.stop_recording()
		if record_voice_button:
			record_voice_button.button_pressed = false
			record_voice_button.text = "Record Voice"

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
		print(this_packet)
		var packet_sender: int = this_packet['remote_steam_id']
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
			GameNetwork.process_player_update(data)
		"chat":
			var chat_message: String = data.get("text", "")
			print("Chat from %s: %s" % [sender_id, chat_message])
		"voice_data":
			var voice_buffer: PackedByteArray = data.get("buffer", PackedByteArray())
			if voice_buffer.size() > 0 and voip:
				voip.receive_voice_data(voice_buffer)
		"start_game":
			print("Received start game signal from host!")
			GameNetwork.set_lobby(lobby_id, lobby_members.duplicate(true), false)
			GameNetwork.connect_to_host(sender_id)
			get_tree().change_scene_to_file(ReturnScene.resource_path)
		"accept_game":
			print("Received accept game from: %s" % sender_id)

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

func _on_lobby_chat_update(_this_lobby_id: int, changed_id: int, making_change_id: int, chat_state: int) -> void:
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
	get_tree().change_scene_to_file(ReturnScene.resource_path)

func start_game() -> void:
	# Only the host can start the game
	if Steam.getLobbyOwner(lobby_id) == steam_id:
		print("Starting game...")
		# Save lobby state to the persistent singleton before scene change
		GameNetwork.set_lobby(lobby_id, lobby_members.duplicate(true), true)
		GameNetwork.create_steam_socket()

		# Give the socket a brief moment to initialize before telling clients to connect
		await get_tree().create_timer(0.5).timeout

		# Send start game message to all players
		send_p2p_packet(0, {"message": "start_game"})
		# Load your game scene
		get_tree().change_scene_to_file(ReturnScene.resource_path)
func record_voice(is_recording: bool) -> void:
	print("Voice recording toggled: %s" % is_recording)
	if voip:
		if is_recording:
			voip.start_recording()
			if record_voice_button:
				record_voice_button.text = "Stop Recording"
		else:
			voip.stop_recording()
			if record_voice_button:
				record_voice_button.text = "Record Voice"
	else:
		print("WARNING: Voip node not found!")

func _on_voice_data_ready(buffer: PackedByteArray) -> void:
	# Send compressed voice data to all lobby members over P2P (unreliable for low latency)
	if lobby_id > 0:
		send_p2p_packet(0, {"message": "voice_data", "buffer": buffer}, Steam.P2P_SEND_UNRELIABLE_NO_DELAY)
