extends InteractionPoint

func interact(item: GrabbableObject):
	if (item and item.item_id not in valid_objects):
		return false
	var target_pos = position + Vector3(0,1.5,0)
	item.move_to_position(target_pos)
	item.gravity_scale = 0
	item.freeze = true
	item.set_freeze_mode(RigidBody3D.FREEZE_MODE_STATIC) #alternatively replace with static version if want no more grab after
	return true
