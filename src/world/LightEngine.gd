## LightEngine.gd — Sky and block light propagation.
## compute_sky_light_for_chunk and compute_block_light_for_chunk are static so
## they can be called safely from WorkerThreadPool tasks (no scene-tree access,
## only PackedArray reads/writes on the chunk that is privately owned by that task).
class_name LightEngine
extends Node

const CHUNK_SIZE := 16
const MAX_LIGHT  := 15

var _manager: ChunkManager


func setup(manager: ChunkManager) -> void:
	_manager = manager


## Top-down sky light scan.  Called on the worker thread during chunk generation.
static func compute_sky_light_for_chunk(chunk: Chunk) -> void:
	var blocks     := chunk.blocks
	var light_data := chunk.light_data
	var flags      := BlockRegistry._block_flags
	var flags_size := flags.size()
	const SQ := 256; const S := 16

	for lx in S:
		for lz in S:
			var sky := MAX_LIGHT
			for ly in range(S - 1, -1, -1):
				var bid := blocks[ly * SQ + lz * S + lx]
				# Opaque block (known, not transparent, not fluid) blocks sky light
				if bid != 0 and bid < flags_size and (flags[bid] & 3) == 0:
					sky = 0
				var idx := ly * SQ + lz * S + lx
				# Preserve block-light nibble (low 4 bits), set sky-light nibble (high 4 bits)
				light_data[idx] = (sky << 4) | (light_data[idx] & 0x0F)


## BFS block light propagation.  Called on the worker thread during chunk generation.
## Uses integer-encoded positions (lx | ly<<4 | lz<<8) and pop_back (O(1)) instead
## of Vector3i + pop_front (O(n)) to avoid per-node allocations and array shifts.
static func compute_block_light_for_chunk(chunk: Chunk) -> void:
	var blocks      := chunk.blocks
	var light_data  := chunk.light_data
	var flags       := BlockRegistry._block_flags
	var light_lvls  := BlockRegistry._block_light_level
	var flags_size  := flags.size()
	var lvls_size   := light_lvls.size()
	const SQ := 256; const S := 16; const SZ_CB := 4096

	# Seed queue with all light-emitting blocks
	var queue: Array = []
	for idx in SZ_CB:
		var bid := blocks[idx]
		if bid == 0 or bid >= lvls_size:
			continue
		var lvl := light_lvls[bid]
		if lvl == 0:
			continue
		light_data[idx] = (light_data[idx] & 0xF0) | lvl
		var ly := idx / SQ
		var rem := idx % SQ
		var lz := rem / S
		var lx := rem % S
		queue.append(lx | (ly << 4) | (lz << 8))

	# Propagate light — DFS order is correct (only queued when new_light > current)
	while not queue.is_empty():
		var enc: int = queue.pop_back()
		var lx := enc & 0xF
		var ly := (enc >> 4) & 0xF
		var lz := (enc >> 8) & 0xF
		var cur := light_data[ly * SQ + lz * S + lx] & 0x0F
		if cur <= 1:
			continue
		var nl := cur - 1

		# +X
		if lx + 1 < S:
			var ni := ly * SQ + lz * S + lx + 1
			var nb := blocks[ni]
			if nb == 0 or nb >= flags_size or (flags[nb] & 3) != 0:
				if nl > (light_data[ni] & 0x0F):
					light_data[ni] = (light_data[ni] & 0xF0) | nl
					queue.append((lx + 1) | (ly << 4) | (lz << 8))
		# -X
		if lx > 0:
			var ni := ly * SQ + lz * S + lx - 1
			var nb := blocks[ni]
			if nb == 0 or nb >= flags_size or (flags[nb] & 3) != 0:
				if nl > (light_data[ni] & 0x0F):
					light_data[ni] = (light_data[ni] & 0xF0) | nl
					queue.append((lx - 1) | (ly << 4) | (lz << 8))
		# +Y
		if ly + 1 < S:
			var ni := (ly + 1) * SQ + lz * S + lx
			var nb := blocks[ni]
			if nb == 0 or nb >= flags_size or (flags[nb] & 3) != 0:
				if nl > (light_data[ni] & 0x0F):
					light_data[ni] = (light_data[ni] & 0xF0) | nl
					queue.append(lx | ((ly + 1) << 4) | (lz << 8))
		# -Y
		if ly > 0:
			var ni := (ly - 1) * SQ + lz * S + lx
			var nb := blocks[ni]
			if nb == 0 or nb >= flags_size or (flags[nb] & 3) != 0:
				if nl > (light_data[ni] & 0x0F):
					light_data[ni] = (light_data[ni] & 0xF0) | nl
					queue.append(lx | ((ly - 1) << 4) | (lz << 8))
		# +Z
		if lz + 1 < S:
			var ni := ly * SQ + (lz + 1) * S + lx
			var nb := blocks[ni]
			if nb == 0 or nb >= flags_size or (flags[nb] & 3) != 0:
				if nl > (light_data[ni] & 0x0F):
					light_data[ni] = (light_data[ni] & 0xF0) | nl
					queue.append(lx | (ly << 4) | ((lz + 1) << 8))
		# -Z
		if lz > 0:
			var ni := ly * SQ + (lz - 1) * S + lx
			var nb := blocks[ni]
			if nb == 0 or nb >= flags_size or (flags[nb] & 3) != 0:
				if nl > (light_data[ni] & 0x0F):
					light_data[ni] = (light_data[ni] & 0xF0) | nl
					queue.append(lx | (ly << 4) | ((lz - 1) << 8))


## Relight a chunk after a block is placed or removed (main thread only).
func on_block_changed(world_pos: Vector3i) -> void:
	var cp := Chunk.world_to_chunk(world_pos)
	var chunk := _manager.get_chunk(cp)
	if chunk == null:
		return
	LightEngine.compute_sky_light_for_chunk(chunk)
	LightEngine.compute_block_light_for_chunk(chunk)
	chunk.is_dirty = true
