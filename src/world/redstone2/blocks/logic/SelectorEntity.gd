## SelectorEntity.gd — Boolean selector (Sélecteur booléen). ID 4017.
## N data inputs + 1 select input. Routes the Nth input to output based on select value.
## Select input: analog 0-255 mapped to input index 0..(N-1).
class_name SelectorEntity
extends R2BlockEntity

const DATA_FACES: Array[Vector3i] = [
	Vector3i(-1, 0, 0),   # West  = input 0
	Vector3i(0, 1, 0),    # Up    = input 1
	Vector3i(0, -1, 0),   # Down  = input 2
	Vector3i(0, 0, -1),   # North = input 3
]
const SELECT_FACE := Vector3i(0, 0, 1)   # South = select input


func _init(pos: Vector3i) -> void:
	super(pos, "r2_selector")


func _get_input_faces() -> Array:
	return [FACE_NX, FACE_PY, FACE_NY, FACE_NZ, FACE_PZ]


func _get_output_faces() -> Array:
	return [facing]


func phase_calculate() -> void:
	var sel_sig := get_face_input(SELECT_FACE)
	var sel_idx := int(float(sel_sig.to_analog()) / 255.0 * float(DATA_FACES.size() - 1) + 0.5)
	sel_idx = clampi(sel_idx, 0, DATA_FACES.size() - 1)
	var nb: R2BlockEntity = R2Engine.get_block(world_pos + DATA_FACES[sel_idx])
	if nb != null:
		emit_output(nb.get_output(0))
	else:
		emit_bool(false)
