## NetworkColorizerEntity.gd — Network colorizer (Coloriseur de réseau). ID 4073.
## Tags all adjacent R2 wires/buses with a visual channel color for the overlay.
## Does not affect signal routing — purely cosmetic/organizational.
class_name NetworkColorizerEntity
extends R2BlockEntity

var network_color: int  = 0    # 0-15 → one of 16 overlay colors
var network_label: String = "" # optional user label visible in overlay
var propagate:     bool  = true  # if true, color spreads to connected wires


func _init(pos: Vector3i) -> void:
	super(pos, "r2_colorizer")


func _get_input_faces() -> Array:
	return []


func _get_output_faces() -> Array:
	return []


func phase_calculate() -> void:
	if not propagate: return
	# Tag adjacent R2 entities with this color
	var faces := [FACE_PX, FACE_NX, FACE_PY, FACE_NY, FACE_PZ, FACE_NZ]
	for face in faces:
		var nb := R2Engine.get_block(world_pos + face)
		if nb == null: continue
		# Only tag wire/bus entities
		if nb is WireEntity or nb is BusEntity:
			# Store color in metadata (accessed by overlay)
			nb.set_meta("r2_network_color", network_color)
			nb.set_meta("r2_network_label", network_label)


func get_debug_dict() -> Dictionary:
	var d := super.get_debug_dict()
	d["network_color"] = network_color
	d["network_label"] = network_label
	return d


func serialize() -> Dictionary:
	var d := super.serialize()
	d["network_color"] = network_color
	d["network_label"] = network_label
	d["propagate"]     = propagate
	return d


func deserialize(data: Dictionary) -> void:
	network_color = data.get("network_color", 0)
	network_label = data.get("network_label", "")
	propagate     = data.get("propagate", true)
	super.deserialize(data)
