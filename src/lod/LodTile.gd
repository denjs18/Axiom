## LodTile.gd — Height-field data for one LOD tile.
## LOD1: covers 1 chunk XZ (16×16 blocks), 16×16 columns, col_width=1.
## LOD2: covers 4×4 chunks XZ (64×64 blocks), 16×16 columns, col_width=4.
class_name LodTile
extends RefCounted

const CACHE_VERSION := 1
const COLS          := 16   # Columns per tile side (always 16 for both LOD levels)

var tile_pos:  Vector2i   # Tile-space (tx, tz) coords
var lod_level: int        # 1 or 2

var is_ready: bool = false

# Per-column arrays (COLS × COLS = 256 entries)
var heights:       PackedInt32Array   # World Y of surface block
var surface_colors: PackedColorArray  # Color at surface
var water_mask:    PackedByteArray    # 1 = water visible above surface block


func _init(tx: int, tz: int, level: int) -> void:
	tile_pos  = Vector2i(tx, tz)
	lod_level = level
	var n := COLS * COLS
	heights        = PackedInt32Array(); heights.resize(n);        heights.fill(0)
	surface_colors = PackedColorArray(); surface_colors.resize(n)
	water_mask     = PackedByteArray();  water_mask.resize(n);     water_mask.fill(0)


## World-space XZ origin of this tile (bottom-left corner).
func get_world_origin_xz() -> Vector2i:
	if lod_level == 1:
		return Vector2i(tile_pos.x * 16, tile_pos.y * 16)
	return Vector2i(
		tile_pos.x * LodSettings.LOD2_CHUNKS_PER_TILE * 16,
		tile_pos.y * LodSettings.LOD2_CHUNKS_PER_TILE * 16
	)


## Width of each column quad in world blocks (1 for LOD1, 4 for LOD2).
func get_col_width() -> int:
	return 1 if lod_level == 1 else LodSettings.LOD2_COL_WIDTH


func serialize() -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(CACHE_VERSION)
	buf.put_u8(lod_level)
	buf.put_32(tile_pos.x)
	buf.put_32(tile_pos.y)
	var n := COLS * COLS
	for i in n:
		buf.put_32(heights[i])
	for i in n:
		var c := surface_colors[i]
		buf.put_float(c.r)
		buf.put_float(c.g)
		buf.put_float(c.b)
	buf.put_data(water_mask)
	return buf.data_array


static func deserialize(data: PackedByteArray) -> LodTile:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	if buf.get_u8() != CACHE_VERSION:
		return null
	var lvl := buf.get_u8()
	var tx  := buf.get_32()
	var tz  := buf.get_32()
	var tile := LodTile.new(tx, tz, lvl)
	var n := COLS * COLS
	for i in n:
		tile.heights[i] = buf.get_32()
	for i in n:
		tile.surface_colors[i] = Color(buf.get_float(), buf.get_float(), buf.get_float())
	tile.water_mask = buf.get_data(n)[1]
	tile.is_ready   = true
	return tile
