## DimensionManager.gd — Portal detection/ignition and dimension travel.
## Nether portals: obsidian frame lit with flint & steel (interior 2-4 wide, 3-5 tall).
## End portals: found in End shrines; walking in teleports to The End.
class_name DimensionManager
extends Node

const NETHER_SCALE := 8   # 1 nether block = 8 overworld blocks

const OBSIDIAN_ID      := 101
const NETHER_PORTAL_ID := 93
const END_PORTAL_ID    := 94

const MIN_INNER_W := 2
const MAX_INNER_W := 4
const MIN_INNER_H := 3
const MAX_INNER_H := 5

signal dimension_changed(from_dim: String, to_dim: String)

var _manager: ChunkManager
var _portal_cooldown: float = 0.0
const PORTAL_COOLDOWN := 4.0

# Where the player entered a nether portal in each dimension (return anchor)
var _overworld_anchor: Vector3 = Vector3.ZERO


func setup(manager: ChunkManager) -> void:
	_manager = manager


func _process(delta: float) -> void:
	if _portal_cooldown > 0.0:
		_portal_cooldown -= delta


func can_travel() -> bool:
	return _portal_cooldown <= 0.0


# ── Portal ignition (flint & steel on obsidian) ────────────────────────────────

## Try to light a nether portal. `air_pos` is the air cell adjacent to the
## clicked obsidian face. Returns true if a portal was created.
func try_ignite(air_pos: Vector3i) -> bool:
	if _manager.get_block_at(air_pos) != 0:
		return false
	# Try both frame orientations
	for axis in [Vector3i(1, 0, 0), Vector3i(0, 0, 1)]:
		var cells := _detect_frame_interior(air_pos, axis)
		if not cells.is_empty():
			for cell in cells:
				_manager.set_block_at(cell, NETHER_PORTAL_ID)
			EventBus.show_message.emit("Le portail s'embrase...", 3.0)
			return true
	return false


## Returns all interior cells if `start` sits inside a valid obsidian frame
## whose width axis is `axis`; empty array otherwise.
func _detect_frame_interior(start: Vector3i, axis: Vector3i) -> Array:
	# Fall to the interior floor
	var base := start
	var guard := 0
	while _manager.get_block_at(base + Vector3i(0, -1, 0)) == 0 and guard < MAX_INNER_H:
		base += Vector3i(0, -1, 0)
		guard += 1
	if _manager.get_block_at(base + Vector3i(0, -1, 0)) != OBSIDIAN_ID:
		return []
	# Find the left edge along the axis
	var left := base
	guard = 0
	while _manager.get_block_at(left - axis) == 0 and guard < MAX_INNER_W:
		left -= axis
		guard += 1
	if _manager.get_block_at(left - axis) != OBSIDIAN_ID:
		return []
	# Measure interior width
	var width := 0
	var probe := left
	while _manager.get_block_at(probe) == 0 and width <= MAX_INNER_W:
		width += 1
		probe += axis
	if _manager.get_block_at(probe) != OBSIDIAN_ID:
		return []
	if width < MIN_INNER_W or width > MAX_INNER_W:
		return []
	# Measure interior height (all columns must match)
	var height := 0
	var done := false
	while height <= MAX_INNER_H and not done:
		for c in width:
			var cell := left + axis * c + Vector3i(0, height, 0)
			var bid := _manager.get_block_at(cell)
			if bid == OBSIDIAN_ID:
				done = true
				break
			if bid != 0:
				return []   # something else inside the frame
		if not done:
			height += 1
	if height < MIN_INNER_H or height > MAX_INNER_H:
		return []
	# Validate the frame: bottom, top, and both sides must be obsidian
	for c in width:
		if _manager.get_block_at(left + axis * c + Vector3i(0, -1, 0)) != OBSIDIAN_ID:
			return []
		if _manager.get_block_at(left + axis * c + Vector3i(0, height, 0)) != OBSIDIAN_ID:
			return []
	for r in height:
		if _manager.get_block_at(left - axis + Vector3i(0, r, 0)) != OBSIDIAN_ID:
			return []
		if _manager.get_block_at(left + axis * width + Vector3i(0, r, 0)) != OBSIDIAN_ID:
			return []
	# Collect interior cells
	var cells: Array = []
	for r in height:
		for c in width:
			cells.append(left + axis * c + Vector3i(0, r, 0))
	return cells


# ── Travel ─────────────────────────────────────────────────────────────────────

## Player stood in a nether portal long enough — travel between overworld/nether.
func travel_nether(player_world_pos: Vector3) -> void:
	if _portal_cooldown > 0.0:
		return
	_portal_cooldown = PORTAL_COOLDOWN
	var dim := GameManager.current_dimension
	if dim == "overworld":
		_overworld_anchor = player_world_pos
		var target := Vector3(
			player_world_pos.x / NETHER_SCALE, 0, player_world_pos.z / NETHER_SCALE)
		_switch_dimension("nether", target, true)
	elif dim == "nether":
		var target := Vector3(
			player_world_pos.x * NETHER_SCALE, 0, player_world_pos.z * NETHER_SCALE)
		if _overworld_anchor != Vector3.ZERO:
			target = _overworld_anchor
		_switch_dimension("overworld", target, true)


## Player stood in an End portal — travel to The End (or back home).
func travel_end(player_world_pos: Vector3) -> void:
	if _portal_cooldown > 0.0:
		return
	_portal_cooldown = PORTAL_COOLDOWN
	var dim := GameManager.current_dimension
	if dim == "the_end":
		var player := GameManager.local_player
		var back: Vector3 = player.respawn_position if player != null else Vector3(8, 80, 8)
		_switch_dimension("overworld", back, false)
	else:
		_overworld_anchor = player_world_pos
		_switch_dimension("the_end", Vector3(8, 66, 8), false)


func _switch_dimension(target_dim: String, target_pos: Vector3, build_return_portal: bool) -> void:
	var from_dim := GameManager.current_dimension
	GameManager.current_dimension = target_dim

	# Unload current dimension chunks (saving them first)
	_manager.save_all_chunks()
	var to_free: Array = []
	for key in _manager.loaded_chunks.keys():
		to_free.append(key)
	for key in to_free:
		if _manager._renderers.has(key):
			_manager._renderers[key].queue_free()
	_manager.loaded_chunks.clear()
	_manager._renderers.clear()
	_manager._gen_queue.clear()
	_manager._queued.clear()
	_manager.dimension = target_dim
	_manager._last_player_chunk = Vector3i(-999, -999, -999)

	# Re-target the generator + LOD for the new dimension
	var world := GameManager.world_node
	if world != null:
		var wg = world.get("world_generator")
		if wg != null:
			wg.initialize(GameManager.world_seed, target_dim)
			wg.generation_type = GameManager.generation_type
		var lod = world.get("lod_manager")
		if lod != null:
			lod.clear_all()
			lod.initialize(GameManager.current_world_name, target_dim, wg)

	# Load the arrival area synchronously and find safe ground
	var arrive := _prepare_arrival(target_dim, target_pos, build_return_portal)

	# Teleport the player
	var player := GameManager.local_player
	if player != null and player.has_method("teleport"):
		player.teleport(arrive)

	dimension_changed.emit(from_dim, target_dim)
	EventBus.player_dimension_changed.emit(player, from_dim, target_dim)
	EventBus.show_message.emit(_dim_label(target_dim), 3.5)
	print("[DimensionManager] %s → %s at %v" % [from_dim, target_dim, arrive])


func _dim_label(dim: String) -> String:
	match dim:
		"nether":    return "— Le Nether —"
		"the_end":   return "— L'End —"
		_:           return "— Le Monde —"


## Sync-load chunks at the destination, find (or carve) a safe spot,
## optionally build a return portal, and force collision meshes.
func _prepare_arrival(dim: String, target: Vector3, build_portal: bool) -> Vector3:
	var tx := floori(target.x)
	var tz := floori(target.z)
	var cx := floori(float(tx) / 16.0)
	var cz := floori(float(tz) / 16.0)

	var cy_min: int = ChunkManager.DIM_Y_MIN.get(dim, -8)
	var cy_max: int = ChunkManager.DIM_Y_MAX.get(dim, 19)

	# Load the full column of chunks at the destination (3×3 columns)
	for dcx in range(-1, 2):
		for dcz in range(-1, 2):
			for cy in range(cy_min, cy_max + 1):
				_manager.ensure_chunk_sync(Vector3i(cx + dcx, cy, cz + dcz))

	# Find a safe standing spot: solid ground with 2 air above
	var stand_y := _find_safe_y(tx, tz, dim)
	if stand_y == -9999:
		# Carve a pocket with a floor
		stand_y = 64 if dim != "nether" else 70
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				_manager.set_block_at(Vector3i(tx + dx, stand_y - 1, tz + dz), OBSIDIAN_ID)
				for dy in range(0, 4):
					_manager.set_block_at(Vector3i(tx + dx, stand_y + dy, tz + dz), 0)

	if build_portal:
		_build_return_portal(Vector3i(tx + 2, stand_y, tz))

	# Force collision for the chunks around the arrival point
	var world := GameManager.world_node
	if world != null and world.has_method("prepare_respawn_area"):
		world.prepare_respawn_area(Vector3(tx, stand_y, tz))

	return Vector3(tx + 0.5, float(stand_y) + 0.2, tz + 0.5)


func _find_safe_y(wx: int, wz: int, dim: String) -> int:
	var y_top := 120 if dim == "nether" else 200
	var y_bot := 8 if dim == "nether" else 0
	for y in range(y_top, y_bot, -1):
		var ground := _manager.get_block_at(Vector3i(wx, y - 1, wz))
		if ground == 0 or BlockRegistry.is_fluid(ground):
			continue
		if _manager.get_block_at(Vector3i(wx, y, wz)) == 0 \
				and _manager.get_block_at(Vector3i(wx, y + 1, wz)) == 0:
			return y
	return -9999


## Standing frame with lit portal right next to the arrival point.
func _build_return_portal(base: Vector3i) -> void:
	# Frame: 4 wide × 5 tall (interior 2×3) in the X plane
	for dx in range(0, 4):
		for dy in range(0, 5):
			var edge := dx == 0 or dx == 3 or dy == 0 or dy == 4
			var pos := base + Vector3i(dx, dy, 0)
			if edge:
				_manager.set_block_at(pos, OBSIDIAN_ID)
			else:
				_manager.set_block_at(pos, NETHER_PORTAL_ID)
	# Clear space in front of the portal
	for dx in range(0, 4):
		for dy in range(1, 4):
			for dz in [1, 2]:
				var pos := base + Vector3i(dx, dy, dz)
				if _manager.get_block_at(pos) != 0:
					_manager.set_block_at(pos, 0)
