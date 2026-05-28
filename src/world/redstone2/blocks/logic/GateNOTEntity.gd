## GateNOTEntity.gd — Inverter / NOT gate. ID 4010.
## 1 input (back face), 1 output (facing direction).
## Latency modes: 0 = combinatorial (instant), 1 = 1-tick delay.
class_name GateNOTEntity
extends R2BlockEntity

var latency: int = 1   # 0 or 1
var _prev:   bool = false


func _init(pos: Vector3i) -> void:
	super(pos, "r2_gate_not")


func _get_input_faces() -> Array:
	return [-facing]


func _get_output_faces() -> Array:
	return [facing]


func phase_calculate() -> void:
	var v := get_face_input(-facing).to_bool()
	if latency == 0:
		emit_bool(not v)
	else:
		emit_bool(not _prev)
		_prev = v


func serialize() -> Dictionary:
	var d := super.serialize()
	d["latency"] = latency
	d["prev"]    = _prev
	return d


func deserialize(data: Dictionary) -> void:
	latency = data.get("latency", 1)
	_prev   = data.get("prev", false)
	super.deserialize(data)
