## Chunk.gd — 16x16x16 voxel chunk with 3D position.
class_name Chunk
extends RefCounted

const SIZE := 16
const SIZE_SQ := SIZE * SIZE
const SIZE_CB := SIZE * SIZE * SIZE

var blocks: PackedInt32Array
var metadata: Dictionary = {}
var light_data: PackedByteArray
var biome_data: PackedByteArray

var chunk_pos: Vector3i  # (cx, cy, cz)
var dimension: String = "overworld"
var is_generated: bool = false
var is_dirty: bool = false
var is_loaded: bool = false
var is_all_air: bool = true   # set false by rebuild_heightmap when any block found

var heightmap: PackedInt32Array  # max non-air local Y per XZ column
# World-space Y of the terrain surface per XZ column (set by the generator).
# Drives sky-light: cells above the surface get full sky light.
var world_surface: PackedInt32Array


func _init(cx: int, cy: int, cz: int, dim: String = "overworld") -> void:
	chunk_pos = Vector3i(cx, cy, cz)
	dimension = dim
	blocks = PackedInt32Array()
	blocks.resize(SIZE_CB)
	blocks.fill(0)
	light_data = PackedByteArray()
	light_data.resize(SIZE_CB)
	light_data.fill(0)
	biome_data = PackedByteArray()
	biome_data.resize(64)
	biome_data.fill(0)
	heightmap = PackedInt32Array()
	heightmap.resize(SIZE_SQ)
	heightmap.fill(-1)
	world_surface = PackedInt32Array()
	world_surface.resize(SIZE_SQ)
	world_surface.fill(-99999)   # default: everything above → full sky light


static func local_to_index(lx: int, ly: int, lz: int) -> int:
	return ly * SIZE_SQ + lz * SIZE + lx


func get_block(lx: int, ly: int, lz: int) -> int:
	if not _in_bounds(lx, ly, lz):
		return 0
	return blocks[local_to_index(lx, ly, lz)]


func set_block(lx: int, ly: int, lz: int, id: int) -> void:
	if not _in_bounds(lx, ly, lz):
		return
	blocks[local_to_index(lx, ly, lz)] = id
	is_dirty = true
	if id != 0:
		is_all_air = false
	_update_heightmap_at(lx, ly, lz)

## No bounds check, no heightmap update — use during bulk generation only.
## Caller must call rebuild_heightmap() once after all placements.
func set_block_fast(lx: int, ly: int, lz: int, id: int) -> void:
	blocks[ly * SIZE_SQ + lz * SIZE + lx] = id


func get_block_meta(lx: int, ly: int, lz: int) -> Dictionary:
	return metadata.get(local_to_index(lx, ly, lz), {})


func set_block_meta(lx: int, ly: int, lz: int, meta: Dictionary) -> void:
	var idx := local_to_index(lx, ly, lz)
	if meta.is_empty():
		metadata.erase(idx)
	else:
		metadata[idx] = meta
	is_dirty = true


func get_block_light(lx: int, ly: int, lz: int) -> int:
	if not _in_bounds(lx, ly, lz):
		return 0
	return light_data[local_to_index(lx, ly, lz)] & 0x0F


func get_sky_light(lx: int, ly: int, lz: int) -> int:
	if not _in_bounds(lx, ly, lz):
		return 15
	return (light_data[local_to_index(lx, ly, lz)] >> 4) & 0x0F


func set_light(lx: int, ly: int, lz: int, block_light: int, sky_light: int) -> void:
	if not _in_bounds(lx, ly, lz):
		return
	light_data[local_to_index(lx, ly, lz)] = (sky_light << 4) | block_light


func get_height(lx: int, lz: int) -> int:
	return heightmap[lz * SIZE + lx]


## World Y of the bottom block in this chunk.
func world_y_base() -> int:
	return chunk_pos.y * SIZE


## World-space origin (min corner).
func get_world_origin() -> Vector3i:
	return Vector3i(chunk_pos.x * SIZE, chunk_pos.y * SIZE, chunk_pos.z * SIZE)


## World position → 3D chunk coords.
static func world_to_chunk(world_pos: Vector3i) -> Vector3i:
	return Vector3i(
		floori(float(world_pos.x) / SIZE),
		floori(float(world_pos.y) / SIZE),
		floori(float(world_pos.z) / SIZE)
	)


## World position → local position within this chunk.
static func world_to_local(world_pos: Vector3i, cy: int) -> Vector3i:
	return Vector3i(
		posmod(world_pos.x, SIZE),
		world_pos.y - cy * SIZE,
		posmod(world_pos.z, SIZE)
	)


## Rebuild the full heightmap — call once after bulk block writes (e.g. generation).
func rebuild_heightmap() -> void:
	is_all_air = true
	for lx in SIZE:
		for lz in SIZE:
			var max_y := SIZE - 1
			while max_y >= 0:
				if blocks[max_y * SIZE_SQ + lz * SIZE + lx] != 0:
					break
				max_y -= 1
			heightmap[lz * SIZE + lx] = max_y
			if max_y >= 0:
				is_all_air = false

func _update_heightmap_at(lx: int, ly: int, lz: int) -> void:
	var col_idx := lz * SIZE + lx
	var current_top := heightmap[col_idx]
	if blocks[local_to_index(lx, ly, lz)] != 0:
		if ly > current_top:
			heightmap[col_idx] = ly
	else:
		if ly == current_top:
			var max_y := ly - 1
			while max_y >= 0:
				if blocks[local_to_index(lx, max_y, lz)] != 0:
					break
				max_y -= 1
			heightmap[col_idx] = max_y


func _in_bounds(lx: int, ly: int, lz: int) -> bool:
	return lx >= 0 and lx < SIZE and ly >= 0 and ly < SIZE and lz >= 0 and lz < SIZE


const SAVE_VERSION := 2
# Version marker stored as -(1000000 + version): far outside the legal chunk
# coordinate range (±16383), so legacy files (that start with chunk_pos.x)
# can never be confused with versioned ones.
const _VERSION_BASE := 1000000

func serialize() -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_32(-(_VERSION_BASE + SAVE_VERSION))
	buf.put_32(chunk_pos.x)
	buf.put_32(chunk_pos.y)
	buf.put_32(chunk_pos.z)
	buf.put_string(dimension)
	buf.put_8(1 if is_generated else 0)
	var rle := _rle_encode(blocks)
	buf.put_32(rle.size())
	buf.put_data(rle)
	buf.put_data(light_data)
	for i in SIZE_SQ:
		buf.put_32(world_surface[i])
	var meta_keys := metadata.keys()
	buf.put_32(meta_keys.size())
	for key in meta_keys:
		buf.put_32(key)
		buf.put_string(JSON.stringify(metadata[key]))
	return buf.data_array


static func deserialize(data: PackedByteArray) -> Chunk:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	var version := 1
	var first: int = buf.get_32()
	var cx: int
	if first <= -_VERSION_BASE:
		version = -first - _VERSION_BASE
		cx = buf.get_32()
	else:
		cx = first
	var cy: int = buf.get_32()
	var cz: int = buf.get_32()
	var dim: String = buf.get_string()
	var generated: bool = buf.get_8() == 1
	var chunk := Chunk.new(cx, cy, cz, dim)
	chunk.is_generated = generated
	var rle_size: int = buf.get_32()
	chunk.blocks = chunk._rle_decode(buf.get_data(rle_size)[1])
	chunk.light_data = buf.get_data(SIZE_CB)[1]
	if version >= 2:
		for i in SIZE_SQ:
			chunk.world_surface[i] = buf.get_32()
	var meta_count: int = buf.get_32()
	for _i in meta_count:
		var key: int = buf.get_32()
		chunk.metadata[key] = JSON.parse_string(buf.get_string())
	return chunk


func _rle_encode(arr: PackedInt32Array) -> PackedByteArray:
	var result := PackedByteArray()
	var i := 0
	while i < arr.size():
		var val := arr[i]
		var count := 1
		while i + count < arr.size() and arr[i + count] == val and count < 65535:
			count += 1
		var entry := PackedByteArray()
		entry.resize(6)
		entry.encode_s32(0, val)
		entry.encode_u16(4, count)
		result.append_array(entry)
		i += count
	return result


func _rle_decode(data: PackedByteArray) -> PackedInt32Array:
	var result := PackedInt32Array()
	var i := 0
	while i + 6 <= data.size():
		var val := data.decode_s32(i)
		var count := data.decode_u16(i + 4)
		for _j in count:
			result.append(val)
		i += 6
	return result
