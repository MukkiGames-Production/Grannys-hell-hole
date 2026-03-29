extends InteractionPoint

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var targetpos: Node3D = $TargetPos

func interact(item: GrabbableObject):
	if item and item.item_id not in valid_objects:
		return false
	if item.item_id == "Book":
		animation_player.play("bookshelf_open")
		move_to_point(item, targetpos.global_position, true)
		item.reparent(self, true)
		GameNetwork.send_p2p_packet(0, {"message": "player_action", "action": "bookshelf_open","item_id": "Bookshelf" })
	return true
