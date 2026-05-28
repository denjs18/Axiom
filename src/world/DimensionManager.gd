## DimensionManager.gd — Handles dimension switching (portals, coordinate scaling).
class_name DimensionManager
extends Node

const NETHER_SCALE := 8  # 1 nether block = 8 overworld blocks

# Nether portal: 4-wide obsidian frame
const NETHER_PORTAL_BLOCK := 1  # placeholder for lit portal block id (to expand)
const OBSIDIAN_ID := 101
const NETHERRACK_ID := 1000

signal dimension_changed(from_dim: String, to_dim: String)

var _current_dim: String = "overworld"
var _manager: ChunkManager
var _portal_cooldown: float = 0.0
const PORTAL_COOLDOWN := 3.0


func setup(manager: ChunkManager) -> void:
	_manager = manager
	_current_dim = GameManager.current_dimension


func _process(delta: float) -> void:
	if _portal_cooldown > 0.0:
		_portal_cooldown -= delta


## Check if a nether portal frame is complete at given position.
## Returns true if a valid 2x3 or 2x4 obsidian frame is found.
func check_nether_portal(world_pos: Vector3i) -> bool:
	if _portal_cooldown > 0.0:
		return false
	# Check X-axis portal (width along X)
	if _is_valid_nether_portal_x(world_pos):
		return true
	# Check Z-axis portal
	if _is_valid_nether_portal_z(world_pos):
		return true
	return false


func _is_valid_nether_portal_x(pos: Vector3i) -> bool:
	# Find leftmost obsidian
	var left := pos.x
	while left > pos.x - 4 and _manager.get_block_at(Vector3i(left - 1, pos.y, pos.z)) == OBSIDIAN_ID:
		left -= 1
	# Count width
	var width := 0
	var x := left
	while _manager.get_block_at(Vector3i(x, pos.y, pos.z)) == OBSIDIAN_ID and width <= 4:
		width += 1; x += 1
	if width < 4:
		return false
	# Check height (4 tall frame)
	for dx in width:
		for dy in 4:
			var check := Vector3i(left + dx, pos.y + dy, pos.z)
			var bid := _manager.get_block_at(check)
			var is_frame := (dx == 0 or dx == width - 1 or dy == 0 or dy == 3)
			if is_frame and bid != OBSIDIAN_ID:
				return false
	return true


func _is_valid_nether_portal_z(pos: Vector3i) -> bool:
	var left := pos.z
	while left > pos.z - 4 and _manager.get_block_at(Vector3i(pos.x, pos.y, left - 1)) == OBSIDIAN_ID:
		left -= 1
	var width := 0
	var z := left
	while _manager.get_block_at(Vector3i(pos.x, pos.y, z)) == OBSIDIAN_ID and width <= 4:
		width += 1; z += 1
	if width < 4:
		return false
	for dz in width:
		for dy in 4:
			var check := Vector3i(pos.x, pos.y + dy, left + dz)
			var bid := _manager.get_block_at(check)
			var is_frame := (dz == 0 or dz == width - 1 or dy == 0 or dy == 3)
			if is_frame and bid != OBSIDIAN_ID:
				return false
	return true


## Teleport player to nether (or back to overworld).
func enter_nether_portal(player_world_pos: Vector3) -> void:
	if _portal_cooldown > 0.0:
		return
	_portal_cooldown = PORTAL_COOLDOWN

	if _current_dim == "overworld":
		var nether_pos := Vector3(
			player_world_pos.x / NETHER_SCALE,
			player_world_pos.y,
			player_world_pos.z / NETHER_SCALE
		)
		_switch_dimension("nether", nether_pos)
	elif _current_dim == "nether":
		var overworld_pos := Vector3(
			player_world_pos.x * NETHER_SCALE,
			player_world_pos.y,
			player_world_pos.z * NETHER_SCALE
		)
		_switch_dimension("overworld", overworld_pos)


## Teleport to The End (fixed spawn near End origin).
func enter_end_portal() -> void:
	if _current_dim != "overworld":
		return
	_switch_dimension("the_end", Vector3(0, 64, 0))


## Return from End to overworld (player spawn).
func exit_end_portal(player_spawn: Vector3) -> void:
	if _current_dim != "the_end":
		return
	_switch_dimension("overworld", player_spawn)


func _switch_dimension(target_dim: String, target_pos: Vector3) -> void:
	var from_dim := _current_dim
	_current_dim = target_dim
	GameManager.current_dimension = target_dim

	# Reload chunk manager for new dimension
	_manager.dimension = target_dim
	_manager.loaded_chunks.clear()
	_manager._renderers.clear()
	_manager._gen_queue.clear()
	_manager._queued.clear()
	# Clear all renderer nodes
	for child in _manager.get_children():
		if child is ChunkRenderer:
			child.queue_free()

	# Teleport player
	var player := GameManager.local_player
	if player and player.has_method("teleport"):
		player.teleport(target_pos)

	dimension_changed.emit(from_dim, target_dim)
	EventBus.player_dimension_changed.emit(GameManager.local_player, from_dim, target_dim)
	print("[DimensionManager] Switched %s → %s at %v" % [from_dim, target_dim, target_pos])
