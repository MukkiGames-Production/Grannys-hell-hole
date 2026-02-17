extends Button

func _ready() -> void:
	print("Menubutton: _ready called")
	pressed.connect(_on_multiplayer_button_pressed)
	print("Menubutton: pressed signal connected")

func _on_multiplayer_button_pressed() -> void:
	print("Menubutton: Button pressed! Changing scene to lobby...")
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")
