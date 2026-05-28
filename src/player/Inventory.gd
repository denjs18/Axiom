## Inventory.gd
## Full player inventory: 36 slots (9 hotbar + 27 main) + 4 armor + 1 offhand.
## Uses ItemStack dicts: {id: String, count: int, meta: Dictionary}
class_name Inventory
extends Node

const HOTBAR_SIZE := 9
const MAIN_SIZE := 27
const ARMOR_SIZE := 4
const OFFHAND_SIZE := 1
const TOTAL_SIZE := HOTBAR_SIZE + MAIN_SIZE  # 36

var slots: Array = []         # 36 general slots (0-8 = hotbar, 9-35 = main)
var armor_slots: Array = []   # [head, chest, legs, feet]
var offhand: Dictionary = {}  # Single offhand slot

signal slot_changed(slot_index: int, new_stack: Dictionary)
signal armor_changed(slot_index: int, new_stack: Dictionary)
signal offhand_changed(new_stack: Dictionary)


func _ready() -> void:
	slots.resize(TOTAL_SIZE)
	slots.fill({})
	armor_slots.resize(ARMOR_SIZE)
	armor_slots.fill({})
	offhand = {}


# --- Hotbar ---

func get_hotbar_item(slot: int) -> Dictionary:
	if slot < 0 or slot >= HOTBAR_SIZE:
		return {}
	return slots[slot]


func consume_hotbar_item(slot: int, count: int) -> void:
	remove_items(slot, count)


# --- Core operations ---

func get_slot(index: int) -> Dictionary:
	if index < 0 or index >= TOTAL_SIZE:
		return {}
	return slots[index]


func set_slot(index: int, stack: Dictionary) -> void:
	if index < 0 or index >= TOTAL_SIZE:
		return
	slots[index] = stack
	slot_changed.emit(index, stack)
	EventBus.player_inventory_changed.emit(get_parent(), index)


func add_items(item_id: String, count: int, meta: Dictionary = {}) -> int:
	"""Add items to inventory. Returns number of items that didn't fit."""
	var remaining := count
	# First: stack into existing stacks
	for i in TOTAL_SIZE:
		if remaining <= 0:
			break
		var slot: Dictionary = slots[i]
		if ItemRegistry.is_empty_stack(slot):
			continue
		if slot.get("id") != item_id or slot.get("meta", {}) != meta:
			continue
		var item := ItemRegistry.get_item(item_id)
		var max_stack: int = item.max_stack if item else 64
		var can_add: int = max_stack - slot.get("count", 0)
		if can_add <= 0:
			continue
		var add_amount := mini(can_add, remaining)
		slots[i]["count"] += add_amount
		remaining -= add_amount
		slot_changed.emit(i, slots[i])

	# Second: fill empty slots
	for i in TOTAL_SIZE:
		if remaining <= 0:
			break
		if not ItemRegistry.is_empty_stack(slots[i]):
			continue
		var item := ItemRegistry.get_item(item_id)
		var max_stack := item.max_stack if item else 64
		var add_amount := mini(max_stack, remaining)
		slots[i] = {"id": item_id, "count": add_amount, "meta": meta.duplicate()}
		remaining -= add_amount
		slot_changed.emit(i, slots[i])

	return remaining


func remove_items(slot_index: int, count: int) -> void:
	if slot_index < 0 or slot_index >= TOTAL_SIZE:
		return
	var slot: Dictionary = slots[slot_index]
	if ItemRegistry.is_empty_stack(slot):
		return
	var new_count: int = slot.get("count", 0) - count
	if new_count <= 0:
		slots[slot_index] = {}
	else:
		slots[slot_index]["count"] = new_count
	slot_changed.emit(slot_index, slots[slot_index])


func has_item(item_id: String, count: int = 1) -> bool:
	return count_item(item_id) >= count


func count_item(item_id: String) -> int:
	var total := 0
	for slot in slots:
		if slot.get("id", "") == item_id:
			total += slot.get("count", 0)
	return total


func consume_item(item_id: String, count: int) -> bool:
	"""Remove count items from inventory. Returns false if insufficient."""
	if not has_item(item_id, count):
		return false
	var remaining := count
	for i in TOTAL_SIZE:
		if remaining <= 0:
			break
		if slots[i].get("id", "") != item_id:
			continue
		var avail: int = slots[i].get("count", 0)
		var take := mini(avail, remaining)
		remove_items(i, take)
		remaining -= take
	return true


# --- Drag & Drop ---

## Move stack from one slot to another. Handles splitting and merging.
func move_stack(from_slot: int, to_slot: int) -> void:
	var from_stack := get_slot(from_slot)
	var to_stack := get_slot(to_slot)

	if ItemRegistry.is_empty_stack(from_stack):
		return

	if ItemRegistry.is_empty_stack(to_stack):
		set_slot(to_slot, from_stack.duplicate())
		set_slot(from_slot, {})
	elif ItemRegistry.stacks_can_merge(from_stack, to_stack):
		var item := ItemRegistry.get_item(from_stack.get("id", ""))
		var max_stack := item.max_stack if item else 64
		var total: int = int(from_stack.get("count", 0)) + int(to_stack.get("count", 0))
		if total <= max_stack:
			to_stack["count"] = total
			set_slot(to_slot, to_stack)
			set_slot(from_slot, {})
		else:
			to_stack["count"] = max_stack
			from_stack["count"] = total - max_stack
			set_slot(to_slot, to_stack)
			set_slot(from_slot, from_stack)
	else:
		# Swap
		set_slot(to_slot, from_stack.duplicate())
		set_slot(from_slot, to_stack.duplicate())


## Split stack: take half from source and return it.
func split_stack(slot_index: int) -> Dictionary:
	var slot := get_slot(slot_index)
	if ItemRegistry.is_empty_stack(slot):
		return {}
	var count: int = slot.get("count", 0)
	if count <= 1:
		return {}
	var take := count / 2
	var new_count := count - take
	slots[slot_index]["count"] = new_count
	slot_changed.emit(slot_index, slots[slot_index])
	return {"id": slot.get("id"), "count": take, "meta": slot.get("meta", {}).duplicate()}


# --- Auto-sort ---

func auto_sort() -> void:
	# Collect all items (excluding hotbar)
	var item_map: Dictionary = {}
	for i in range(HOTBAR_SIZE, TOTAL_SIZE):
		var slot: Dictionary = slots[i]
		if ItemRegistry.is_empty_stack(slot):
			continue
		var key: String = str(slot.get("id", "")) + str(slot.get("meta", {}))
		if not item_map.has(key):
			item_map[key] = {"id": slot.get("id"), "count": 0, "meta": slot.get("meta", {})}
		item_map[key]["count"] += slot.get("count", 0)
		slots[i] = {}

	# Sort by display name
	var items := item_map.values()
	items.sort_custom(func(a, b):
		var na := ItemRegistry.get_item(a["id"])
		var nb := ItemRegistry.get_item(b["id"])
		var da: String = na.display_name if na else str(a["id"])
		var db: String = nb.display_name if nb else str(b["id"])
		return da < db
	)

	# Re-fill main inventory
	var fill_index := HOTBAR_SIZE
	for item in items:
		var item_def := ItemRegistry.get_item(item["id"])
		var max_stack := item_def.max_stack if item_def else 64
		var remaining: int = item["count"]
		while remaining > 0 and fill_index < TOTAL_SIZE:
			var put := mini(remaining, max_stack)
			slots[fill_index] = {"id": item["id"], "count": put, "meta": item["meta"].duplicate()}
			slot_changed.emit(fill_index, slots[fill_index])
			remaining -= put
			fill_index += 1

	# Clear remaining slots
	while fill_index < TOTAL_SIZE:
		slots[fill_index] = {}
		slot_changed.emit(fill_index, {})
		fill_index += 1


# --- Armor ---

func get_armor_slot(index: int) -> Dictionary:
	if index < 0 or index >= ARMOR_SIZE:
		return {}
	return armor_slots[index]


func set_armor_slot(index: int, stack: Dictionary) -> void:
	if index < 0 or index >= ARMOR_SIZE:
		return
	armor_slots[index] = stack
	armor_changed.emit(index, stack)
	_recalculate_armor()


func _recalculate_armor() -> void:
	var total_armor := 0.0
	for slot in armor_slots:
		if ItemRegistry.is_empty_stack(slot):
			continue
		var item := ItemRegistry.get_item(slot.get("id", ""))
		if item:
			total_armor += item.armor
	var player := get_parent()
	if player and player.has_method("get") and "armor_value" in player:
		player.armor_value = total_armor


# --- Serialization ---

func serialize() -> Dictionary:
	var data := {}
	data["slots"] = slots.duplicate(true)
	data["armor"] = armor_slots.duplicate(true)
	data["offhand"] = offhand.duplicate()
	return data


func deserialize(data: Dictionary) -> void:
	if data.has("slots"):
		slots = data["slots"].duplicate(true)
		while slots.size() < TOTAL_SIZE:
			slots.append({})
	if data.has("armor"):
		armor_slots = data["armor"].duplicate(true)
	if data.has("offhand"):
		offhand = data["offhand"].duplicate()
	_recalculate_armor()
