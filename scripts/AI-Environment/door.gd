extends Node3D

@export var status : State = State.CLOSED
@export var okay_status : State = State.CLOSED # AI expects door to be closed, NONE if it dont matta

enum State {
	OPEN,
	CLOSED,
	NONE
}

@onready var door: Node3D = $"."
@onready var debug_text: Label3D = $DebugText
@onready var door_model: Node3D = $DoorModel
@onready var door_body: AnimatableBody3D = $DoorModel/AnimatableBody3D
@onready var animation_player: AnimationPlayer = $AnimationPlayer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_update_debug_text()
	animation_player.process_mode = Node.PROCESS_MODE_ALWAYS
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	door_body.sync_to_physics = true


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func toggle_door():
	if animation_player.is_playing():
		return

	if status == State.CLOSED:
		# open
		status = State.OPEN
		# do door anim
		animation_player.play("open_door")
	else:
		#close
		status = State.CLOSED
		# do door anim
		animation_player.play_backwards("open_door")

	_update_debug_text()


func _update_debug_text() -> void:
	if not debug_text:
		return

	match status:
		State.OPEN:
			debug_text.text = "Door Open"
		State.CLOSED:
			debug_text.text = "Door Closed"
		_:
			debug_text.text = "Door"
