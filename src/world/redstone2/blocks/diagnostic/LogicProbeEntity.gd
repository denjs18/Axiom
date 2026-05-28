## LogicProbeEntity.gd — Logic probe (Sonde logique). ID 4070.
## Reads any adjacent R2 block's output and re-emits it for inspection.
## Also records last event, type, channel, conversion flag, error.
class_name LogicProbeEntity
extends R2BlockEntity

var watch_face: Vector3i = FACE_NX
var watch_ch:   int      = 0

# Inspection data (read by overlay / UI)
var probe_type:    int    = R2Signal.Type.BOOLEAN
var probe_value:   int    = 0
var probe_bool:    bool   = false
var probe_channel: int    = 0
var probe_tick:    int    = 0
var probe_source:  Vector3i = Vector3i.ZERO
var probe_error:   String  = ""
var probe_converted: bool  = false


func _init(pos: Vector3i) -> void:
	super(pos, "r2_probe")


func _get_input_faces() -> Array:
	return [watch_face]


func _get_output_faces() -> Array:
	return [facing]   # pass-through: re-emit whatever we read


func phase_calculate() -> void:
	var sig := get_face_input(watch_face)
	if sig == null:
		probe_type    = R2Signal.Type.BOOLEAN
		probe_value   = 0
		probe_bool    = false
		probe_channel = watch_ch
		probe_tick    = current_tick
		probe_source  = Vector3i.ZERO
		probe_error   = "no_signal"
		return

	probe_type      = sig.type
	probe_value     = sig.to_analog()
	probe_bool      = sig.to_bool()
	probe_channel   = sig.channel
	probe_tick      = sig.creation_tick
	probe_source    = sig.source_pos
	probe_converted = sig.is_conversion
	probe_error     = ""

	# Pass through
	_next_outputs[0] = sig.duplicate_signal()


func phase_emit() -> void:
	super.phase_emit()


func get_debug_dict() -> Dictionary:
	var d := super.get_debug_dict()
	d["probe_type"]    = probe_type
	d["probe_value"]   = probe_value
	d["probe_bool"]    = probe_bool
	d["probe_channel"] = probe_channel
	d["probe_tick"]    = probe_tick
	d["probe_source"]  = probe_source
	d["probe_converted"] = probe_converted
	d["probe_error"]   = probe_error
	return d


func serialize() -> Dictionary:
	var d := super.serialize()
	d["watch_face"] = [watch_face.x, watch_face.y, watch_face.z]
	d["watch_ch"]   = watch_ch
	return d


func deserialize(data: Dictionary) -> void:
	var wf := data.get("watch_face", [-1, 0, 0]) as Array
	if wf.size() == 3: watch_face = Vector3i(int(wf[0]), int(wf[1]), int(wf[2]))
	watch_ch = data.get("watch_ch", 0)
	super.deserialize(data)
