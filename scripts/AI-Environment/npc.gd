extends CharacterBody3D

@export var speed := 5.0
@export var stop_distance := 1.0
@export var chase_target: CharacterBody3D
@export var status : State = State.IDLE

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var update_timer: Timer = $UpdateTimer
@onready var debug_text: Label3D = $DebugText

enum State {
	CHASE,
	ROAM,
	IDLE
}

func _ready() -> void:
	var root := get_tree().current_scene
	status = State.CHASE
	chase_target = root.find_child("Player")
	agent.path_desired_distance = stop_distance
	agent.target_desired_distance = stop_distance

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

	if status == State.CHASE:
		chase()

	# Stop if we’re done
	if agent.is_navigation_finished():
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	# Follow next nav point
	var next_pos := agent.get_next_path_position()
	var to_next := next_pos - global_position
	to_next.y = 0.0
	
	debug_text.text = "%s dxz=%.3f dy=%.3f" % [
		State.keys()[status],
		Vector2(next_pos.x - global_position.x, next_pos.z - global_position.z).length(),
		abs(next_pos.y - global_position.y)
	]

	if to_next.length() > 0.001:
		var dir := to_next.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()

func _on_update_timer_timeout() -> void:
	if status == State.CHASE:
		chase()
