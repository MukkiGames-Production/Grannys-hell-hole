extends InteractionPoint
var player
var ui

func empty_interact():
	player = get_tree().get_first_node_in_group("players")
	if not player or player.in_customization:
		return
	player.in_customization = true
	
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	ui = preload("res://scenes/UI/CharacterCustomizationUI.tscn").instantiate()
	get_tree().get_root().add_child(ui)
	ui.closed.connect(exit_customization)
	
func exit_customization():
	if player:
		player.in_customization = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if ui:
		ui.queue_free()
		ui = null
