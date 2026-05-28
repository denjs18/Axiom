## MultiplierEntity.gd — Analog multiplier (Multiplicateur). ID 4024.
## Computes (A × B) / scale, where scale prevents output overflow.
class_name MultiplierEntity
extends R2BlockEntity

var scale: int = 255   # divisor after multiplication; default keeps result in 0-255 range


func _init(pos: Vector3i) -> void:
	super(pos, "r2_multiplier")


func _get_input_faces() -> Array:
	return [FACE_NX, FACE_NZ]


func _get_output_faces() -> Array:
	return [facing]


func phase_calculate() -> void:
	var a    := get_face_input(FACE_NX).to_analog()
	var b    := get_face_input(FACE_NZ).to_analog()
	var denom := maxi(scale, 1)
	var result := clampi((a * b) / denom, 0, 255)
	emit_analog(result)


func serialize() -> Dictionary:
	var d := super.serialize()
	d["scale"] = scale
	return d


func deserialize(data: Dictionary) -> void:
	scale = data.get("scale", 255)
	super.deserialize(data)
