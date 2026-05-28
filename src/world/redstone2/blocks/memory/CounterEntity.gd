## CounterEntity.gd — Up/down counter (Compteur). ID 4044.
## Counts pulses on increment/decrement inputs. Configurable min/max/loop/overflow port.
class_name CounterEntity
extends R2BlockEntity

var min_val:    int  = 0
var max_val:    int  = 255
var loop:       bool = true    # wrap on overflow
var _count:     int  = 0
var _prev_inc:  bool = false
var _prev_dec:  bool = false


func _init(pos: Vector3i) -> void:
	super(pos, "r2_counter")


func _get_input_faces() -> Array:
	# Increment = back (NX), Decrement = top (PY), Reset = bottom (NY)
	return [FACE_NX, FACE_PY, FACE_NY]


func _get_output_faces() -> Array:
	# Count value = front, Overflow/underflow = side
	return [facing, FACE_PZ]


func phase_calculate() -> void:
	var inc := get_face_input(FACE_NX).to_bool()
	var dec := get_face_input(FACE_PY).to_bool()
	var rst := get_face_input(FACE_NY).to_bool()

	if rst:
		_count = min_val
		_prev_inc = inc
		_prev_dec = dec
		return

	var overflow := false
	if inc and not _prev_inc:
		_count += 1
		if _count > max_val:
			overflow = true
			_count = min_val if loop else max_val

	if dec and not _prev_dec:
		_count -= 1
		if _count < min_val:
			overflow = true
			_count = max_val if loop else min_val

	_prev_inc = inc
	_prev_dec = dec

	# Overflow signal on channel 1
	if overflow:
		_next_outputs[1] = R2Signal.make_event(1, world_pos)
	else:
		_next_outputs[1] = R2Signal.make_bool(false, 1, world_pos)


func phase_emit() -> void:
	var range_size := maxi(max_val - min_val, 1)
	var out := int(float(_count - min_val) / float(range_size) * 255.0)
	emit_analog(clampi(out, 0, 255))
	super.phase_emit()


func serialize() -> Dictionary:
	var d := super.serialize()
	d["min_val"]  = min_val
	d["max_val"]  = max_val
	d["loop"]     = loop
	d["count"]    = _count
	d["prev_inc"] = _prev_inc
	d["prev_dec"] = _prev_dec
	return d


func deserialize(data: Dictionary) -> void:
	min_val  = data.get("min_val", 0)
	max_val  = data.get("max_val", 255)
	loop     = data.get("loop", true)
	_count   = data.get("count", 0)
	_prev_inc = data.get("prev_inc", false)
	_prev_dec = data.get("prev_dec", false)
	super.deserialize(data)
