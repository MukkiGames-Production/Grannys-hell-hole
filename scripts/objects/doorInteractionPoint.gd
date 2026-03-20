extends InteractionPoint


func empty_interact() -> void:
	var door := _find_door_controller()
	if door:
		door.toggle_door()


func _find_door_controller() -> Node:
	var node: Node = self
	while node:
		if node.has_method("toggle_door"):
			return node
		node = node.get_parent()
	return null
