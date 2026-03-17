extends Area3D
class_name InteractionPoint

@export var valid_objects: Array[String]

var explosion: PackedScene = preload("res://scenes/BigBoom.tscn")

func interact(item: GrabbableObject) -> bool:
	# Base class only enforces valid objects
	return item and item.item_id in valid_objects

func empty_interact():
	print("uh oh can't interact with nothing in hand")

#helpers
	
#moves relative to interaction object
func move_to_point(item, offset: Vector3, duration: float = 0.3):
	# Stop physics motion
	item.linear_velocity = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO
	item.freeze = true  # optional: prevents physics interference

	var target = global_position + offset
	var tween = create_tween()
	tween.tween_property(item, "global_position", target, duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)

#also makes items not grabbable 
func freeze_in_place(item: GrabbableObject): 
	item.gravity_scale = 0
	item.freeze = true
	item.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	item.lock_rotation = true
	item.is_grabbable = false
	item.collision_layer = 10 #super copium but the player and falling wall keep moving it.
	item.collision_mask = 0 
	
func summon_boom(radius: float = 1.0, strength: float = 5, offset: Vector3 = Vector3(0,0,0)):
	var boom = explosion.instantiate()
	add_child(boom)
	boom.global_position = global_position + offset
	print(boom.position)
	boom.create(radius, strength)
	
