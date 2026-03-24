extends InteractionPoint

func interact(item: GrabbableObject):
	if (item and item.item_id not in valid_objects):
		return false
	move_to_point(item, Vector3(0, 1.5, 0), true)
	freeze_in_place(item)
	summon_boom(5.0, 10) #radius, strength
	return true
