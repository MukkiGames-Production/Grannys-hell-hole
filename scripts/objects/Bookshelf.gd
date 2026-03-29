extends InteractionPoint

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var targetpos: Node3D = $TargetPos
func interact(item: GrabbableObject):
	if item and item.item_id not in valid_objects:
		return false
	if item.item_id == "Book":
		open_bookshelf.rpc(item.get_path())

	return true

@rpc("call_local", "any_peer")
func open_bookshelf(item_path: NodePath):
	var item = get_node_or_null(item_path)
	if item:
		animation_player.play("bookshelf_open")
		move_to_point(item, targetpos.global_position, true)
		item.reparent(self, true)
