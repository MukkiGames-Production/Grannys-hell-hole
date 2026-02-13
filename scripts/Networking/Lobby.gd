extends Node

const PACKET_READ_LIMIT: int = 32

var lobby_data
var lobby_id: int = 0
var lobby_members: Array = []
var lobby_members_max: int = 10
var lobby_vote_kick: bool = false
var steam_id: int = 0
var steam_username: String = ""

func _ready()->void:
	Steam.join_requested.connect(_on_lobby_join_requested)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_data_update.connect(_on_lobby_data_update)
	Steam.lobby_invite.connect(_on_lobby_invite)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_message.connect(_on_lobby_message)
	Steam.persona_state_change.connect(_on_persona_change)
func check_command_line() -> void:
	var these_arguments: Array = OS.get_cmdline_args()

    # There are arguments to process
    if these_arguments.size() > 0:
        # A Steam connection argument exists
        if these_arguments[0] == "+connect_lobby":
            # Lobby invite exists so try to connect to it
            if int(these_arguments[1]) > 0:
                # At this point, you'll probably want to change scenes
                # Something like a loading into lobby screen
                print("Command line lobby ID: %s" % these_arguments[1])
                join_lobby(int(these_arguments[1]))

func create_lobby()->void:
	if lobby_id == 0:
		Steam.create_lobby(Steam.LOBBY_TYPE_PUBLIC, lobby_members_max)



func _on_lobby_created(connect: int, this_lobby_id: int) -> void:
    if connect == 1:
        # Set the lobby ID
        lobby_id = this_lobby_id
        print("Created a lobby: %s" % lobby_id)

        # Set this lobby as joinable, just in case, though this should be done by default
        Steam.setLobbyJoinable(lobby_id, true)

        # Set some lobby data
        Steam.setLobbyData(lobby_id, "name", "Gramps' Lobby")
        Steam.setLobbyData(lobby_id, "mode", "GodotSteam test")

        # Allow P2P connections to fallback to being relayed through Steam if needed
        var set_relay: bool = Steam.allowP2PPacketRelay(true)
        print("Allowing Steam to be relay backup: %s" % set_relay)
func _on_open_lobby_list_pressed()->void:
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	print("Requesting a lobby list")
	Steam.requestLobbyList()

func _on_lobby_match_list(these_lobbies: Array)-> void:
	for this_lobby in these_lobbies:
		var lobby_name: String = Steam.getLobbyData(this_lobby,"name");
		var lobby_mode: String = Steam.getLobbyData(this_lobby,"mode");

		var lobby_num_members: int = Steam.getNumLobbyMembers(this_lobby)

		var lobby_button: Button = Button.new()
		lobby_button.set_text("Lobby %s: %s [%s] - %s Player(s)" % [this_lobby, lobby_name, lobby_mode, lobby_num_members])
		lobby_button.set_size(Vector2(800,50))
		lobby_button.set_name("lobby_%s" % this_lobby)
		lobby_button.connect("pressed", Callable(self,"join_lobby").bind(this_lobby))

		$Lobbies/Scroll/List.add_child(lobby_button)
