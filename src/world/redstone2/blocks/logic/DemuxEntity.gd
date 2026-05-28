## DemuxEntity.gd — Boolean demultiplexer (Démultiplexeur booléen). ID 4019.
## Routes a single data input to one of up to 4 outputs based on a select signal.
## Output channel = selected index. Other channels emit false.
class_name DemuxEntity
extends R2BlockEntity

const DATA_IN_FACE := Vector3i(-1, 0, 0)   # West = data input
const SEL_FACE     := Vector3i(0, 0, 1)    # South = select (0–3 via analog)

# Output faces: channels 0-3
const OUT_FACES: Array[Vector3i] = [
	Vector3i(1, 0, 0),    # East  = output 0
	Vector3i(0, 1, 0),    # Up    = output 1
	Vector3i(0, -1, 0),   # Down  = output 2
	Vector3i(0, 0, -1),   # North = output 3
]


func _init(pos: Vector3i) -> void:
	super(pos, "r2_demux")


func _get_input_faces() -> Array:
	return [FACE_NX, FACE_PZ]


func _get_output_faces() -> Array:
	return [FACE_PX, FACE_PY, FACE_NY, FACE_NZ]


func phase_calculate() -> void:
	var data_in := get_face_input(DATA_IN_FACE).to_bool()
	var sel     := get_face_input(SEL_FACE).to_analog()
	var idx     := clampi(int(float(sel) / 64.0), 0, 3)
	for i in OUT_FACES.size():
		emit_bool(data_in and i == idx, i)


func _get_output_toward(target_pos: Vector3i) -> R2Signal:
	var dir := target_pos - world_pos
	var idx := OUT_FACES.find(dir)
	if idx >= 0:
		return get_output(idx)
	return null
