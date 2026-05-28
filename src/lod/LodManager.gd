## LodManager.gd — Manages LOD tile lifecycle alongside the normal ChunkManager.
## LOD1: one tile per chunk column (16×16 blocks). Visible between render_distance and lod1_distance.
## LOD2: one tile per 4×4 chunk block (64×64 blocks). Visible between lod1_distance and lod2_distance.
## Generation is async (WorkerThreadPool); results are cached to disk.
class_name LodManager
extends Node

const SAVE_DIR := "user://worlds/"

var _world_name:      String        = ""
var _dimension:       String        = "overworld"
var _world_generator: WorldGenerator = null

# tile_key → LodTile (loaded tiles)
var _lod1_tiles: Dictionary = {}
var _lod2_tiles: Dictionary = {}

# tile_key → LodRenderer node
var _lod1_renderers: Dictionary = {}
var _lod2_renderers: Dictionary = {}

# Tiles currently in the submission queue or being generated on a worker thread
var _queued_lod1: Dictionary = {}
var _queued_lod2: Dictionary = {}

# Deferred submission queues (sorted farthest-first so pop_back = closest)
var _lod1_queue: Array = []
var _lod2_queue: Array = []

# Thread-safe result bucket — worker threads push finished tiles here
var _mutex:   Mutex = Mutex.new()
var _pending: Array = []   # LodTile[]

var _player_chunk:      Vector2i = Vector2i.ZERO
var _last_player_chunk: Vector2i = Vector2i(-99999, -99999)

# Per-frame submission budget (caps file-system and thread-pool pressure)
const MAX_LOD1_DRAIN_PER_FRAME := 8
const MAX_LOD2_DRAIN_PER_FRAME := 4
const MAX_FINALIZE_PER_FRAME   := 4


func initialize(wname: String, dim: String, gen: WorldGenerator) -> void:
	_world_name      = wname
	_dimension       = dim
	_world_generator = gen


func update_player_position(world_pos: Vector3) -> void:
	if not LodSettings.lod_enabled:
		return
	var cx := floori(world_pos.x / 16.0)
	var cz := floori(world_pos.z / 16.0)
	var nc := Vector2i(cx, cz)
	if nc == _last_player_chunk:
		return
	_last_player_chunk = nc
	_player_chunk      = nc
	_schedule_lod1()
	_schedule_lod2()
	_unload_far_tiles()


func _process(_delta: float) -> void:
	if not LodSettings.lod_enabled:
		return
	_drain_lod1_queue()
	_drain_lod2_queue()
	_finalize_pending()


# ── Scheduling ─────────────────────────────────────────────────────────────────

func _schedule_lod1() -> void:
	var rd  := LodSettings.render_distance
	var ld1 := LodSettings.lod1_distance
	var new_tiles: Array = []
	for dx in range(-ld1, ld1 + 1):
		for dz in range(-ld1, ld1 + 1):
			var dist := maxi(absi(dx), absi(dz))
			if dist <= rd or dist > ld1:
				continue
			var tx  := _player_chunk.x + dx
			var tz  := _player_chunk.y + dz
			var key := _lod1_key(tx, tz)
			if _lod1_tiles.has(key) or _queued_lod1.has(key):
				continue
			_queued_lod1[key] = true
			new_tiles.append(Vector2i(tx, tz))

	if new_tiles.is_empty():
		return
	# Sort farthest-first → pop_back() gives closest (highest priority)
	var pc := _player_chunk
	new_tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return maxi(absi(a.x - pc.x), absi(a.y - pc.y)) > \
			   maxi(absi(b.x - pc.x), absi(b.y - pc.y))
	)
	_lod1_queue.append_array(new_tiles)


func _schedule_lod2() -> void:
	var ld1  := LodSettings.lod1_distance
	var ld2  := LodSettings.lod2_distance
	var cpt  := LodSettings.LOD2_CHUNKS_PER_TILE
	var ptx  := floori(float(_player_chunk.x) / float(cpt))
	var ptz  := floori(float(_player_chunk.y) / float(cpt))
	var tld1 := ceili(float(ld1) / float(cpt))
	var tld2 := ceili(float(ld2) / float(cpt))
	var new_tiles: Array = []
	for dtx in range(-tld2, tld2 + 1):
		for dtz in range(-tld2, tld2 + 1):
			var dist := maxi(absi(dtx), absi(dtz))
			if dist <= tld1 or dist > tld2:
				continue
			var tx  := ptx + dtx
			var tz  := ptz + dtz
			var key := _lod2_key(tx, tz)
			if _lod2_tiles.has(key) or _queued_lod2.has(key):
				continue
			_queued_lod2[key] = true
			new_tiles.append(Vector2i(tx, tz))

	if new_tiles.is_empty():
		return
	var pc := _player_chunk
	var c  := cpt
	new_tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := maxi(absi(a.x * c - pc.x), absi(a.y * c - pc.y))
		var db := maxi(absi(b.x * c - pc.x), absi(b.y * c - pc.y))
		return da > db
	)
	_lod2_queue.append_array(new_tiles)


# ── Queue drain (rate-limited, spreads I/O across frames) ─────────────────────

func _drain_lod1_queue() -> void:
	var budget := MAX_LOD1_DRAIN_PER_FRAME
	while not _lod1_queue.is_empty() and budget > 0:
		var pos: Vector2i = _lod1_queue.pop_back()
		var key           := _lod1_key(pos.x, pos.y)
		if _lod1_tiles.has(key):
			_queued_lod1.erase(key)
			continue
		_submit_lod1(pos.x, pos.y, key)
		budget -= 1


func _drain_lod2_queue() -> void:
	var budget := MAX_LOD2_DRAIN_PER_FRAME
	while not _lod2_queue.is_empty() and budget > 0:
		var pos: Vector2i = _lod2_queue.pop_back()
		var key           := _lod2_key(pos.x, pos.y)
		if _lod2_tiles.has(key):
			_queued_lod2.erase(key)
			continue
		_submit_lod2(pos.x, pos.y, key)
		budget -= 1


# ── Submission (cache check + async generation) ────────────────────────────────

func _submit_lod1(tx: int, tz: int, key: int) -> void:
	if LodSettings.cache_enabled:
		var path := _get_cache_path(1, tx, tz)
		if FileAccess.file_exists(path):
			var file := FileAccess.open(path, FileAccess.READ)
			if file:
				var tile := LodTile.deserialize(file.get_buffer(file.get_length()))
				file.close()
				if tile != null:
					_queued_lod1.erase(key)
					_finalize_tile(tile)
					return

	if _world_generator == null:
		_queued_lod1.erase(key)
		return
	var gen  := _world_generator
	var mtx  := _mutex
	var pend := _pending
	WorkerThreadPool.add_task(func() -> void:
		var tile := LodTileGenerator.generate_lod1(tx, tz, gen)
		mtx.lock()
		pend.append(tile)
		mtx.unlock()
	)


func _submit_lod2(tx: int, tz: int, key: int) -> void:
	if LodSettings.cache_enabled:
		var path := _get_cache_path(2, tx, tz)
		if FileAccess.file_exists(path):
			var file := FileAccess.open(path, FileAccess.READ)
			if file:
				var tile := LodTile.deserialize(file.get_buffer(file.get_length()))
				file.close()
				if tile != null:
					_queued_lod2.erase(key)
					_finalize_tile(tile)
					return

	if _world_generator == null:
		_queued_lod2.erase(key)
		return
	var gen  := _world_generator
	var mtx  := _mutex
	var pend := _pending
	WorkerThreadPool.add_task(func() -> void:
		var tile := LodTileGenerator.generate_lod2(tx, tz, gen)
		mtx.lock()
		pend.append(tile)
		mtx.unlock()
	)


# ── Finalization (main thread only) ───────────────────────────────────────────

func _finalize_pending() -> void:
	_mutex.lock()
	var batch: Array = _pending.duplicate()
	_pending.clear()
	_mutex.unlock()
	if batch.is_empty():
		return

	# Sort closest-first so the player sees nearby tiles appear first
	var pc := _player_chunk
	batch.sort_custom(func(a: LodTile, b: LodTile) -> bool:
		var oa := a.get_world_origin_xz()
		var ob := b.get_world_origin_xz()
		var da := maxi(absi(oa.x / 16 - pc.x), absi(oa.y / 16 - pc.y))
		var db := maxi(absi(ob.x / 16 - pc.x), absi(ob.y / 16 - pc.y))
		return da < db
	)

	var count := 0
	for tile: LodTile in batch:
		if count >= MAX_FINALIZE_PER_FRAME:
			_mutex.lock()
			_pending.append_array(batch.slice(count))
			_mutex.unlock()
			break
		_finalize_tile(tile)
		count += 1


func _finalize_tile(tile: LodTile) -> void:
	if tile == null:
		return
	if tile.lod_level == 1:
		var key := _lod1_key(tile.tile_pos.x, tile.tile_pos.y)
		_queued_lod1.erase(key)
		if _lod1_tiles.has(key):
			return
		_lod1_tiles[key] = tile
		_spawn_renderer(tile, _lod1_renderers, key)
		if LodSettings.cache_enabled:
			_save_tile_async(tile)
	else:
		var key := _lod2_key(tile.tile_pos.x, tile.tile_pos.y)
		_queued_lod2.erase(key)
		if _lod2_tiles.has(key):
			return
		_lod2_tiles[key] = tile
		_spawn_renderer(tile, _lod2_renderers, key)
		if LodSettings.cache_enabled:
			_save_tile_async(tile)


func _spawn_renderer(tile: LodTile, renderers: Dictionary, key: int) -> void:
	if renderers.has(key):
		return
	var renderer := LodRenderer.new()
	add_child(renderer)
	renderer.setup(tile, _compute_skip_skirts(tile))
	renderers[key] = renderer


func _compute_skip_skirts(tile: LodTile) -> int:
	# Suppress skirts on inner edges (the edges that face toward the player/LOD0 area).
	# bit0=west  bit1=east  bit2=north  bit3=south
	var skip := 0
	var pc   := _player_chunk
	var tdx: int
	var tdz: int
	if tile.lod_level == 1:
		tdx = tile.tile_pos.x - pc.x
		tdz = tile.tile_pos.y - pc.y
	else:
		var cpt := LodSettings.LOD2_CHUNKS_PER_TILE
		var ptx := floori(float(pc.x) / float(cpt))
		var ptz := floori(float(pc.y) / float(cpt))
		tdx = tile.tile_pos.x - ptx
		tdz = tile.tile_pos.y - ptz

	# Tile is east of player  → its west edge is inner → suppress west skirt
	if tdx > 0:  skip |= 1
	# Tile is west of player  → its east edge is inner → suppress east skirt
	if tdx < 0:  skip |= 2
	# Tile is south of player → its north edge is inner → suppress north skirt
	if tdz > 0:  skip |= 4
	# Tile is north of player → its south edge is inner → suppress south skirt
	if tdz < 0:  skip |= 8
	return skip


# ── Unloading ─────────────────────────────────────────────────────────────────

func _unload_far_tiles() -> void:
	var rd   := LodSettings.render_distance
	var ld1  := LodSettings.lod1_distance
	var ld2  := LodSettings.lod2_distance
	var cpt  := LodSettings.LOD2_CHUNKS_PER_TILE
	var pc   := _player_chunk
	var ptx  := floori(float(pc.x) / float(cpt))
	var ptz  := floori(float(pc.y) / float(cpt))
	var tld2 := ceili(float(ld2) / float(cpt))

	var to_remove: Array = []

	for key in _lod1_tiles:
		var pos := _lod1_pos(key)
		var dist := maxi(absi(pos.x - pc.x), absi(pos.y - pc.y))
		# Remove if inside render_distance (real chunks cover it) or beyond LOD1 range
		if dist <= rd or dist > ld1 + 2:
			to_remove.append(key)
	for key in to_remove:
		_lod1_tiles.erase(key)
		if _lod1_renderers.has(key):
			_lod1_renderers[key].queue_free()
			_lod1_renderers.erase(key)

	to_remove.clear()
	for key in _lod2_tiles:
		var pos  := _lod2_pos(key)
		var dist := maxi(absi(pos.x - ptx), absi(pos.y - ptz))
		if dist > tld2 + 1:
			to_remove.append(key)
	for key in to_remove:
		_lod2_tiles.erase(key)
		if _lod2_renderers.has(key):
			_lod2_renderers[key].queue_free()
			_lod2_renderers.erase(key)


# ── Cache I/O (async write so disk writes don't stall the main thread) ────────

func _save_tile_async(tile: LodTile) -> void:
	var path := _get_cache_path(tile.lod_level, tile.tile_pos.x, tile.tile_pos.y)
	var data := tile.serialize()
	WorkerThreadPool.add_task(func() -> void:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_buffer(data)
			file.close()
	)


func _get_cache_path(level: int, tx: int, tz: int) -> String:
	return SAVE_DIR + _world_name + "/" + _dimension + \
		   "/lod/lod%d_%d_%d.bin" % [level, tx, tz]


# ── Key packing (15-bit each, ±16383 range) ────────────────────────────────────

func _lod1_key(tx: int, tz: int) -> int:
	return ((tx + 16384) & 0x7FFF) | (((tz + 16384) & 0x7FFF) << 15)

func _lod1_pos(key: int) -> Vector2i:
	return Vector2i((key & 0x7FFF) - 16384, ((key >> 15) & 0x7FFF) - 16384)

func _lod2_key(tx: int, tz: int) -> int:
	return ((tx + 4096) & 0x1FFF) | (((tz + 4096) & 0x1FFF) << 13)

func _lod2_pos(key: int) -> Vector2i:
	return Vector2i((key & 0x1FFF) - 4096, ((key >> 13) & 0x1FFF) - 4096)


## Debug info string for HUD.
func get_debug_info() -> String:
	return "LOD1: %d tiles  LOD2: %d tiles  queue: %d/%d" % [
		_lod1_tiles.size(), _lod2_tiles.size(),
		_lod1_queue.size(), _lod2_queue.size()
	]
