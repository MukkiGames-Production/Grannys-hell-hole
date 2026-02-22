extends BasePlayer
class_name CrippledPlayer

@export var speed := 15.0
@export var accel_target := 4.0
@export var brake := 22.0
@export var steer_max_deg := 55.0
@export var steer_speed_deg_per_sec := 140.0
@export var steer_center_deg_per_sec := 220.0
@export var max_turn_rate_deg_per_sec := 320.0
@export var rolling_resistance_target := 3.5
@export var side_friction_target := 12.5
@export var wheel_visual: Node3D
@export var start_kick_speed := 0.7
@export var kick_deadzone := 0.04

var _prev_throttle := 0.0
var steer_deg := 0.0
var accel := accel_target
var rolling_resistance := rolling_resistance_target
var side_friction := side_friction_target
var head_yaw := 0.0
var head_pitch := 0.0
var error := 0.05

func _ready() -> void:
	super._ready()
	head_yaw = camera_pivot.rotation.y
	head_pitch = camera_pivot.rotation.x

func _handle_mouse_look(event: InputEventMouseMotion) -> void:
	head_yaw -= event.relative.x * mouse_sensitivity
	head_pitch = clamp(
		head_pitch - event.relative.y * mouse_sensitivity,
		deg_to_rad(-80),
		deg_to_rad(80)
	)
	camera_pivot.rotation = Vector3(head_pitch, head_yaw, 0.0)

func _physics_process(delta: float) -> void:
	var throttle = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var steer_in: float
	if throttle >= 0:
		steer_in = -Input.get_action_strength("move_right") + Input.get_action_strength("move_left")
	else:
		steer_in = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")

	# Optional accel/friction tweak when steering (your original logic)
	if abs(steer_in) > error:
		accel = 3.0
		rolling_resistance = 12.5
		side_friction = 3.5
	else:
		accel = accel_target
		# Optionally reset rolling/side friction here if desired

	var target_steer = steer_in * steer_max_deg
	var steer_rate = steer_speed_deg_per_sec if abs(steer_in) > 0.001 else steer_center_deg_per_sec
	steer_deg = move_toward(steer_deg, target_steer, steer_rate * delta)

	if wheel_visual:
		wheel_visual.rotation.y = deg_to_rad(steer_deg)

	# Yaw turning based on steer + speed
	var planar_speed = Vector2(velocity.x, velocity.z).length()
	var speed_factor = clamp(planar_speed / max(speed, 0.001), 0.0, 1.0)
	var steer_factor = steer_deg / max(steer_max_deg, 0.001)
	var turn_rate = deg_to_rad(max_turn_rate_deg_per_sec) * steer_factor * speed_factor
	rotate_y(turn_rate * delta)

	# Forward/back + side friction logic
	var fwd = -transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()

	var right = transform.basis.x
	right.y = 0
	right = right.normalized()

	var v = Vector3(velocity.x, 0, velocity.z)
	var v_fwd = fwd * v.dot(fwd)
	var v_side = right * v.dot(right)

	var target_fwd = fwd * (throttle * speed)
	var reversing = abs(throttle) > 0.001 and v_fwd.dot(target_fwd) < 0.0
	var drive_rate = brake if reversing else accel

	# Start kick
	var throttle_active = abs(throttle) > kick_deadzone
	var was_active = abs(_prev_throttle) > kick_deadzone
	var starting_move = throttle_active and not was_active
	if starting_move and not reversing:
		var desired_fwd_speed = throttle * speed
		var cur_fwd_speed = v.dot(fwd)
		var remaining = max(0.0, abs(desired_fwd_speed) - abs(cur_fwd_speed))
		var kick = min(start_kick_speed, remaining)
		v_fwd += fwd * sign(desired_fwd_speed) * kick

	if abs(throttle) > 0.001:
		v_fwd = v_fwd.move_toward(target_fwd, drive_rate * delta)
	else:
		v_fwd = v_fwd.move_toward(Vector3.ZERO, rolling_resistance * delta)

	v_side = v_side.move_toward(Vector3.ZERO, side_friction * delta)
	v = v_fwd + v_side

	velocity.x = v.x
	velocity.z = v.z
	_prev_throttle = throttle

	move_and_slide()
