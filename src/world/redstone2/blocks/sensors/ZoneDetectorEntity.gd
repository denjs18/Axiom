## ZoneDetectorEntity.gd — Configurable zone detector (Détecteur de zone). ID 4032.
## Monitors a cubic zone for entity presence, entry, or exit.
class_name ZoneDetectorEntity
extends R2BlockEntity

var zone_size:  Vector3i = Vector3i(3, 3, 3)   # half-extents
var zone_offset: Vector3i = Vector3i(0, 0, 0)   # offset from block center

enum DetectMode { OCCUPIED = 0, ENTRY = 1, EXIT = 2 }
var detect_mode: int = DetectMode.OCCUPIED

var _prev_occupied: bool = false


func _init(pos: Vector3i) -> void:
	super(pos, "r2_zone")


func _get_input_faces() -> Array:
	return []


func _get_output_faces() -> Array:
	return ALL_FACES


func phase_calculate() -> void:
	var cm := R2Engine.get_chunk_manager()
	if cm == null:
		emit_bool(false)
		return

	var parent := cm.get_parent()
	if parent == null:
		emit_bool(false)
		return

	var world_3d := parent.get_world_3d()
	if world_3d == null:
		emit_bool(false)
		return

	var space  := world_3d.direct_space_state
	var center := Vector3(world_pos + zone_offset) + Vector3(0.5, 0.5, 0.5)
	var shape  := BoxShape3D.new()
	shape.size = Vector3(zone_size) * 2.0
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape     = shape
	params.transform = Transform3D(Basis.IDENTITY, center)
	params.collision_mask = 4 | 8

	var hits     := space.intersect_shape(params, 32)
	var occupied := not hits.is_empty()

	match detect_mode:
		DetectMode.OCCUPIED:
			emit_bool(occupied)
		DetectMode.ENTRY:
			if occupied and not _prev_occupied: emit_event()
			else: emit_bool(false)
		DetectMode.EXIT:
			if not occupied and _prev_occupied: emit_event()
			else: emit_bool(false)

	_prev_occupied = occupied


func serialize() -> Dictionary:
	var d := super.serialize()
	d["zone_size"]    = [zone_size.x, zone_size.y, zone_size.z]
	d["zone_offset"]  = [zone_offset.x, zone_offset.y, zone_offset.z]
	d["detect_mode"]  = detect_mode
	d["prev_occupied"] = _prev_occupied
	return d


func deserialize(data: Dictionary) -> void:
	var zs := data.get("zone_size", [3,3,3]) as Array
	var zo := data.get("zone_offset", [0,0,0]) as Array
	if zs.size() == 3: zone_size   = Vector3i(int(zs[0]), int(zs[1]), int(zs[2]))
	if zo.size() == 3: zone_offset = Vector3i(int(zo[0]), int(zo[1]), int(zo[2]))
	detect_mode   = data.get("detect_mode", DetectMode.OCCUPIED)
	_prev_occupied = data.get("prev_occupied", false)
	super.deserialize(data)
