extends GrabbableObject
class_name explodingObject


@export var fuse_duration := 3.0
var explosion: PackedScene = preload("res://scenes/BigBoom.tscn")
var is_lit := false
	
func summon_boom(radius: float = 1.0, strength: float = 5, offset: Vector3 = Vector3(0,0,0)):
	await get_tree().create_timer(fuse_duration).timeout
	var boom = explosion.instantiate()
	get_tree().root.add_child(boom)
	boom.global_position = global_position + offset
	boom.create(radius, strength)
	queue_free()
	
	
