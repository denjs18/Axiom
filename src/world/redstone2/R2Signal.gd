## R2Signal.gd — Signal data transported through the Redstone 2.0 network.
## Three types: Boolean (0/1), Analog (0-255), Event (timestamped pulse).
class_name R2Signal
extends RefCounted

enum Type { BOOLEAN = 0, ANALOG = 1, EVENT = 2 }

var type:          int      = Type.BOOLEAN
var bool_value:    bool     = false
var analog_value:  int      = 0        # 0–255
var channel:       int      = 0        # 0–15 (8 on basic bus, 16 on advanced)
var source_pos:    Vector3i = Vector3i.ZERO
var priority:      int      = 0
var creation_tick: int      = 0
var is_conversion: bool     = false    # true when auto-converted between types
var debug_flag:    bool     = false


# ── Constructors ──────────────────────────────────────────────────────────────

static func make_bool(v: bool, ch: int = 0, src: Vector3i = Vector3i.ZERO) -> R2Signal:
	var s := R2Signal.new()
	s.type         = Type.BOOLEAN
	s.bool_value   = v
	s.analog_value = 255 if v else 0
	s.channel      = ch
	s.source_pos   = src
	return s


static func make_analog(v: int, ch: int = 0, src: Vector3i = Vector3i.ZERO) -> R2Signal:
	var s := R2Signal.new()
	s.type         = Type.ANALOG
	s.analog_value = clampi(v, 0, 255)
	s.bool_value   = v >= 1
	s.channel      = ch
	s.source_pos   = src
	return s


static func make_event(ch: int = 0, src: Vector3i = Vector3i.ZERO) -> R2Signal:
	var s := R2Signal.new()
	s.type         = Type.EVENT
	s.bool_value   = true
	s.analog_value = 255
	s.channel      = ch
	s.source_pos   = src
	return s


static func make_off() -> R2Signal:
	return R2Signal.make_bool(false)


# ── Conversion ────────────────────────────────────────────────────────────────

func to_bool(threshold: int = 1) -> bool:
	match type:
		Type.BOOLEAN: return bool_value
		Type.ANALOG:  return analog_value >= threshold
		Type.EVENT:   return true
	return false


func to_analog() -> int:
	match type:
		Type.BOOLEAN: return 255 if bool_value else 0
		Type.ANALOG:  return analog_value
		Type.EVENT:   return 255
	return 0


func as_type(target_type: int, threshold: int = 1) -> R2Signal:
	if type == target_type:
		return self
	var s := R2Signal.new()
	s.type         = target_type
	s.channel      = channel
	s.source_pos   = source_pos
	s.is_conversion = true
	match target_type:
		Type.BOOLEAN:
			s.bool_value   = to_bool(threshold)
			s.analog_value = 255 if s.bool_value else 0
		Type.ANALOG:
			s.analog_value = to_analog()
			s.bool_value   = s.analog_value >= threshold
		Type.EVENT:
			s.bool_value   = true
			s.analog_value = 255
	return s


# ── Conflict resolution ───────────────────────────────────────────────────────
# Strategies match R2Engine constants: PRIORITY=0, LOCAL=1, MAX=2, MIN=3, SUM=4, AVG=5

static func resolve(signals: Array, strategy: int) -> R2Signal:
	if signals.is_empty():
		return R2Signal.make_off()
	if signals.size() == 1:
		return signals[0] as R2Signal
	match strategy:
		1:   # LOCAL — first source wins
			return signals[0] as R2Signal
		2:   # MAX
			var best: R2Signal = signals[0]
			for s: R2Signal in signals:
				if s.to_analog() > best.to_analog():
					best = s
			return best
		3:   # MIN
			var best: R2Signal = signals[0]
			for s: R2Signal in signals:
				if s.to_analog() < best.to_analog():
					best = s
			return best
		4:   # SUM (clamped)
			var total := 0
			for s: R2Signal in signals:
				total += s.to_analog()
			return R2Signal.make_analog(mini(total, 255), (signals[0] as R2Signal).channel)
		5:   # AVERAGE
			var total := 0
			for s: R2Signal in signals:
				total += s.to_analog()
			return R2Signal.make_analog(total / signals.size(), (signals[0] as R2Signal).channel)
		_:   # PRIORITY (0) — highest priority wins
			var best: R2Signal = signals[0]
			for s: R2Signal in signals:
				if s.priority > best.priority:
					best = s
			return best


# ── Utilities ─────────────────────────────────────────────────────────────────

func type_name() -> String:
	match type:
		Type.BOOLEAN: return "bool"
		Type.ANALOG:  return "analog"
		Type.EVENT:   return "event"
	return "?"


func value_str() -> String:
	match type:
		Type.BOOLEAN: return "1" if bool_value else "0"
		Type.ANALOG:  return str(analog_value)
		Type.EVENT:   return "EVT"
	return "?"


func duplicate_signal() -> R2Signal:
	var s := R2Signal.new()
	s.type          = type
	s.bool_value    = bool_value
	s.analog_value  = analog_value
	s.channel       = channel
	s.source_pos    = source_pos
	s.priority      = priority
	s.creation_tick = creation_tick
	s.is_conversion = is_conversion
	s.debug_flag    = debug_flag
	return s
