extends Area3D
@onready var anim: AnimationPlayer = $"../AnimationPlayer"

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D)->void:
	if body.is_in_group("players"):

		if anim.is_playing():
			return
		anim.play("open_door")
