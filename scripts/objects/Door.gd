extends Area3D

func _on_body_entered(body: CharacterBody3D)->void:
	if body.is_in_group("players"):
		var anim = $AnimationPlayer
		if anim.is_playing():
			return
		anim.play("open")
