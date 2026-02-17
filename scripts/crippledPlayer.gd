extends CharacterBody3D

const JUMP_VELOCITY = 4.5


@export var speed = 15.0
@export var accel_target := 4.0
@export var brake := 22.0
@export var mouse_sensitivity := 0.002
@export var camera_pivot: Node3D
@export var camera: Camera3D

@export var steer_max_deg := 55.0
@export var steer_speed_deg_per_sec := 140.0	# how fast wheels tilt toward target
@export var steer_center_deg_per_sec := 220.0
@export var max_turn_rate_deg_per_sec := 320.0
@export var rolling_resistance_target := 3.5
@export var side_friction_target := 12.5

@export var wheel_visual: Node3D

var steer_deg := 0.0
var accel := 0
var rolling_resistance := 3.5
var side_friction := 12.5

var object_in_sight: Dictionary			#result of raycast, first object player can see
var held_object: GrabbableObject = null
var seesInteractable: bool = false
var head_yaw := 0.0
var head_pitch := 0.0

var error := 0.05

signal look_at_interactable(can_see: bool) #signal to reticle to change type when looking/not looking at grabbable

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED) #move mouse does not move cursor
	head_yaw = camera_pivot.rotation.y
	head_pitch = camera_pivot.rotation.x

# Godot docs recommend keeping (almost) all movement/transform-driving logic in _physics_process() when using interpolation (we are).
func _physics_process(delta: float) -> void:
	# throttle: +1 forward, -1 back
	var boost := 0.0
	var throttle := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	if (throttle > 0+error or throttle < 0-error):
		boost = 0.5
	var steer_in := -Input.get_action_strength("move_right") + Input.get_action_strength("move_left")
	if (steer_in > 0+error or steer_in < 0-error):
		accel = 3.0
		rolling_resistance = 12.5
		side_friction = 3.5
	else:
		accel = accel_target

	# wheel steer angle clamped to +-15 deg
	var target_steer := steer_in * steer_max_deg
	var steer_rate := steer_speed_deg_per_sec if abs(steer_in) > 0.001 else steer_center_deg_per_sec
	steer_deg = move_toward(steer_deg, target_steer, steer_rate * delta)

	if wheel_visual != null:
		wheel_visual.rotation.y = deg_to_rad(steer_deg)

	# turn body (yaw)
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	var speed_factor = clamp(planar_speed / max(speed, 0.001), 0.0, 1.0)
	var steer_factor = steer_deg / max(steer_max_deg, 0.001)

	var turn_rate = deg_to_rad(max_turn_rate_deg_per_sec) * steer_factor * speed_factor
	rotate_y(turn_rate * delta)

	# forward/back movement with low rolling resistance (wheel direction),
	# but strong sideways friction (no easy lateral slide)
	var fwd := -transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()

	var right := transform.basis.x
	right.y = 0.0
	right = right.normalized()

	var v := Vector3(velocity.x, 0.0, velocity.z)

	# Decompose current planar velocity into forward + sideways relative to facing
	var v_fwd := fwd * v.dot(fwd)
	var v_side := right * v.dot(right)

	# Desired forward velocity (wheel direction only)
	var target_fwd = fwd * (throttle * speed)

	# Drive when throttling; coast when not
	var reversing = abs(throttle) > 0.001 and v_fwd.dot(target_fwd) < 0.0
	var drive_rate = (brake if reversing else accel)

	if abs(throttle) > 0.001:
		v_fwd = v_fwd.move_toward(target_fwd, drive_rate * delta)
	else:
		# COAST: small decel forward/back
		v_fwd = v_fwd.move_toward(Vector3.ZERO, rolling_resistance * delta)

	# ALWAYS kill sideways drift hard
	v_side = v_side.move_toward(Vector3.ZERO, side_friction * delta)

	v = v_fwd + v_side
	velocity.x = v.x
	velocity.z = v.z

	move_and_slide()


func _process(delta: float) -> void:
	var space_state = get_world_3d().direct_space_state

	var from = camera.global_position
	var to = from + camera.global_transform.basis.z * -5.0

	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	query.collide_with_areas = true

	object_in_sight = space_state.intersect_ray(query)

	var currently_sees: bool = (object_in_sight) \
								and (object_in_sight.collider != held_object) \
								and (object_in_sight.collider is GrabbableObject or object_in_sight.collider is InteractionPoint)

	if currently_sees != seesInteractable:
		seesInteractable = currently_sees
		emit_signal("look_at_interactable", seesInteractable)

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
		head_yaw -= event.relative.x * mouse_sensitivity
		head_pitch = clamp(
			head_pitch - event.relative.y * mouse_sensitivity,
			deg_to_rad(-80),
			deg_to_rad(80)
		)

		camera_pivot.rotation = Vector3(head_pitch, head_yaw, 0.0)
		#print(camera.rotation_degrees, camera_pivot.rotation_degrees)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		try_interact()

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
