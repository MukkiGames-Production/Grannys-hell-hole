extends Node3D
class_name BreakableWall

## The force applied to pieces when breaking
@export var explosion_force: float = 5.0
## Random variation in explosion direction
@export var explosion_randomness: float = 2.0
## How long pieces stay before being removed (0 = never remove)
@export var piece_lifetime: float = 5.0
## Mass of each piece
@export var piece_mass: float = 1.0
## Distance at which the wall breaks when player approaches
@export var trigger_distance: float = 2.0

## Whether the wall has been broken
var is_broken: bool = false
var player: Node3D = null


func _ready() -> void:
	# Find the player in the scene
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")

	# If player isn't in a group, try to find by class/name
	if player == null:
		player = get_tree().get_first_node_in_group("Player")

	# If still not found, search for CharacterBody3D nodes
	if player == null:
		var characters := get_tree().get_nodes_in_group("") # empty fallback
		for node in get_tree().root.get_children():
			player = _find_player_recursive(node)
			if player:
				break


func _find_player_recursive(node: Node) -> Node3D:
	if node is CharacterBody3D:
		return node
	for child in node.get_children():
		var result := _find_player_recursive(child)
		if result:
			return result
	return null


func _process(_delta: float) -> void:
	if is_broken or player == null:
		return

	# Check distance to player
	var distance := global_position.distance_to(player.global_position)
	if distance <= trigger_distance:
		break_wall(player.global_position)


## Call this function to break the wall
func break_wall(impact_position: Vector3 = Vector3.ZERO) -> void:
	if is_broken:
		return

	is_broken = true
	var impact_point := impact_position if impact_position != Vector3.ZERO else global_position

	# Find all MeshInstance3D children (recursively)
	var meshes := _get_all_meshes(self)

	for mesh in meshes:
		_convert_to_physics_piece(mesh, impact_point)

	# Stop processing since wall is broken
	set_process(false)


## Recursively find all MeshInstance3D nodes
func _get_all_meshes(node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []

	for child in node.get_children():
		if child is MeshInstance3D:
			meshes.append(child)
		# Recurse into children
		meshes.append_array(_get_all_meshes(child))

	return meshes


## Convert a mesh into a physics-enabled piece
func _convert_to_physics_piece(mesh: MeshInstance3D, impact_point: Vector3) -> void:
	# Create a new RigidBody3D
	var rigid_body := RigidBody3D.new()
	rigid_body.mass = piece_mass

	# Store the mesh's global transform before reparenting
	var global_xform := mesh.global_transform

	# Remove mesh from its current parent
	var old_parent := mesh.get_parent()
	old_parent.remove_child(mesh)

	# Add rigid body to the scene root (so it's independent)
	get_tree().current_scene.add_child(rigid_body)
	rigid_body.global_transform = global_xform

	# Add mesh as child of rigid body (reset local transform)
	rigid_body.add_child(mesh)
	mesh.transform = Transform3D.IDENTITY

	# Create a collision shape from the mesh
	_add_collision_shape(rigid_body, mesh)

	# Apply explosion impulse
	var direction := (rigid_body.global_position - impact_point).normalized()
	if direction == Vector3.ZERO:
		direction = Vector3.UP

	# Add randomness
	direction += Vector3(
		randf_range(-explosion_randomness, explosion_randomness),
		randf_range(0, explosion_randomness),
		randf_range(-explosion_randomness, explosion_randomness)
	).normalized() * 0.5

	direction = direction.normalized()
	rigid_body.apply_central_impulse(direction * explosion_force)

	# Add some rotation
	rigid_body.apply_torque_impulse(Vector3(
		randf_range(-1, 1),
		randf_range(-1, 1),
		randf_range(-1, 1)
	) * explosion_force * 0.5)

	# Remove after lifetime if specified
	if piece_lifetime > 0:
		_schedule_removal(rigid_body)


## Add a collision shape to the rigid body based on the mesh
func _add_collision_shape(rigid_body: RigidBody3D, mesh: MeshInstance3D) -> void:
	var collision_shape := CollisionShape3D.new()

	# Try to create a convex shape from the mesh
	if mesh.mesh:
		var shape := mesh.mesh.create_convex_shape()
		if shape:
			collision_shape.shape = shape
		else:
			# Fallback to a box shape based on AABB
			var aabb := mesh.mesh.get_aabb()
			var box := BoxShape3D.new()
			box.size = aabb.size
			collision_shape.shape = box
			collision_shape.position = aabb.get_center()

	rigid_body.add_child(collision_shape)


## Schedule a piece to be removed after the lifetime
func _schedule_removal(rigid_body: RigidBody3D) -> void:
	await get_tree().create_timer(piece_lifetime).timeout

	if is_instance_valid(rigid_body):
		rigid_body.queue_free()
