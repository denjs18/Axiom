## LegacyConverterEntity.gd — Legacy redstone ↔ Redstone 2.0 bridge. ID 4004.
## Legacy face (default: west): reads old redstone power 0–15 from world metadata.
## R2 face (default: east): connects to the R2 network with full 0–255 range.
## Conversions: 0–15 ↔ 0–255 (linear), pulse legacy → event, comparator output → analog.
class_name LegacyConverterEntity
extends R2BlockEntity

var legacy_face: Vector3i = FACE_NX   # west
var r2_face:     Vector3i = FACE_PX   # east

var _legacy_power: int = 0   # cached legacy power level


func _init(pos: Vector3i) -> void:
	super(pos, "r2_legacy_conv")


func _get_input_faces() -> Array:
	return [r2_face]


func _get_output_faces() -> Array:
	return [r2_face, legacy_face]


func phase_acquire(tick: int) -> void:
	current_tick = tick
	_inputs.clear()
	_face_inputs.clear()

	# R2 side input
	var nb_r2: R2BlockEntity = R2Engine.get_block(world_pos + r2_face)
	if nb_r2 != null:
		var sig := nb_r2._get_output_toward(world_pos)
		if sig != null:
			_inputs[0] = [sig]
			_face_inputs[r2_face] = sig

	# Legacy side: read redstone power from block metadata
	var legacy_id := R2Engine.get_block_id(world_pos + legacy_face)
	var legacy_def := BlockRegistry.get_block(legacy_id)
	_legacy_power = 0
	if legacy_def != null:
		_legacy_power = legacy_def.redstone_power


func phase_calculate() -> void:
	if _legacy_power > 0:
		# Legacy → R2: scale 0–15 to 0–255
		var analog := int(float(_legacy_power) / 15.0 * 255.0)
		var sig := R2Signal.make_analog(analog, 0, world_pos + legacy_face)
		sig.is_conversion = true
		emit_output(sig, 0)   # R2 output
		emit_analog(0, 1)     # No legacy output needed (legacy drives us)
	else:
		# R2 → Legacy: scale 0–255 to 0–15
		var r2_in := get_input(0)
		emit_output(r2_in, 0)
		var legacy_val := int(float(r2_in.to_analog()) / 255.0 * 15.0)
		var legacy_sig := R2Signal.make_analog(legacy_val, 1, world_pos)
		legacy_sig.is_conversion = true
		emit_output(legacy_sig, 1)   # legacy output


func _get_output_toward(target_pos: Vector3i) -> R2Signal:
	var dir := target_pos - world_pos
	if dir == r2_face:
		return get_output(0)
	if dir == legacy_face:
		return get_output(1)
	return null


func serialize() -> Dictionary:
	var d := super.serialize()
	d["legacy_face"] = [legacy_face.x, legacy_face.y, legacy_face.z]
	d["r2_face"]     = [r2_face.x, r2_face.y, r2_face.z]
	return d


func deserialize(data: Dictionary) -> void:
	var lf: Array = data.get("legacy_face", [-1, 0, 0])
	var rf: Array = data.get("r2_face", [1, 0, 0])
	if lf.size() == 3: legacy_face = Vector3i(int(lf[0]), int(lf[1]), int(lf[2]))
	if rf.size() == 3: r2_face     = Vector3i(int(rf[0]), int(rf[1]), int(rf[2]))
	super.deserialize(data)
