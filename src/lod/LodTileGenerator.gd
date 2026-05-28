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


static func _block_color(block_id: int) -> Color:
	match block_id:
		2:    return Color(0.18, 0.40, 0.10)   # grass — muted, natural
		3:    return Color(0.50, 0.33, 0.20)   # dirt
		1:    return Color(0.52, 0.52, 0.52)   # stone
		50:   return Color(0.28, 0.28, 0.32)   # deepslate
		8:    return Color(0.86, 0.80, 0.52)   # sand
		9:    return Color(0.50, 0.48, 0.46)   # gravel
		10, 11, 12, 13, 14, 15, 16, 17:
			return Color(0.42, 0.32, 0.18)   # wood logs
		90:   return Color(0.16, 0.34, 0.72)   # water — deeper blue
		91:   return Color(0.95, 0.36, 0.00)   # lava
		100:  return Color(0.18, 0.18, 0.18)   # bedrock
		197:  return Color(0.60, 0.45, 0.28)   # mycelium
		1000: return Color(0.60, 0.08, 0.08)   # netherrack
		2000: return Color(0.86, 0.84, 0.55)   # end_stone
		_:
			var h := block_id
			return Color(
				0.22 + (h & 0xFF) / 640.0,
				0.22 + ((h >> 8) & 0xFF) / 640.0,
				0.22 + ((h >> 16) & 0xFF) / 640.0
			)
