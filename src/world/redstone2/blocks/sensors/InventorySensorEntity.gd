## InventorySensorEntity.gd — Inventory sensor (Capteur d'inventaire). ID 4033.
## Reads any container's inventory and emits configurable analog/boolean signals.
class_name InventorySensorEntity
extends R2BlockEntity

enum ReadMode {
	EMPTY_NOT_EMPTY = 0,  # bool: non-empty = true
	CAPACITY_USED   = 1,  # analog: filled slots / total * 255
	TOTAL_ITEMS     = 2,  # analog: total item count (clamped 0-255)
	FILTERED_COUNT  = 3,  # analog: count of specific item (filter_item)
	SLOTS_OCCUPIED  = 4,  # analog: number of occupied slots
	ITEM_PRESENT    = 5,  # bool: filter_item is in inventory
	CHARGE_LEVEL    = 6,  # analog: if fill_ratio >= threshold → 255 else 0
}

var read_mode:   int    = ReadMode.CAPACITY_USED
var filter_item: String = ""     # item id for FILTERED_COUNT and ITEM_PRESENT
var threshold:   float  = 0.75   # for CHARGE_LEVEL mode (0.0-1.0)
var watch_face:  Vector3i = FACE_NX   # which adjacent face to read from


func _init(pos: Vector3i) -> void:
	super(pos, "r2_inv_sensor")


func _get_input_faces() -> Array:
	return []


func _get_output_faces() -> Array:
	return ALL_FACES


func phase_calculate() -> void:
	var watch_pos := world_pos + watch_face
	# Try to get a block entity at the watched position
	var cm := R2Engine.get_chunk_manager()
	if cm == null:
		emit_analog(0)
		return

	var parent := cm.get_parent()
	if parent == null:
		emit_analog(0)
		return

	var bem := parent.get_node_or_null("BlockEntityManager")
	if bem == null:
		emit_analog(0)
		return

	var entity = bem.get_entity(watch_pos)
	if entity == null:
		emit_bool(read_mode == ReadMode.EMPTY_NOT_EMPTY and false)
		return

	var slots: Array = []
	if entity.has_method("get_all_slots"):
		slots = entity.get_all_slots()
	elif entity.has_method("serialize"):
		# Fallback: try to extract slots from serialized data
		var data: Dictionary = entity.serialize()
		if data.has("slots"):
			slots = data["slots"] as Array

	var total_slots := maxi(slots.size(), 1)
	var occupied    := 0
	var total_count := 0
	var filtered    := 0
	for slot in slots:
		if slot is Dictionary and not slot.is_empty() and slot.get("id", "") != "":
			occupied    += 1
			var cnt: int = int(slot.get("count", 1))
			total_count += cnt
			if filter_item != "" and slot.get("id", "") == filter_item:
				filtered += cnt

	match read_mode:
		ReadMode.EMPTY_NOT_EMPTY:
			emit_bool(occupied > 0)
		ReadMode.CAPACITY_USED:
			emit_analog(int(float(occupied) / float(total_slots) * 255.0))
		ReadMode.TOTAL_ITEMS:
			emit_analog(mini(total_count, 255))
		ReadMode.FILTERED_COUNT:
			emit_analog(mini(filtered, 255))
		ReadMode.SLOTS_OCCUPIED:
			emit_analog(mini(occupied, 255))
		ReadMode.ITEM_PRESENT:
			emit_bool(filtered > 0)
		ReadMode.CHARGE_LEVEL:
			var ratio := float(occupied) / float(total_slots)
			emit_bool(ratio >= threshold)


func serialize() -> Dictionary:
	var d := super.serialize()
	d["read_mode"]   = read_mode
	d["filter_item"] = filter_item
	d["threshold"]   = threshold
	d["watch_face"]  = [watch_face.x, watch_face.y, watch_face.z]
	return d


func deserialize(data: Dictionary) -> void:
	read_mode   = data.get("read_mode", ReadMode.CAPACITY_USED)
	filter_item = data.get("filter_item", "")
	threshold   = data.get("threshold", 0.75)
	var wf := data.get("watch_face", [-1, 0, 0]) as Array
	if wf.size() == 3: watch_face = Vector3i(int(wf[0]), int(wf[1]), int(wf[2]))
	super.deserialize(data)
