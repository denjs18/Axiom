## WireEntity.gd — Logical wire (Fil logique). ID 4000.
## Passive mode: attenuation -1 analog per hop. Active mode: no attenuation up to 32 hops.
## Connects to all 6 faces by default; supports mono-channel or multi-channel.
class_name WireEntity
extends R2BlockEntity

enum Mode { PASSIVE = 0, ACTIVE = 1 }
enum SignalMode { BOOLEAN = 0, ANALOG = 1 }

var mode:        int = Mode.PASSIVE
var signal_mode: int = SignalMode.ANALOG
var channel:     int = 0


func _init(pos: Vector3i) -> void:
	super(pos, "r2_wire")


func phase_calculate() -> void:
	var best := get_input(channel)
	var val  := best.to_analog()
	if mode == Mode.PASSIVE and val > 0:
		val = maxi(val - 1, 0)
	if signal_mode == SignalMode.BOOLEAN:
		emit_bool(val > 0, channel)
	else:
		emit_analog(val, channel)


func _get_output_toward(target_pos: Vector3i) -> R2Signal:
	var dir := target_pos - world_pos
	if dir not in ALL_FACES:
		return null
	return get_output(channel)


func serialize() -> Dictionary:
	var d := super.serialize()
	d["mode"]        = mode
	d["signal_mode"] = signal_mode
	d["channel"]     = channel
	return d


func deserialize(data: Dictionary) -> void:
	mode        = data.get("mode", Mode.PASSIVE)
	signal_mode = data.get("signal_mode", SignalMode.ANALOG)
	channel     = data.get("channel", 0)
	super.deserialize(data)
