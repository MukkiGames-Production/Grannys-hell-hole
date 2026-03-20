extends CharacterBody3D
class_name DummyPlayer

@export var gravity = 20
@export var mouse_sensitivity := 0.002
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

# Virtual method — child classes override this for yaw/pitch handling
func _handle_mouse_look(event: InputEventMouseMotion) -> void:
	pass  # override in children

func _process(delta: float) -> void:
	if is_charging_throw:
		throw_charge += delta
		throw_charge = clamp(throw_charge, 0.0, max_charge_time)
	
		
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
	
	bones[0].apply_central_impulse(1.5 * v)
	for i in range(1, bones.size()):
		bones[i].apply_central_impulse(v)
		
		
func disable_ragdoll() -> void:
	stu_mesh_normal.visible = true
	stu_mesh_ragdoll.visible = false
	stus_bone_simulator.physical_bones_stop_simulation()
