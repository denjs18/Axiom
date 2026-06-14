## ItemRegistry.gd
## Autoload singleton. Loads all item definitions from JSON and block-derived items.
extends Node

const DATA_PATHS := [
	"res://data/items/items_tools.json",
	"res://data/items/items_armor.json",
	"res://data/items/items_food.json",
	"res://data/items/items_materials.json",
	"res://data/items/items_blocks.json",
	"res://data/items/items_redstone2.json",
]

var _items_by_id: Dictionary = {}    # "axiom:stone" -> ItemDef
var _items_by_short: Dictionary = {} # "stone" -> ItemDef


class ItemDef:
	var id: String           # "axiom:diamond_sword"
	var short_id: String     # "diamond_sword"
	var display_name: String
	var max_stack: int
	var texture: String
	var tool: String
	var tool_level: int
	var durability: int
	var mining_speed: float
	var damage: float
	var armor: int
	var armor_toughness: float
	var slot: String         # "head","chest","legs","feet","offhand"
	var tier: int
	var fireproof: bool
	var food_value: int
	var saturation: float
	var effects: Array
	var tags: Array
	var raw: Dictionary

	func _init(data: Dictionary, ns: String) -> void:
		raw = data
		short_id = data.get("id", "unknown")
		id = ns + ":" + short_id
		display_name = data.get("display_name", short_id)
		max_stack = data.get("max_stack", 64)
		texture = data.get("texture", short_id)
		tool = data.get("tool", "")
		tool_level = data.get("tool_level", 0)
		durability = data.get("durability", 0)
		mining_speed = data.get("mining_speed", 1.0)
		damage = data.get("damage", 0.0)
		armor = data.get("armor", 0)
		armor_toughness = data.get("armor_toughness", 0.0)
		slot = data.get("slot", "")
		tier = data.get("tier", 0)
		fireproof = data.get("fireproof", false)
		food_value = data.get("food_value", 0)
		saturation = data.get("saturation", 0.0)
		effects = data.get("effects", [])
		tags = data.get("tags", [])

	func is_tool() -> bool:
		return tool != "" and tool != "none"

	func is_weapon() -> bool:
		return tool == "sword" or tool == "axe" or tool == "trident"

	func is_armor() -> bool:
		return slot in ["head", "chest", "legs", "feet"]

	func is_food() -> bool:
		return food_value > 0

	func is_stackable() -> bool:
		return max_stack > 1

	func has_durability() -> bool:
		return durability > 0


func _ready() -> void:
	_load_all_items()
	_register_block_items()
	print("[ItemRegistry] Loaded %d items." % _items_by_id.size())


func _load_all_items() -> void:
	for path in DATA_PATHS:
		if ContentFlags.is_file_disabled(path):
			continue  # non-vanilla file skipped while in vanilla mode
		if FileAccess.file_exists(path):
			_load_item_file(path)


func _load_item_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var json_text := file.get_as_text()
	file.close()
	var data: Variant = JSON.parse_string(json_text)
	if not data is Dictionary:
		return
	var ns: String = data.get("namespace", "axiom")
	for item_data in data.get("items", []):
		if item_data is Dictionary:
			if ContentFlags.is_item_disabled(item_data):
				continue  # non-vanilla item set aside while in vanilla mode
			_register_item(ItemDef.new(item_data, ns))


func _register_block_items() -> void:
	# Auto-create item versions of all registered blocks
	for block_id in BlockRegistry.get_all_block_ids():
		var block := BlockRegistry.get_block(block_id)
		if block == null or block.is_air():
			continue
		if _items_by_id.has(block.full_id):
			continue  # Item already defined explicitly
		var item_data := {
			"id": block.name,
			"display_name": block.display_name,
			"max_stack": 64,
			"texture": block.name,
			"is_block": true,
			"block_id": block.id,
		}
		_register_item(ItemDef.new(item_data, "axiom"))


func _register_item(item: ItemDef) -> void:
	_items_by_id[item.id] = item
	_items_by_short[item.short_id] = item


# --- Public API ---

func get_item(id: String) -> ItemDef:
	if _items_by_id.has(id):
		return _items_by_id[id]
	return _items_by_short.get(id)


func get_item_count() -> int:
	return _items_by_id.size()


## All registered item ids ("axiom:..."). Used by the creative inventory.
func get_all_item_ids() -> Array:
	return _items_by_id.keys()


func is_block_item(item_id: String) -> bool:
	var item := get_item(item_id)
	return item != null and item.raw.get("is_block", false)


func get_block_id_for_item(item_id: String) -> int:
	var item := get_item(item_id)
	if item != null:
		var bid: int = item.raw.get("block_id", BlockRegistry.AIR_ID)
		if bid != BlockRegistry.AIR_ID:
			return bid
	# Fallback: derive block name from item ID  (e.g. "axiom:oak_log" → "oak_log")
	var block_name := item_id.split(":")[-1]
	var block := BlockRegistry.get_block_by_name(block_name)
	if block != null:
		return block.id
	return BlockRegistry.AIR_ID


# Create an ItemStack dictionary (used everywhere in inventories)
static func make_stack(item_id: String, count: int = 1, meta: Dictionary = {}) -> Dictionary:
	return {"id": item_id, "count": count, "meta": meta}


func is_empty_stack(stack: Dictionary) -> bool:
	return stack.is_empty() or stack.get("count", 0) <= 0 or stack.get("id", "") == ""


static func stacks_can_merge(a: Dictionary, b: Dictionary) -> bool:
	return a.get("id") == b.get("id") and a.get("meta", {}) == b.get("meta", {})
