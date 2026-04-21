extends RigidBody3D
class_name GrabbableObject
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@export var item_id: String = ""
@export var hold_distance := 1.0
@export var follow_speed := 40.0
@export var hold_offset := Vector3(0.6, -0.4, -2.0)
@export var hold_rotation_offset := Vector3.ZERO
@export var is_grabbable := true

#for holding item in center
@export var center_position: Vector3 = Vector3(0, 0, 0) 
@export var center_rotation: Vector3 = Vector3(0, 0, 0)

@onready var explosion: PackedScene = preload("res://scenes/BigBoom.tscn")

var is_held := false
var holder: Node3D = null
var holding_player: BasePlayer = null
var _last_velocity := Vector3.ZERO

var is_charging = false #used to determine if object position is

func _ready():
	contact_monitor = true
	max_contacts_reported = 10
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	if not is_held or holder == null:
		_last_velocity = linear_velocity
		return
	freeze = true  # keep frozen while held so gravity never kicks in
	var target_pos
	if is_charging:
		target_pos = holder.global_transform.origin + holder.global_transform.basis.z * -hold_distance + holder.global_transform.basis.y * -0.3 #no x when chargingw
	else:
		target_pos = holder.global_transform.origin + holder.global_transform.basis.z * -hold_distance + holder.global_transform.basis.x * 0.6 + holder.global_transform.basis.y * -0.3
	
	global_position = global_position.lerp(target_pos, follow_speed * delta)

	var current_scale = scale
	var target_basis = holder.global_basis.orthonormalized() * Basis.from_euler(hold_rotation_offset)
	global_basis = global_basis.orthonormalized().slerp(target_basis, follow_speed * delta)
	scale = current_scale

	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

func use() -> void:
	pass

#check for player, and if hit, ragdoll
func _on_body_entered(body):
	if body.is_in_group("players"):
		try_ragdoll(body)
	_check_fast_hit(body)

func try_ragdoll(body):
	var speed = linear_velocity.length()
	print("pelted stu with speed " + str(speed))

	if speed > 4.0:
		var boom = explosion.instantiate()
		add_child(boom)
		boom.global_position = global_position
		print(boom.position)
		boom.create(1.0, 5)



func grab(camera: Node3D, stu: BasePlayer):
	is_charging = false
	is_held = true
	holder = camera
	holding_player = stu
	freeze = true
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	GameNetwork.send_p2p_packet(0, {
		"message": "player_action",
		"action": "grab",
		"item_id": item_id,
		"id": Steam.getSteamID(),
	}, Steam.P2P_SEND_RELIABLE)

func release():
	var pos := global_position
	is_held = false
	holder = null
	freeze = false
	set_collision_layer_value(1, true)
	set_collision_mask_value(1, true)
	GameNetwork.send_p2p_packet(0, {
		"message": "player_action",
		"action": "release",
		"item_id": item_id,
		"id": Steam.getSteamID(),
		"px": pos.x,
		"py": pos.y,
		"pz": pos.z,
	}, Steam.P2P_SEND_RELIABLE)
	
func special(): ##on right click down
	pass

func special_released(): ##on right click up
	pass

func place_on(interaction_point: Node3D):
	var target_pos := interaction_point.global_position + Vector3(0, 1.5, 0)
	is_held = false
	holder = null
	GameNetwork.send_p2p_packet(0, {
		"message": "player_action",
		"action": "place",
		"item_id": item_id,
		"id": Steam.getSteamID(),
		"px": target_pos.x,
		"py": target_pos.y,
		"pz": target_pos.z,
	}, Steam.P2P_SEND_RELIABLE)

func move_to_position(target: Vector3, duration: float = 0.3):
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true
	var tween = create_tween()
	tween.tween_property(self, "global_position", target, duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)

func replace_model(model: Mesh, new_id: String = item_id):
	mesh_instance.mesh = model
	item_id = new_id
	GameNetwork.send_p2p_packet(0, {
		"message": "player_action",
		"action": "replace_model",
		"item_id": item_id,
		"mesh":model,
		"id": Steam.getSteamID(),
	}, Steam.P2P_SEND_RELIABLE)

func get_holder_look_point(max_distance: float = 100.0) -> Vector3:
	if holder == null:
		return global_position

	var from = holder.global_position
	var to = from + (-holder.global_basis.z) * max_distance

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]

	var result = space_state.intersect_ray(query)
	if result:
		return result.position

	return to

func get_holder_look_hit(max_distance: float = 100.0) -> Dictionary:
	if holder == null:
		return {}

	var from = holder.global_position
	var to = from + (-holder.global_basis.z) * max_distance

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]

	return space_state.intersect_ray(query)

func _check_fast_hit(body: Node3D, threshold: float = 10.0) -> void:
	if _last_velocity.length() >= threshold:
		on_fast_hit(body)

func on_fast_hit(body: Node3D) -> void:
	pass

func consume(except: Array[Node3D], reparent_target: Node3D) -> void:
	if holding_player != null:
		holding_player.held_object_consumed()

	is_held = false
	holder = null
	holding_player = null
	var except_set := {}

	for node in except:
		if node == null:
			continue
		if node == self:
			continue
		if not is_ancestor_of(node):
			continue

		except_set[node] = true

	var top_level_excepts: Array[Node3D] = []
	for node in except_set.keys():
		var parent = node.get_parent()
		var covered_by_except_ancestor := false

		while parent != null and parent != self:
			if except_set.has(parent):
				covered_by_except_ancestor = true
				break
			parent = parent.get_parent()

		if not covered_by_except_ancestor:
			top_level_excepts.append(node)
	for node in top_level_excepts:
		node.reparent(reparent_target, true)

	queue_free()
	
func start_moving_to_center() -> void:
	is_charging = true
