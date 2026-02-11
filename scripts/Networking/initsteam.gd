
class_name InitSteam extends Node

func _ready()->void:
	init_steam()
func _process(_delta: float) -> void:
	Steam.run_callbacks()
func init_steam()->void:
	var init_res:Dictionary = Steam.steamInitEx(480)
	print("Steam init result: ", init_res)
	var app_installed_depots: Array = Steam.getInstalledDepots( 480 )
	var app_languages: String = Steam.getAvailableGameLanguages()
	var app_owner: int = Steam.getAppOwner()
	var build_id: int = Steam.getAppBuildId()
	var game_language: String = Steam.getCurrentGameLanguage()
	# var install_dir: Dictionary = Steam.getAppInstallDir( 480 )
	var is_on_steam_deck: bool = Steam.isSteamRunningOnSteamDeck()
	var is_on_vr: bool = Steam.isSteamRunningInVR()
	var is_online: bool = Steam.loggedOn()
	var is_owned: bool = Steam.isSubscribed()
	var launch_command_line: String = Steam.getLaunchCommandLine()
	var steam_id: int = Steam.getSteamID()
	var steam_username: String = Steam.getPersonaName()
	var ui_language: String = Steam.getSteamUILanguage()
	print("App installed depots: ", app_installed_depots)
	print("App languages: ", app_languages)
	print("App owner: ", app_owner)
	print("Build ID: ", build_id)
