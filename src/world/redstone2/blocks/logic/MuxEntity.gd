## MuxEntity.gd — Boolean multiplexer (Multiplexeur booléen). ID 4018.
## Select input (south face) picks one of 4 data sources to route to output.
## Used for memory addressing, display routing, or conditional paths.
class_name MuxEntity
extends R2BlockEntity

# Data source faces (0–3)
const DATA_FACES: Array[Vector3i] = [
	Vector3i(-1, 0, 0),   # West  = source 0
	Vector3i(0, 1, 0),    # Up    = source 1
	Vector3i(0, -1, 0),   # Down  = source 2
	Vector3i(0, 0, -1),   # North = source 3
]
const SEL_FACE := Vector3i(0, 0, 1)   # South = 2-bit select (0-3 via analog)


func _init(pos: Vector3i) -> void:
	super(pos, "r2_mux")


func _get_input_faces() -> Array:
	return [FACE_NX, FACE_PY, FACE_NY, FACE_NZ, FACE_PZ]


func _get_output_faces() -> Array:
	return [facing]


func phase_calculate() -> void:
	var sel := get_face_input(SEL_FACE).to_analog()
	var idx := clampi(int(float(sel) / 64.0), 0, 3)   # 0-63→0, 64-127→1, 128-191→2, 192-255→3
	var nb: R2BlockEntity = R2Engine.get_block(world_pos + DATA_FACES[idx])
	if nb != null:
		emit_output(nb.get_output(0))
	else:
		emit_bool(false)
