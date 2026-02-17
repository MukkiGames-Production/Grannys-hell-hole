extends TextureRect

@export var reticleWhenNotLooking: Texture2D
@export var reticleWhenLooking: Texture2D

func _on_player_look_at_interactable(can_see: bool) -> void:
	if can_see:
		texture = reticleWhenLooking
	else:
		texture = reticleWhenNotLooking
