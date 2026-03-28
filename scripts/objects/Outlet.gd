extends InteractionPoint

var isSparking = false
var last_item_id = ""
#const SPARKS_SCENE = preload("res://scenes/BigBoom.tscn")

func interact(item: GrabbableObject):
	if (item and item.item_id not in valid_objects):
		return false
	last_item_id = item.item_id
	if(item.item_id == "Fork"):
		var rotation = Basis(Vector3(0, 0, 1), deg_to_rad(90))
		move_to_point(item, Vector3(0, 0, 0), .3, true, rotation)
		freeze_in_place(item)
		isSparking = true
		valid_objects.append("TNT")
		valid_objects.erase("Fork")
	elif(item.item_id == "TNT"):
		move_to_point(item, Vector3(0, 0, 0), .3, false)
		item.summon_boom(10.0, 15.0)


	#var sparks = SPARKS_SCENE.instantiate()
	#add_child(sparks)
	#sparks.global_position = global_position

	return true

func returns_item() -> bool:
	return last_item_id == "TNT"
