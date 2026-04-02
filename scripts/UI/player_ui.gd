extends Control

@export var time_label: Label
@export var schedule_label: Label

func _ready() -> void:
	# If labels aren't assigned via inspector, try finding them by expected names
	if not time_label and has_node("TimeLabel"):
		time_label = $TimeLabel
	if not schedule_label and has_node("ScheduleLabel"):
		schedule_label = $ScheduleLabel

	if Scheduler:
		# Connect to Scheduler signals to update schedule block efficiently
		Scheduler.block_changed.connect(_on_block_changed)

		# Initial UI setup
		if schedule_label:
			schedule_label.text = "Schedule: " + Scheduler.get_current_block_name()

func _process(_delta: float) -> void:
	# Update the time continuously as it changes every frame
	if Scheduler and time_label:
		time_label.text = "Time: " + Scheduler.get_time_string()

func _on_block_changed(new_block_name: String) -> void:
	if schedule_label:
		schedule_label.text = "Schedule: " + new_block_name
