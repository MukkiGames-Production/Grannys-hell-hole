extends CharacterBody3D
class_name BasePlayer

@export var mouse_sensitivity := 0.002
@export var camera_pivot: Node3D
@export var camera: Camera3D
@export var max_throw_force := 20.0
@export var max_charge_time := 1.5  # seconds to reach full power
@onready var animation: AnimationPlayer = $AnimationPlayer

var is_charging_throw := false
var throw_charge := 0.0
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
				held_object.place_on(target)  # sends network "place" action
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
