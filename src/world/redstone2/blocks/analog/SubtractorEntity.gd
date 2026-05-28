## SubtractorEntity.gd — Analog subtractor (Soustracteur). ID 4023.
## Computes A - B, with configurable underflow behavior.
class_name SubtractorEntity
extends R2BlockEntity

enum Underflow { CLAMP_ZERO = 0, SIGNED_INTERNAL = 1 }

var underflow: int = Underflow.CLAMP_ZERO


func _init(pos: Vector3i) -> void:
	super(pos, "r2_subtractor")


func _get_input_faces() -> Array:
	return [FACE_NX, FACE_NZ]   # A = back, B = side


func _get_output_faces() -> Array:
	return [facing]


func phase_calculate() -> void:
	var a := get_face_input(FACE_NX).to_analog()
	var b := get_face_input(FACE_NZ).to_analog()
	var result := a - b
	match underflow:
		Underflow.CLAMP_ZERO:     result = maxi(result, 0)
		Underflow.SIGNED_INTERNAL: result = clampi(result + 128, 0, 255)  # shifted signed
	emit_analog(result)


func serialize() -> Dictionary:
	var d := super.serialize()
	d["underflow"] = underflow
	return d


func deserialize(data: Dictionary) -> void:
	underflow = data.get("underflow", Underflow.CLAMP_ZERO)
	super.deserialize(data)
