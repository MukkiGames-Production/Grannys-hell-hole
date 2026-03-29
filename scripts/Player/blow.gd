extends Node3D
class_name BlowCone

@export var area: Area3D
@export var collision_shape: CollisionShape3D
@export var force: float = 0.001
@export var angle: float = 30.0

func apply_blow(origin: Vector3, forward: Vector3) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	for body in area.get_overlapping_bodies():
		if body is BasePlayer or body is DummyPlayer:
			body.boom_ragdoll(origin, 5)
	queue_free()
