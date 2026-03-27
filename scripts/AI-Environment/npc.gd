extends CharacterBody3D
class_name NPC
@export var speed := 6.0
@export var patrol_speed := 3.2
@export var investigate_speed := 2.6
@export var chase_speed := 7.0
@export var investigate_stop_time := 3.5
@export var chase_target: CharacterBody3D
@export var status : State = State.IDLE
@export var map : Node3D 
#var patrols : Dictionary[Node3D, int] = {}
var patrola : Node3D
var patrolb : Node3D
@export var patrol_route : String = "a"
@export var schedule_entries: Array[Dictionary] = [
	{ "block": "EARLY_MORNING", "location_key": "patrol_a", "behavior": "patrol", "priority": 0 },
	{ "block": "MORNING",       "location_key": "dining_hall", "behavior": "patrol", "priority": 0 },
	{ "block": "AFTERNOON",     "location_key": "patrol_b", "behavior": "patrol", "priority": 0 },
	{ "block": "EVENING",       "location_key": "patrol_a", "behavior": "patrol", "priority": 0 },
	{ "block": "NIGHT",         "location_key": "idle_spot", "behavior": "idle", "priority": 0 },
	{ "block": "LATE_NIGHT",    "location_key": "idle_spot", "behavior": "idle", "priority": 0 },
]
var current_schedule_entry: Dictionary = {}
var current_patrol : Array[Node]
var timer_expired_count : int = 0
var patrol_dir : int = 1 # 1 = forward, -1 = backward
var current_patrol_pt : int = 0 # not unique to any patrol route

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var update_timer: Timer = $UpdateTimer
@onready var debug_text: Label3D = $DebugText
@onready var wait_timer: Timer = $WaitTimer
@onready var detect_timer: Timer = $DetectTimer
@onready var ray_c: RayCast3D = $RayCastC
@onready var ray_l: RayCast3D = $RayCastL
@onready var ray_r: RayCast3D = $RayCastR
@onready var eyes: Area3D = $Eyes
var detect_candidate: BasePlayer = null

var investigate_source : Marker3D = null

enum State {
	CHASE,
	ROAM,
	PATROL,
	INVESTIGATE,
	IDLE
}

const DOOR_STATE_NONE := 2
const INVESTIGATE_TO_FIRST := 0
const INVESTIGATE_TO_SECOND := 1
const INVESTIGATE_WAIT_AT_SECOND := 2

var known_doors: Array[Node3D] = []
var investigate_door: Node3D = null
var investigate_first_marker: Marker3D = null
var investigate_second_marker: Marker3D = null
var investigate_phase: int = INVESTIGATE_TO_FIRST
var investigate_wait_left: float = 0.0
var previous_state_before_investigate: State = State.IDLE




func _ready() -> void:
	if not multiplayer.is_server():
		set_physics_process(false)
		$UpdateTimer.stop()
		GameNetwork.npc_update_received.connect(_on_npc_update)
		return
	var root := get_tree().current_scene
	#status = State.CHASE
	#chase_target = root.find_child("Player")
	if map == null:
		map = root.find_child("Map", true, false)
	if map == null:
		map = root.find_child("map", true, false)
	agent.path_desired_distance = 1.0
	agent.target_desired_distance = 1.5

	if map:
		patrola = map.find_child("PatrolA", true, false)
		patrolb = map.find_child("PatrolB", true, false)

	_cache_doors()

	Scheduler.register_npc(self, schedule_entries)

	if status == State.IDLE:
		status = State.PATROL
		if patrol_route == "b":
			startPatrolB()
		else:
			startPatrolA()



func _exit_tree() -> void:
	if has_node("/root/Scheduler"):
		Scheduler.unregister_npc(self)

func _on_scheduler_block_changed(_new_block_name: String) -> void:
	return

func _apply_schedule_for_current_block() -> void:
	current_schedule_entry = Scheduler.get_schedule_for(self)

	if current_schedule_entry.is_empty():
		status = State.IDLE
		return

	var behavior: String = current_schedule_entry.get("behavior", "idle")
	var location_key: String = current_schedule_entry.get("location_key", "")

	match behavior:
		"chase":
			status = State.CHASE
			chase()
		"patrol":
			status = State.PATROL
			_apply_location(location_key)
		"idle":
			status = State.IDLE
			velocity.x = 0.0
			velocity.z = 0.0
		_:
			status = State.IDLE

func _apply_location(location_key: String) -> void:
	match location_key:
		"patrol_a":
			startPatrolA()
		"patrol_b":
			startPatrolB()
		"dining_hall":
			var dining := map.find_child("DinningRoom", true, false)
			if dining:
				set_move_target((dining as Node3D).global_position)
		"idle_spot":
			var idle := map.find_child("IdleSpot", true, false)
			if idle:
				set_move_target((idle as Node3D).global_position)
		_:
			# fallback
			startPatrolA()

#func set_move_target(world_pos: Vector3) -> void:
	#agent.target_position = world_pos
func advance_patrol_point(pts: Array[Node], reverse: bool) -> void:
	if pts.size() <= 1:
		return

	if reverse:
		current_patrol_pt += patrol_dir
		if current_patrol_pt >= pts.size():
			current_patrol_pt = pts.size() - 2
			patrol_dir = -1
		elif current_patrol_pt < 0:
			current_patrol_pt = 1
			patrol_dir = 1
	else:
		current_patrol_pt = (current_patrol_pt+1) % pts.size()

	var next_pt := current_patrol_pt
	agent.target_position = pts[next_pt].global_position

func startPatrolA():
	if patrola == null:
		return
	current_patrol = patrola.get_children()
	if current_patrol.is_empty():
		return
	current_patrol_pt = clamp(current_patrol_pt, 0, current_patrol.size() - 1)
	agent.target_position = (current_patrol[current_patrol_pt] as Node3D).global_position

func startPatrolB():
	if patrolb == null:
		return
	current_patrol = patrolb.get_children()
	if current_patrol.is_empty():
		return
	current_patrol_pt = clamp(current_patrol_pt, 0, current_patrol.size() - 1)
	agent.target_position = (current_patrol[current_patrol_pt] as Node3D).global_position

func start_patrol_wait(seconds: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	wait_timer.start(seconds)
func _on_npc_update(data: Dictionary) -> void:
	if data.get("id", "") == name:
		global_position = Vector3(data.get("px", 0), data.get("py", 0), data.get("pz", 0))
		velocity = Vector3(data.get("vx", 0), data.get("vy", 0), data.get("vz", 0))

func set_move_target(world_pos: Vector3) -> void:
	agent.target_position = world_pos

func chase(): # chases current chase_target
	# if chasee dies or becomes unreachable or timeout, exit state
	if chase_target:
		agent.target_position = chase_target.global_position

func _set_speed_for_state() -> void:
	match status:
		State.CHASE:
			speed = chase_speed
		State.PATROL:
			speed = patrol_speed
		State.INVESTIGATE:
			speed = investigate_speed
		_:
			speed = patrol_speed

func _cache_doors() -> void:
	known_doors.clear()
	var root := get_tree().current_scene
	if root == null:
		return
	for node in root.find_children("*", "Node3D", true, false):
		if _is_door_node(node):
			known_doors.append(node as Node3D)
	
	print("KNOWN DOORS: ", known_doors)

func _is_door_node(node: Node) -> bool:
	if not node.has_method("toggle_door"):
		return false
	if node.get("status") == null:
		return false
	if node.get("okay_status") == null:
		return false
	if node.find_child("ExternalMarker", true, false) == null:
		return false
	if node.find_child("InternalMarker", true, false) == null:
		return false
	return true

func _door_needs_fix(door: Node) -> bool:
	if door == null:
		return false
	var door_status = door.get("status")
	var door_okay_status = door.get("okay_status")
	if door_status == null or door_okay_status == null:
		return false
	if int(door_okay_status) == DOOR_STATE_NONE:
		return false
	return int(door_status) != int(door_okay_status)

func _find_unexpected_door_in_sight() -> Node3D:
	if known_doors.is_empty():
		_cache_doors()
	var best_door: Node3D = null
	var best_dist := INF
	for door in _doors_in_eyes():
		if door == null or not is_instance_valid(door):
			continue
		if not _door_needs_fix(door):
			continue
		if not _door_has_line_of_sight(door):
			continue
		var d := global_position.distance_to(door.global_position)
		if d < best_dist:
			best_dist = d
			best_door = door
	return best_door

func _doors_in_eyes() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var seen: Dictionary = {}
	for body in eyes.get_overlapping_bodies():
		if not (body is Node):
			continue
		var door := _find_door_ancestor(body as Node)
		if door == null:
			continue
		var key := door.get_instance_id()
		if seen.has(key):
			continue
		seen[key] = true
		result.append(door)
	return result

func _find_door_ancestor(start_node: Node) -> Node3D:
	var node: Node = start_node
	while node:
		if _is_door_node(node):
			return node as Node3D
		node = node.get_parent()
	return null

func _door_has_line_of_sight(door: Node3D) -> bool:
	var eye_pos := global_position + Vector3(0.0, 1.4, 0.0)
	var door_pos := _door_target_point(door)

	var query := PhysicsRayQueryParameters3D.create(
		eye_pos,
		door_pos,
		0xFFFFFFFF,
		[self.get_rid()]
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider = hit.get("collider")
	if collider == null:
		return false
	if collider is Node and _node_is_same_or_child_of(collider as Node, door):
		return true
	return false

func _door_target_point(door: Node3D) -> Vector3:
	var external := door.find_child("ExternalMarker", true, false) as Marker3D
	var internal := door.find_child("InternalMarker", true, false) as Marker3D
	if external and internal:
		return (external.global_position + internal.global_position) * 0.5
	return door.global_position + Vector3(0.0, 1.0, 0.0)

func _node_is_same_or_child_of(node: Node, ancestor: Node) -> bool:
	var current: Node = node
	while current:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false

func _start_door_investigation(door: Node3D) -> void:
	if door == null or not is_instance_valid(door):
		return
	var ext := door.find_child("ExternalMarker", true, false) as Marker3D
	var interior := door.find_child("InternalMarker", true, false) as Marker3D
	if ext == null or interior == null:
		return

	previous_state_before_investigate = status
	investigate_door = door

	if global_position.distance_to(ext.global_position) <= global_position.distance_to(interior.global_position):
		investigate_first_marker = ext
		investigate_second_marker = interior
	else:
		investigate_first_marker = interior
		investigate_second_marker = ext

	investigate_phase = INVESTIGATE_TO_FIRST
	investigate_wait_left = 0.0
	investigate_source = investigate_first_marker
	wait_timer.stop()
	status = State.INVESTIGATE
	if investigate_source:
		agent.target_position = investigate_source.global_position

func _clear_investigation_context() -> void:
	investigate_door = null
	investigate_first_marker = null
	investigate_second_marker = null
	investigate_source = null
	investigate_phase = INVESTIGATE_TO_FIRST
	investigate_wait_left = 0.0

func _finish_investigation() -> void:
	var resume_state := previous_state_before_investigate
	_clear_investigation_context()
	status = resume_state
	if status == State.PATROL:
		if patrol_route == "b":
			startPatrolB()
		else:
			startPatrolA()

func _process_investigation(delta: float) -> void:
	if investigate_door == null or not is_instance_valid(investigate_door):
		_finish_investigation()
		return
	if not _door_needs_fix(investigate_door):
		_finish_investigation()
		return

	if investigate_phase == INVESTIGATE_WAIT_AT_SECOND:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		investigate_wait_left -= delta
		if investigate_wait_left <= 0.0:
			npc_toggle_door(investigate_door)
			_finish_investigation()
		return

	if investigate_source == null:
		_finish_investigation()
		return

	var dist_to_target := global_position.distance_to(investigate_source.global_position)
	if dist_to_target <= 1.35 or agent.is_navigation_finished():
		if investigate_phase == INVESTIGATE_TO_FIRST:
			investigate_phase = INVESTIGATE_TO_SECOND
			investigate_source = investigate_second_marker
			if investigate_source:
				agent.target_position = investigate_source.global_position
			return
		if investigate_phase == INVESTIGATE_TO_SECOND:
			investigate_phase = INVESTIGATE_WAIT_AT_SECOND
			investigate_wait_left = investigate_stop_time
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
			return

	if agent.is_navigation_finished():
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	var next_posn := agent.get_next_path_position()
	var to_next := next_posn - global_position
	to_next.y = 0.0

	if to_next.length() > 0.001:
		var nav_dir := to_next.normalized()
		var move_dir := _get_avoidance_dir(nav_dir)
		if move_dir.length() > 0.001:
			velocity.x = move_dir.x * speed
			velocity.z = move_dir.z * speed
		else:
			velocity.x = 0.0
			velocity.z = 0.0
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()
	face_dir(velocity, delta)

func npc_toggle_door(door: Node3D) -> void:
	if door == null or not is_instance_valid(door):
		return
	if not _door_needs_fix(door):
		return
	if door.has_method("toggle_door"):
		door.toggle_door()

func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0

	_set_speed_for_state()

	match status:
		State.PATROL:
			if agent.is_navigation_finished():
				#print("nav finished")
				if wait_timer.is_stopped():
					print("timer is stopped")
					start_patrol_wait(2.2)

					velocity.x = 0.0
					velocity.z = 0.0
					move_and_slide()
					return

			var next_posn := agent.get_next_path_position()
			var to_next := next_posn - global_position
			to_next.y = 0.0

			var dist := to_next.length()
			var max_step := speed * delta

			if dist <= 0.001:
				velocity.x = 0.0
				velocity.z = 0.0
			else:
				var nav_dir := to_next / dist
				var move_dir := _get_avoidance_dir(nav_dir)
				# Stop if we’re done
				if agent.is_navigation_finished():
					velocity.x = 0.0
					velocity.z = 0.0
					move_and_slide()
					return

				if move_dir.length() <= 0.001:
					velocity.x = 0.0
					velocity.z = 0.0
				elif dist <= max_step and move_dir.dot(nav_dir) > 0.85:
					# Close enough and not needing a sharp avoidance turn:
					# move only the remaining amount this frame.
					velocity.x = to_next.x / delta
					velocity.z = to_next.z / delta
				else:
					velocity.x = move_dir.x * speed
					velocity.z = move_dir.z * speed

				move_and_slide()
				face_dir(velocity, delta)

			# CHECK STATE TRANSITIONS:


		State.INVESTIGATE:
			_process_investigation(delta)


		State.CHASE:
			# Stop if we’re done
			if agent.is_navigation_finished():
				velocity.x = 0.0
				velocity.z = 0.0
				move_and_slide()
				return

			# Get next waypoint along the path
			var next_posn := agent.get_next_path_position()

			# Compute direction AFTER possible replacement
			var to_next := next_posn - global_position
			to_next.y = 0.0

			if to_next.length() > 0.001:
				var nav_dir := to_next.normalized()
				var move_dir := _get_avoidance_dir(nav_dir)

				if move_dir.length() > 0.001:
					velocity.x = move_dir.x * speed
					velocity.z = move_dir.z * speed
				else:
					velocity.x = 0.0
					velocity.z = 0.0
			else:
				velocity.x = 0.0
				velocity.z = 0.0

			move_and_slide()
			face_dir(velocity, delta)

			# CHECK STATE TRANSITIONS:


	var data := {
		"message": "npc_update",
		"id": name,
		"px": global_position.x,
		"py": global_position.y,
		"pz": global_position.z,
		"vx": velocity.x,
		"vy": velocity.y,
		"vz": velocity.z
	}
	Scheduler.debug_print_all_schedules()
	GameNetwork.send_p2p_packet(0, data, 0)

func _on_update_timer_timeout() -> void:
	if not multiplayer.is_server(): return

	match status:
		State.CHASE:
			chase()
		State.PATROL:
			var bad_door := _find_unexpected_door_in_sight()
			if bad_door:
				print( "BAD DOOR FOUND: ", bad_door)
				_start_door_investigation(bad_door)
		State.INVESTIGATE:
			if investigate_source:
				agent.target_position = investigate_source.global_position


func _on_wait_timer_timeout() -> void:
	if status == State.PATROL:
		timer_expired_count += 1
		advance_patrol_point(current_patrol, true)
		#patrolA()

func face_dir(dir: Vector3, delta):
	var flat_vel := Vector3(velocity.x, 0.0, velocity.z)
	if flat_vel.length() > 0.001:
		var target_yaw := atan2(-flat_vel.x, -flat_vel.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 8.0 * delta)

func _ray_hits_blocker(ray: RayCast3D) -> bool:
	if not ray.is_colliding():
		return false
	var collider := ray.get_collider()
	if collider == null:
		return false
	if collider is BasePlayer:
		return false
	return true

func _get_avoidance_dir(nav_dir: Vector3) -> Vector3:
	if nav_dir.length() <= 0.001:
		return Vector3.ZERO

	var basis := global_transform.basis

	var forward := -basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var right := basis.x
	right.y = 0.0
	right = right.normalized()

	var left := -right

	var hit_c := _ray_hits_blocker(ray_c)
	var hit_l := _ray_hits_blocker(ray_l)
	var hit_r := _ray_hits_blocker(ray_r)

	# Something directly ahead: choose a side.
	if hit_c:
		if not hit_l and hit_r:
			return (forward + left * 1.4).normalized()
		elif not hit_r and hit_l:
			return (forward + right * 1.4).normalized()
		elif not hit_l and not hit_r:
			# Both sides open: pick the side closer to the nav goal.
			if nav_dir.dot(left) > nav_dir.dot(right):
				return (forward + left * 1.4).normalized()
			else:
				return (forward + right * 1.4).normalized()
		else:
			# Boxed in.
			return Vector3.ZERO

	# No center hit: lightly bias away from side obstacles.
	var steer := nav_dir
	if hit_l:
		steer += right * 0.9
	if hit_r:
		steer += left * 0.9
	steer.y = 0.0
	if steer.length() <= 0.001:
		return Vector3.ZERO

	return steer.normalized()

func _has_line_of_sight_to(player: BasePlayer) -> bool:
	if not is_instance_valid(player):
		return false

	var from := global_position + Vector3(0.0, 1.4, 0.0)
	var to := player.global_position + Vector3(0.0, 1.0, 0.0)

	var query := PhysicsRayQueryParameters3D.create(
		from,
		to,
		0xFFFFFFFF,
		[self.get_rid()]
	)

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false

	return hit["collider"] == player


func _on_eyes_body_entered(body: Node3D) -> void:
	print("Body entered: ", body)
	if status == State.CHASE:
		return
	if not (body is BasePlayer):
		print("body detected is not BasePlayer")
		return
	var player := body as BasePlayer
	if not _has_line_of_sight_to(player):
		return

	# check the players suspicion level, The players suspicion level should be always updated within the baseplayer 
	# player script to maintain a suspicion level . 
	# If we're investigating or patrolling we should chase high suspicion players if we fully detect them
	#      (possibly focus player who's most recently done a suspicious activity like break something/drop 
	#       contraband/etc) 
	# 
	# If the investigate is triggered, we need to add this event to a list somewhere and return to it so
	# if we get distracted and chase someone, we should return to investigating. Things that trigger investigations
	# may have a "fix". Like sweep up broken vase, close door that should be closed that was open, pick up contraband
	
	# Scripted movement State should run priority over everything else, if chasing when scripted movement takes over
	# we should do nothing for now and just let that player go. 
	
	# each Marker3D in a patrol should be able to hold @export metadata for how long to wait, string of animation
	# to play while waiting at this Marker
	
	# each state should have a different customizable speed for the NPC

	# If the player is ragdolled and we're chasing them, stop moving, stop updating target position, wait for player to return to normal state
	# 
	detect_candidate = player
	detect_timer.start(1.8)

func _on_detect_timer_timeout() -> void:
	if status == State.CHASE:
		return
	if detect_candidate == null:
		return
	if not is_instance_valid(detect_candidate):
		detect_candidate = null
		return
	if not eyes.overlaps_body(detect_candidate):
		detect_candidate = null
		return
	if not _has_line_of_sight_to(detect_candidate):
		detect_candidate = null
		return

	if status == State.INVESTIGATE:
		_clear_investigation_context()

	chase_target = detect_candidate
	status = State.CHASE
	chase()
	detect_candidate = null
func _reset_pos():
	global_position = Vector3.ZERO
