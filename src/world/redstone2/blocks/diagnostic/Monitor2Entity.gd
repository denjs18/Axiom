## Monitor2Entity.gd — Signal monitor (Moniteur). ID 4071.
## Displays current value, short history (bar/gauge/text), and emits nothing.
## History is used by the overlay and in-game UI.
class_name Monitor2Entity
extends R2BlockEntity

const HISTORY_SIZE := 32

enum DisplayMode { VALUE = 0, BAR = 1, TEXT = 2, GAUGE = 3 }

var display_mode: int    = DisplayMode.BAR
var label:        String = ""
var watch_ch:     int    = 0

var history:      Array[int] = []   # ring buffer of last HISTORY_SIZE analog values
var _history_idx: int = 0


func _init(pos: Vector3i) -> void:
	super(pos, "r2_monitor")
	history.resize(HISTORY_SIZE)
	history.fill(0)


func _get_input_faces() -> Array:
	return ALL_FACES


func _get_output_faces() -> Array:
	return []   # monitor only, no output


func phase_calculate() -> void:
	var sig := get_input(watch_ch)
	var val := sig.to_analog() if sig != null else 0
	history[_history_idx] = val
	_history_idx = (_history_idx + 1) % HISTORY_SIZE


func get_current_value() -> int:
	return history[(_history_idx - 1 + HISTORY_SIZE) % HISTORY_SIZE]


func get_history_ordered() -> Array[int]:
	var out: Array[int] = []
	for i in HISTORY_SIZE:
		out.append(history[(_history_idx + i) % HISTORY_SIZE])
	return out


func get_debug_dict() -> Dictionary:
	var d := super.get_debug_dict()
	d["current_value"] = get_current_value()
	d["label"]         = label
	d["display_mode"]  = display_mode
	return d


func serialize() -> Dictionary:
	var d := super.serialize()
	d["display_mode"] = display_mode
	d["label"]        = label
	d["watch_ch"]     = watch_ch
	d["history"]      = Array(history)
	d["history_idx"]  = _history_idx
	return d


func deserialize(data: Dictionary) -> void:
	display_mode = data.get("display_mode", DisplayMode.BAR)
	label        = data.get("label", "")
	watch_ch     = data.get("watch_ch", 0)
	var h := data.get("history", []) as Array
	history.resize(HISTORY_SIZE)
	history.fill(0)
	for i in mini(h.size(), HISTORY_SIZE):
		history[i] = int(h[i])
	_history_idx = data.get("history_idx", 0)
	super.deserialize(data)
