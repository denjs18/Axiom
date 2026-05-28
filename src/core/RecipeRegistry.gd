## RecipeRegistry.gd
## Autoload singleton. Loads all crafting/smelting/brewing recipes.
extends Node

const DATA_PATHS := [
	"res://data/recipes/recipes_crafting.json",
	"res://data/recipes/recipes_smelting.json",
	"res://data/recipes/recipes_redstone2.json",
]

# Shaped/shapeless crafting recipes stored by grid hash for fast lookup
var _crafting_shaped: Array = []
var _crafting_shapeless: Array = []
var _smelting: Dictionary = {}       # ingredient_id -> RecipeDef
var _smelting_tag: Array = []        # [{tag, recipe}] for tag-based ingredients
var _blasting: Dictionary = {}
var _smoking: Dictionary = {}


class RecipeDef:
	var id: String
	var type: String
	var result: Dictionary     # {id, count}  — "item" key from JSON normalized to "id"
	var xp: float
	var time: int
	var raw: Dictionary

	func _init(data: Dictionary) -> void:
		raw = data
		id = data.get("id", "")
		type = data.get("type", "shaped")
		# Normalize: JSON uses "item" key, internal stacks use "id"
		var r: Dictionary = data.get("result", {}).duplicate()
		if r.has("item") and not r.has("id"):
			r["id"] = r["item"]
			r.erase("item")
		result = r
		xp = data.get("xp", 0.0)
		time = data.get("time", 200)


class ShapedRecipe extends RecipeDef:
	var pattern: Array      # Array of strings
	var keys: Dictionary    # char -> ingredient
	var width: int
	var height: int
	# Normalized pattern (3x3 grid of ingredient IDs or tags)
	var grid: Array

	func _init(data: Dictionary) -> void:
		super(data)
		pattern = data.get("pattern", [])
		keys = data.get("keys", {})
		height = pattern.size()
		width = 0
		for row in pattern:
			width = max(width, row.length())
		_build_grid()

	func _build_grid() -> void:
		grid = []
		for row in pattern:
			var grid_row := []
			for i in 3:
				if i < row.length():
					var ch: String = row[i]
					if ch == " " or not keys.has(ch):
						grid_row.append(null)
					else:
						grid_row.append(keys[ch])
				else:
					grid_row.append(null)
			grid.append(grid_row)
		while grid.size() < 3:
			grid.append([null, null, null])

	func matches(input_grid: Array, item_registry: ItemRegistry) -> bool:
		# Try all valid offsets for the pattern in the 3x3 grid
		for dy in (3 - height + 1):
			for dx in (3 - width + 1):
				if _check_at_offset(input_grid, dx, dy, item_registry):
					return true
		return false

	func _check_at_offset(input: Array, dx: int, dy: int, _ir) -> bool:
		for y in 3:
			for x in 3:
				var py := y - dy
				var px := x - dx
				var expected = null
				if py >= 0 and py < grid.size() and px >= 0 and px < grid[py].size():
					expected = grid[py][px]
				var actual_stack: Dictionary = input[y][x] if input.size() > y else {}
				var actual_id: String = actual_stack.get("id", "")
				if expected == null:
					if actual_id != "":
						return false
				else:
					if not _ingredient_matches(expected, actual_id):
						return false
		return true

	func _ingredient_matches(expected: Variant, actual_id: String) -> bool:
		if expected is String:
			return expected == actual_id
		if expected is Dictionary:
			if expected.has("tag"):
				return BlockRegistry.get_blocks_by_tag(expected["tag"]).has(
					ItemRegistry.get_block_id_for_item(actual_id)
				) or _item_has_tag(actual_id, expected["tag"])
		return false

	func _item_has_tag(item_id: String, tag: String) -> bool:
		var item := ItemRegistry.get_item(item_id)
		return item != null and tag in item.tags


class ShapelessRecipe extends RecipeDef:
	var ingredients: Array

	func _init(data: Dictionary) -> void:
		super(data)
		ingredients = data.get("ingredients", [])

	func matches(input_items: Array) -> bool:
		var remaining := ingredients.duplicate()
		for stack in input_items:
			if ItemRegistry.is_empty_stack(stack):
				continue
			var found := false
			for i in remaining.size():
				if _ingredient_matches(remaining[i], stack.get("id", "")):
					remaining.remove_at(i)
					found = true
					break
			if not found:
				return false
		return remaining.is_empty()

	func _ingredient_matches(expected: Variant, actual_id: String) -> bool:
		if expected is String:
			return expected == actual_id
		if expected is Dictionary and expected.has("tag"):
			var item := ItemRegistry.get_item(actual_id)
			return item != null and expected["tag"] in item.tags
		return false


func _ready() -> void:
	for path in DATA_PATHS:
		if FileAccess.file_exists(path):
			_load_recipe_file(path)
	print("[RecipeRegistry] Loaded %d shaped, %d shapeless, %d smelting recipes." % [
		_crafting_shaped.size(), _crafting_shapeless.size(), _smelting.size()
	])


func _load_recipe_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary:
		return
	for recipe_data in data.get("recipes", []):
		_register_recipe(recipe_data)


func _register_recipe(data: Dictionary) -> void:
	var rtype: String = data.get("type", "shaped")
	match rtype:
		"shaped":
			_crafting_shaped.append(ShapedRecipe.new(data))
		"shapeless":
			_crafting_shapeless.append(ShapelessRecipe.new(data))
		"smelting":
			var ing = data.get("ingredient", "")
			if ing is Dictionary and ing.has("tag"):
				_smelting_tag.append({"tag": ing["tag"], "recipe": RecipeDef.new(data)})
			else:
				_smelting[str(ing)] = RecipeDef.new(data)
		"blasting":
			_blasting[str(data.get("ingredient", ""))] = RecipeDef.new(data)
		"smoking":
			_smoking[str(data.get("ingredient", ""))] = RecipeDef.new(data)


# --- Public API ---

func get_all_crafting_recipes() -> Array:
	return _crafting_shaped + _crafting_shapeless


## Find matching shaped or shapeless recipe for a 3x3 grid input.
## grid: Array of 3 rows, each row is Array of 3 ItemStack dicts
func find_crafting_recipe(grid: Array) -> RecipeDef:
	for recipe in _crafting_shaped:
		if recipe.matches(grid, ItemRegistry):
			return recipe
	# Flatten for shapeless
	var flat := []
	for row in grid:
		for stack in row:
			if not ItemRegistry.is_empty_stack(stack):
				flat.append(stack)
	for recipe in _crafting_shapeless:
		if recipe.matches(flat):
			return recipe
	return null


func find_smelting_recipe(ingredient_id: String) -> RecipeDef:
	if _smelting.has(ingredient_id):
		return _smelting[ingredient_id]
	# Check tag-based recipes (e.g. any log → charcoal)
	var item := ItemRegistry.get_item(ingredient_id)
	if item != null:
		for entry in _smelting_tag:
			if entry["tag"] in item.tags:
				return entry["recipe"]
	return null


func find_blasting_recipe(ingredient_id: String) -> RecipeDef:
	return _blasting.get(ingredient_id)


func find_smoking_recipe(ingredient_id: String) -> RecipeDef:
	return _smoking.get(ingredient_id)
