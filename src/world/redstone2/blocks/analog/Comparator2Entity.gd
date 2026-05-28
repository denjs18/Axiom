## Comparator2Entity.gd — Comparator 2.0 (Comparateur 2.0). ID 4020.
## Extends the vanilla comparator with 9 modes and a secondary output port.
class_name Comparator2Entity
extends R2BlockEntity

enum Mode {
	TRANSMIT   = 0,   # output = main input
	COMPARE    = 1,   # output = 255 if main > side, else 0
	SUBTRACT   = 2,   # output = max(main - side, 0)
	MIN        = 3,   # output = min(main, side)
	MAX        = 4,   # output = max(main, side)
	CLAMP      = 5,   # output = clamp(main, side_a, side_b)
	DEADBAND   = 6,   # output = 0 if |main-side| < threshold else main
	THRESHOLD  = 7,   # output = 255 if main >= side, else 0
	HYSTERESIS = 8,   # output latches high/low with configurable band
}

var mode:      int  = Mode.TRANSMIT
var threshold: int  = 128   # used in CLAMP, DEADBAND, THRESHOLD, HYSTERESIS
var hyst_band: int  = 16    # hysteresis band size
var _latched:  bool = false  # for HYSTERESIS


func _init(pos: Vector3i) -> void:
	super(pos, "r2_comparator2")


func _get_input_faces() -> Array:
	return [FACE_NX, FACE_NZ, FACE_PZ]   # back, left side, right side


func _get_output_faces() -> Array:
	return [facing, FACE_PY]   # main output forward, state output up


func phase_calculate() -> void:
	var main_in := get_face_input(FACE_NX).to_analog()
	var side_a  := get_face_input(FACE_NZ).to_analog()
	var side_b  := get_face_input(FACE_PZ).to_analog()

	var out: int = 0
	var state_out: bool = false

	match mode:
		Mode.TRANSMIT:
			out = main_in
		Mode.COMPARE:
			out = 255 if main_in > side_a else 0
			state_out = main_in > side_a
		Mode.SUBTRACT:
			out = maxi(main_in - side_a, 0)
		Mode.MIN:
			out = mini(main_in, side_a)
		Mode.MAX:
			out = maxi(main_in, side_a)
		Mode.CLAMP:
			out = clampi(main_in, side_a, maxi(side_a, side_b))
		Mode.DEADBAND:
			out = 0 if absi(main_in - side_a) < threshold else main_in
		Mode.THRESHOLD:
			out = 255 if main_in >= side_a else 0
			state_out = main_in >= side_a
		Mode.HYSTERESIS:
			if not _latched and main_in >= threshold + hyst_band:
				_latched = true
			elif _latched and main_in <= threshold - hyst_band:
				_latched = false
			out = 255 if _latched else 0
			state_out = _latched

	emit_analog(out, 0)
	emit_bool(state_out, 1)   # secondary state output on channel 1


func _get_output_toward(target_pos: Vector3i) -> R2Signal:
	var dir := target_pos - world_pos
	if dir == facing:
		return get_output(0)
	if dir == FACE_PY:
		return get_output(1)
	return null


func serialize() -> Dictionary:
	var d := super.serialize()
	d["mode"]      = mode
	d["threshold"] = threshold
	d["hyst_band"] = hyst_band
	d["latched"]   = _latched
	return d


func deserialize(data: Dictionary) -> void:
	mode      = data.get("mode", Mode.TRANSMIT)
	threshold = data.get("threshold", 128)
	hyst_band = data.get("hyst_band", 16)
	_latched  = data.get("latched", false)
	super.deserialize(data)
