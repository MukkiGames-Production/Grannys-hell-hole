extends InteractionPoint

@export var hotladle: Mesh
@export var carrot: PackedScene

var cups = 5
@onready var stew: MeshInstance3D = $StuInteractablesStew

func interact(item: GrabbableObject):
	if (item and item.item_id not in valid_objects) or cups < 1:
		return false
	
	item.freeze = false ##stop phys
	item.is_held = false ##item no longer held
	var saved_holder = item.holder ##save holder for return 

	move_to_point(item, Vector3(0, 1.5, 0), 0.3, true) ##move ladle to pot
	
	cups = cups - 1
	##tween the stew down a little
	stew.global_position = stew.global_position - Vector3(0, .1, 0)
	if cups < 1:
		stew.queue_free()
		stew = null
		var instance = carrot.instantiate()
		get_tree().current_scene.add_child(instance)
		instance.global_position = global_position
	
	item.replace_model(hotladle, "Hot_ladle")
	
	var tween = create_tween()
	tween.tween_interval(0.8)
	tween.tween_callback(func(): _finish(item, saved_holder)) ##return to holder

	return true

func _finish(item: GrabbableObject, holder: Node3D):
	item.holder = holder
	item.is_held = true
	if cups < 1:
		queue_free()
	
func returns_item() -> bool:
	return true  # default: item stays in hand
