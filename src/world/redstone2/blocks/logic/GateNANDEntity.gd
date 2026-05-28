## GateNANDEntity.gd — NAND gate. ID 4014. Output = NOT(AND of all inputs).
class_name GateNANDEntity
extends R2BlockEntity

var input_count: int = 2


func _init(pos: Vector3i) -> void:
	super(pos, "r2_gate_nand")


func _get_input_faces() -> Array:
	match input_count:
		2: return [FACE_NX, FACE_NZ]
		3: return [FACE_NX, FACE_NZ, FACE_NY]
		4: return [FACE_NX, FACE_NZ, FACE_NY, FACE_PY]
		_: return [FACE_NX, FACE_NZ]
	return [FACE_NX, FACE_NZ]


func _get_output_faces() -> Array:
	return [facing]


func phase_calculate() -> void:
	var all_true := true
	for face in _get_input_faces():
		var nb: R2BlockEntity = R2Engine.get_block(world_pos + face)
		if nb == null or not nb.get_output(0).to_bool():
			all_true = false
			break
	emit_bool(not all_true)


func serialize() -> Dictionary:
	var d := super.serialize()
	d["input_count"] = input_count
	return d


func deserialize(data: Dictionary) -> void:
	input_count = data.get("input_count", 2)
	super.deserialize(data)
