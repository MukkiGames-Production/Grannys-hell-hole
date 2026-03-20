extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const INTERACTION_LAYER_8_MASK := 1 << 7

@export var mouse_sensitivity := 0.002
@export var camera_pivot: Node3D
@export var camera: Camera3D

var object_in_sight: Dictionary			#result of raycast, first object player can see
var held_object: GrabbableObject = null
var seesInteractable: bool = false

signal look_at_interactable(can_see: bool) #signal to reticle to change type when looking/not looking at grabbable

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED) #move mouse does not move cursor

@rpc("call_local", "any_peer")
func _physics_process(delta: float) -> void:
	# Get input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back") #needs to be in settings -> Input Map
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
	var player_data := {
		"message": "player_update",
		"id": Steam.getSteamID(),
		"px": global_position.x,
		"py": global_position.y,
		"pz": global_position.z,
		"rx": global_rotation.x,
		"ry": global_rotation.y,
		"rz": global_rotation.z,
		"vx": velocity.x,
		"vy": velocity.y,
		"vz": velocity.z
	}
	GameNetwork.send_p2p_packet(0, player_data, Steam.P2P_SEND_RELIABLE)
	move_and_slide()



func _process(delta: float) -> void:
	var space_state = get_world_3d().direct_space_state

	var from = camera.global_position
	var to = from + camera.global_transform.basis.z * -5.0

	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	query.collide_with_areas = true
	query.collision_mask = query.collision_mask | INTERACTION_LAYER_8_MASK

	object_in_sight = space_state.intersect_ray(query)

	var currently_sees: bool = (object_in_sight) \
								and (object_in_sight.collider != held_object) \
								and (object_in_sight.collider is GrabbableObject or object_in_sight.collider is InteractionPoint or object_in_sight.collider is DoorInteractionArea)

	if currently_sees != seesInteractable:
		seesInteractable = currently_sees
		emit_signal("look_at_interactable", seesInteractable)

@rpc("call_local", "any_peer")
func _unhandled_input(event):
	# Toggle menu with Escape
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Ignore all mouse input when menu is open (mouse visible)
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouseMotion:
		# Rotate player (yaw)
		rotate_y(-event.relative.x * mouse_sensitivity)
		# Rotate camera (pitch)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		# Clamp vertical look so you can't flip
		camera_pivot.rotation.x = clamp(
			camera_pivot.rotation.x,
			deg_to_rad(-80),
			deg_to_rad(80)
		)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		try_interact()
@rpc("call_local", "any_peer")
func try_interact():
	if not object_in_sight:
		return

	var target = object_in_sight.collider

	#case 1: holding item, use on point or drop item
	if held_object:
		if target is InteractionPoint:
			if target.interact(held_object):	#checks if successful check
				held_object.release()
				held_object = null

		else:
			held_object.release()
			held_object = null
		return

	#case 2: not holding anything, pick up or null
	if target is GrabbableObject:
		held_object = target
		held_object.grab(camera)
		print("Picked up " + str(held_object))
	elif target is InteractionPoint:
		target.empty_interact()
	elif target is DoorInteractionArea:
		target.interact()
