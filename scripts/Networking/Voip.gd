extends Node

signal voice_data_ready(buffer: PackedByteArray)

@export var auto_record: bool = false

var current_sample_rate: int = 48000
var has_loopback: bool = true
var is_recording: bool = false
var steam_initialized: bool = false
var local_playback: AudioStreamGeneratorPlayback = null
var local_voice_buffer: PackedByteArray = PackedByteArray()
var network_playback: AudioStreamGeneratorPlayback = null
var network_voice_buffer: PackedByteArray = PackedByteArray()
var packet_read_limit: int = 5
var steam_id: int = 0

@onready var local_player: AudioStreamPlayer = $Local
@onready var network_player: AudioStreamPlayer = $Network

func _ready() -> void:
	# Set up audio players immediately (no Steam dependency)
	_setup_audio_players()

	# Try to initialize Steam-dependent stuff; if Steam isn't ready yet, defer it
	if _try_steam_init():
		print("[VOIP] Steam ready at _ready()")
	else:
		print("[VOIP] Steam not ready yet, deferring initialization...")
		_wait_for_steam()

func _try_steam_init() -> bool:
	# Guard: Steam might not be initialized yet (e.g. Voip._ready fires before InitSteam)
	if not Steam.loggedOn():
		return false

	steam_id = Steam.getSteamID()
	steam_initialized = true
	print("[VOIP] Steam initialized, steam_id=%s" % steam_id)

	if auto_record and not is_recording:
		start_recording()

	return true

func _wait_for_steam() -> void:
	# Poll every 0.1s until Steam is ready
	var timer: SceneTreeTimer = get_tree().create_timer(0.1)
	timer.timeout.connect(_on_steam_retry)

func _on_steam_retry() -> void:
	if _try_steam_init():
		print("[VOIP] Steam ready after deferred init")
	else:
		# Still not ready, try again
		if is_inside_tree():
			_wait_for_steam()

func _setup_audio_players() -> void:
	if local_player and local_player.stream:
		local_player.stream.mix_rate = current_sample_rate
		local_player.play()
		local_playback = local_player.get_stream_playback()

	if network_player and network_player.stream:
		network_player.stream.mix_rate = current_sample_rate
		network_player.play()
		network_playback = network_player.get_stream_playback()

func _process(_delta: float) -> void:
	if is_recording and steam_initialized:
		check_for_voice()

func start_recording() -> void:
	if not steam_initialized:
		print("[VOIP] Cannot start recording: Steam not initialized")
		return
	is_recording = true
	Steam.setInGameVoiceSpeaking(steam_id, true)
	Steam.startVoiceRecording()
	print("[VOIP] Voice recording started")

func stop_recording() -> void:
	is_recording = false
	if steam_initialized:
		Steam.setInGameVoiceSpeaking(steam_id, false)
		Steam.stopVoiceRecording()
	print("[VOIP] Voice recording stopped")

func check_for_voice() -> void:
	# Call getVoice() directly every frame — no deprecated availability check needed.
	# Returns Dictionary with: result (int), buffer (PackedByteArray), written (int)
	var voice_data: Dictionary = Steam.getVoice()

	# VOICE_RESULT_OK = 0 means compressed voice data is available
	# VOICE_RESULT_NOT_RECORDING = 3 means no data yet (silence / no mic input) — skip quietly
	if voice_data['result'] != Steam.VOICE_RESULT_OK or voice_data['written'] <= 0:
		return

	print("[VOIP] Voice data captured: written=%s bytes" % voice_data['written'])

	# Emit signal so the lobby/network layer can send this to other players
	voice_data_ready.emit(voice_data['buffer'])

	# If loopback is enabled, play it back locally for testing
	if has_loopback:
		process_voice_data(voice_data['buffer'], "local")

func get_sample_rate(use_optimal: bool) -> void:
	if not steam_initialized:
		return

	if use_optimal:
		current_sample_rate = Steam.getVoiceOptimalSampleRate()
	else:
		current_sample_rate = 48000

	if local_player and local_player.stream:
		local_player.stream.mix_rate = current_sample_rate
	if network_player and network_player.stream:
		network_player.stream.mix_rate = current_sample_rate

func process_voice_data(compressed_buffer: PackedByteArray, voice_source: String) -> void:
	if not steam_initialized:
		return

	# Use the optimal sample rate for decompression
	get_sample_rate(true)

	var decompressed_voice: Dictionary = Steam.decompressVoice(compressed_buffer, current_sample_rate)

	if decompressed_voice['result'] != Steam.VOICE_RESULT_OK or decompressed_voice['size'] <= 0:
		return

	var buffer: PackedByteArray = decompressed_voice['uncompressed']
	buffer.resize(decompressed_voice['size'])

	var playback: AudioStreamGeneratorPlayback = null

	if voice_source == "local":
		local_voice_buffer = buffer
		playback = local_playback
	elif voice_source == "network":
		network_voice_buffer = buffer
		playback = network_playback

	if playback == null:
		return

	# Convert 16-bit PCM samples to audio frames and push to the generator
	var byte_index: int = 0
	var frames_available: int = playback.get_frames_available()
	var frames_pushed: int = 0

	while byte_index + 1 < buffer.size() and frames_pushed < frames_available:
		# Steam voice is 16-bit signed little-endian mono PCM
		var raw_value: int = buffer[byte_index] | (buffer[byte_index + 1] << 8)
		# Convert unsigned to signed 16-bit
		if raw_value >= 32768:
			raw_value -= 65536
		# Normalize to -1.0 to 1.0 range
		var amplitude: float = float(raw_value) / 32768.0

		# push_frame() takes a Vector2: x = left channel, y = right channel
		playback.push_frame(Vector2(amplitude, amplitude))

		byte_index += 2
		frames_pushed += 1

func receive_voice_data(compressed_buffer: PackedByteArray) -> void:
	# Called when receiving compressed voice data from the network
	process_voice_data(compressed_buffer, "network")

func set_loopback(enabled: bool) -> void:
	has_loopback = enabled
	print("[VOIP] Loopback set to: %s" % enabled)
