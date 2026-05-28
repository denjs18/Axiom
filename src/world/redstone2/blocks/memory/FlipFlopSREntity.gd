## FlipFlopSREntity.gd — SR flip-flop (Bascule SR). ID 4041.
## Set input forces Q=true, Reset input forces Q=false.
## Configurable priority when both are active simultaneously.
class_name FlipFlopSREntity
extends R2BlockEntity

enum Priority { SET = 0, RESET = 1, HOLD = 2 }

var priority: int = Priority.SET
var _state:   bool = false


func _init(pos: Vector3i) -> void:
	super(pos, "r2_ff_sr")


func _get_input_faces() -> Array:
	# Set = back (NX), Reset = top (PY)
	return [FACE_NX, FACE_PY]


func _get_output_faces() -> Array:
	return [facing, FACE_NY]   # Q on front, not-Q on bottom


func phase_calculate() -> void:
	var s := get_face_input(FACE_NX).to_bool()
	var r := get_face_input(FACE_PY).to_bool()

	if s and r:
		match priority:
			Priority.SET:   _state = true
			Priority.RESET: _state = false
			Priority.HOLD:  pass   # keep current
	elif s:
		_state = true
	elif r:
		_state = false


func phase_emit() -> void:
	emit_bool(_state)
	_next_outputs[1] = R2Signal.make_bool(not _state, 1, world_pos)
	super.phase_emit()


func serialize() -> Dictionary:
	var d := super.serialize()
	d["priority"] = priority
	d["state"]    = _state
	return d


func deserialize(data: Dictionary) -> void:
	priority = data.get("priority", Priority.SET)
	_state   = data.get("state", false)
	super.deserialize(data)
