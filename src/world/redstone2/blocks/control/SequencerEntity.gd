## SequencerEntity.gd — Step sequencer (Séquenceur). ID 4051.
## Cycles through ordered steps, each with a fixed duration or condition-based advance.
## Output = current step index (analog 0-255) + per-step channel pulse.
class_name SequencerEntity
extends R2BlockEntity

# Each step: { "duration": int (ticks), "condition_ch": int or -1, "label": String }
var steps: Array = [
	{"duration": 10, "condition_ch": -1, "label": "Step 0"},
	{"duration": 10, "condition_ch": -1, "label": "Step 1"},
]
var loop:       bool = true
var stop_on_error: bool = false

var _current_step:  int  = 0
var _step_ticks:    int  = 0
var _running:       bool = false
var _done:          bool = false
var _prev_start:    bool = false
var _prev_stop:     bool = false


func _init(pos: Vector3i) -> void:
	super(pos, "r2_sequencer")


func _get_input_faces() -> Array:
	# Start = back (NX), Stop/Reset = top (PY), Advance = bottom (NY)
	return [FACE_NX, FACE_PY, FACE_NY]


func _get_output_faces() -> Array:
	return [facing, FACE_PZ]   # step index = front, done/loop pulse = side


func phase_calculate() -> void:
	var start   := get_face_input(FACE_NX).to_bool()
	var stop    := get_face_input(FACE_PY).to_bool()
	var advance := get_face_input(FACE_NY).to_bool()

	if stop and not _prev_stop:
		_running = false
		_current_step = 0
		_step_ticks   = 0
		_done = false

	if start and not _prev_start:
		_running = true
		_current_step = 0
		_step_ticks   = 0
		_done = false

	_prev_start = start
	_prev_stop  = stop

	if not _running or steps.is_empty():
		return

	var step_data: Dictionary = steps[_current_step] if _current_step < steps.size() else {}
	var duration: int = step_data.get("duration", 10)
	var cond_ch: int  = step_data.get("condition_ch", -1)

	var should_advance := false
	if advance:
		should_advance = true
	elif cond_ch >= 0:
		# Advance when condition channel goes high
		var cond_sig := get_input(cond_ch)
		should_advance = cond_sig != null and cond_sig.to_bool()
	else:
		_step_ticks += 1
		if _step_ticks >= duration:
			should_advance = true

	if should_advance:
		_step_ticks   = 0
		_current_step += 1
		if _current_step >= steps.size():
			if loop:
				_current_step = 0
				_done = true   # pulse done on loop
			else:
				_current_step = steps.size() - 1
				_running = false
				_done = true


func phase_emit() -> void:
	var num := maxi(steps.size(), 1)
	var idx_analog := int(float(_current_step) / float(num) * 255.0)
	emit_analog(clampi(idx_analog, 0, 255))
	_next_outputs[1] = R2Signal.make_bool(_done, 1, world_pos)
	_done = false
	super.phase_emit()


func serialize() -> Dictionary:
	var d := super.serialize()
	d["steps"]         = steps.duplicate(true)
	d["loop"]          = loop
	d["current_step"]  = _current_step
	d["step_ticks"]    = _step_ticks
	d["running"]       = _running
	return d


func deserialize(data: Dictionary) -> void:
	steps         = data.get("steps", [{"duration": 10, "condition_ch": -1}])
	loop          = data.get("loop", true)
	_current_step = data.get("current_step", 0)
	_step_ticks   = data.get("step_ticks", 0)
	_running      = data.get("running", false)
	super.deserialize(data)
