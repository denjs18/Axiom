## TimerEntity.gd — Configurable timer (Minuterie). ID 4045.
## Modes: delay, interval, cooldown, watchdog, retriggerable.
class_name TimerEntity
extends R2BlockEntity

enum Mode {
	DELAY       = 0,   # emit once after N ticks from rising edge
	INTERVAL    = 1,   # repeat every N ticks while input is high
	COOLDOWN    = 2,   # emit true then block for N ticks
	WATCHDOG    = 3,   # emit alarm if no input pulse within N ticks
	RETRIGGER   = 4,   # restart countdown on each new pulse
}

var mode:       int = Mode.DELAY
var duration:   int = 10   # ticks

var _ticks_left:    int  = 0
var _armed:         bool = false
var _alarm:         bool = false
var _prev_input:    bool = false
var _watchdog_idle: int  = 0


func _init(pos: Vector3i) -> void:
	super(pos, "r2_timer")


func _get_input_faces() -> Array:
	return [FACE_NX]


func _get_output_faces() -> Array:
	return [facing]


func phase_calculate() -> void:
	var inp := get_face_input(FACE_NX).to_bool()
	var rising := inp and not _prev_input
	_prev_input = inp

	match mode:
		Mode.DELAY:
			if rising:
				_ticks_left = duration
				_armed = true
			if _armed and _ticks_left > 0:
				_ticks_left -= 1
			if _armed and _ticks_left == 0 and rising == false:
				# fire: will be reset next tick
				pass

		Mode.INTERVAL:
			if inp:
				if _ticks_left <= 0:
					_ticks_left = duration
				else:
					_ticks_left -= 1
			else:
				_ticks_left = 0

		Mode.COOLDOWN:
			if rising and _ticks_left <= 0:
				_ticks_left = duration
			elif _ticks_left > 0:
				_ticks_left -= 1

		Mode.WATCHDOG:
			if rising:
				_watchdog_idle = 0
				_alarm = false
			else:
				_watchdog_idle += 1
				if _watchdog_idle >= duration:
					_alarm = true

		Mode.RETRIGGER:
			if rising:
				_ticks_left = duration
			elif _ticks_left > 0:
				_ticks_left -= 1


func phase_emit() -> void:
	var out := false
	match mode:
		Mode.DELAY:
			out = (_armed and _ticks_left == 0)
			if out: _armed = false
		Mode.INTERVAL:
			out = (_ticks_left == 0 and get_face_input(FACE_NX).to_bool())
		Mode.COOLDOWN:
			out = (_ticks_left > 0 and _ticks_left == duration)
		Mode.WATCHDOG:
			out = _alarm
		Mode.RETRIGGER:
			out = (_ticks_left == 0 and _armed)
			if out: _armed = false

	if out:
		emit_event()
		_armed = false
	else:
		emit_bool(false)


func serialize() -> Dictionary:
	var d := super.serialize()
	d["mode"]          = mode
	d["duration"]      = duration
	d["ticks_left"]    = _ticks_left
	d["armed"]         = _armed
	d["alarm"]         = _alarm
	d["prev_input"]    = _prev_input
	d["watchdog_idle"] = _watchdog_idle
	return d


func deserialize(data: Dictionary) -> void:
	mode          = data.get("mode", Mode.DELAY)
	duration      = data.get("duration", 10)
	_ticks_left   = data.get("ticks_left", 0)
	_armed        = data.get("armed", false)
	_alarm        = data.get("alarm", false)
	_prev_input   = data.get("prev_input", false)
	_watchdog_idle = data.get("watchdog_idle", 0)
	super.deserialize(data)
