## GateNOREntity.gd — NOR gate. ID 4015. Output = NOT(OR of all inputs).
class_name GateNOREntity
extends R2BlockEntity

var input_count: int = 2


func _init(pos: Vector3i) -> void:
	super(pos, "r2_gate_nor")


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
	var any_true := false
	for face in _get_input_faces():
		var nb: R2BlockEntity = R2Engine.get_block(world_pos + face)
		if nb != null and nb.get_output(0).to_bool():
			any_true = true
			break
	emit_bool(not any_true)


func serialize() -> Dictionary:
	var d := super.serialize()
	d["input_count"] = input_count
	return d


func deserialize(data: Dictionary) -> void:
	input_count = data.get("input_count", 2)
	super.deserialize(data)
