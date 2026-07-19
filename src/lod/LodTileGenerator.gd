## LodTileGenerator.gd — Generates LodTile height-field data from WorldGenerator noise.
## All methods are static and read-only — safe to call from WorkerThreadPool tasks.
class_name LodTileGenerator

const SEA_LEVEL := 63


static func generate_lod1(tx: int, tz: int, gen: WorldGenerator) -> LodTile:
	var tile := LodTile.new(tx, tz, 1)
	var wx0  := float(tx * 16)
	var wz0  := float(tz * 16)
	for z in LodTile.COLS:
		for x in LodTile.COLS:
			var wx    := wx0 + float(x)
			var wz    := wz0 + float(z)
			var h     := gen._compute_height(wx, wz)
			var biome := gen._sample_biome(wx, wz)
			var sid   := gen._surface_block(biome, h)
			var i     := z * LodTile.COLS + x
			tile.heights[i]        = h
			tile.surface_colors[i] = _block_color(sid)
			tile.water_mask[i]     = 1 if h < SEA_LEVEL else 0
	tile.is_ready = true
	return tile


static func generate_lod2(tx: int, tz: int, gen: WorldGenerator) -> LodTile:
	var tile := LodTile.new(tx, tz, 2)
	var cpt  := LodSettings.LOD2_CHUNKS_PER_TILE
	var cw   := float(LodSettings.LOD2_COL_WIDTH)
	var wx0  := float(tx * cpt * 16)
	var wz0  := float(tz * cpt * 16)
	# Sample center of each 4×4-block macro-column
	for z in LodTile.COLS:
		for x in LodTile.COLS:
			var wx    := wx0 + float(x) * cw + cw * 0.5
			var wz    := wz0 + float(z) * cw + cw * 0.5
			var h     := gen._compute_height(wx, wz)
			var biome := gen._sample_biome(wx, wz)
			var sid   := gen._surface_block(biome, h)
			var i     := z * LodTile.COLS + x
			tile.heights[i]        = h
			tile.surface_colors[i] = _block_color(sid)
			tile.water_mask[i]     = 1 if h < SEA_LEVEL else 0
	tile.is_ready = true
	return tile


# id → average top-texture color, built ON THE MAIN THREAD before any worker
# task runs (build_color_table), then read-only from threads. This replaces the
# old hardcoded id table that no longer matched real block ids (snow/terracotta
# surfaces rendered as random hash colors — the red/cream walls on the horizon).
static var _color_table: PackedColorArray = PackedColorArray()


static func build_color_table() -> void:
	var n: int = BlockRegistry._block_flags.size()
	if n <= 0:
		return
	var table := PackedColorArray()
	table.resize(n)
	for id in n:
		if id == 0:
			table[id] = Color(0.5, 0.5, 0.5)
			continue
		var c: Color = BlockTextureAtlas.get_block_top_color(id)
		# Slightly muted so far terrain sits back instead of popping
		table[id] = Color(c.r * 0.92, c.g * 0.92, c.b * 0.92)
	# Water reads better as the classic deep blue than as its texture average
	table[90] = Color(0.16, 0.34, 0.72)
	_color_table = table


static func _block_color(block_id: int) -> Color:
	if block_id >= 0 and block_id < _color_table.size():
		return _color_table[block_id]
	return Color(0.5, 0.5, 0.5)
