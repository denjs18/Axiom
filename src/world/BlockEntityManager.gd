## BlockEntityManager.gd — Manages all active block entities (chests, furnaces, etc.)
class_name BlockEntityManager
extends Node

# Vector3i → BlockEntity
var _entities: Dictionary = {}

var _tick_timer: float = 0.0
const TICK_RATE := 0.05  # 20 ticks/sec


func _process(delta: float) -> void:
	_tick_timer += delta
	if _tick_timer >= TICK_RATE:
		_tick_timer -= TICK_RATE
		_tick_all(TICK_RATE)


func _tick_all(delta: float) -> void:
	for key in _entities:
		_entities[key].tick(delta)


## Place a new block entity at world position.
func create_entity(world_pos: Vector3i, block_id: int) -> BlockEntity:
	var entity: BlockEntity = null

	# Redstone 2.0 blocks (IDs 4000-4074)
	if R2Registry.is_r2_block(block_id):
		entity = R2Registry.create_entity(block_id, world_pos)
		if entity:
			_entities[world_pos] = entity
		return entity

	match block_id:
		64:  entity = ChestEntity.new(world_pos)    # chest
		65:  entity = ChestEntity.new(world_pos)    # trapped_chest
		67:  entity = ChestEntity.new(world_pos)    # barrel
		61:  entity = FurnaceEntity.new(world_pos)  # furnace
		62:  entity = FurnaceEntity.new(world_pos)  # blast_furnace
		63:  entity = FurnaceEntity.new(world_pos)  # smoker
		_:   return null
	if entity:
		_entities[world_pos] = entity
	return entity


## Get existing entity at position (or null).
func get_entity(world_pos: Vector3i) -> BlockEntity:
	return _entities.get(world_pos)


## Remove entity (block was broken).
func remove_entity(world_pos: Vector3i) -> void:
	_entities.erase(world_pos)


## Save all entities to a dictionary (keyed by "x,y,z").
func serialize() -> Dictionary:
	var result: Dictionary = {}
	for pos in _entities:
		var key := "%d,%d,%d" % [pos.x, pos.y, pos.z]
		result[key] = _entities[pos].serialize()
	return result


## Load entities from saved dictionary.
func deserialize(data: Dictionary) -> void:
	_entities.clear()
	for key in data:
		var parts: PackedStringArray = key.split(",")
		var pos := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
		var saved: Dictionary = data[key]
		var entity_type: String = saved.get("type", "")
		var entity: BlockEntity = null
		# Redstone 2.0 blocks
		if R2Registry.is_r2_type(entity_type):
			entity = R2Registry.create_from_type(entity_type, pos)
		else:
			match entity_type:
				"chest":   entity = ChestEntity.new(pos)
				"furnace": entity = FurnaceEntity.new(pos)
		if entity:
			entity.deserialize(saved)
			_entities[pos] = entity
