## AdderEntity.gd — Analog adder (Additionneur). ID 4022.
## Computes A + B, with configurable overflow behavior.
class_name AdderEntity
extends R2BlockEntity

enum Overflow { SATURATE = 0, WRAP = 1 }

var overflow: int = Overflow.SATURATE


func _init(pos: Vector3i) -> void:
	super(pos, "r2_adder")


func _get_input_faces() -> Array:
	return [FACE_NX, FACE_NZ]   # A = back, B = side


func _get_output_faces() -> Array:
	return [facing]


func phase_calculate() -> void:
	var a := get_face_input(FACE_NX).to_analog()
	var b := get_face_input(FACE_NZ).to_analog()
	var sum := a + b
	match overflow:
		Overflow.SATURATE: sum = mini(sum, 255)
		Overflow.WRAP:     sum = sum % 256
	emit_analog(sum)


func serialize() -> Dictionary:
	var d := super.serialize()
	d["overflow"] = overflow
	return d


func deserialize(data: Dictionary) -> void:
	overflow = data.get("overflow", Overflow.SATURATE)
	super.deserialize(data)
