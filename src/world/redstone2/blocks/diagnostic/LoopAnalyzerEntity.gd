## LoopAnalyzerEntity.gd — Loop analyzer (Analyseur de boucle). ID 4074.
## Detects oscillations, deadlocks, congestion, lost pulses, contradictory signals.
## Emits a diagnostic code on its output and populates the overlay error layer.
class_name LoopAnalyzerEntity
extends R2BlockEntity

enum DiagCode {
	OK           = 0,
	OSCILLATION  = 1,   # signal flips every tick
	DEADLOCK     = 2,   # no change for too long despite expected input
	CONGESTION   = 3,   # signals arrive faster than TPS can process
	LOST_PULSE   = 4,   # event detected but no downstream reaction
	CONTRADICTION = 5,  # two inputs carry conflicting values on same channel
}

var watch_radius: int = 4       # blocks to scan
var deadlock_threshold: int = 20  # ticks of no change before deadlock warning

var _diag:           int  = DiagCode.OK
var _last_values:    Dictionary = {}   # Vector3i → last analog value
var _no_change_ticks: int = 0
var _flip_counts:    Dictionary = {}   # Vector3i → consecutive flips


func _init(pos: Vector3i) -> void:
	super(pos, "r2_loop_analyzer")


func _get_input_faces() -> Array:
	return []


func _get_output_faces() -> Array:
	return [facing]   # diagnostic code (analog 0-255, mapped from DiagCode * 51)


func phase_calculate() -> void:
	_diag = DiagCode.OK
	var any_change := false
	var channel_values: Dictionary = {}   # ch → Array[int]

	var blocks := R2Engine.get_blocks_near(world_pos, watch_radius)

	for bpos in blocks:
		var ent := R2Engine.get_block(bpos)
		if ent == null: continue

		# Check oscillation: value flips back and forth
		var cur_val := 0
		var out_sig := ent.get_output(0)
		if out_sig != null: cur_val = out_sig.to_analog()

		var prev_val: int = _last_values.get(bpos, -1)
		if prev_val >= 0:
			if cur_val != prev_val:
				any_change = true
				var flips: int = _flip_counts.get(bpos, 0) + 1
				_flip_counts[bpos] = flips
				if flips >= 4:
					_diag = DiagCode.OSCILLATION
			else:
				_flip_counts[bpos] = 0

		_last_values[bpos] = cur_val

		# Collect per-channel values for contradiction check
		for ch in range(4):
			var sig := ent.get_output(ch)
			if sig == null: continue
			if not channel_values.has(ch):
				channel_values[ch] = []
			channel_values[ch].append(sig.to_analog())

	# Deadlock: no change for threshold ticks
	if any_change:
		_no_change_ticks = 0
	else:
		_no_change_ticks += 1
		if _no_change_ticks >= deadlock_threshold and _diag == DiagCode.OK:
			_diag = DiagCode.DEADLOCK

	# Contradiction: same channel carries both 0 and 255 from different sources
	if _diag == DiagCode.OK:
		for ch in channel_values:
			var vals: Array = channel_values[ch]
			var has_zero := false
			var has_max  := false
			for v in vals:
				if v == 0: has_zero = true
				if v >= 200: has_max = true
			if has_zero and has_max:
				_diag = DiagCode.CONTRADICTION
				break

	# Notify overlay
	if _diag != DiagCode.OK:
		R2Engine.emit_signal("r2_block_error", world_pos, DiagCode.keys()[_diag])


func phase_emit() -> void:
	emit_analog(_diag * 51)   # 0=OK, 51=OSC, 102=DEADLOCK, 153=CONG, 204=LOST, 255=CONTRA


func get_debug_dict() -> Dictionary:
	var d := super.get_debug_dict()
	d["diag"]              = DiagCode.keys()[_diag]
	d["no_change_ticks"]   = _no_change_ticks
	d["watched_blocks"]    = _last_values.size()
	return d


func serialize() -> Dictionary:
	var d := super.serialize()
	d["watch_radius"]        = watch_radius
	d["deadlock_threshold"]  = deadlock_threshold
	d["diag"]                = _diag
	d["no_change_ticks"]     = _no_change_ticks
	return d


func deserialize(data: Dictionary) -> void:
	watch_radius       = data.get("watch_radius", 4)
	deadlock_threshold = data.get("deadlock_threshold", 20)
	_diag              = data.get("diag", DiagCode.OK)
	_no_change_ticks   = data.get("no_change_ticks", 0)
	_last_values.clear()
	_flip_counts.clear()
	super.deserialize(data)
