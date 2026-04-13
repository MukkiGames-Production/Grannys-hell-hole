extends NPC
class_name Warden

@export var lasso_range: float = 10.0
@export var lasso_cooldown: float = 5.0
@export var lasso_speed: float = 5.0
@export var is_disabled: bool = false

@onready var lasso_node: RopeGenMesh3D  = $Lasso

var lasso_target: Node3D = null
var can_throw_lasso: bool = true
var lasso_timer: Timer = Timer.new()
var is_throwing_lasso: bool = false
var lasso_active_points: PackedVector3Array = PackedVector3Array()

func _ready() -> void:
	super._ready()

	lasso_timer.wait_time = lasso_cooldown
	lasso_timer.one_shot = true
	lasso_timer.timeout.connect(_on_lasso_timer_timeout)
	add_child(lasso_timer)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if is_disabled:
		return

	if status == State.CHASE and is_instance_valid(chase_target) and can_throw_lasso and not is_throwing_lasso:
		var dist = global_position.distance_to(chase_target.global_position)
		if dist <= lasso_range and _has_line_of_sight_to(chase_target):
			_throw_lasso(chase_target)

	if is_throwing_lasso:
		_process_lasso(delta)

func _throw_lasso(target: Node3D) -> void:
	print("[Warden] Throwing lasso at ", target.name)
	lasso_target = target
	can_throw_lasso = false
	is_throwing_lasso = true

	# Initialize the rope points
	lasso_active_points.clear()
	# Point 0 is the warden's hand/body
	lasso_active_points.append(global_position + Vector3(0, 1.5, 0))
	# Point 1 is the moving end of the lasso
	lasso_active_points.append(global_position + Vector3(0, 1.5, 0))

	lasso_node.rope_data.points = _get_lasso_points()
	if lasso_node.has_method("_regen_meshes"):
		lasso_node._regen_meshes(lasso_node.rope_data)
	lasso_node.visible = true

func _process_lasso(delta: float) -> void:
	if not is_instance_valid(lasso_target):
		_end_lasso()
		return

	# Update the start point to always track the Warden
	lasso_active_points[0] = global_position + Vector3(0, 1.5, 0)

	# Move the end point towards the target
	var target_pos = lasso_target.global_position + Vector3(0, 1.0, 0)
	var current_end = lasso_active_points[1]

	var dir = (target_pos - current_end).normalized()
	var step = dir * lasso_speed * delta
	var new_end = current_end + step

	# Check if we hit the target
	if new_end.distance_to(target_pos) < step.length() or current_end.distance_to(target_pos) < 0.5:
		lasso_active_points[1] = target_pos
		_lasso_hit()
	else:
		lasso_active_points[1] = new_end
	if lasso_active_points[1].distance_to(global_position) > lasso_range * 1.5:
		# If the lasso goes too far without hitting, end it
		_end_lasso()
		return
	# Redraw the mesh
	lasso_node.rope_data.points = _get_lasso_points()
	if lasso_node.has_method("_regen_meshes"):
		lasso_node._regen_meshes(lasso_node.rope_data)

func _lasso_hit() -> void:
	print("[Warden] Lasso connected!")
	is_throwing_lasso = false

	if is_instance_valid(lasso_target):
		# Tell the player they got lassoed/ragdolled
		if lasso_target.has_method("enable_ragdoll"):
			# Pull them towards the warden slightly
			var pull_dir = (global_position - lasso_target.global_position).normalized()
			pull_dir.y = 0.5 # Add some upward lift
			lasso_target.enable_ragdoll(pull_dir * 10.0)

	# Start cooldown before we can throw again
	lasso_timer.start()

	# Clear the rope mesh shortly after
	await get_tree().create_timer(5.0).timeout
	lasso_node.visible = false

func _end_lasso() -> void:
	is_throwing_lasso = false
	lasso_target = null
	lasso_node.visible = false
	lasso_timer.start()

func _on_lasso_timer_timeout() -> void:
	can_throw_lasso = true

func _get_lasso_points() -> PackedVector3Array:
	var local_points := PackedVector3Array()
	if lasso_active_points.size() < 2:
		return local_points

	var start_pos = lasso_active_points[0]
	var end_pos = lasso_active_points[1]

	# The straight part
	local_points.append(lasso_node.to_local(start_pos))
	local_points.append(lasso_node.to_local(end_pos))

	# The loop part
	var loop_radius := 0.6
	var loop_segments := 12
	var dir = (end_pos - start_pos).normalized()
	if dir.length() < 0.01:
		dir = Vector3.FORWARD

	var up = Vector3.UP
	if abs(dir.dot(Vector3.UP)) > 0.99:
		up = Vector3.RIGHT

	var right = dir.cross(up).normalized()
	var local_up = right.cross(dir).normalized()

	for i in range(1, loop_segments + 1):
		var angle = (float(i) / float(loop_segments)) * TAU
		var offset = right * cos(angle) * loop_radius + local_up * sin(angle) * loop_radius
		local_points.append(lasso_node.to_local(end_pos + dir * 0.1 + offset))

	# Connect back to the knot to finish the loop
	local_points.append(lasso_node.to_local(end_pos))

	return local_points
