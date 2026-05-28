## RegisterEntity.gd — Analog register / latch (Registre). ID 4043.
## Stores an analog value on a clock pulse. Configurable bit width (8/16/32).
class_name RegisterEntity
extends R2BlockEntity

enum BitWidth { BITS_8 = 8, BITS_16 = 16, BITS_32 = 32 }

var bit_width:  int  = BitWidth.BITS_8   # max storable value = (2^n)-1
var latch_mode: bool = false             # latch: hold last valid when clock low
var _stored:    int  = 0
var _prev_clk:  bool = false


func _init(pos: Vector3i) -> void:
	super(pos, "r2_register")


func _get_input_faces() -> Array:
	# Data = back (NX), Clock = top (PY), Reset = bottom (NY)
	return [FACE_NX, FACE_PY, FACE_NY]


func _get_output_faces() -> Array:
	return [facing]


func phase_calculate() -> void:
	var data_sig := get_face_input(FACE_NX)
	var clk      := get_face_input(FACE_PY).to_bool()
	var rst      := get_face_input(FACE_NY).to_bool()

	if rst:
		_stored = 0
		_prev_clk = clk
		return

	if clk and not _prev_clk:   # rising edge: latch data
		var raw := data_sig.to_analog()
		var mask := (1 << bit_width) - 1
		# Map 0-255 to 0-(2^n - 1) then back to 0-255 for output
		_stored = raw & mask

	_prev_clk = clk


func phase_emit() -> void:
	var mask := (1 << bit_width) - 1
	# Output: stored value scaled back to 0-255
	var out := int(float(_stored & mask) / float(mask) * 255.0)
	emit_analog(clampi(out, 0, 255))


func serialize() -> Dictionary:
	var d := super.serialize()
	d["bit_width"]  = bit_width
	d["latch_mode"] = latch_mode
	d["stored"]     = _stored
	d["prev_clk"]   = _prev_clk
	return d


func deserialize(data: Dictionary) -> void:
	bit_width  = data.get("bit_width", BitWidth.BITS_8)
	latch_mode = data.get("latch_mode", false)
	_stored    = data.get("stored", 0)
	_prev_clk  = data.get("prev_clk", false)
	super.deserialize(data)
