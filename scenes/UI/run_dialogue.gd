extends RichTextLabel

@export var type_speed: float = 0.01
@export var dialogue_box: PanelContainer
@export var stu_voice: AudioStreamPlayer
@export var npc_voice: AudioStreamPlayer

signal dialogue_finished
signal advance_requested  # Emitted when player wants to skip or continue

var skipping := false
var waiting_for_input := false

func _ready() -> void:
	dialogue_box.visible = false

# Main dialogue runner
func run_dialogue(dialogue_json) -> void:
	dialogue_box.visible = true
	var dialogue_data = dialogue_json.data
	var lines = dialogue_data["lines"]
	
	for line in lines:
		var text = line["text"]
		var color = Color.WHITE
		
		match line["speaker"]:
			"Stu":
				color = Color.PINK
			"NPC":
				color = Color.MEDIUM_PURPLE
		
		await show_line(text, color)
		await get_tree().create_timer(0.5).timeout
	
	dialogue_box.visible = false
	
	# === DIALOGUE IS NOW COMPLETELY FINISHED ===
	dialogue_finished.emit()


# Display one line of text
func show_line(text: String, color: Color) -> void:
	if text.is_empty():
		return
	
	# Set correct voice
	var sound: AudioStreamPlayer = stu_voice if color == Color.PINK else npc_voice
	
	clear()
	push_color(color)
	append_text(text)
	pop()
	
	visible_characters = 0
	skipping = false
	waiting_for_input = false
	
	var timer := 0.0
	
	# ── Typing phase ────────────────────────────────
	while visible_characters < text.length():
		if skipping:
			visible_characters = text.length()
			break
		
		timer += get_process_delta_time()
		if timer >= type_speed:
			visible_characters += 1
			sound.play()
			
			# Punctuation pauses
			var current_char = text[visible_characters - 1]
			if current_char in [".", "!", "?"]:
				timer = -type_speed * 3
			elif current_char == ",":
				timer = -type_speed * 1.5
			else:
				timer = 0.0
		
		await get_tree().process_frame
	
	# ── All text is now visible ─────────────────────
	waiting_for_input = true
	await get_tree().create_timer(0.01).timeout
	
	# Wait for signal instead of click
	await advance_requested
	waiting_for_input = false
	text = ""   # Clear the RichTextLabel content


# ── Signal Handler ─────────────────────────────────
func _on_advance_requested() -> void:
	if not waiting_for_input:
		skipping = true   # Skip during typing
	else:
		# Continue to next line
		pass  # The await will continue

# Public method so other scripts can also trigger it (e.g. keyboard, controller, auto-advance, etc.)
func request_advance() -> void:
	advance_requested.emit()
