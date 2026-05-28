## BlockEntity.gd — Base class for interactive blocks (Chest, Furnace, etc.)
## Block entities are stored in BlockEntityManager and keyed by world position.
class_name BlockEntity
extends RefCounted

var world_pos: Vector3i
var type: String = ""

func _init(pos: Vector3i, entity_type: String) -> void:
	world_pos = pos
	type = entity_type

## Called every game tick (20/sec).
func tick(_delta: float) -> void:
	pass

## Serialize to Dictionary for saving.
func serialize() -> Dictionary:
	return {"type": type, "pos": [world_pos.x, world_pos.y, world_pos.z]}

## Restore from saved Dictionary.
func deserialize(data: Dictionary) -> void:
	pass
