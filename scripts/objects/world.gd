extends Node3D

func _ready()->void:
	var init_steam_node = InitSteam.new()
	add_child(init_steam_node)
	
