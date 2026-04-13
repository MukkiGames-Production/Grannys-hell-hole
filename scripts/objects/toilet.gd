extends InteractionPoint



func interact(item: GrabbableObject):
	if (item and item.item_id not in valid_objects):
		return false

	item.freeze = false ##stop phys
	item.is_held = false ##item no longer held
	var saved_holder = item.holder ##save holder for return

	move_to_point(item, Vector3(0, 1.5, 0), 0.3, true) ##move ladle to pot

	var tween = create_tween()
	tween.tween_interval(0.8)
	tween.tween_callback(func(): _finish(item, saved_holder)) ##return to holder

	return true

func _finish(item: GrabbableObject, holder: Node3D):
	item.holder = holder
	item.is_held = true
