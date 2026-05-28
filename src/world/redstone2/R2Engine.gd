## R2Engine.gd — Redstone 2.0 logic engine (autoload singleton).
## Runs a 5-phase deterministic tick cycle at TPS (default 10/sec).
## Phases per tick: Acquire → Calculate → Memory → Emit → Act.
##
## All R2BlockEntity instances self-register here when created.
class_name R2Engine
extends Node

# ── Conflict resolution strategy constants ────────────────────────────────────
const RESOLVE_PRIORITY := 0   # highest-priority source wins
const RESOLVE_LOCAL    := 1   # first connected source wins
const RESOLVE_MAX      := 2   # highest analog value wins
const RESOLVE_MIN      := 3   # lowest analog value wins
const RESOLVE_SUM      := 4   # sum, clamped to 255
const RESOLVE_AVG      := 5   # arithmetic mean

# ── Tick timing ───────────────────────────────────────────────────────────────
const TPS           := 10
const TICK_INTERVAL := 1.0 / TPS

var _tick_accum:   float = 0.0
var _current_tick: int   = 0

# ── Block registry ────────────────────────────────────────────────────────────
## All active R2 block entities, keyed by world position.
var _blocks: Dictionary = {}   # Vector3i → R2BlockEntity

# ── World access ──────────────────────────────────────────────────────────────
## Set by World scene when it loads; used by sensors and actuators.
var _chunk_manager = null

# ── Debug / overlay ───────────────────────────────────────────────────────────
var debug_enabled: bool = false
signal debug_toggled(enabled: bool)

# ── Neighbor directions ───────────────────────────────────────────────────────
const DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

# ── R2-specific signals (added to EventBus pattern) ───────────────────────────
signal r2_output_changed(pos: Vector3i, channel: int, sig: R2Signal)
signal r2_block_error(pos: Vector3i, error_msg: String)
signal r2_block_registered(pos: Vector3i, entity_type: String)
signal r2_block_unregistered(pos: Vector3i)


func _ready() -> void:
	EventBus.block_placed.connect(_on_block_placed)
	EventBus.block_broken.connect(_on_block_broken)


func _physics_process(delta: float) -> void:
	_tick_accum += delta
	while _tick_accum >= TICK_INTERVAL:
		_tick_accum -= TICK_INTERVAL
		_evaluate_tick()


# ── Core 5-phase tick ─────────────────────────────────────────────────────────

func _evaluate_tick() -> void:
	_current_tick += 1
	var all_blocks: Array = _blocks.values()
	if all_blocks.is_empty():
		return

	# Phase 1 — Acquire: each block reads its neighbors' previous outputs.
	for b in all_blocks:
		(b as R2BlockEntity).phase_acquire(_current_tick)

	# Phase 2 — Calculate: compute new outputs from acquired inputs.
	for b in all_blocks:
		(b as R2BlockEntity).phase_calculate()

	# Phase 3 — Memory: validate persistent state changes (latches, registers).
	for b in all_blocks:
		(b as R2BlockEntity).phase_memory()

	# Phase 4 — Emit: swap pending outputs into active outputs.
	for b in all_blocks:
		(b as R2BlockEntity).phase_emit()

	# Phase 5 — Act: apply world effects (set blocks, move pistons, etc.).
	for b in all_blocks:
		(b as R2BlockEntity).phase_act()


# ── Block registry API ────────────────────────────────────────────────────────

func register_block(entity: R2BlockEntity) -> void:
	_blocks[entity.world_pos] = entity
	r2_block_registered.emit(entity.world_pos, entity.type)


func unregister_block(world_pos: Vector3i) -> void:
	if _blocks.has(world_pos):
		_blocks.erase(world_pos)
		r2_block_unregistered.emit(world_pos)


func get_block(world_pos: Vector3i) -> R2BlockEntity:
	return _blocks.get(world_pos)


func get_output_at(world_pos: Vector3i, channel: int = 0) -> R2Signal:
	var b: R2BlockEntity = _blocks.get(world_pos)
	if b == null:
		return R2Signal.make_off()
	return b.get_output(channel)


func get_current_tick() -> int:
	return _current_tick


# ── World access ──────────────────────────────────────────────────────────────

func set_chunk_manager(cm) -> void:
	_chunk_manager = cm


func get_block_id(world_pos: Vector3i) -> int:
	if _chunk_manager == null:
		return 0
	return _chunk_manager.get_block_at(world_pos)


func set_world_block(world_pos: Vector3i, block_id: int) -> void:
	if _chunk_manager != null:
		_chunk_manager.set_block_at(world_pos, block_id)


func get_chunk_manager():
	return _chunk_manager


# ── Neighbor notification ─────────────────────────────────────────────────────

func notify_neighbors(pos: Vector3i) -> void:
	for d in DIRS:
		var b: R2BlockEntity = _blocks.get(pos + d)
		if b != null:
			b.on_neighbor_changed(pos)


func _on_block_placed(pos: Vector3i, _bid: int, _meta: Dictionary) -> void:
	notify_neighbors(pos)


func _on_block_broken(pos: Vector3i, _bid: int, _player) -> void:
	_blocks.erase(pos)
	notify_neighbors(pos)


# ── Debug ─────────────────────────────────────────────────────────────────────

func toggle_debug() -> void:
	debug_enabled = not debug_enabled
	debug_toggled.emit(debug_enabled)


func get_debug_info() -> String:
	return "R2 blocks: %d  tick: %d  TPS: %d" % [_blocks.size(), _current_tick, TPS]


## Returns all registered R2 blocks within radius of a world position.
func get_blocks_near(center: Vector3, radius: float) -> Array:
	var result: Array = []
	for pos: Vector3i in _blocks.keys():
		if Vector3(pos).distance_to(center) <= radius:
			result.append(_blocks[pos])
	return result


## Loop detection — returns true if a combinatorial cycle exists at this position.
func detect_loop(start_pos: Vector3i) -> bool:
	var visited: Dictionary = {}
	var stack: Array = [start_pos]
	while not stack.is_empty():
		var pos: Vector3i = stack.pop_back()
		if visited.has(pos):
			return true
		visited[pos] = true
		var b: R2BlockEntity = _blocks.get(pos)
		if b == null:
			continue
		for face in b._get_output_faces():
			var nb_pos := pos + face
			if _blocks.has(nb_pos):
				stack.append(nb_pos)
	return false
