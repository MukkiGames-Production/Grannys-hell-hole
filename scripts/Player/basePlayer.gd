extends CharacterBody3D
class_name BasePlayer

@export var mouse_sensitivity := 0.002
@export var camera_pivot: Node3D
@export var camera: Camera3D
@onready var animation: AnimationPlayer = $AnimationPlayer

var object_in_sight: Dictionary = {}  # raycast result
var held_object: GrabbableObject = null
var sees_interactable: bool = false

signal look_at_interactable(can_see: bool)  # for reticle/UI feedback

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


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

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		try_interact()

# Virtual method — child classes override this for yaw/pitch handling
func _handle_mouse_look(event: InputEventMouseMotion) -> void:
	pass  # override in children

func _physics_process(_delta: float) -> void:
	_update_interaction_raycast()
@rpc("call_local", "any_peer")
func _update_interaction_raycast() -> void:
	var space_state = get_world_3d().direct_space_state
	var from = camera.global_position
	var to = from + camera.global_transform.basis.z * -5.0  # 5 units forward

	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	query.collide_with_areas = true  # important for InteractionPoint (Area3D)

	object_in_sight = space_state.intersect_ray(query)

	var currently_sees = false
	if object_in_sight:
		var collider = object_in_sight.collider
		if collider != held_object:
			if (collider is GrabbableObject and collider.is_grabbable) or collider is InteractionPoint:
				currently_sees = true

	if currently_sees != sees_interactable:
		sees_interactable = currently_sees
		look_at_interactable.emit(sees_interactable)
@rpc("call_local", "any_peer")
func try_interact() -> void:
	var target = null
	if object_in_sight:
		target = object_in_sight.collider

	# Case 1: Holding something → try place or drop
	if held_object:
		if target is InteractionPoint:
			if target.interact(held_object):  # success → item was placed/used
				held_object.release()
				held_object = null
				return
		# Otherwise just drop
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
