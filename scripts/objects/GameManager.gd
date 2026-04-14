extends Node3D
@onready var player = preload("res://scenes/stu_with_ragdoll.tscn")
@onready var voip: Node = $Voip

## Dictionary mapping remote steam_id -> their CharacterBody3D node
var remote_players: Dictionary = {}

## Dictionary mapping item_id -> the GrabbableObject node in the scene
var scene_objects: Dictionary = {}

## Dictionary mapping remote steam_id -> the item_id they are holding
var remote_held_items: Dictionary = {}

## Reference to the local player node (inside the instanced main.tscn, which is "Node3D")
@onready var local_player: CharacterBody3D = $Main/Stu

func _ready() -> void:
	# Initialize Steam if not already done
	var init_steam_node = InitSteam.new()
	add_child(init_steam_node)

	# Connect to the persistent GameNetwork autoload for incoming packets
	GameNetwork.p2p_packet_received.connect(_on_p2p_packet_received)
	GameNetwork.player_joined.connect(_on_player_joined)
	GameNetwork.player_left.connect(_on_player_left)

	# Spawn remote player nodes for everyone already in the lobby (except us)
	if GameNetwork.lobby_id > 0:
		print("[World] Game started with %s players in lobby" % GameNetwork.lobby_members.size())
		for member in GameNetwork.lobby_members:
			if member["steam_id"] != GameNetwork.steam_id and member["steam_id"] != Steam.getSteamID() and member["steam_name"] != Steam.getPersonaName():
				_spawn_remote_player(member["steam_id"], member["steam_name"])
	else:
		print("[World] No active lobby — running in single-player mode")

	voip.voice_data_ready.connect(_on_voice_data_ready)
	voip.start_recording()
	voip.set_loopback(true)



	# Build a lookup table of all interactive objects by their item_id
	_register_scene_objects()

func _register_scene_objects() -> void:
	# Find all interactive nodes under $Main and index them

	for node in _find_nodes_of_type($Main, "GrabbableObject"):
		if node is GrabbableObject and node.item_id != "":
			scene_objects[node.item_id] = node
			print("[World] Registered scene object: %s" % node.item_id)
		elif node is InteractionPoint:
			scene_objects[node.name] = node
			print("[World] Registered interaction point: %s" % node.name)

func _find_nodes_of_type(root: Node, type_name: String) -> Array:
	var results := []
	for child in root.get_children():
		if child.get_class() == type_name or child is GrabbableObject or child is InteractionPoint:
			results.append(child)
		results.append_array(_find_nodes_of_type(child, type_name))
	return results

@rpc("call_local", "any_peer")
func _on_voice_data_ready(buffer: PackedByteArray) -> void:
	GameNetwork.send_p2p_packet(0, {
		"message": "voice_data",
		"buffer": buffer,
		"id": Steam.getSteamID(),
	}, Steam.P2P_SEND_RELIABLE)
	if voip.has_loopback:
		voip.process_voice_data(buffer, "local")

func _physics_process(_delta: float) -> void:
	if GameNetwork.lobby_id <= 0:
		return
	if not is_instance_valid(local_player):
		return



	# Update held objects to follow their remote player holders
	for steam_id in remote_held_items:
		var item_id: String = remote_held_items[steam_id]
		var obj: GrabbableObject = scene_objects.get(item_id, null)
		var holder: Node3D = remote_players.get(steam_id, null)
		if obj and holder and is_instance_valid(obj) and is_instance_valid(holder):
			# Position the object in front of the remote player
			var target_pos := holder.global_position + holder.global_transform.basis.z * -1.0 + holder.global_transform.basis.x * 0.6 + holder.global_transform.basis.y * 0.3
			obj.global_position = obj.global_position.lerp(target_pos, 0.5)

# ---- Packet handling ----

func _on_p2p_packet_received(sender_id: int, data: Dictionary) -> void:
	var msg: String = data.get("message", "")

	match msg:
		"player_update":
			_handle_player_update(sender_id, data)
		"voice_data":
			_handle_voice_data(data)
		"player_action":
			_handle_player_action(sender_id, data)
		"npc_update":
			_handle_npc_update(data)
		"handshake":
			print("[World] Received handshake from %s" % sender_id)
		_:
			print("[World] Unhandled packet type '%s' from %s" % [msg, sender_id])
func _handle_npc_update(data: Dictionary) -> void:
	var npc_id: String = data.get("id", "")
	var npc_node: Node = $Main.get_node_or_null(npc_id)
	if npc_node and is_instance_valid(npc_node):
		npc_node.global_position = Vector3(data.get("px", 0), data.get("py", 0), data.get("pz", 0))
		npc_node.velocity = Vector3(data.get("vx", 0), data.get("vy", 0), data.get("vz", 0))
		npc_node.status = data.get("status",0 )


func _handle_player_update(sender_id: int, data: Dictionary) -> void:
	var sender_name: String = Steam.getFriendPersonaName(sender_id)
	if sender_id not in remote_players:
		_spawn_remote_player(sender_id, sender_name)
		return
	var remote: Node3D = remote_players[sender_id]
	if not is_instance_valid(remote):
		return

	var target_pos := Vector3(
		data.get("px", 0.0),
		data.get("py", 0.0),
		data.get("pz", 0.0),
	)
	var target_rot := Vector3(
		data.get("rx", 0.0),
		data.get("ry", 0.0),
		data.get("rz", 0.0),
	)

	# Lerp for smooth movement instead of snapping
	remote.global_position = remote.global_position.lerp(target_pos, 0.5)
	remote.global_rotation = target_rot

	# Play animations on remote players
	var remote_walking: bool = data.get("is_walking", false)
	var anim_player: AnimationPlayer = remote.get_node_or_null("AnimationPlayer")
	if anim_player:
		if remote_walking and not anim_player.is_playing():
			anim_player.play("Walk")
		elif not remote_walking and anim_player.is_playing():
			anim_player.stop()


func _handle_voice_data(data: Dictionary) -> void:
	var voice_buffer: PackedByteArray = data.get("buffer", PackedByteArray())
	if voice_buffer.size() > 0:
		if voip.has_method("receive_voice_data"):
			voip.receive_voice_data(voice_buffer)

func _handle_player_action(sender_id: int, data: Dictionary) -> void:
	var action: String = data.get("action", "")
	var item_id: String = data.get("item_id", "")
	print("[World] Player %s performed action: %s (item: %s)" % [sender_id, action, item_id])

	match action:
		"grab":
			_handle_remote_grab(sender_id, item_id)
		"release":
			var pos := Vector3(data.get("px", 0.0), data.get("py", 0.0), data.get("pz", 0.0))
			_handle_remote_release(sender_id, item_id, pos)
		"place":
			var pos := Vector3(data.get("px", 0.0), data.get("py", 0.0), data.get("pz", 0.0))
			_handle_remote_place(sender_id, item_id, pos)
		"break_wall":
			var pos := Vector3(data.get("px", 0.0), data.get("py", 0.0), data.get("pz", 0.0))
			_handle_remote_break_wall(pos)
		"enable_ragdoll":
			var v := Vector3(data.get("vx", 0.0), data.get("vy", 0.0), data.get("vz", 0.0))
			_handle_remote_ragdoll(sender_id, v)
		"bookshelf_open":
			var book_id: String = data.get("book_id", "")
			_handle_remote_bookshelf_open(sender_id, item_id, book_id)
		"replace_model":
			var new_model_id: String = data.get("new_model_id", "")
			_handle_remote_replace_model(sender_id, item_id, new_model_id)
		"disable_ragdoll":
			_handle_remote_disable_ragdoll(sender_id)
		"reset_game":
			_do_reset()
		_:
			print("[World] Unknown action: %s" % action)
func _handle_remote_bookshelf_open(sender_id: int, item_id: String, book_id: String) -> void:
	var obj: Node = scene_objects.get(item_id, null)
	var book: Node = scene_objects.get(book_id, null)

	if obj and is_instance_valid(obj) and obj.has_node("AnimationPlayer"):
		var anim_player: AnimationPlayer = obj.get_node("AnimationPlayer")
		anim_player.play("bookshelf_open")

		if book and is_instance_valid(book) and obj.has_node("TargetPos"):
			var target = obj.get_node("TargetPos")
			if obj.has_method("move_to_point"):
				obj.move_to_point(book, target.global_position, true)
			book.reparent(obj, true)

		print("[World] Remote player %s opened bookshelf %s" % [sender_id, item_id])
func _handle_remote_replace_model(sender_id: int, item_id: String, new_model_id: String) -> void:
	var obj: GrabbableObject = scene_objects.get(item_id, null)
	if obj and is_instance_valid(obj):
		obj.replace_model(obj.mesh, new_model_id)
		print("[World] Remote player %s replaced model of %s with %s" % [sender_id, item_id, new_model_id])
func _handle_remote_grab(sender_id: int, item_id: String) -> void:
	var obj: GrabbableObject = scene_objects.get(item_id, null)
	if obj and is_instance_valid(obj):
		obj.freeze = true
		obj.is_held = true
		# Don't set holder — the local _physics_process on world.gd moves it
		remote_held_items[sender_id] = item_id
		print("[World] Remote player %s grabbed %s" % [sender_id, item_id])

func _handle_remote_release(sender_id: int, item_id: String, pos: Vector3) -> void:
	remote_held_items.erase(sender_id)
	var obj: GrabbableObject = scene_objects.get(item_id, null)
	if obj and is_instance_valid(obj):
		obj.is_held = false
		obj.holder = null
		obj.freeze = false
		obj.global_position = pos
		print("[World] Remote player %s released %s at %s" % [sender_id, item_id, pos])

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		_on_debug_reset_pressed()

func _on_debug_reset_pressed() -> void:
	if GameNetwork.lobby_id > 0:
		GameNetwork.send_p2p_packet(0, {"message": "player_action", "action": "reset_game"})
	_do_reset()

func _do_reset() -> void:
	print("[World] Resetting game state...")
	get_tree().reload_current_scene()

func _handle_remote_place(sender_id: int, item_id: String, pos: Vector3) -> void:
	remote_held_items.erase(sender_id)
	var obj: GrabbableObject = scene_objects.get(item_id, null)
	if obj and is_instance_valid(obj):
		obj.is_held = false
		obj.holder = null
		obj.freeze = true
		obj.gravity_scale = 0
		obj.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		obj.lock_rotation = true
		obj.is_grabbable = false
		obj.collision_layer = 4
		obj.collision_mask = 0
		# Tween to final position
		var tween := create_tween()
		tween.tween_property(obj, "global_position", pos, 0.3)\
			.set_trans(Tween.TRANS_SINE)\
			.set_ease(Tween.EASE_OUT)
		print("[World] Remote player %s placed %s at %s" % [sender_id, item_id, pos])

func _handle_remote_ragdoll(sender_id: int, v: Vector3) -> void:
	var remote = remote_players.get(sender_id, null)
	if remote and is_instance_valid(remote) and remote.has_method("enable_ragdoll"):
		remote.enable_ragdoll(v)
		print("[World] Remote player %s ragdolled" % sender_id)

func _handle_remote_disable_ragdoll(sender_id: int) -> void:
	var remote = remote_players.get(sender_id, null)
	if remote and is_instance_valid(remote) and remote.has_method("disable_ragdoll"):
		remote.disable_ragdoll()
		print("[World] Remote player %s disabled ragdoll" % sender_id)

func _handle_remote_break_wall(impact_pos: Vector3) -> void:
	var wall = $Main/breakablewall
	if wall and is_instance_valid(wall) and wall is BreakableWall:
		if not wall.is_broken:
			# Call break_wall but we need to avoid it re-sending the packet.
			# Since is_broken gets set to true first, and we're calling from
			# the same code path, we directly trigger the break visuals.
			wall.is_broken = true
			var impact_point :Vector3 = impact_pos if impact_pos != Vector3.ZERO else wall.global_position
			var meshes :Array[MeshInstance3D]= wall._get_all_meshes(wall)
			for mesh in meshes:
				wall._convert_to_physics_piece(mesh, impact_point)
			wall.set_process(false)
			print("[World] Remote player broke the wall")

# ---- Remote player management ----

func _spawn_remote_player(peer_steam_id: int, peer_name: String) -> void:
	if peer_steam_id in remote_players:
		return

	var remote := player.instantiate() as CharacterBody3D
	remote.name = "RemotePlayer_%s" % peer_steam_id

	# Name label above head
	var label_3d := Label3D.new()
	label_3d.text = peer_name
	label_3d.position = Vector3(0, 2, 0)
	label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_3d.font_size = 32
	label_3d.no_depth_test = true
	remote.add_child(label_3d)

	# Default spawn position (same as local player start)

	remote.call_deferred("set_global_transform", Transform3D(Basis(), Vector3(3, 2.3, 0)))
	remote.connect("ready", func():
		remote.set_physics_process(false)
		remote.set_process(false)
		remote.set_process_input(false)
		remote.set_process_unhandled_input(false)
	)

	# var cam = remote.get_node_or_null("CameraPivot/Camera3D")
	# # if cam:
	# # 	cam.current = false
	# # 	cam.queue_free()

	if (peer_steam_id == Steam.getSteamID() or peer_name == Steam.getPersonaName()):
		return
	$Main.add_child(remote, true)
	remote_players[peer_steam_id] = remote
	print("[World] Spawned remote player: %s (steam_id: %s)" % [peer_name, peer_steam_id])

func _remove_remote_player(peer_steam_id: int) -> void:
	if peer_steam_id in remote_players:
		var node: Node = remote_players[peer_steam_id]
		if is_instance_valid(node):
			node.queue_free()
		remote_players.erase(peer_steam_id)
		# Drop any item they were holding
		remote_held_items.erase(peer_steam_id)
		print("[World] Removed remote player: %s" % peer_steam_id)

# ---- Lobby change callbacks ----

func _on_player_joined(peer_steam_id: int, player_name: String) -> void:
	print("[World] Player joined mid-game: %s (%s)" % [player_name, peer_steam_id])
	_spawn_remote_player(peer_steam_id, player_name)

func _on_player_left(peer_steam_id: int) -> void:
	print("[World] Player left: %s" % peer_steam_id)
	_remove_remote_player(peer_steam_id)

func _exit_tree() -> void:
	if GameNetwork.p2p_packet_received.is_connected(_on_p2p_packet_received):
		GameNetwork.p2p_packet_received.disconnect(_on_p2p_packet_received)
	if GameNetwork.player_joined.is_connected(_on_player_joined):
		GameNetwork.player_joined.disconnect(_on_player_joined)
	if GameNetwork.player_left.is_connected(_on_player_left):
		GameNetwork.player_left.disconnect(_on_player_left)
