extends RigidBody3D
class_name GrabbableObject

@export var item_id: String = ""  # unique identifier for this object
@export var hold_distance := 1.0
@export var follow_speed := 15.0
@export var hold_offset := Vector3(0.6, -0.4, -2.0)
@export var is_grabbable := true

@onready var explosion: PackedScene = preload("res://scenes/BigBoom.tscn")

var is_held := false
var holder: Node3D = null

func _ready():
	contact_monitor = true
	max_contacts_reported = 10

func _physics_process(delta):
	if not is_held or holder == null:
		return

	# Desired position in front of the holder (camera)
	var target_pos = holder.global_transform.origin + holder.global_transform.basis.z * -hold_distance + holder.global_transform.basis.x * 0.6 + holder.global_transform.basis.y * -0.3

	# Smooth follow
	global_position = global_position.lerp(target_pos, follow_speed * delta)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	
#check for player, and if hit, ragdoll
func _on_body_entered(body):
	if body.is_in_group("players"):
		try_ragdoll(body)
		
func try_ragdoll(body):
	var speed = linear_velocity.length()
	print("pelted stu with speed " + str(speed))

	if speed > 4.0: 
		var boom = explosion.instantiate()
		add_child(boom)
		boom.global_position = global_position
		print(boom.position)
		boom.create(1.0, 5)
		


#grab helper
func grab(camera: Node3D):
	is_held = true
	holder = camera
	freeze = true
	GameNetwork.send_p2p_packet(0, {
		"message": "player_action",
		"action": "grab",
		"item_id": item_id,
		"id": Steam.getSteamID(),
	}, Steam.P2P_SEND_RELIABLE)

func release():
	var pos := global_position
	is_held = false
	holder = null
	freeze = false
	GameNetwork.send_p2p_packet(0, {
		"message": "player_action",
		"action": "release",
		"item_id": item_id,
		"id": Steam.getSteamID(),
		"px": pos.x,
		"py": pos.y,
		"pz": pos.z,
	}, Steam.P2P_SEND_RELIABLE)

# Called when item is placed on an interaction point
func place_on(interaction_point: Node3D):
	var target_pos := interaction_point.global_position + Vector3(0, 1.5, 0)
	is_held = false
	holder = null
	GameNetwork.send_p2p_packet(0, {
		"message": "player_action",
		"action": "place",
		"item_id": item_id,
		"id": Steam.getSteamID(),
		"px": target_pos.x,
		"py": target_pos.y,
		"pz": target_pos.z,
	}, Steam.P2P_SEND_RELIABLE)

#move helper
func move_to_position(target: Vector3, duration: float = 0.3):
	# Stop physics motion
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true  # optional: prevents physics interference

	var tween = create_tween()
	tween.tween_property(self, "global_position", target, duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)
