## FlipFlopDEntity.gd — D flip-flop (Bascule D). ID 4042.
## Samples the Data input on the rising edge of Clock. Emits Q and not-Q.
class_name FlipFlopDEntity
extends R2BlockEntity

var _q:         bool = false
var _prev_clk:  bool = false


func _init(pos: Vector3i) -> void:
	super(pos, "r2_ff_d")


func _get_input_faces() -> Array:
	# Data = back (NX), Clock = top (PY)
	return [FACE_NX, FACE_PY]


func _get_output_faces() -> Array:
	return [facing, FACE_NY]   # Q on front, not-Q on bottom


func phase_calculate() -> void:
	var data := get_face_input(FACE_NX).to_bool()
	var clk  := get_face_input(FACE_PY).to_bool()

	if clk and not _prev_clk:   # rising edge
		_q = data

	_prev_clk = clk


func phase_emit() -> void:
	emit_bool(_q)
	_next_outputs[1] = R2Signal.make_bool(not _q, 1, world_pos)
	super.phase_emit()


func serialize() -> Dictionary:
	var d := super.serialize()
	d["q"]        = _q
	d["prev_clk"] = _prev_clk
	return d


func deserialize(data: Dictionary) -> void:
	_q        = data.get("q", false)
	_prev_clk = data.get("prev_clk", false)
	super.deserialize(data)
