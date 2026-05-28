## ChestEntity.gd — 27-slot storage block entity.
class_name ChestEntity
extends BlockEntity

const SLOT_COUNT := 27

var slots: Array = []  # Array of {item_id, count, meta} dicts


func _init(pos: Vector3i) -> void:
	super(pos, "chest")
	slots.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		slots[i] = {}


func get_slot(idx: int) -> Dictionary:
	if idx < 0 or idx >= SLOT_COUNT:
		return {}
	return slots[idx]


func set_slot(idx: int, stack: Dictionary) -> void:
	if idx < 0 or idx >= SLOT_COUNT:
		return
	slots[idx] = stack


## Try to add items; returns overflow count.
func add_items(item_id: String, count: int) -> int:
	var remaining := count
	# Merge with existing stacks
	for i in SLOT_COUNT:
		if remaining <= 0:
			break
		var slot: Dictionary = slots[i]
		if slot.is_empty() or slot.get("item_id") != item_id:
			continue
		var item := ItemRegistry.get_item(item_id)
		var max_stack: int = item.max_stack if item else 64
		var space: int = max_stack - int(slot.get("count", 0))
		var take := mini(space, remaining)
		slot["count"] = slot.get("count", 0) + take
		slots[i] = slot
		remaining -= take
	# Fill empty slots
	for i in SLOT_COUNT:
		if remaining <= 0:
			break
		if not slots[i].is_empty():
			continue
		var item := ItemRegistry.get_item(item_id)
		var max_stack: int = item.max_stack if item else 64
		var take := mini(max_stack, remaining)
		slots[i] = {"item_id": item_id, "count": take, "meta": {}}
		remaining -= take
	return remaining


func serialize() -> Dictionary:
	var base := super.serialize()
	base["slots"] = slots.duplicate(true)
	return base


func deserialize(data: Dictionary) -> void:
	var saved_slots: Array = data.get("slots", [])
	for i in mini(saved_slots.size(), SLOT_COUNT):
		slots[i] = saved_slots[i]
