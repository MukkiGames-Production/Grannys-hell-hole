extends ProgressBar

var player

func _ready():
	visible = false
	await get_tree().process_frame
	var players = get_tree().get_nodes_in_group("players")
	if players.size() > 0: #just get me fo now
		player = players[0]

	min_value=0
	max_value=player.max_charge_time
	fill_mode = 0
	
	value_changed.connect(_on_value_changed)
	

func _process(_delta):
	if player:
		value = player.throw_charge
		
func _on_value_changed(new_value):
	visible = new_value > min_value
