extends InteractionPoint
func empty_interact():
	var player = get_tree().get_first_node_in_group("players")
	if not player or player.in_customization:
		return  # already open, do nothing
	
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	player.in_customization = true
	
	var ui_scene = preload("res://scenes/UI/CharacterCustomizationUI.tscn")
	var ui = ui_scene.instantiate()
	get_tree().get_root().add_child(ui)
