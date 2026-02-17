extends Area3D
class_name InteractionPoint

@export var valid_objects: Array[String]

func interact(item: GrabbableObject) -> bool:
	# Base class only enforces valid objects
	return item and item.item_id in valid_objects

func empty_interact():
	print("uh oh can't interact with nothing in hand")
