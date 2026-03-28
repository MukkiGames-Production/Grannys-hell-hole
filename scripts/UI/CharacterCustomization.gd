extends Control

func _input(event: InputEvent):
	if event is InputEventMouseButton:
		print("UI received click at: ", event.position)
