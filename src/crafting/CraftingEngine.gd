## CraftingEngine.gd
## Handles crafting grid operations and recipe matching.
## Used by crafting table UI and player 2x2 crafting.
class_name CraftingEngine
extends Node

const GRID_SIZE_2X2 := 2
const GRID_SIZE_3X3 := 3

signal recipe_found(recipe: RecipeRegistry.RecipeDef)
signal recipe_cleared()
signal craft_completed(result: Dictionary)


## The current 3x3 crafting grid (Array of 3 rows, each Array of 3 stacks)
var grid: Array = []
var grid_size: int = 3
var _cached_recipe: RecipeRegistry.RecipeDef = null
var _owner_inventory: Inventory = null


func _ready() -> void:
	_reset_grid()


func setup(inventory: Inventory, size: int = 3) -> void:
	_owner_inventory = inventory
	grid_size = size
	_reset_grid()


func _reset_grid() -> void:
	grid = []
	for _y in grid_size:
		var row := []
		for _x in grid_size:
			row.append({})
		grid.append(row)
	_cached_recipe = null


## Set item in crafting grid slot.
func set_grid_slot(row: int, col: int, stack: Dictionary) -> void:
	if row < 0 or row >= grid_size or col < 0 or col >= grid_size:
		return
	grid[row][col] = stack
	_update_recipe()


func get_grid_slot(row: int, col: int) -> Dictionary:
	if row < 0 or row >= grid_size or col < 0 or col >= grid_size:
		return {}
	return grid[row][col].duplicate()


## Clear the entire grid.
func clear_grid() -> void:
	_reset_grid()
	recipe_cleared.emit()


func _update_recipe() -> void:
	# Always use 3x3 search (pads 2x2 to 3x3)
	var search_grid := _to_3x3()
	var recipe := RecipeRegistry.find_crafting_recipe(search_grid)
	if recipe != _cached_recipe:
		_cached_recipe = recipe
		if recipe:
			recipe_found.emit(recipe)
		else:
			recipe_cleared.emit()


func _to_3x3() -> Array:
	if grid_size == 3:
		return grid
	# Pad 2x2 into 3x3
	var result := []
	for y in 3:
		var row := []
		for x in 3:
			if y < 2 and x < 2:
				row.append(grid[y][x])
			else:
				row.append({})
		result.append(row)
	return result


## Get current recipe result (or empty dict).
func get_result() -> Dictionary:
	if _cached_recipe == null:
		return {}
	return _cached_recipe.result.duplicate()


## Attempt to perform one craft. Consumes ingredients, returns result stack.
func craft_one() -> Dictionary:
	if _cached_recipe == null:
		return {}
	if _owner_inventory == null:
		return {}

	var result := _cached_recipe.result.duplicate()
	# Consume ingredients and return result — caller decides where result goes
	_consume_ingredients()
	craft_completed.emit(result)
	EventBus.item_crafted.emit(result, _owner_inventory.get_parent() if _owner_inventory else null)
	_update_recipe()
	return result


## Craft as many times as possible, adding all results to inventory (Shift+Click behavior).
func craft_all() -> int:
	if _owner_inventory == null:
		return 0
	var count := 0
	while _cached_recipe != null:
		var result := _cached_recipe.result.duplicate()
		var remaining := _owner_inventory.add_items(result.get("id", ""), result.get("count", 1))
		if remaining > 0:
			break
		_consume_ingredients()
		craft_completed.emit(result)
		EventBus.item_crafted.emit(result, _owner_inventory.get_parent())
		_update_recipe()
		count += 1
	return count


func _consume_ingredients() -> void:
	var search_grid := _to_3x3()
	for row in search_grid:
		for stack in row:
			if not ItemRegistry.is_empty_stack(stack):
				# Find slot in inventory grid and remove one
				for r in grid_size:
					for c in grid_size:
						var gs: Dictionary = grid[r][c]
						if gs.get("id") == stack.get("id") and gs.get("count", 0) > 0:
							gs["count"] -= 1
							if gs["count"] <= 0:
								grid[r][c] = {}
							else:
								grid[r][c] = gs
							break


## Move remaining grid items back to inventory when closing.
func return_items_to_inventory() -> void:
	if _owner_inventory == null:
		return
	for row in grid:
		for stack in row:
			if not ItemRegistry.is_empty_stack(stack):
				_owner_inventory.add_items(stack.get("id", ""), stack.get("count", 1), stack.get("meta", {}))
	clear_grid()


## Check if all required ingredients exist in the grid.
func can_craft() -> bool:
	return _cached_recipe != null
