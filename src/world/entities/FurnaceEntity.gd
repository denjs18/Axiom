## FurnaceEntity.gd — Smelting block entity.
## Slots: input={id,count,meta}, fuel={id,count,meta}, output={id,count,meta}
class_name FurnaceEntity
extends BlockEntity

var fuel_slot: Dictionary = {}
var input_slot: Dictionary = {}
var output_slot: Dictionary = {}

var fuel_time_remaining: float = 0.0
var cook_time: float = 0.0
var cook_total: float = 10.0
var is_burning: bool = false

signal state_changed(burning: bool)


func _init(pos: Vector3i) -> void:
	super(pos, "furnace")


func tick(delta: float) -> void:
	var had_fuel := is_burning

	# Consume next fuel unit when the current burns out
	if fuel_time_remaining <= 0.0 and not input_slot.is_empty():
		var fval := _get_fuel_time(fuel_slot.get("id", ""))
		if fval > 0.0:
			fuel_time_remaining = fval
			_consume_one(fuel_slot)
			is_burning = true

	if fuel_time_remaining > 0.0:
		fuel_time_remaining -= delta
		if fuel_time_remaining <= 0.0:
			fuel_time_remaining = 0.0
			is_burning = false

	# Cook
	if is_burning and not input_slot.is_empty():
		var recipe := _find_recipe(input_slot.get("id", ""))
		if recipe != null:
			cook_total = float(recipe.time) / 20.0
			cook_time += delta
			if cook_time >= cook_total:
				cook_time = 0.0
				_smelt_item(recipe)
		else:
			cook_time = 0.0
	else:
		cook_time = maxf(cook_time - delta * 2.0, 0.0)

	if had_fuel != is_burning:
		state_changed.emit(is_burning)


func _find_recipe(item_id: String) -> RecipeRegistry.RecipeDef:
	return RecipeRegistry.find_smelting_recipe(item_id)


func _consume_one(slot: Dictionary) -> void:
	var cnt: int = slot.get("count", 1) - 1
	if cnt <= 0:
		slot.clear()
	else:
		slot["count"] = cnt


func _smelt_item(recipe: RecipeRegistry.RecipeDef) -> void:
	_consume_one(input_slot)

	var result_id: String = recipe.result.get("id", "")
	if result_id.is_empty():
		return
	if output_slot.is_empty():
		output_slot = {"id": result_id, "count": 1, "meta": {}}
	elif output_slot.get("id") == result_id:
		var item := ItemRegistry.get_item(result_id)
		var max_stack: int = item.max_stack if item else 64
		if output_slot.get("count", 0) < max_stack:
			output_slot["count"] = output_slot.get("count", 0) + 1


func _get_fuel_time(item_id: String) -> float:
	if item_id.is_empty():
		return 0.0
	var item := ItemRegistry.get_item(item_id)
	if item == null:
		return 0.0
	return float(item.raw.get("fuel_time", 0)) / 20.0


func get_cook_progress() -> float:
	return cook_time / cook_total if cook_total > 0.0 else 0.0


func get_fuel_progress() -> float:
	var total := _get_fuel_time(fuel_slot.get("id", ""))
	if total <= 0.0 and is_burning:
		return fuel_time_remaining / 4.0  # fallback
	return fuel_time_remaining / total if total > 0.0 else 0.0


func is_fuel(item_id: String) -> bool:
	return _get_fuel_time(item_id) > 0.0


func serialize() -> Dictionary:
	var base := super.serialize()
	base["fuel"]           = fuel_slot.duplicate()
	base["input"]          = input_slot.duplicate()
	base["output"]         = output_slot.duplicate()
	base["fuel_remaining"] = fuel_time_remaining
	base["cook_time"]      = cook_time
	return base


func deserialize(data: Dictionary) -> void:
	fuel_slot           = data.get("fuel", {})
	input_slot          = data.get("input", {})
	output_slot         = data.get("output", {})
	fuel_time_remaining = data.get("fuel_remaining", 0.0)
	cook_time           = data.get("cook_time", 0.0)
	is_burning          = fuel_time_remaining > 0.0
