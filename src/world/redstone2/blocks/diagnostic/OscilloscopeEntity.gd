## OscilloscopeEntity.gd — Oscilloscope (Oscilloscope). ID 4072.
## Records signal waveform over time. Useful for timing analysis of clocks and pulses.
class_name OscilloscopeEntity
extends R2BlockEntity

const BUFFER_SIZE := 64

var watch_ch:      int   = 0
var trigger_level: int   = 128   # value above which trigger fires
var trigger_mode:  bool  = false  # false=free-run, true=triggered

var waveform:      Array[int] = []
var _buf_idx:      int = 0
var _triggered:    bool = false
var _trigger_tick: int  = -1


func _init(pos: Vector3i) -> void:
	super(pos, "r2_oscilloscope")
	waveform.resize(BUFFER_SIZE)
	waveform.fill(0)


func _get_input_faces() -> Array:
	return ALL_FACES


func _get_output_faces() -> Array:
	return []


func phase_calculate() -> void:
	var sig := get_input(watch_ch)
	var val := sig.to_analog() if sig != null else 0

	if trigger_mode:
		if not _triggered and val >= trigger_level:
			_triggered    = true
			_trigger_tick = current_tick
			_buf_idx      = 0
		if _triggered:
			waveform[_buf_idx] = val
			_buf_idx += 1
			if _buf_idx >= BUFFER_SIZE:
				_triggered = false
				_buf_idx   = 0
	else:
		waveform[_buf_idx] = val
		_buf_idx = (_buf_idx + 1) % BUFFER_SIZE


func get_waveform_ordered() -> Array[int]:
	var out: Array[int] = []
	for i in BUFFER_SIZE:
		out.append(waveform[(_buf_idx + i) % BUFFER_SIZE])
	return out


func get_debug_dict() -> Dictionary:
	var d := super.get_debug_dict()
	d["trigger_level"] = trigger_level
	d["triggered"]     = _triggered
	d["trigger_tick"]  = _trigger_tick
	return d


func serialize() -> Dictionary:
	var d := super.serialize()
	d["watch_ch"]      = watch_ch
	d["trigger_level"] = trigger_level
	d["trigger_mode"]  = trigger_mode
	d["waveform"]      = Array(waveform)
	d["buf_idx"]       = _buf_idx
	return d


func deserialize(data: Dictionary) -> void:
	watch_ch      = data.get("watch_ch", 0)
	trigger_level = data.get("trigger_level", 128)
	trigger_mode  = data.get("trigger_mode", false)
	var w := data.get("waveform", []) as Array
	waveform.resize(BUFFER_SIZE)
	waveform.fill(0)
	for i in mini(w.size(), BUFFER_SIZE):
		waveform[i] = int(w[i])
	_buf_idx = data.get("buf_idx", 0)
	super.deserialize(data)
