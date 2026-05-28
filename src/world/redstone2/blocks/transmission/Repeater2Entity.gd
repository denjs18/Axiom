## Repeater2Entity.gd — Repeater 2.0 (Répéteur 2.0). ID 4002.
## Directional: input from back face, output to front face (facing direction).
## Supports 7 modes and configurable latency (0/1/2/4/8/16 ticks).
class_name Repeater2Entity
extends R2BlockEntity

enum Mode {
	BUFFER        = 0,   # pass-through, normalize signal strength to 255
	DELAY         = 1,   # N-tick delay pipeline
	PULSE_STRETCH = 2,   # extend pulses to minimum length
	PULSE_SHORTEN = 3,   # cap output pulse length
	LOCK          = 4,   # side-input locks output frozen
	ONE_SHOT      = 5,   # emit one pulse when input goes high, then wait for reset
	HEARTBEAT     = 6,   # re-emit periodically while signal is high
}

const VALID_DELAYS := [0, 1, 2, 4, 8, 16]

var mode:         int  = Mode.BUFFER
var delay_ticks:  int  = 1
var pulse_length: int  = 2      # ticks, for STRETCH / SHORTEN modes

# Internal state
var _delay_buffer: Array  = []   # ring buffer for DELAY mode
var _locked_out:   R2Signal = null
var _shot_fired:   bool     = false
var _counter:      int      = 0


func _init(pos: Vector3i) -> void:
	super(pos, "r2_repeater")


func _get_input_faces() -> Array:
	return [-facing]   # back face


func _get_output_faces() -> Array:
	return [facing]


func phase_calculate() -> void:
	var sig := get_face_input(-facing)

	match mode:
		Mode.BUFFER:
			# Normalize: preserve type, set analog to 255 if active
			if sig.to_bool():
				emit_analog(255)
			else:
				emit_bool(false)

		Mode.DELAY:
			_delay_buffer.append(sig.duplicate_signal())
			if _delay_buffer.size() > delay_ticks:
				emit_output(_delay_buffer.pop_front() as R2Signal)
			else:
				emit_bool(false)

		Mode.PULSE_STRETCH:
			if sig.to_bool():
				_counter = pulse_length
			if _counter > 0:
				_counter -= 1
				emit_bool(true)
			else:
				emit_bool(false)

		Mode.PULSE_SHORTEN:
			if sig.to_bool():
				if _counter < pulse_length:
					_counter += 1
					emit_bool(true)
				else:
					emit_bool(false)
			else:
				_counter = 0
				emit_bool(false)

		Mode.LOCK:
			var locked := false
			for face in ALL_FACES:
				if face == facing or face == -facing:
					continue
				var nb: R2BlockEntity = R2Engine.get_block(world_pos + face)
				if nb != null and nb.get_output(0).to_bool():
					locked = true
					break
			if not locked:
				_locked_out = sig.duplicate_signal()
			if _locked_out != null:
				emit_output(_locked_out)
			else:
				emit_bool(false)

		Mode.ONE_SHOT:
			if sig.to_bool() and not _shot_fired:
				_shot_fired = true
				emit_bool(true)
			else:
				if not sig.to_bool():
					_shot_fired = false
				emit_bool(false)

		Mode.HEARTBEAT:
			if sig.to_bool():
				_counter += 1
				if _counter >= delay_ticks:
					_counter = 0
					emit_bool(true)
				else:
					emit_bool(false)
			else:
				_counter = 0
				emit_bool(false)


func serialize() -> Dictionary:
	var d := super.serialize()
	d["mode"]         = mode
	d["delay_ticks"]  = delay_ticks
	d["pulse_length"] = pulse_length
	d["shot_fired"]   = _shot_fired
	d["counter"]      = _counter
	return d


func deserialize(data: Dictionary) -> void:
	mode         = data.get("mode", Mode.BUFFER)
	delay_ticks  = data.get("delay_ticks", 1)
	pulse_length = data.get("pulse_length", 2)
	_shot_fired  = data.get("shot_fired", false)
	_counter     = data.get("counter", 0)
	super.deserialize(data)
