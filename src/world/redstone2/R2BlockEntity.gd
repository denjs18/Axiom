## R2BlockEntity.gd — Base class for all Redstone 2.0 block entities.
## Provides the 5-phase evaluation contract (Acquire/Calculate/Memory/Emit/Act)
## and port management (input faces, output faces, channel routing).
##
## Lifecycle:
##   1. BlockEntityManager creates via R2Registry.create_entity(block_id, pos)
##   2. _init calls super(pos, type_string) and self-registers with R2Engine
##   3. R2Engine calls phase_*() methods each logic tick
##   4. On block break: BlockEntityManager.remove_entity → _on_removed
class_name R2BlockEntity
extends BlockEntity

# ── Face direction constants ───────────────────────────────────────────────────
const FACE_PX := Vector3i(1, 0, 0)     # East
const FACE_NX := Vector3i(-1, 0, 0)    # West
const FACE_PY := Vector3i(0, 1, 0)     # Up
const FACE_NY := Vector3i(0, -1, 0)    # Down
const FACE_PZ := Vector3i(0, 0, 1)     # South
const FACE_NZ := Vector3i(0, 0, -1)    # North

const ALL_FACES: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

# ── State ─────────────────────────────────────────────────────────────────────

## Primary facing direction for directional blocks (gates, repeaters, etc.).
var facing: Vector3i = FACE_PX

## How to resolve conflicts when multiple sources drive the same input port.
var input_resolve: int = R2Engine.RESOLVE_MAX

## Current logic tick number (set by engine during phase_acquire).
var current_tick: int = 0

## Non-empty when the block is in an error state.
var error: String = ""

# Per-tick signal buffers (channel → Array[R2Signal])
var _inputs: Dictionary = {}

# Active outputs (last-emitted, readable by neighbors during phase_acquire)
var _outputs: Dictionary = {}

# Pending outputs staged in phase_calculate, swapped into _outputs in phase_emit
var _next_outputs: Dictionary = {}

# Per-face input cache (face Vector3i → R2Signal), populated in phase_acquire
var _face_inputs: Dictionary = {}


func _init(pos: Vector3i, entity_type: String) -> void:
	super(pos, entity_type)
	R2Engine.register_block(self)


# ── BlockEntity overrides ─────────────────────────────────────────────────────

## R2Engine drives evaluation — BlockEntityManager.tick() is a no-op here.
func tick(_delta: float) -> void:
	pass


# ── 5-Phase interface ─────────────────────────────────────────────────────────

## Phase 1 — Read previous-tick outputs from connected R2 neighbors.
## Populates _inputs (channel → Array[R2Signal]) and _face_inputs (face → R2Signal).
func phase_acquire(tick: int) -> void:
	current_tick = tick
	_inputs.clear()
	_face_inputs.clear()

	for face in _get_input_faces():
		var nb_pos := world_pos + face
		var nb: R2BlockEntity = R2Engine.get_block(nb_pos)
		if nb == null:
			continue
		var sig := nb._get_output_toward(world_pos)
		if sig == null:
			continue
		_face_inputs[face] = sig
		var ch := sig.channel
		if not _inputs.has(ch):
			_inputs[ch] = []
		(_inputs[ch] as Array).append(sig)


## Phase 2 — Compute new outputs from acquired inputs into _next_outputs.
## Must NOT read from R2Engine (only from _inputs / _face_inputs).
func phase_calculate() -> void:
	pass


## Phase 3 — Commit persistent state (latches, registers, memories).
func phase_memory() -> void:
	pass


## Phase 4 — Swap _next_outputs → _outputs (atomic publish).
func phase_emit() -> void:
	_outputs = _next_outputs.duplicate()
	_next_outputs.clear()


## Phase 5 — Apply world effects (actuators only). May call R2Engine.set_world_block().
func phase_act() -> void:
	pass


# ── Port configuration ────────────────────────────────────────────────────────

## Override to restrict which faces accept input signals.
func _get_input_faces() -> Array:
	return ALL_FACES


## Override to restrict which faces emit output signals.
func _get_output_faces() -> Array:
	return ALL_FACES


## Called when adjacent world changes (block placed/broken nearby).
func on_neighbor_changed(_from_pos: Vector3i) -> void:
	pass


# ── Signal accessors ──────────────────────────────────────────────────────────

## Returns the merged (resolved) input on a channel.
func get_input(channel: int = 0) -> R2Signal:
	var arr: Array = _inputs.get(channel, [])
	return R2Signal.resolve(arr, input_resolve)


## Returns the signal received from a specific face last tick.
func get_face_input(face: Vector3i) -> R2Signal:
	return _face_inputs.get(face, R2Signal.make_off())


## Returns the currently active output on a channel.
func get_output(channel: int = 0) -> R2Signal:
	return _outputs.get(channel, R2Signal.make_off())


## Stage a pending output (called in phase_calculate / phase_memory).
func emit_output(sig: R2Signal, channel: int = 0) -> void:
	_next_outputs[channel] = sig


func emit_bool(v: bool, channel: int = 0) -> void:
	emit_output(R2Signal.make_bool(v, channel, world_pos), channel)


func emit_analog(v: int, channel: int = 0) -> void:
	emit_output(R2Signal.make_analog(v, channel, world_pos), channel)


func emit_event(channel: int = 0) -> void:
	emit_output(R2Signal.make_event(channel, world_pos), channel)


## Returns the output signal directed toward a specific neighbor.
## Only returns non-null if target is in the output faces.
func _get_output_toward(target_pos: Vector3i) -> R2Signal:
	var dir := target_pos - world_pos
	if dir not in _get_output_faces():
		return null
	return get_output(0)


# ── Serialization ─────────────────────────────────────────────────────────────

func serialize() -> Dictionary:
	return {
		"type":   type,
		"facing": [facing.x, facing.y, facing.z],
		"error":  error,
	}


func deserialize(data: Dictionary) -> void:
	error = data.get("error", "")
	var f: Array = data.get("facing", [1, 0, 0])
	if f.size() == 3:
		facing = Vector3i(int(f[0]), int(f[1]), int(f[2]))
	R2Engine.register_block(self)


# ── Debug ─────────────────────────────────────────────────────────────────────

func get_debug_dict() -> Dictionary:
	var ins: Dictionary = {}
	for ch: int in _inputs.keys():
		ins[str(ch)] = get_input(ch).value_str()
	var outs: Dictionary = {}
	for ch: int in _outputs.keys():
		outs[str(ch)] = get_output(ch).value_str()
	return {
		"type":    type,
		"pos":     "%d,%d,%d" % [world_pos.x, world_pos.y, world_pos.z],
		"inputs":  ins,
		"outputs": outs,
		"facing":  "%d,%d,%d" % [facing.x, facing.y, facing.z],
		"error":   error,
		"tick":    current_tick,
	}
