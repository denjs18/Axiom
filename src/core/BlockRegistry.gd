## BlockRegistry.gd
## Autoload singleton. Loads all block definitions from JSON files
## and provides fast lookup by numeric ID or string name.
extends Node

const DATA_PATHS := [
	"res://data/blocks/blocks_overworld.json",
	"res://data/blocks/blocks_nether.json",
	"res://data/blocks/blocks_end.json",
	"res://data/blocks/blocks_redstone2.json",
]

# Block data dictionaries
var _blocks_by_id: Dictionary = {}      # int -> BlockDef
var _blocks_by_name: Dictionary = {}    # "axiom:stone" -> BlockDef
var _blocks_by_tag: Dictionary = {}     # "axiom:logs" -> Array[int]
# Packed lookup tables indexed by block ID — thread-safe (read-only after _ready)
var _block_flags: PackedByteArray        # bit0=transparent, bit1=fluid
var _block_light_level: PackedByteArray  # light emission level (0-15)
var _block_shape: PackedByteArray        # SHAPE_* code per block id

# Shape codes used by the mesher (must stay in sync with ChunkRenderer)
const SHAPE_CUBE  := 0
const SHAPE_CROSS := 1   # plants: flowers, saplings, grass tufts, crops
const SHAPE_TORCH := 2   # small stick with glowing tip
const SHAPE_SLAB  := 3   # bottom half block (beds, slabs)

# Shared block property constants
const AIR_ID := 0
const CHUNK_SIZE := 16


class BlockDef:
	var id: int
	var name: String          # "stone"
	var full_id: String       # "axiom:stone"
	var display_name: String
	var solid: bool
	var transparent: bool
	var light_level: int
	var light_when_active: int
	var hardness: float
	var blast_resistance: float
	var tool: String
	var tool_level: int
	var drops: Array
	var texture: Variant       # String or Dictionary
	var fluid: bool
	var gravity: bool
	var flammable: bool
	var interactive: bool
	var has_inventory: bool
	var inventory_size: int
	var redstone_power: int
	var tags: Array
	var variants: Array
	var shape: String
	var entity_script: String
	var ui_scene: String
	var raw: Dictionary

	func _init(data: Dictionary, ns: String) -> void:
		raw = data
		id = data.get("id", 0)
		name = data.get("name", "unknown")
		full_id = ns + ":" + name
		display_name = data.get("display_name", name)
		solid = data.get("solid", true)
		transparent = data.get("transparent", false)
		light_level = data.get("light_level", 0)
		light_when_active = data.get("light_when_active", light_level)
		hardness = data.get("hardness", 1.0)
		blast_resistance = data.get("blast_resistance", 1.0)
		tool = data.get("tool", "none")
		tool_level = data.get("tool_level", 0)
		drops = data.get("drops", [])
		texture = data.get("texture", name)
		fluid = data.get("fluid", false)
		gravity = data.get("gravity", false)
		flammable = data.get("flammable", false)
		interactive = data.get("interactive", false)
		has_inventory = data.get("has_inventory", false)
		inventory_size = data.get("inventory_size", 0)
		redstone_power = data.get("redstone_power", 0)
		tags = data.get("tags", [])
		variants = data.get("variants", [])
		shape = data.get("shape", "cube")
		entity_script = data.get("entity", "")
		ui_scene = data.get("ui_scene", "")

	func is_air() -> bool:
		return id == AIR_ID

	func is_passable() -> bool:
		return not solid or fluid

	func get_texture_for_face(face: String) -> String:
		if texture is String:
			return texture
		if texture is Dictionary:
			# "south" face = front of block (default facing direction)
			if face == "south" and texture.has("front"):
				return texture["front"]
			return texture.get(face, texture.get("side", name))
		return name

	func get_drop_list(_tool_used: String, _tool_lvl: int, fortune: int, silk_touch: bool) -> Array:
		var result := []
		for drop in drops:
			if drop.get("requires_silk_touch", false) and not silk_touch:
				continue
			if not drop.get("requires_silk_touch", false) and silk_touch and drop.has("requires_silk_touch"):
				continue
			var chance: float = drop.get("chance", 1.0)
			if randf() > chance:
				continue
			var count_data = drop.get("count", 1)
			var count: int
			if count_data is Array and count_data.size() == 2:
				count = randi_range(count_data[0], count_data[1])
			else:
				count = int(count_data)
			if drop.get("fortune", false) and fortune > 0:
				count = max(count, randi_range(count, count * (fortune + 1)))
			result.append({"item": drop.get("item", ""), "count": count})
		return result


func _ready() -> void:
	_load_all_blocks()
	_build_flag_table()
	print("[BlockRegistry] Loaded %d blocks." % _blocks_by_id.size())


func _build_flag_table() -> void:
	var max_id := 0
	for bid in _blocks_by_id:
		if bid > max_id:
			max_id = bid
	_block_flags.resize(max_id + 1)
	_block_flags.fill(0)
	_block_light_level.resize(max_id + 1)
	_block_light_level.fill(0)
	_block_shape.resize(max_id + 1)
	_block_shape.fill(0)
	for bid in _blocks_by_id:
		var block: BlockDef = _blocks_by_id[bid]
		var f: int = 0
		if block.transparent: f |= 1
		if block.fluid: f |= 2
		_block_flags[bid] = f
		if bid < _block_light_level.size():
			_block_light_level[bid] = block.light_level
		var shape_code := SHAPE_CUBE
		match block.shape:
			"cross", "crop", "plant": shape_code = SHAPE_CROSS
			"torch":                  shape_code = SHAPE_TORCH
			"slab", "bed":            shape_code = SHAPE_SLAB
		_block_shape[bid] = shape_code


func get_shape(id: int) -> int:
	if id < 0 or id >= _block_shape.size():
		return SHAPE_CUBE
	return _block_shape[id]


func _load_all_blocks() -> void:
	for path in DATA_PATHS:
		if ContentFlags.is_file_disabled(path):
			continue  # non-vanilla file skipped while in vanilla mode
		_load_block_file(path)


func _load_block_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("[BlockRegistry] File not found: %s" % path)
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("[BlockRegistry] Failed to open: %s" % path)
		return

	var json_text := file.get_as_text()
	file.close()

	var data: Variant = JSON.parse_string(json_text)
	if not data is Dictionary:
		push_error("[BlockRegistry] Invalid JSON in: %s" % path)
		return

	var block_ns: String = data.get("namespace", "axiom")
	var id_offset: int = data.get("id_offset", 0)
	var blocks_array: Array = data.get("blocks", [])
	var file_name := path.get_file()

	for block_data in blocks_array:
		if not block_data is Dictionary:
			continue
		if ContentFlags.is_block_disabled(block_data, file_name):
			continue  # non-vanilla block set aside while in vanilla mode
		var block := BlockDef.new(block_data, block_ns)
		if id_offset > 0:
			block.id += id_offset
		_register_block(block)


func _register_block(block: BlockDef) -> void:
	if _blocks_by_id.has(block.id):
		push_warning("[BlockRegistry] ID collision for %d (%s)" % [block.id, block.full_id])
		return
	_blocks_by_id[block.id] = block
	_blocks_by_name[block.full_id] = block
	# Register by short name too for convenience
	_blocks_by_name[block.name] = block

	for tag in block.tags:
		if not _blocks_by_tag.has(tag):
			_blocks_by_tag[tag] = []
		_blocks_by_tag[tag].append(block.id)


# --- Public API ---

func get_block(id: int) -> BlockDef:
	return _blocks_by_id.get(id)


func get_block_by_name(block_name: String) -> BlockDef:
	return _blocks_by_name.get(block_name)


func get_blocks_by_tag(tag: String) -> Array:
	return _blocks_by_tag.get(tag, [])


func is_air(id: int) -> bool:
	return id == AIR_ID


func is_solid(id: int) -> bool:
	var b := get_block(id)
	return b != null and b.solid


func is_transparent(id: int) -> bool:
	var b := get_block(id)
	return b == null or b.transparent


func is_fluid(id: int) -> bool:
	var b := get_block(id)
	return b != null and b.fluid


func get_light_level(id: int) -> int:
	var b := get_block(id)
	return b.light_level if b != null else 0


func get_hardness(id: int) -> float:
	var b := get_block(id)
	return b.hardness if b != null else 1.0


func get_all_block_ids() -> Array:
	return _blocks_by_id.keys()


func get_block_count() -> int:
	return _blocks_by_id.size()
