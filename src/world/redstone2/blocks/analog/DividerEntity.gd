## DividerEntity.gd — Analog divider (Diviseur). ID 4025.
## Computes A / B with configurable divide-by-zero handling.
class_name DividerEntity
extends R2BlockEntity

enum DivByZero { OUTPUT_ZERO = 0, OUTPUT_MAX = 1, OUTPUT_ERROR = 2, HOLD_LAST = 3 }

var div_by_zero: int = DivByZero.OUTPUT_ZERO
var _last_out:   int = 0


func _init(pos: Vector3i) -> void:
	super(pos, "r2_divider")


func _get_input_faces() -> Array:
	return [FACE_NX, FACE_NZ]   # A = back, B = side


func _get_output_faces() -> Array:
	return [facing]


func phase_calculate() -> void:
	var a := get_face_input(FACE_NX).to_analog()
	var b := get_face_input(FACE_NZ).to_analog()
	var result: int
	if b == 0:
		match div_by_zero:
			DivByZero.OUTPUT_ZERO:  result = 0
			DivByZero.OUTPUT_MAX:   result = 255
			DivByZero.HOLD_LAST:    result = _last_out
			DivByZero.OUTPUT_ERROR:
				error = "DIV/0"
				result = 0
	else:
		error = ""
		result = clampi((a * 255) / b, 0, 255)   # scale so full 0-255 range is usable
	_last_out = result
	emit_analog(result)


func serialize() -> Dictionary:
	var d := super.serialize()
	d["div_by_zero"] = div_by_zero
	d["last_out"]    = _last_out
	return d


func deserialize(data: Dictionary) -> void:
	div_by_zero = data.get("div_by_zero", DivByZero.OUTPUT_ZERO)
	_last_out   = data.get("last_out", 0)
	super.deserialize(data)
