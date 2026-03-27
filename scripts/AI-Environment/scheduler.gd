# scheduler.gd
# Autoload this node (singleton) via Project > Project Settings > Autoload
# so every NPC can call Scheduler.get_current_block() from anywhere.
#
# Time model
# ----------
# One full in-game "day" lasts REAL_DAY_DURATION_SECONDS real-world seconds.
# game_time_normalized is a value in [0.0, 1.0) that represents how far
# through the current day we are.  Multiply by 24 to get the "hour".
#
# Day blocks
# ----------
# Each block has a name, a start hour (inclusive) and an end hour (exclusive).
# Blocks are evaluated in order; the first one whose window contains the
# current hour wins.
#
# NPC schedules
# -------------
# Register an NPC with register_npc().  The schedule is an Array of dicts:
#
#   {
#       "block":        "MORNING",          # matches a DayBlock.name
#       "location_key": "dining_hall",      # arbitrary string your NPC reads
#       "behavior":     "eat",              # arbitrary string your NPC reads
#       "priority":     0,                  # higher overrides lower (optional)
#   }
#
# Call get_schedule_for(npc) to retrieve the highest-priority entry matching
# the current block.  NPCs should poll this every update-timer tick.

extends Node
# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted whenever the active time block changes.
signal block_changed(new_block_name: String)

## Emitted once per in-game day when the day rolls over.
signal new_day(day_number: int)

# ---------------------------------------------------------------------------
# Exported tunables
# ---------------------------------------------------------------------------

## How many real-world seconds make up one full in-game day.
@export var real_day_duration_seconds: float = 50.0   # 8 minutes default

## Which hour the day starts at (0–23).  Lets you skip the night if desired.
@export var start_hour: float = 6.0

## Pause the clock (useful for cutscenes / menus).
@export var paused: bool = false

# ---------------------------------------------------------------------------
# Built-in day blocks
# Each dict: { name, start_hour, end_hour }
# start_hour is INCLUSIVE, end_hour is EXCLUSIVE.
# Hours wrap correctly across midnight.
# ---------------------------------------------------------------------------

var day_blocks: Array[Dictionary] = [
	{ "name": "EARLY_MORNING", "start_hour": 6.0,  "end_hour": 8.0  },
	{ "name": "MORNING",       "start_hour": 8.0,  "end_hour": 12.0 },
	{ "name": "AFTERNOON",     "start_hour": 12.0, "end_hour": 17.0 },
	{ "name": "EVENING",       "start_hour": 17.0, "end_hour": 20.0 },
	{ "name": "NIGHT",         "start_hour": 20.0, "end_hour": 23.0 },
	{ "name": "LATE_NIGHT",    "start_hour": 23.0, "end_hour": 6.0  },  # wraps midnight
]

# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------

## Current in-game hour (0.0 – 24.0).
var current_hour: float = 6.0

## Elapsed seconds within the current day.
var elapsed_seconds: float = 0.0

## How many full days have passed since the game started.
var day_count: int = 0

## The name of the currently active block, e.g. "MORNING".
var current_block_name: String = ""

# Internal: normalised position through the playable day (0→1).
var _playable_span: float = 0.0

# Registry: { npc_node -> Array[Dictionary] }
var _npc_schedules: Dictionary = {}

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_playable_span = real_day_duration_seconds   # full 24 h by default
	current_hour = start_hour
	_update_block()


func _process(delta: float) -> void:
	if paused:
		return

	elapsed_seconds += delta

	# Map elapsed time → hour (0–24)
	var progress: float = fmod(elapsed_seconds, real_day_duration_seconds) / real_day_duration_seconds
	current_hour = fmod(start_hour + progress * 24.0, 24.0)

	# Check for day rollover
	var new_day_count: int = int(elapsed_seconds / real_day_duration_seconds)
	if new_day_count > day_count:
		day_count = new_day_count
		new_day.emit(day_count)

	_update_block()

# ---------------------------------------------------------------------------
# Block helpers
# ---------------------------------------------------------------------------

func _update_block() -> void:
	var block := _find_block_for_hour(current_hour)
	if block.name != current_block_name:
		current_block_name = block.name
		block_changed.emit(current_block_name)


## Returns the DayBlock dict whose window contains *hour*.
func _find_block_for_hour(hour: float) -> Dictionary:
	for block in day_blocks:
		if _hour_in_block(hour, block):
			return block
	# Fallback: return the first block
	return day_blocks[0]


func _hour_in_block(hour: float, block: Dictionary) -> bool:
	var s: float = block.start_hour
	var e: float = block.end_hour
	if s < e:
		return hour >= s and hour < e
	else:
		# Wraps midnight  (e.g. 23 → 6)
		return hour >= s or hour < e


## Returns the current block dict.
func get_current_block() -> Dictionary:
	return _find_block_for_hour(current_hour)


## Returns the current block name string.
func get_current_block_name() -> String:
	return current_block_name


## Returns a formatted time string, e.g.  "08:45".
func get_time_string() -> String:
	var h: int = int(current_hour)
	var m: int = int(fmod(current_hour, 1.0) * 60.0)
	return "%02d:%02d" % [h, m]

# ---------------------------------------------------------------------------
# NPC registration & schedule lookup
# ---------------------------------------------------------------------------

## Register an NPC with its schedule.
## schedule_entries is an Array of dicts (see top-of-file format).
func register_npc(npc: Node, schedule_entries: Array) -> void:
	_npc_schedules[npc] = schedule_entries


## Remove an NPC from the registry (call from npc._exit_tree).
func unregister_npc(npc: Node) -> void:
	_npc_schedules.erase(npc)


## Returns the highest-priority schedule entry for *npc* matching the
## current block, or an empty dict if nothing matches.
func get_schedule_for(npc: Node) -> Dictionary:
	if not _npc_schedules.has(npc):
		return {}

	var entries: Array = _npc_schedules[npc]
	var best: Dictionary = {}
	var best_priority: int = -9999

	for entry in entries:
		if entry.get("block", "") == current_block_name:
			var p: int = entry.get("priority", 0)
			if p > best_priority:
				best_priority = p
				best = entry

	return best


## Convenience: returns just the location_key for *npc* this block, or "".
func get_location_for(npc: Node) -> String:
	return get_schedule_for(npc).get("location_key", "")


## Convenience: returns just the behavior string for *npc* this block, or "".
func get_behavior_for(npc: Node) -> String:
	return get_schedule_for(npc).get("behavior", "")

# ---------------------------------------------------------------------------
# Debug helpers
# ---------------------------------------------------------------------------

## Prints a human-readable summary of the current time state.
#func debug_print_status() -> void:
	#print("[Scheduler] Day %d | %s | Block: %s" % [day_count, get_time_string(), current_block_name])


## Prints every registered NPC and their current schedule entry.
func debug_print_all_schedules() -> void:
	pass
	#debug_print_status()
	#for npc in _npc_schedules.keys():
		#var entry := get_schedule_for(npc)
		#if entry.is_empty():
			#print("  %s → (no entry for %s)" % [npc.name, current_block_name])
		#else:
			#print("  %s → location='%s'  behavior='%s'  priority=%d" % [
				#npc.name,
				#entry.get("location_key", ""),
				#entry.get("behavior", ""),
				#entry.get("priority", 0)
			#])
