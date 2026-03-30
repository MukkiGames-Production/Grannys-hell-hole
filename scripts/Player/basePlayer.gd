extends CharacterBody3D
class_name BasePlayer

@export var gravity = 20
@export var mouse_sensitivity := 0.002
@export var camera_pivot: Node3D
@export var camera: Camera3D
@export var max_throw_force := 20.0
@export var max_charge_time := 1.5  # seconds to reach full power
@export var ragdoll_time := 3.5 # seconds the player will not have control after entering ragdoll
@export var ragdoll_skeleton: Skeleton3D
@export var stus_bone_simulator: PhysicalBoneSimulator3D
@export var stus_root_bone: PhysicalBone3D
@export var stu_mesh_normal: MeshInstance3D
@export var stu_mesh_ragdoll: MeshInstance3D

@export var animation: AnimationPlayer

var is_charging_throw := false
var throw_charge := 0.0
var object_in_sight: Dictionary = {}  # raycast result
var held_object: GrabbableObject = null
var sees_interactable: bool = false
var ragdoll_timer: Timer = Timer.new()
var ragdoll_state = false

var root_bone_idx: int = -1

signal look_at_interactable(can_see: bool)  # for reticle/UI feedback
const INTERACTION_LAYER_8_MASK := 1 << 7

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	#initialize ragdoll timer
	ragdoll_timer.wait_time = ragdoll_time
	ragdoll_timer.one_shot = true
	ragdoll_timer.timeout.connect(_on_ragdoll_timer_timeout)
	root_bone_idx = ragdoll_skeleton.find_bone("Root")  # or "Hips", "pelvis", "Spine", whatever your rig's main/root bone is
	print(root_bone_idx)
	add_child(ragdoll_timer)

	#make ragdoll body invis
	stu_mesh_ragdoll.visible = false

	for child in stus_bone_simulator.get_children():
		if child is PhysicalBone3D:
			bones.append(child)
			child.angular_damp = 10

func _unhandled_input(event: InputEvent) -> void:
	# Toggle mouse capture with Escape
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		# Early return so mouse motion doesn't process while menu is open
		return

	# Ignore mouse input when menu visible
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouseMotion:
		_handle_mouse_look(event)

	if event.is_action_pressed("interact"):
		if event is InputEventKey and event.echo:
			return
		try_door_interact()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if held_object:
				is_charging_throw = true
				throw_charge = 0.0
			else:
				try_interact()
		else:
			# Mouse released → throw
			if is_charging_throw and held_object:
				if throw_charge > 0.25:
					_throw_held_object()
				else:
					try_interact()
				is_charging_throw = false

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			print("Right click", held_object.has_method("use"))
			if held_object and held_object.has_method("use"):
				held_object.use()

# Virtual method — child classes override this for yaw/pitch handling
func _handle_mouse_look(event: InputEventMouseMotion) -> void:
	pass  # override in children

func _process(delta: float) -> void:
	_update_interaction_raycast()
	if is_charging_throw:
		throw_charge += delta
		throw_charge = clamp(throw_charge, 0.0, max_charge_time)

func _throw_held_object() -> void:
	if not held_object:
		return

	var power_ratio = throw_charge / max_charge_time
	var force = power_ratio * max_throw_force

	var throw_dir = (-camera.global_transform.basis.z + Vector3.UP * 0.2).normalized()

	var obj := held_object
	held_object = null

	obj.release()

	# Apply impulse AFTER release
	obj.apply_central_impulse(throw_dir * force)
	print(throw_dir * force)
	if (force > max_throw_force/4):
		obj.apply_torque_impulse(Vector3(
			randf_range(-0.5, 0.5),
			randf_range(-0.5, 0.5),
			randf_range(-0.5, 0.5)
		))

	print("Threw with force:", force)
	throw_charge = 0.0

func _update_interaction_raycast() -> void:
	var space_state = get_world_3d().direct_space_state
	var from = camera.global_position
	var to = from + camera.global_transform.basis.z * -5.0  # 5 units forward

	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	query.collide_with_areas = true  # important for Area3D interactions
	query.collision_mask = query.collision_mask | INTERACTION_LAYER_8_MASK

	object_in_sight = space_state.intersect_ray(query)

	var currently_sees = false
	if object_in_sight:
		var collider = object_in_sight.collider
		if collider != held_object:
			if (collider is GrabbableObject and collider.is_grabbable) or collider is InteractionPoint or collider is DoorInteractionArea:
				currently_sees = true

	if currently_sees != sees_interactable:
		sees_interactable = currently_sees
		look_at_interactable.emit(sees_interactable)
@rpc("call_local", "any_peer")
func try_interact() -> void:
	var target = null
	if object_in_sight:
		target = object_in_sight.collider

	print("collider clicked: ", target)

	# Case 1: Holding something → try place or drop
	if held_object:
		if target is InteractionPoint:
			if target.interact(held_object):
				if not target.returns_item():
					held_object.place_on(target)
					held_object = null
			return
		held_object.release()
		held_object = null
		return

	# Case 2: Not holding → pick up or empty interact
	if target is GrabbableObject and target.is_grabbable:
		held_object = target
		held_object.grab(camera)
		print("Picked up ", held_object)
	elif target is InteractionPoint:
		target.empty_interact()


func try_door_interact() -> void:
	if not object_in_sight:
		return

	var target = object_in_sight.collider
	var door = _find_door_controller(target)
	if door:
		door.toggle_door()


func _find_door_controller(start: Object) -> Node:
	var node := start as Node
	while node:
		if node.has_method("toggle_door"):
			return node
		node = node.get_parent()
	return null

func boom_ragdoll(origin: Vector3, strength: float):
	# Horizontal direction only (ignore Y difference)

	var horizontal = global_transform.origin - origin
	horizontal.y = 0.0
	horizontal = horizontal.normalized()

	# Add upward lift
	var up_force = Vector3.UP * 0.4  # tweak this value

	# Combine and normalize once
	var final_dir = (horizontal + up_force).normalized()

	velocity += final_dir * strength

	ragdoll_state = true
	ragdoll_timer.start()

	enable_ragdoll(final_dir * strength)

func _on_ragdoll_timer_timeout():
	ragdoll_state = false
	disable_ragdoll()

var bones = [] #initialized in ready()
func enable_ragdoll(v) -> void:
	stu_mesh_normal.visible = false
	stu_mesh_ragdoll.visible = true
	stus_bone_simulator.physical_bones_start_simulation()

	bones[0].apply_central_impulse(1.2 * v)
	for i in range(1, bones.size()):
		bones[i].apply_central_impulse(v)

	if GameNetwork.lobby_id > 0:
		GameNetwork.send_p2p_packet(0, {
			"message": "player_action",
			"action": "enable_ragdoll",
			"vx": v.x,
			"vy": v.y,
			"vz": v.z
		}, Steam.P2P_SEND_RELIABLE)


func disable_ragdoll() -> void:
	stu_mesh_normal.visible = true
	stu_mesh_ragdoll.visible = false
	stus_bone_simulator.physical_bones_stop_simulation()

	if GameNetwork.lobby_id > 0:
		GameNetwork.send_p2p_packet(0, {
			"message": "player_action",
			"action": "disable_ragdoll"
		}, Steam.P2P_SEND_RELIABLE)
