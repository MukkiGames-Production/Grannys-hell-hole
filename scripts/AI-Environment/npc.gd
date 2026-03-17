extends CharacterBody3D

@export var speed := 5.0
@export var stop_distance := 1.0
@export var chase_target: CharacterBody3D
@export var status : State = State.IDLE

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var update_timer: Timer = $UpdateTimer
@onready var debug_text: Label3D = $DebugText
@onready var last_to_next : Vector3 = Vector3.ZERO
enum State {
	CHASE,
	ROAM,
	IDLE,
	RESET
}

func _ready() -> void:
	if not multiplayer.is_server():
		set_physics_process(false)
		$UpdateTimer.stop()
		return
	var root := get_tree().current_scene
	status = State.CHASE
	chase_target = root.find_child("Player")
	agent.path_desired_distance = stop_distance
	agent.target_desired_distance = stop_distance

@rpc("unreliable", "call_remote", "authority")
func sync_npc_state(pos: Vector3, vel: Vector3) -> void:
	global_position = pos
	velocity = vel

func set_move_target(world_pos: Vector3) -> void:
	agent.target_position = world_pos

func chase(): # chases current chase_target
	# if chasee dies or becomes unreachable or timeout, exit state

	# else update current target:
	agent.target_position = chase_target.global_position

func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0

	# Update target (you can move this to the timer later if you want)
	if status == State.CHASE:
		if chase_target:
			agent.target_position = chase_target.global_position

	# Stop if we’re done
	if agent.is_navigation_finished():
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()

		return

	# Get next waypoint along the path
	var next_pos := agent.get_next_path_position()

	# Debug + “skip vertical projection first point” handling
	var path := agent.get_current_navigation_path()
	var idx := agent.get_current_navigation_path_index()

	# If next waypoint is basically straight down/up, use the next corner instead.
	if Vector2(next_pos.x - global_position.x, next_pos.z - global_position.z).length() < 0.01:
		if path.size() > idx + 1:
			next_pos = path[idx + 1]

	# Compute direction AFTER possible replacement
	var to_next := next_pos - global_position
	to_next.y = 0.0
	if(last_to_next != to_next):
		last_to_next = to_next
	else:
		to_next = Vector3.ZERO
		_reset_pos()
	debug_text.text = "idx=%d/%d nxt(dxz=%.3f dy=%.3f) vel=%.2f fin=%s" % [
		idx, path.size(),
		Vector2(next_pos.x - global_position.x, next_pos.z - global_position.z).length(),
		abs(next_pos.y - global_position.y),
		Vector2(velocity.x, velocity.z).length(),
		str(agent.is_navigation_finished())
	]


	# Constant-speed movement (no acceleration)
	if to_next.length() > 0.001:
		var dir := to_next.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()
	rpc("sync_npc_state", global_position, velocity)

func _on_update_timer_timeout() -> void:
	if not multiplayer.is_server(): return
	if status == State.CHASE:
		chase()


func _reset_pos():
	global_position = Vector3.ZERO
