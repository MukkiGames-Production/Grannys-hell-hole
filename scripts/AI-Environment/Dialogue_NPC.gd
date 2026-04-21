extends Node3D

@export var status : State = State.IDLE
@export var dialogue_json: JSON

enum State {
	IDLE,
	TALKING,
	NONE
}

@onready var npc_model: Node3D = $NPCModel
@onready var npc_body: AnimatableBody3D = $NPCModel/AnimatableBody3D
@onready var animation_player: AnimationPlayer = $AnimationPlayer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass
	#animation_player.process_mode = Node.PROCESS_MODE_ALWAYS
	#animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	#npc_body.sync_to_physics = true

func activate():
	return dialogue_json
