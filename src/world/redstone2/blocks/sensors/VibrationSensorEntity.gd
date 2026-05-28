## VibrationSensorEntity.gd — Advanced vibration sensor (Capteur de vibration). ID 4037.
## Inspired by sculk sensor. Filters vibrations by category, emits intensity + event.
class_name VibrationSensorEntity
extends R2BlockEntity

# Vibration category bitmask (matches GameEvents or custom EventBus events)
enum VibCategory {
	STEP         = 1,    # footstep
	PLACE        = 2,    # block placed
	BREAK        = 4,    # block broken
	HIT          = 8,    # entity hurt
	EXPLOSION    = 16,   # TNT / creeper
	FLUID        = 32,   # fluid flow / bucket
	PROJECTILE   = 64,   # arrow / trident
	ANY          = 127,
}

enum OutputMode {
	INTENSITY = 0,   # analog: 0-255 based on distance
	EVENT     = 1,   # event pulse on detection
	BOTH      = 2,   # channel 0 = intensity, channel 1 = event
}

var category_filter: int = VibCategory.ANY
var detect_radius:   float = 8.0
var output_mode:     int = OutputMode.BOTH
var cooldown_ticks:  int = 2   # min ticks between detections

var _cooldown_remaining: int = 0
var _pending_intensity:  int = 0
var _received_vibration: bool = false

# Called externally by game systems when vibrations occur.
# category: VibCategory flag, origin: world position of the event.
func receive_vibration(category: int, origin: Vector3i) -> void:
	if not (category & category_filter): return
	var dist := float((origin - world_pos).length())
	if dist > detect_radius: return
	if _cooldown_remaining > 0: return
	var intensity := int((1.0 - dist / detect_radius) * 255.0)
	_pending_intensity  = clampi(intensity, 1, 255)
	_received_vibration = true


func _init(pos: Vector3i) -> void:
	super(pos, "r2_vibration")


func _get_input_faces() -> Array:
	return []


func _get_output_faces() -> Array:
	return ALL_FACES


func phase_calculate() -> void:
	if _cooldown_remaining > 0:
		_cooldown_remaining -= 1

	if not _received_vibration:
		match output_mode:
			OutputMode.INTENSITY: emit_analog(0)
			OutputMode.EVENT:     emit_bool(false)
			OutputMode.BOTH:
				emit_analog(0)
				_emit_channel(1, R2Signal.make_bool(false, 1, world_pos))
		return

	_received_vibration    = false
	_cooldown_remaining    = cooldown_ticks

	match output_mode:
		OutputMode.INTENSITY:
			emit_analog(_pending_intensity)
		OutputMode.EVENT:
			emit_event()
		OutputMode.BOTH:
			emit_analog(_pending_intensity)
			_emit_channel(1, R2Signal.make_event(1, world_pos))


func _emit_channel(ch: int, sig: R2Signal) -> void:
	if _next_outputs == null: _next_outputs = {}
	_next_outputs[ch] = sig


func serialize() -> Dictionary:
	var d := super.serialize()
	d["category_filter"]   = category_filter
	d["detect_radius"]     = detect_radius
	d["output_mode"]       = output_mode
	d["cooldown_ticks"]    = cooldown_ticks
	d["cooldown_remaining"] = _cooldown_remaining
	return d


func deserialize(data: Dictionary) -> void:
	category_filter    = data.get("category_filter", VibCategory.ANY)
	detect_radius      = data.get("detect_radius", 8.0)
	output_mode        = data.get("output_mode", OutputMode.BOTH)
	cooldown_ticks     = data.get("cooldown_ticks", 2)
	_cooldown_remaining = data.get("cooldown_remaining", 0)
	super.deserialize(data)
