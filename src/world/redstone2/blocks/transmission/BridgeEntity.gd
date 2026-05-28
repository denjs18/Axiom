## BridgeEntity.gd — Logic bridge (Pont logique). ID 4003.
## Crosses two signal paths without mixing them, using independent per-axis routing.
## Three variants: horizontal (X/Z crossing), vertical (Y/Z crossing), channel (ch0/ch1).
class_name BridgeEntity
extends R2BlockEntity

enum BridgeType { HORIZONTAL = 0, VERTICAL = 1, CHANNEL = 2 }

var bridge_type: int = BridgeType.HORIZONTAL


func _init(pos: Vector3i) -> void:
	super(pos, "r2_bridge")


func _axis_a() -> Array:
	match bridge_type:
		BridgeType.HORIZONTAL: return [FACE_NX, FACE_PX]
		BridgeType.VERTICAL:   return [FACE_NY, FACE_PY]
		_:                     return [FACE_NX, FACE_PX]
	return [FACE_NX, FACE_PX]


func _axis_b() -> Array:
	match bridge_type:
		BridgeType.HORIZONTAL: return [FACE_NZ, FACE_PZ]
		BridgeType.VERTICAL:   return [FACE_NZ, FACE_PZ]
		_:                     return [FACE_NZ, FACE_PZ]
	return [FACE_NZ, FACE_PZ]


func _get_input_faces() -> Array:
	return _axis_a() + _axis_b()


func _get_output_faces() -> Array:
	return _axis_a() + _axis_b()


func phase_acquire(tick: int) -> void:
	current_tick = tick
	_inputs.clear()
	_face_inputs.clear()
	for face in _axis_a():
		var nb: R2BlockEntity = R2Engine.get_block(world_pos + face)
		if nb != null:
			var s := nb._get_output_toward(world_pos)
			if s != null:
				_face_inputs[face] = s
				if not _inputs.has(0): _inputs[0] = []
				(_inputs[0] as Array).append(s)
	for face in _axis_b():
		var nb: R2BlockEntity = R2Engine.get_block(world_pos + face)
		if nb != null:
			var s := nb._get_output_toward(world_pos)
			if s != null:
				_face_inputs[face] = s
				if not _inputs.has(1): _inputs[1] = []
				(_inputs[1] as Array).append(s)


func phase_calculate() -> void:
	emit_output(get_input(0), 0)
	emit_output(get_input(1), 1)


func _get_output_toward(target_pos: Vector3i) -> R2Signal:
	var dir := target_pos - world_pos
	if dir in _axis_a():
		return get_output(0)
	if dir in _axis_b():
		return get_output(1)
	return null


func serialize() -> Dictionary:
	var d := super.serialize()
	d["bridge_type"] = bridge_type
	return d


func deserialize(data: Dictionary) -> void:
	bridge_type = data.get("bridge_type", BridgeType.HORIZONTAL)
	super.deserialize(data)
