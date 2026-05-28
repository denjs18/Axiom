## PresenceDetectorEntity.gd — Presence detector (Détecteur de présence). ID 4031.
## Detects entities (player, mobs, items, vehicles) in a configurable area around the block.
class_name PresenceDetectorEntity
extends R2BlockEntity

enum EntityFilter {
	PLAYER   = 1,
	PASSIVE  = 2,
	HOSTILE  = 4,
	ITEM     = 8,
	VEHICLE  = 16,
	ANY      = 31,
}

enum DetectMode { PRESENCE = 0, ENTRY = 1, EXIT = 2, COUNT = 3, DENSITY = 4 }

var filter:      int = EntityFilter.ANY
var detect_mode: int = DetectMode.PRESENCE
var radius:      float = 4.0

var _prev_count: int  = 0
var _in_range:   bool = false


func _init(pos: Vector3i) -> void:
	super(pos, "r2_presence")


func _get_input_faces() -> Array:
	return []


func _get_output_faces() -> Array:
	return ALL_FACES


func phase_calculate() -> void:
	var count := _count_entities()

	match detect_mode:
		DetectMode.PRESENCE:
			emit_bool(count > 0)
		DetectMode.COUNT:
			emit_analog(mini(count, 255))
		DetectMode.DENSITY:
			var density := int(float(count) / (radius * radius * radius) * 255.0)
			emit_analog(mini(density, 255))
		DetectMode.ENTRY:
			var entered := count > 0 and _prev_count == 0
			if entered: emit_event()
			else: emit_bool(false)
		DetectMode.EXIT:
			var exited := count == 0 and _prev_count > 0
			if exited: emit_event()
			else: emit_bool(false)

	_prev_count = count


func _count_entities() -> int:
	var cm := R2Engine.get_chunk_manager()
	if cm == null:
		return 0
	var space := cm.get_parent().get_world_3d().direct_space_state if cm.get_parent() != null else null
	if space == null:
		return 0

	var center := Vector3(world_pos) + Vector3(0.5, 0.5, 0.5)
	var shape   := SphereShape3D.new()
	shape.radius = radius
	var params  := PhysicsShapeQueryParameters3D.new()
	params.shape     = shape
	params.transform = Transform3D(Basis.IDENTITY, center)
	params.collision_mask = 4 | 8   # mobs on layer 3, items on layer 4

	var hits := space.intersect_shape(params, 64)
	var count := 0
	for h in hits:
		var node := h.get("collider") as Node
		if node == null: continue
		var passes := false
		if (filter & EntityFilter.PLAYER)  and node.is_in_group("players"):  passes = true
		if (filter & EntityFilter.PASSIVE) and node.is_in_group("passive"):  passes = true
		if (filter & EntityFilter.HOSTILE) and node.is_in_group("hostile"):  passes = true
		if (filter & EntityFilter.ITEM)    and node.is_in_group("item_drop"): passes = true
		if passes: count += 1
	return count


func serialize() -> Dictionary:
	var d := super.serialize()
	d["filter"]      = filter
	d["detect_mode"] = detect_mode
	d["radius"]      = radius
	d["prev_count"]  = _prev_count
	return d


func deserialize(data: Dictionary) -> void:
	filter      = data.get("filter", EntityFilter.ANY)
	detect_mode = data.get("detect_mode", DetectMode.PRESENCE)
	radius      = data.get("radius", 4.0)
	_prev_count = data.get("prev_count", 0)
	super.deserialize(data)
