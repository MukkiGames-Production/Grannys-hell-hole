extends InteractionPoint

@export var wall_broken : Mesh

func empty_interact():
	replace_model(wall_broken)
