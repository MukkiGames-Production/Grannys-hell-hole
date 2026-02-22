extends Node

# noise emission flow:
# Item is dropped (or environment item is dropped or scripted noise event)
# -> check if noise is an okay noise - if yes, do nothing
# -> check if noise originated from a player inside an okay zoen - if yes, do nothing
# if no, pathfind noise from origin to active AI
# -> check if noise path is > limit for that AI, if yes, 
												# -> check if already in a chase, if no, chase

# note: maybe we can have group of suspicious players who were nearest (in radius) 
# of item drop location. This way it doesn't feel like AI just "knows" who dropped it when 
# the AI couldn't see and teammates were nearby.

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
