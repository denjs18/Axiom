## LogicLampEntity.gd — Logic lamp (Lampe logique). ID 4064.
## Variable intensity, optional color channel. Returns current intensity as feedback.
class_name LogicLampEntity
extends R2BlockEntity

var color_channel: int = 0   # 0 = white/default; 1-15 for tinted variants
var min_intensity: int = 0   # minimum light level when input is 0 (always-on dim)

var _intensity: int = 0


func _init(pos: Vector3i) -> void:
	super(pos, "r2_logic_lamp")


func _get_input_faces() -> Array:
	# Intensity = back (NX, analog), Color override = top (PY, analog channel index)
	return [FACE_NX, FACE_PY]


func _get_output_faces() -> Array:
	# Feedback = front (analog intensity)
	return [facing]


func phase_calculate() -> void:
	var inp := get_face_input(FACE_NX).to_analog()
	var col := get_face_input(FACE_PY).to_analog()

	_intensity = maxi(min_intensity, inp)

	if col > 0:
		color_channel = clampi(int(float(col) / 256.0 * 15.0), 0, 15)


func phase_act() -> void:
	# Update block metadata for renderer (light level)
	var cm := R2Engine.get_chunk_manager()
	if cm == null: return
	var chunk = cm.get_chunk(Vector3i(world_pos.x >> 4, world_pos.y >> 4, world_pos.z >> 4))
	if chunk == null: return
	if chunk.has_method("set_block_light"):
		var light_level := int(float(_intensity) / 255.0 * 15.0)
		chunk.set_block_light(world_pos.x & 15, world_pos.y & 15, world_pos.z & 15, light_level)


func phase_emit() -> void:
	emit_analog(_intensity)


func serialize() -> Dictionary:
	var d := super.serialize()
	d["color_channel"] = color_channel
	d["min_intensity"] = min_intensity
	d["intensity"]     = _intensity
	return d


func deserialize(data: Dictionary) -> void:
	color_channel = data.get("color_channel", 0)
	min_intensity = data.get("min_intensity", 0)
	_intensity    = data.get("intensity", 0)
	super.deserialize(data)
