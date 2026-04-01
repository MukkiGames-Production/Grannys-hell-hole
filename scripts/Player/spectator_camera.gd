extends Node3D
class_name SpectatorCamera

@export var pivot: Node3D
@export var camera = Camera3D

@export var mouse_sensitivity := 0.002

@export var valid_players: Array[Node] = []

var target_index := 0
var target = null

func _ready() -> void:
	camera.current = false
	visible = false
	set_process_input(false)
	set_process_unhandled_input(false)
	
	valid_players = get_tree().get_nodes_in_group("players")
	print("Valid Players: " + str(valid_players))
	
func activate():
	camera.current = true
	set_process_input(true)
	set_process_unhandled_input(true)
	visible = true
	
	target_index = 0
	target = valid_players[target_index]
	
func _unhandled_input(event: InputEvent) -> void:
	# Toggle mouse capture with Escape
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			return
		
		# Switch player (only when mouse is captured)
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			if event.keycode == KEY_A:
				valid_players = get_tree().get_nodes_in_group("players")
				switch_player(-1)
			elif event.keycode == KEY_D:
				valid_players = get_tree().get_nodes_in_group("players")
				switch_player(1)

	# Ignore mouse input when menu visible
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouseMotion:
		_handle_mouse_look(event)
		

func _handle_mouse_look(event: InputEventMouseMotion) -> void:
	rotate_y(-event.relative.x * mouse_sensitivity)
	pivot.rotate_x(-event.relative.y * mouse_sensitivity)

func _process(delta: float) -> void:
	if target:
		self.global_position = target.global_position + Vector3(0, 1.5, -0.5)
		set_third_person_cam_pos()
		
		camera.rotation.x = clamp(
			self.rotation.x,
			deg_to_rad(-80),
			deg_to_rad(80)
		)
	elif get_tree().get_nodes_in_group("players"):
		switch_player(1)
		
func switch_player(direction: int) -> void:
	print(direction)
	if valid_players.is_empty():
		return
	
	target_index += direction
	
	# Wrap around
	if target_index < 0:
		target_index = valid_players.size() - 1
	elif target_index >= valid_players.size():
		target_index = 0
	
	target = valid_players[target_index]

func set_third_person_cam_pos():
	var origin = pivot.global_transform.origin
	
	# Direction backwards from player
	var direction = pivot.global_transform.basis.z.normalized()
	
	var max_distance = 4.0
	var target_position = origin + direction * max_distance

	# Raycast
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(origin, target_position)
	query.exclude = [target]  # avoid hitting the player
	
	var result = space_state.intersect_ray(query)

	if result:
		# Move camera to hit point (slightly forward to avoid clipping)
		camera.global_transform.origin = result.position + result.normal * 0.2
	else:
		# No collision → full distance
		camera.global_transform.origin = target_position
