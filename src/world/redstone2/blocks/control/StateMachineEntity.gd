## StateMachineEntity.gd — Finite state machine (Machine à états). ID 4052.
## Named states with conditional transitions. Entry/exit actions via output channels.
## States and transitions are stored as data for in-game editing.
class_name StateMachineEntity
extends R2BlockEntity

# states: Array of { "name": String, "entry_ch": int, "exit_ch": int, "output": int }
# transitions: Array of { "from": String, "to": String, "trigger_ch": int, "condition_op": String, "condition_val": int }
var states:      Array = [
	{"name": "idle", "entry_ch": -1, "exit_ch": -1, "output": 0},
	{"name": "active", "entry_ch": -1, "exit_ch": -1, "output": 255},
]
var transitions: Array = [
	{"from": "idle",   "to": "active", "trigger_ch": 0, "condition_op": "bool_true",  "condition_val": 1},
	{"from": "active", "to": "idle",   "trigger_ch": 0, "condition_op": "bool_false", "condition_val": 0},
]
var default_state:  String = "idle"
var security_state: String = ""   # state on error (empty = no change)

var _current: String = ""
var _entry_pulse: bool = false
var _exit_pulse:  bool = false
var _entry_ch: int = -1
var _exit_ch:  int = -1


func _init(pos: Vector3i) -> void:
	super(pos, "r2_state_machine")
	_current = default_state


func _get_input_faces() -> Array:
	return ALL_FACES


func _get_output_faces() -> Array:
	return ALL_FACES


func phase_calculate() -> void:
	if _current == "" and states.size() > 0:
		_current = (states[0] as Dictionary).get("name", "idle")

	_entry_pulse = false
	_exit_pulse  = false

	for tr in transitions:
		if not tr is Dictionary: continue
		if tr.get("from", "") != _current: continue

		var ch: int    = tr.get("trigger_ch", 0)
		var op: String = tr.get("condition_op", "bool_true")
		var thr: int   = tr.get("condition_val", 1)
		var sig        := get_input(ch)
		var val: int   = sig.to_analog() if sig != null else 0

		var passes := false
		match op:
			"bool_true":  passes = (val > 0)
			"bool_false": passes = (val == 0)
			"gt":         passes = (val > thr)
			"lt":         passes = (val < thr)
			"eq":         passes = (val == thr)
			"neq":        passes = (val != thr)
			"gte":        passes = (val >= thr)
			"lte":        passes = (val <= thr)

		if passes:
			var to_name: String = tr.get("to", "")
			if to_name != "" and to_name != _current:
				_exit_pulse = true
				_exit_ch    = _get_state_ch(_current, "exit_ch")
				_current    = to_name
				_entry_pulse = true
				_entry_ch   = _get_state_ch(_current, "entry_ch")
			break


func _get_state_ch(state_name: String, key: String) -> int:
	for s in states:
		if s is Dictionary and s.get("name", "") == state_name:
			return s.get(key, -1)
	return -1


func _get_state_output(state_name: String) -> int:
	for s in states:
		if s is Dictionary and s.get("name", "") == state_name:
			return s.get("output", 0)
	return 0


func phase_emit() -> void:
	# Channel 0: current state index (0-255 mapped)
	var idx := 0
	for i in states.size():
		if (states[i] as Dictionary).get("name", "") == _current:
			idx = i
			break
	var out := int(float(idx) / float(maxi(states.size() - 1, 1)) * 255.0)
	_next_outputs[0] = R2Signal.make_analog(clampi(out, 0, 255), 0, world_pos)

	# Channel 1: current state output value
	_next_outputs[1] = R2Signal.make_analog(_get_state_output(_current), 1, world_pos)

	# Entry/exit pulses on dedicated channels
	if _entry_pulse and _entry_ch >= 0:
		_next_outputs[_entry_ch] = R2Signal.make_event(_entry_ch, world_pos)
	if _exit_pulse and _exit_ch >= 0:
		_next_outputs[_exit_ch]  = R2Signal.make_event(_exit_ch, world_pos)

	super.phase_emit()


func serialize() -> Dictionary:
	var d := super.serialize()
	d["states"]        = states.duplicate(true)
	d["transitions"]   = transitions.duplicate(true)
	d["default_state"] = default_state
	d["security_state"] = security_state
	d["current"]       = _current
	return d


func deserialize(data: Dictionary) -> void:
	states         = data.get("states", [])
	transitions    = data.get("transitions", [])
	default_state  = data.get("default_state", "idle")
	security_state = data.get("security_state", "")
	_current       = data.get("current", default_state)
	super.deserialize(data)
