## RangeMapperEntity.gd — Range mapper / scaling unit (Mappeur de plage). ID 4026.
## Maps input range [in_min, in_max] to output range [out_min, out_max].
## Supports linear interpolation and step (N paliers) modes.
class_name RangeMapperEntity
extends R2BlockEntity

enum MapMode { LINEAR = 0, STEP = 1 }

var in_min:   int = 0
var in_max:   int = 255
var out_min:  int = 0
var out_max:  int = 255
var map_mode: int = MapMode.LINEAR
var steps:    int = 4   # number of discrete steps in STEP mode


func _init(pos: Vector3i) -> void:
	super(pos, "r2_range_mapper")


func _get_input_faces() -> Array:
	return [FACE_NX]


func _get_output_faces() -> Array:
	return [facing]


func phase_calculate() -> void:
	var v := float(get_face_input(FACE_NX).to_analog())
	var span_in  := float(in_max - in_min)
	var span_out := float(out_max - out_min)

	if span_in == 0.0:
		emit_analog(out_min)
		return

	var t := clampf((v - float(in_min)) / span_in, 0.0, 1.0)

	var result: int
	match map_mode:
		MapMode.LINEAR:
			result = int(float(out_min) + t * span_out)
		MapMode.STEP:
			var step_idx := int(t * float(steps))
			step_idx = clampi(step_idx, 0, steps - 1)
			result = out_min + int(float(step_idx) / float(steps - 1) * span_out)

	emit_analog(clampi(result, 0, 255))


func serialize() -> Dictionary:
	var d := super.serialize()
	d["in_min"]   = in_min
	d["in_max"]   = in_max
	d["out_min"]  = out_min
	d["out_max"]  = out_max
	d["map_mode"] = map_mode
	d["steps"]    = steps
	return d


func deserialize(data: Dictionary) -> void:
	in_min   = data.get("in_min", 0)
	in_max   = data.get("in_max", 255)
	out_min  = data.get("out_min", 0)
	out_max  = data.get("out_max", 255)
	map_mode = data.get("map_mode", MapMode.LINEAR)
	steps    = data.get("steps", 4)
	super.deserialize(data)
