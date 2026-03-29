extends Node3D

@export var area: Area3D          # ← drag your Area3D here in editor
@export var collision_shape: CollisionShape3D
@export var strength: float = 1.0

var is_exploding := false

func create(radius: float, new_strength: float) -> void:
	collision_shape.shape.radius = radius
	strength = new_strength
	
	await get_tree().physics_frame
	await get_tree().physics_frame #only works with two for some reason?
	
	# Now apply the effect once, to whoever is overlapping right now
	for body in area.get_overlapping_bodies():
		if body is BasePlayer or body is DummyPlayer:
			body.boom_ragdoll(global_position, strength)  # adjust multiplier as needed
			print("BOOM applied via poll!")
	
	print("aaaa - exploding now")
	queue_free()
