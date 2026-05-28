## QuantifierEntity.gd — Analog quantifier (Quantificateur). ID 4027.
## Converts a continuous analog value into N discrete steps (bins).
## Output is the bin index scaled back to 0-255, useful for stage selectors.
class_name QuantifierEntity
extends R2BlockEntity

var num_steps: int = 8   # number of discrete output levels (2–256)


func _init(pos: Vector3i) -> void:
	super(pos, "r2_quantifier")


func _get_input_faces() -> Array:
	return [FACE_NX]


func _get_output_faces() -> Array:
	return [facing]


func phase_calculate() -> void:
	var v    := get_face_input(FACE_NX).to_analog()
	var n    := maxi(num_steps, 2)
	var bin  := int(float(v) / 256.0 * float(n))
	bin = clampi(bin, 0, n - 1)
	var out := int(float(bin) / float(n - 1) * 255.0)
	emit_analog(clampi(out, 0, 255))


func serialize() -> Dictionary:
	var d := super.serialize()
	d["num_steps"] = num_steps
	return d


func deserialize(data: Dictionary) -> void:
	num_steps = data.get("num_steps", 8)
	super.deserialize(data)
