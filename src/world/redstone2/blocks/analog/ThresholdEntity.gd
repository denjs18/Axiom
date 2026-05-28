## ThresholdEntity.gd — Analog threshold to boolean converter (Seuil). ID 4021.
## Outputs true when analog input meets or exceeds threshold. Optional window and inversion.
class_name ThresholdEntity
extends R2BlockEntity

var threshold_low:  int  = 128   # lower bound
var threshold_high: int  = 255   # upper bound (window mode)
var window_mode:    bool = false  # true = output high when value is IN [low, high]
var inverted:       bool = false  # invert output


func _init(pos: Vector3i) -> void:
	super(pos, "r2_threshold")


func _get_input_faces() -> Array:
	return [FACE_NX]   # back face


func _get_output_faces() -> Array:
	return [facing]


func phase_calculate() -> void:
	var v := get_face_input(FACE_NX).to_analog()
	var result: bool
	if window_mode:
		result = v >= threshold_low and v <= threshold_high
	else:
		result = v >= threshold_low
	if inverted:
		result = not result
	emit_bool(result)


func serialize() -> Dictionary:
	var d := super.serialize()
	d["threshold_low"]  = threshold_low
	d["threshold_high"] = threshold_high
	d["window_mode"]    = window_mode
	d["inverted"]       = inverted
	return d


func deserialize(data: Dictionary) -> void:
	threshold_low  = data.get("threshold_low", 128)
	threshold_high = data.get("threshold_high", 255)
	window_mode    = data.get("window_mode", false)
	inverted       = data.get("inverted", false)
	super.deserialize(data)
