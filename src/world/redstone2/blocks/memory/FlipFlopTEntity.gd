## FlipFlopTEntity.gd — T flip-flop / toggle (Bascule T). ID 4040.
## Each rising-edge pulse on input toggles the stored state. Optional reset input.
class_name FlipFlopTEntity
extends R2BlockEntity

var _state:      bool = false
var _prev_input: bool = false


func _init(pos: Vector3i) -> void:
	super(pos, "r2_ff_t")


func _get_input_faces() -> Array:
	# Clock input: back face. Reset input: bottom face.
	return [FACE_NX, FACE_NY]


func _get_output_faces() -> Array:
	return [facing, FACE_PY]   # Q on front, not-Q on top


func phase_calculate() -> void:
	var clk  := get_face_input(FACE_NX).to_bool()
	var rst  := get_face_input(FACE_NY).to_bool()

	if rst:
		_state = false
	elif clk and not _prev_input:   # rising edge
		_state = not _state

	_prev_input = clk


func phase_memory() -> void:
	pass   # state already updated in calculate


func phase_emit() -> void:
	emit_bool(_state)
	_next_outputs[1] = R2Signal.make_bool(not _state, 1, world_pos)
	super.phase_emit()


func serialize() -> Dictionary:
	var d := super.serialize()
	d["state"]      = _state
	d["prev_input"] = _prev_input
	return d


func deserialize(data: Dictionary) -> void:
	_state      = data.get("state", false)
	_prev_input = data.get("prev_input", false)
	super.deserialize(data)
