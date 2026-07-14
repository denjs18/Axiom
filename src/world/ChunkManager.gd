## ChunkManager.gd — Manages 3D chunk loading/unloading around the player.
class_name ChunkManager
extends Node

const CHUNK_SIZE := 16
const SAVE_DIR   := "user://worlds/"

const DIM_Y_MIN := {"overworld": -8, "nether": 0, "the_end": 0}
const DIM_Y_MAX := {"overworld": 19, "nether": 7, "the_end": 15}

@export var render_distance:          int = 4
@export var vertical_render_distance: int = 2
@export var unload_distance:          int = 7
@export var vertical_unload_distance: int = 4

var world_name: String = ""
var dimension:  String = "overworld"
var world_seed: int    = 0

# "cx,cy,cz" → Chunk
var loaded_chunks: Dictionary = {}
# "cx,cy,cz" → ChunkRenderer node
var _renderers: Dictionary = {}
# Generation queue (Vector3i chunk coords)
var _gen_queue: Array  = []
var _queued:    Dictionary = {}   # keys already queued or in-flight

var _world_generator: WorldGenerator
var _player_chunk:      Vector3i = Vector3i.ZERO
var _last_player_chunk: Vector3i = Vector3i(-999, -999, -999)
var _renderer_scene:    PackedScene = null   # Cached — loaded once

# Thread-safe result queue from worker threads
var _mutex:          Mutex = Mutex.new()
var _pending_chunks: Array = []   # Chunks generated on worker, awaiting main-thread finalization

signal chunk_loaded(chunk_pos: Vector3i)
signal chunk_unloaded(chunk_pos: Vector3i)


func _ready() -> void:
	pass


func initialize(wname: String, wseed: int, dim: String = "overworld") -> void:
	world_name = wname
	world_seed = wseed
	dimension  = dim


func _process(_delta: float) -> void:
	_finalize_pending_chunks()
	_process_gen_queue()


func update_player_position(world_pos: Vector3) -> void:
	var new_chunk := Vector3i(
		floori(world_pos.x / CHUNK_SIZE),
		floori(world_pos.y / CHUNK_SIZE),
		floori(world_pos.z / CHUNK_SIZE)
	)
	if new_chunk == _last_player_chunk:
		return
	_last_player_chunk = new_chunk
	_player_chunk = new_chunk
	_schedule_load_unload()
	_request_collision_for_near_chunks()


func _schedule_load_unload() -> void:
	var cy_min: int = DIM_Y_MIN.get(dimension, -8)
	var cy_max: int = DIM_Y_MAX.get(dimension, 19)

	for dx in range(-render_distance, render_distance + 1):
		for dy in range(-vertical_render_distance, vertical_render_distance + 1):
			for dz in range(-render_distance, render_distance + 1):
				var cp := _player_chunk + Vector3i(dx, dy, dz)
				cp.y = clampi(cp.y, cy_min, cy_max)
				var key := _chunk_key(cp)
				if not loaded_chunks.has(key) and not _queued.has(key):
					_gen_queue.append(cp)
					_queued[key] = true

	_gen_queue.sort_custom(_sort_by_dist_desc)

	# Unload far chunks
	var to_unload: Array = []
	for key in loaded_chunks:
		var cp := _key_to_pos(key)
		if abs(cp.x - _player_chunk.x) > unload_distance or \
		   abs(cp.y - _player_chunk.y) > vertical_unload_distance or \
		   abs(cp.z - _player_chunk.z) > unload_distance:
			to_unload.append(key)
	for key in to_unload:
		_unload_chunk(key)


# Sort farthest-first so pop_back() gives the nearest chunk in O(1).
# pop_front() on a GDScript Array is O(n) — on 100+ entries this wastes time every frame.
func _sort_by_dist_desc(a: Vector3i, b: Vector3i) -> bool:
	return a.distance_squared_to(_player_chunk) > b.distance_squared_to(_player_chunk)


# ── Generation queue — submit to worker threads ────────────────────────────────

func _process_gen_queue() -> void:
	# Limit in-flight tasks so we don't flood the thread pool
	var max_submit := 4
	while not _gen_queue.is_empty() and max_submit > 0:
		var cp: Vector3i = _gen_queue.pop_back()   # O(1) — queue is sorted farthest-first
		var key          := _chunk_key(cp)
		_queued.erase(key)
		if loaded_chunks.has(key):
			continue

		# Try loading from disk on main thread (fast I/O path)
		var saved := _try_load_chunk(cp)
		if saved != null:
			_finalize_chunk(saved)
		else:
			# Generate blocks on a worker thread
			WorkerThreadPool.add_task(_generate_chunk_async.bind(cp))

		max_submit -= 1


func _generate_chunk_async(cp: Vector3i) -> void:
	# ⚠ Runs on a worker thread — NO scene-tree or rendering calls here.
	var chunk := Chunk.new(cp.x, cp.y, cp.z, dimension)
	if _world_generator != null:
		_world_generator.generate_chunk(chunk, world_seed)
	# Light computation is safe here: chunk is privately owned, BlockRegistry
	# packed arrays are read-only after _ready(), FastNoiseLite is already used above.
	LightEngine.compute_sky_light_for_chunk(chunk)
	LightEngine.compute_block_light_for_chunk(chunk)
	chunk.is_generated = true
	_mutex.lock()
	_pending_chunks.append(chunk)
	_mutex.unlock()


const MAX_FINALIZATIONS_PER_FRAME := 4

func _finalize_pending_chunks() -> void:
	_mutex.lock()
	var pending: Array = _pending_chunks.duplicate()
	_pending_chunks.clear()
	_mutex.unlock()
	if pending.is_empty():
		return
	# Nearest chunks first — player sees close terrain appear before distant
	pending.sort_custom(func(a: Chunk, b: Chunk) -> bool:
		return a.chunk_pos.distance_squared_to(_player_chunk) < b.chunk_pos.distance_squared_to(_player_chunk)
	)
	if pending.size() > MAX_FINALIZATIONS_PER_FRAME:
		_mutex.lock()
		_pending_chunks.append_array(pending.slice(MAX_FINALIZATIONS_PER_FRAME))
		_mutex.unlock()
		pending.resize(MAX_FINALIZATIONS_PER_FRAME)
	for chunk: Chunk in pending:
		_finalize_chunk(chunk)


## Generate (or load) a chunk synchronously on the main thread.
## Used only for spawn-point detection — prefer async path for normal gameplay.
func ensure_chunk_sync(cp: Vector3i) -> void:
	var key := _chunk_key(cp)
	if loaded_chunks.has(key):
		return
	var chunk := _try_load_chunk(cp)
	if chunk == null:
		chunk = Chunk.new(cp.x, cp.y, cp.z, dimension)
		if _world_generator != null:
			_world_generator.generate_chunk(chunk, world_seed)
		LightEngine.compute_sky_light_for_chunk(chunk)
		LightEngine.compute_block_light_for_chunk(chunk)
		chunk.is_generated = true
	_finalize_chunk(chunk)


func _finalize_chunk(chunk: Chunk) -> void:
	var key := _chunk_key(chunk.chunk_pos)
	if loaded_chunks.has(key):
		return
	loaded_chunks[key] = chunk
	_spawn_renderer(chunk)
	# Build mesh + collision synchronously for chunks the player is about to walk into.
	# This prevents the 2-3 frame window where a visible mesh has no physics.
	var cp := chunk.chunk_pos
	if (abs(cp.x - _player_chunk.x) <= 1 and
			abs(cp.y - _player_chunk.y) <= 1 and
			abs(cp.z - _player_chunk.z) <= 1):
		if _renderers.has(key):
			(_renderers[key] as ChunkRenderer).force_initial_build()
	chunk_loaded.emit(chunk.chunk_pos)
	EventBus.chunk_loaded.emit(chunk.chunk_pos)


# ── Chunk I/O ──────────────────────────────────────────────────────────────────

func _try_load_chunk(cp: Vector3i) -> Chunk:
	var path := _get_chunk_path(cp)
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var data := file.get_buffer(file.get_length())
	file.close()
	return Chunk.deserialize(data)


func _unload_chunk(key: int) -> void:
	if not loaded_chunks.has(key):
		return
	var chunk: Chunk = loaded_chunks[key]
	_save_chunk(chunk)
	loaded_chunks.erase(key)
	if _renderers.has(key):
		_renderers[key].queue_free()
		_renderers.erase(key)
	chunk_unloaded.emit(chunk.chunk_pos)
	EventBus.chunk_unloaded.emit(chunk.chunk_pos)


func _save_chunk(chunk: Chunk) -> void:
	var path := _get_chunk_path(chunk.chunk_pos)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_buffer(chunk.serialize())
		file.close()


func _spawn_renderer(chunk: Chunk) -> void:
	var key := _chunk_key(chunk.chunk_pos)
	if _renderers.has(key):
		return
	if _renderer_scene == null:
		_renderer_scene = load("res://scenes/world/ChunkRenderer.tscn") as PackedScene
	if _renderer_scene == null:
		return
	var renderer: ChunkRenderer = _renderer_scene.instantiate()
	renderer.setup(chunk, self)
	add_child(renderer)
	_renderers[key] = renderer


# ── Block access ───────────────────────────────────────────────────────────────

func get_block_at(world_pos: Vector3i) -> int:
	var cp    := Chunk.world_to_chunk(world_pos)
	var chunk := get_chunk(cp)
	if chunk == null:
		return 0
	var local := Chunk.world_to_local(world_pos, cp.y)
	return chunk.get_block(local.x, local.y, local.z)


func set_block_at(world_pos: Vector3i, block_id: int, meta: Dictionary = {}) -> void:
	var cp    := Chunk.world_to_chunk(world_pos)
	var chunk := get_chunk(cp)
	if chunk == null:
		return
	var local := Chunk.world_to_local(world_pos, cp.y)
	chunk.set_block(local.x, local.y, local.z, block_id)
	if not meta.is_empty():
		chunk.set_block_meta(local.x, local.y, local.z, meta)
	_mark_dirty(cp, true)   # own chunk: rebuild collision too
	# Neighbours: visual only
	if local.x == 0:  _mark_dirty(cp + Vector3i(-1, 0, 0))
	elif local.x == 15: _mark_dirty(cp + Vector3i(1, 0, 0))
	if local.z == 0:  _mark_dirty(cp + Vector3i(0, 0, -1))
	elif local.z == 15: _mark_dirty(cp + Vector3i(0, 0, 1))
	if local.y == 0:  _mark_dirty(cp + Vector3i(0, -1, 0))
	elif local.y == 15: _mark_dirty(cp + Vector3i(0, 1, 0))


func get_chunk(cp: Vector3i) -> Chunk:
	return loaded_chunks.get(_chunk_key(cp))


func _mark_dirty(cp: Vector3i, with_collision: bool = false) -> void:
	var key := _chunk_key(cp)
	if _renderers.has(key):
		_renderers[key].mark_dirty(with_collision)


## When the player moves to a new chunk, ask nearby renderers to build collision
## if they haven't yet (they may have cleared _col_dirty when they were out of range).
func _request_collision_for_near_chunks() -> void:
	for dx in range(-2, 3):
		for dy in range(-1, 2):
			for dz in range(-2, 3):
				var key := _chunk_key(_player_chunk + Vector3i(dx, dy, dz))
				if _renderers.has(key):
					(_renderers[key] as ChunkRenderer).request_collision()


# ── Raycast ────────────────────────────────────────────────────────────────────

func raycast(origin: Vector3, direction: Vector3, max_distance: float = 6.0) -> Dictionary:
	var pos      := origin
	var step     := direction.normalized() * 0.05
	var traveled := 0.0
	var prev_pos := Vector3i(floori(pos.x), floori(pos.y), floori(pos.z))
	while traveled < max_distance:
		pos      += step
		traveled += 0.05
		var block_pos := Vector3i(floori(pos.x), floori(pos.y), floori(pos.z))
		var bid       := get_block_at(block_pos)
		if bid != 0 and not BlockRegistry.is_fluid(bid):
			var normal := (block_pos - prev_pos).sign()
			return {"hit": true, "position": block_pos, "normal": -normal, "block_id": bid}
		prev_pos = block_pos
	return {"hit": false}


# ── Helpers ────────────────────────────────────────────────────────────────────

# Pack (cx, cy, cz) into a single int64: 15 bits each with +16384 offset.
# Supports chunk coords in range ±16383 (±262 144 blocks per axis).
func _chunk_key(cp: Vector3i) -> int:
	return ((cp.x + 16384) & 0x7FFF) \
		| (((cp.y + 16384) & 0x7FFF) << 15) \
		| (((cp.z + 16384) & 0x7FFF) << 30)


func _key_to_pos(key: int) -> Vector3i:
	return Vector3i(
		(key & 0x7FFF) - 16384,
		((key >> 15) & 0x7FFF) - 16384,
		((key >> 30) & 0x7FFF) - 16384
	)


func _get_chunk_path(cp: Vector3i) -> String:
	return SAVE_DIR + world_name + "/" + dimension + "/c_%d_%d_%d.bin" % [cp.x, cp.y, cp.z]


func save_all_chunks() -> void:
	for key in loaded_chunks:
		_save_chunk(loaded_chunks[key])
	print("[ChunkManager] Saved %d chunks." % loaded_chunks.size())
