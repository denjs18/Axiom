## WorldGenerator.gd — Procedural world generation (per 16x16x16 chunk).
## Overworld: biome terrain, caves, full ore spread, per-species trees, plants.
## Nether: biome zones (wastes, crimson, warped, soul valley, basalt deltas) + ores.
## The End: central island, void ring, outer islands with chorus + End ores.
class_name WorldGenerator
extends RefCounted

const CHUNK_SIZE := 16
const WORLD_MIN_Y := -128
const SEA_LEVEL := 63

var _seed: int = 0
var _dimension: String = "overworld"
var generation_type: String = ""   # "" = normal terrain, "flat" = superflat

# Superflat layout (above the spawn-rejection floor at y=60).
const FLAT_BEDROCK_Y := 60
const FLAT_GRASS_Y   := 63   # dirt fills 61–62, grass on top

var _continental: FastNoiseLite
var _erosion: FastNoiseLite
var _peak_valley: FastNoiseLite
var _biome_temp: FastNoiseLite
var _biome_humid: FastNoiseLite
var _cave_3d: FastNoiseLite
var _cave_cheese: FastNoiseLite
var _detail: FastNoiseLite
var _ore: FastNoiseLite

var _structure_placer: StructurePlacer

# ── Block ID constants (mirrors data/blocks/*.json) ────────────────────────────
const B_STONE := 1;        const B_GRASS := 2;       const B_DIRT := 3
const B_COARSE := 4;       const B_COBBLE := 6;      const B_GRAVEL := 7
const B_SAND := 8;         const B_RED_SAND := 9
const B_OAK_LOG := 10;     const B_OAK_LEAVES := 12
const B_SPRUCE_LOG := 13;  const B_BIRCH_LOG := 15;  const B_JUNGLE_LOG := 17
const B_ACACIA_LOG := 19;  const B_DARK_LOG := 21;   const B_MANGROVE_LOG := 23
const B_CHERRY_LOG := 25
const B_SPRUCE_LEAVES := 47; const B_BIRCH_LEAVES := 48; const B_JUNGLE_LEAVES := 49
const B_ACACIA_LEAVES := 56; const B_DARK_LEAVES := 57;  const B_CHERRY_LEAVES := 58
const B_DEEPSLATE := 50
const B_POPPY := 71;       const B_DANDELION := 72;  const B_ORCHID := 73
const B_SHORT_GRASS := 74; const B_FERN := 75;       const B_DEAD_BUSH := 76
const B_RED_MUSH := 87;    const B_BROWN_MUSH := 88; const B_CANE := 89
const B_END_PORTAL := 94;  const B_END_FRAME := 95
const B_WATER := 90;       const B_LAVA := 91
const B_BEDROCK := 100;    const B_OBSIDIAN := 101;  const B_GLOWSTONE_OW := 110
const B_PUMPKIN := 190;    const B_MOSS := 196;      const B_MYCELIUM := 197
const B_BASALT_OW := 240;  const B_SNOW := 241;      const B_TERRACOTTA := 242
const B_AMETHYST := 222;   const B_TORCH := 46

# Nether
const N_RACK := 1000;   const N_GOLD := 1001;   const N_QUARTZ := 1002
const N_DEBRIS := 1003; const N_SOUL_SAND := 1004; const N_SOUL_SOIL := 1005
const N_BASALT := 1006; const N_BLACKSTONE := 1007; const N_MAGMA := 1009
const N_WART := 1010;   const N_WARPED_WART := 1011
const N_CRIMSON_NYL := 1012; const N_WARPED_NYL := 1013
const N_CRIMSON_STEM := 1014; const N_WARPED_STEM := 1015
const N_GLOWSTONE := 1019
const N_SULFUR := 1050; const N_URANIUM := 1051; const N_VOID_QUARTZ := 1052

# End
const E_STONE := 2000;  const E_BRICKS := 2001;  const E_PURPUR := 2002
const E_CHORUS_FLOWER := 2003; const E_CHORUS_PLANT := 2004
const E_CRYSTALLINE := 2015
const E_VOID_CRYSTAL := 2030; const E_ENDER_SHARD := 2031; const E_NULLITE := 2032


func initialize(world_seed: int, dimension: String) -> void:
	_seed = world_seed
	_dimension = dimension
	_setup_noise()
	_structure_placer = StructurePlacer.new()
	_structure_placer.setup(_seed, Callable(self, "_compute_height"))


func _setup_noise() -> void:
	_continental = _make_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, _seed, 0.002, 2)
	_erosion     = _make_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, _seed + 1, 0.004, 2)
	_peak_valley = _make_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, _seed + 2, 0.003, 2)
	_biome_temp  = _make_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, _seed + 10, 0.001, 1)
	_biome_humid = _make_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, _seed + 11, 0.001, 1)
	_cave_3d     = _make_noise(FastNoiseLite.TYPE_PERLIN, _seed + 20, 0.025, 2)
	_cave_cheese = _make_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, _seed + 21, 0.015, 2)
	_detail      = _make_noise(FastNoiseLite.TYPE_PERLIN, _seed + 30, 0.08, 1)
	_ore         = _make_noise(FastNoiseLite.TYPE_PERLIN, _seed + 40, 0.05, 1)


func _make_noise(type: int, s: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = type
	n.seed = s
	n.frequency = freq
	n.fractal_octaves = octaves
	return n


func generate_chunk(chunk: Chunk, _world_seed: int) -> void:
	if generation_type == "flat":
		_gen_flat(chunk)
		return
	match _dimension:
		"overworld": _gen_overworld(chunk)
		"nether":    _gen_nether(chunk)
		"the_end":   _gen_end(chunk)
		_:           _gen_overworld(chunk)


# ─── SUPERFLAT (creative testing) ─────────────────────────────────────────────

var _flat_ids_cached := false
var _flat_bedrock := 0
var _flat_dirt := 0
var _flat_grass := 0

func _cache_flat_ids() -> void:
	if _flat_ids_cached:
		return
	_flat_ids_cached = true
	var bedrock := BlockRegistry.get_block_by_name("bedrock")
	var dirt := BlockRegistry.get_block_by_name("dirt")
	var grass := BlockRegistry.get_block_by_name("grass_block")
	_flat_bedrock = bedrock.id if bedrock else 0
	_flat_dirt = dirt.id if dirt else 0
	_flat_grass = grass.id if grass else 0

func _gen_flat(chunk: Chunk) -> void:
	_cache_flat_ids()
	var wy0 := chunk.chunk_pos.y * CHUNK_SIZE
	for ly in CHUNK_SIZE:
		var wy := wy0 + ly
		var bid := 0
		if wy == FLAT_BEDROCK_Y:
			bid = _flat_bedrock
		elif wy > FLAT_BEDROCK_Y and wy < FLAT_GRASS_Y:
			bid = _flat_dirt
		elif wy == FLAT_GRASS_Y:
			bid = _flat_grass
		if bid == 0:
			continue  # air
		for lx in CHUNK_SIZE:
			for lz in CHUNK_SIZE:
				chunk.set_block_fast(lx, ly, lz, bid)
	chunk.world_surface.fill(FLAT_GRASS_Y)
	chunk.rebuild_heightmap()


# ─── OVERWORLD ───────────────────────────────────────────────────────────────

func _gen_overworld(chunk: Chunk) -> void:
	var wx0 := chunk.chunk_pos.x * CHUNK_SIZE
	var wy0 := chunk.chunk_pos.y * CHUNK_SIZE
	var wz0 := chunk.chunk_pos.z * CHUNK_SIZE

	# Pre-compute per-column height + biome (256 calls instead of re-sampling per block)
	var heights := PackedInt32Array()
	heights.resize(CHUNK_SIZE * CHUNK_SIZE)
	var biomes: Array = []
	biomes.resize(CHUNK_SIZE * CHUNK_SIZE)
	for lx in CHUNK_SIZE:
		for lz in CHUNK_SIZE:
			var idx := lx * CHUNK_SIZE + lz
			heights[idx] = _compute_height(float(wx0 + lx), float(wz0 + lz))
			biomes[idx]  = _sample_biome(float(wx0 + lx), float(wz0 + lz))
			# Sky light reference: water surface counts as lit
			chunk.world_surface[lz * CHUNK_SIZE + lx] = heights[idx]

	# Terrain pass — uses set_block_fast (no bounds check, no per-block heightmap update)
	for lx in CHUNK_SIZE:
		for lz in CHUNK_SIZE:
			var col  := lx * CHUNK_SIZE + lz
			var height: int   = heights[col]
			var biome_id: String = biomes[col]
			for ly in CHUNK_SIZE:
				_place_overworld_block(chunk, lx, ly, lz, wy0 + ly, height, biome_id)

	# Cave carving — skip entirely for chunks above sea level (huge win for surface chunks)
	if wy0 < SEA_LEVEL:
		_carve_caves(chunk, wx0, wy0, wz0)

	# Ore veins — full vanilla spread + deepslate variants
	_place_ore_veins(chunk, wx0, wy0, wz0)

	# Surface features — trees, plants, flowers, crops of the wild
	_place_surface_features(chunk, wx0, wy0, wz0, heights, biomes)

	# Road network — placed before structures so buildings override path blocks
	_structure_placer.try_place_routes(chunk, wx0, wy0, wz0)

	# Waypoint stalls on road nodes (20% of nodes get a small shelter)
	_structure_placer.try_place_waypoints(chunk, wx0, wy0, wz0)

	# Biome castles — rarer, larger, house guards and merchants
	_structure_placer.try_place_castles(chunk, wx0, wy0, wz0)

	# Boss fortresses — placed after waypoints, before skill structures
	_structure_placer.try_place_boss_fortresses(chunk, wx0, wy0, wz0)

	# Exploration structures (arenas, mines, labs…) with skill altars
	_structure_placer.try_place_structures(chunk, wx0, wy0, wz0)

	# Archives des Architectes — unique underground lore structure
	_structure_placer.try_place_archives(chunk, wx0, wy0, wz0)

	# Nexus pocket room — floating platform at far fixed coordinates
	_structure_placer.try_place_nexus_room(chunk, wx0, wy0, wz0)

	# End shrines — the gateway to The End
	_place_end_shrines(chunk, wx0, wy0, wz0)

	# One heightmap rebuild after all bulk writes
	chunk.rebuild_heightmap()
	chunk.is_dirty = true


## Public: returns the biome ID string at any overworld world position.
## Cheap (just two noise lookups) — safe to call every frame.
func get_biome_at(wx: float, wz: float) -> String:
	var biome := BiomeRegistry.select_biome_at(
		(_biome_temp.get_noise_2d(wx, wz) + 1.0),   # 0..2
		(_biome_humid.get_noise_2d(wx, wz) + 1.0) * 0.5,
		_dimension
	)
	return biome.full_id if biome else "axiom:plains"


func get_surface_y(wx: int, wz: int) -> int:
	return _compute_height(float(wx), float(wz))


func _compute_height(wx: float, wz: float) -> int:
	var c := _continental.get_noise_2d(wx, wz)
	var e := _erosion.get_noise_2d(wx, wz)
	var pv := _peak_valley.get_noise_2d(wx, wz)
	var d := _detail.get_noise_2d(wx, wz)

	var h := 64.0 + c * 40.0
	h = lerp(h, 64.0, ((e + 1.0) * 0.5) * 0.4)
	var pvn := (pv + 1.0) * 0.5
	if pvn > 0.6: h += (pvn - 0.6) * 150.0
	elif pvn < 0.3: h -= (0.3 - pvn) * 80.0
	h += d * 4.0
	return clampi(roundi(h), WORLD_MIN_Y + 5, 310)


func _sample_biome(wx: float, wz: float) -> String:
	var temp := (_biome_temp.get_noise_2d(wx, wz) + 1.0) * 0.5
	var humid := (_biome_humid.get_noise_2d(wx, wz) + 1.0) * 0.5
	var biome := BiomeRegistry.select_biome_at(temp * 2.0, humid, "overworld")
	return biome.id if biome else "plains"


func _place_overworld_block(chunk: Chunk, lx: int, ly: int, lz: int,
		wy: int, height: int, biome_id: String) -> void:
	if wy <= WORLD_MIN_Y + 4:
		var bedrock_hash := absf(_detail.get_noise_3d(float(chunk.chunk_pos.x * CHUNK_SIZE + lx),
				float(wy), float(chunk.chunk_pos.z * CHUNK_SIZE + lz)))
		if wy == WORLD_MIN_Y or bedrock_hash < 0.3:
			chunk.set_block_fast(lx, ly, lz, B_BEDROCK)
		return

	var stone_id := B_DEEPSLATE if wy < 0 else B_STONE
	if wy < height - 3:
		chunk.set_block_fast(lx, ly, lz, stone_id)
	elif wy < height:
		chunk.set_block_fast(lx, ly, lz, B_DIRT)
	elif wy == height:
		chunk.set_block_fast(lx, ly, lz, _surface_block(biome_id, height))
	elif wy <= SEA_LEVEL:
		if wy == height + 1 and height < SEA_LEVEL - 3:
			chunk.set_block_fast(lx, ly, lz, B_GRAVEL)
		else:
			chunk.set_block_fast(lx, ly, lz, B_WATER)


func _surface_block(biome_id: String, height: int) -> int:
	if height < SEA_LEVEL:
		return B_SAND  # underwater surface
	match biome_id:
		"desert", "badlands", "beach", "oasis": return B_SAND
		"gravel_beach":                return B_GRAVEL
		"mushroom_fields":             return B_MYCELIUM
		"swamp", "mangrove_swamp":     return B_GRASS
		"volcanic_rifts":              return B_BASALT_OW
		"boreal_highlands", "snowy_plains", "snowy_taiga": return B_SNOW
		"petrified_forest":            return B_COARSE
		"crystal_mesa":                return B_TERRACOTTA
		"twilight_hollow":             return B_MOSS
		"jagged_peaks":                return B_SNOW if height > 130 else B_STONE
		_:                             return B_GRASS


func _carve_caves(chunk: Chunk, wx0: int, wy0: int, wz0: int) -> void:
	var sz := CHUNK_SIZE
	var sq := sz * sz
	for lx in sz:
		for ly in sz:
			var wy := wy0 + ly
			if wy <= WORLD_MIN_Y + 5:
				continue
			var wx := float(wx0 + lx)
			var wz_base := float(wz0)
			var wyfloat := float(wy)
			for lz in sz:
				var wz := wz_base + lz
				var idx := ly * sq + lz * sz + lx
				var bid: int = chunk.blocks[idx]
				if bid != B_STONE and bid != B_DEEPSLATE and bid != B_DIRT:
					continue
				if absf(_cave_3d.get_noise_3d(wx, wyfloat, wz)) < 0.05:
					chunk.blocks[idx] = 0
				elif bid != B_DIRT and _cave_cheese.get_noise_3d(wx*0.7, wyfloat*0.5, wz*0.7) > 0.55 and wy < 50:
					chunk.blocks[idx] = 0


# ── Ores ───────────────────────────────────────────────────────────────────────

## Full vanilla ore table + deepslate variants below y=0.
## {stone_ore, deepslate_ore, min_y, max_y, tries, r_min, r_max}
const _ORE_VEINS := [
	# stone  deep  miny   maxy  tries rmin rmax
	[30,     31,   -80,   130,   7,   2,   3],   # coal
	[32,     33,   -48,    72,   6,   2,   3],   # iron
	[34,     35,     0,    88,   5,   2,   3],   # copper
	[36,     37,   -56,    32,   3,   1,   2],   # gold
	[38,     39,   -52,    30,   2,   1,   2],   # lapis
	[40,     41,  -100,    12,   4,   1,   3],   # redstone
	[42,     43,  -110,    10,   2,   1,   2],   # diamond
	[44,     45,    40,   140,   1,   1,   1],   # emerald (high altitudes)
]

func _place_ore_veins(chunk: Chunk, wx0: int, wy0: int, wz0: int) -> void:
	var sz := Chunk.SIZE
	var sq := Chunk.SIZE_SQ
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(_seed ^ (wx0 * 1619) ^ (wy0 * 31337) ^ (wz0 * 6271))

	for vein_def in _ORE_VEINS:
		var stone_ore: int = vein_def[0]
		var deep_ore:  int = vein_def[1]
		var min_wy:    int = vein_def[2]
		var max_wy:    int = vein_def[3]
		var tries:     int = vein_def[4]
		var rmin:      int = vein_def[5]
		var rmax:      int = vein_def[6]

		if wy0 + sz <= min_wy or wy0 > max_wy:
			continue

		for _t in tries:
			var cx: int = wx0 + rng.randi() % sz
			var cy: int = clampi(wy0 + (rng.randi() % sz), min_wy, max_wy)
			var cz: int = wz0 + rng.randi() % sz
			var radius: int = rng.randi_range(rmin, rmax)

			for dx in range(-radius, radius + 1):
				for dy in range(-radius, radius + 1):
					for dz in range(-radius, radius + 1):
						if dx*dx + dy*dy + dz*dz > radius*radius:
							continue
						var lx: int = cx + dx - wx0
						var ly: int = cy + dy - wy0
						var lz: int = cz + dz - wz0
						if lx < 0 or lx >= sz or ly < 0 or ly >= sz or lz < 0 or lz >= sz:
							continue
						var idx: int = ly * sq + lz * sz + lx
						var cur: int = chunk.blocks[idx]
						if cur == B_STONE:
							chunk.blocks[idx] = stone_ore
						elif cur == B_DEEPSLATE:
							chunk.blocks[idx] = deep_ore


# ── Surface features: trees + vegetation ───────────────────────────────────────

func _place_surface_features(chunk: Chunk, wx0: int, wy0: int, wz0: int,
		heights: PackedInt32Array, biomes: Array) -> void:
	var rng := RandomNumberGenerator.new()
	var sz := Chunk.SIZE
	var sq := Chunk.SIZE_SQ
	for lx in sz:
		for lz in sz:
			var world_height: int = heights[lx * sz + lz]
			var surface_ly := world_height - wy0
			if surface_ly < 0 or surface_ly + 1 >= sz:
				continue
			var surface_bid: int = chunk.blocks[surface_ly * sq + lz * sz + lx]
			# Skip air and fluids
			if surface_bid == 0 or surface_bid == B_WATER or surface_bid == B_LAVA:
				continue
			rng.seed = hash(Vector3i(wx0 + lx, world_height, wz0 + lz)) ^ _seed
			var biome_id: String = biomes[lx * sz + lz]
			if surface_ly + 8 < sz:
				_try_place_tree(chunk, lx, surface_ly, lz, biome_id, rng)
			_try_place_vegetation(chunk, lx, surface_ly, lz, biome_id, surface_bid,
				world_height, wx0, wz0, rng)
			_try_place_biome_feature(chunk, lx, surface_ly, lz, biome_id, surface_bid, rng)


## Ground cover: flowers, grass tufts, mushrooms, dead bushes, cane, pumpkins.
func _try_place_vegetation(chunk: Chunk, lx: int, surface_ly: int, lz: int,
		biome_id: String, surface_bid: int, world_height: int,
		wx0: int, wz0: int, rng: RandomNumberGenerator) -> void:
	var sz := CHUNK_SIZE
	var above_ly := surface_ly + 1
	if above_ly >= sz:
		return
	var sq := sz * sz
	if chunk.blocks[above_ly * sq + lz * sz + lx] != 0:
		return   # already occupied (tree trunk...)

	# Sugar cane on sand/grass next to water at sea level
	if world_height == SEA_LEVEL and (surface_bid == B_SAND or surface_bid == B_GRASS):
		if _water_adjacent(wx0 + lx, wz0 + lz) and rng.randf() < 0.10:
			var cane_h := rng.randi_range(1, 3)
			for cy in cane_h:
				if above_ly + cy < sz:
					chunk.set_block_fast(lx, above_ly + cy, lz, B_CANE)
			return

	if surface_bid == B_SAND or surface_bid == B_RED_SAND:
		if biome_id in ["desert", "badlands"] and rng.randf() < 0.012:
			chunk.set_block_fast(lx, above_ly, lz, B_DEAD_BUSH)
		return
	if surface_bid != B_GRASS and surface_bid != B_MOSS and surface_bid != B_MYCELIUM:
		return

	var roll := rng.randf()
	match biome_id:
		"plains", "savanna":
			if roll < 0.10:   chunk.set_block_fast(lx, above_ly, lz, B_SHORT_GRASS)
			elif roll < 0.125: chunk.set_block_fast(lx, above_ly, lz, _pick_flower(rng))
			elif roll < 0.1265: chunk.set_block_fast(lx, above_ly, lz, B_PUMPKIN)
		"meadow", "cherry_grove":
			if roll < 0.14:   chunk.set_block_fast(lx, above_ly, lz, B_SHORT_GRASS)
			elif roll < 0.20: chunk.set_block_fast(lx, above_ly, lz, _pick_flower(rng))
		"forest", "birch_forest":
			if roll < 0.08:   chunk.set_block_fast(lx, above_ly, lz, B_SHORT_GRASS)
			elif roll < 0.095: chunk.set_block_fast(lx, above_ly, lz, _pick_flower(rng))
		"dark_forest", "twilight_hollow":
			if roll < 0.04:   chunk.set_block_fast(lx, above_ly, lz, B_SHORT_GRASS)
			elif roll < 0.055: chunk.set_block_fast(lx, above_ly, lz,
				B_RED_MUSH if rng.randf() < 0.5 else B_BROWN_MUSH)
		"taiga", "snowy_taiga", "boreal_highlands":
			if roll < 0.05:   chunk.set_block_fast(lx, above_ly, lz, B_FERN)
			elif roll < 0.08: chunk.set_block_fast(lx, above_ly, lz, B_SHORT_GRASS)
		"jungle", "bamboo_jungle", "vertical_jungle":
			if roll < 0.10:   chunk.set_block_fast(lx, above_ly, lz, B_FERN)
			elif roll < 0.16: chunk.set_block_fast(lx, above_ly, lz, B_SHORT_GRASS)
			elif roll < 0.168: chunk.set_block_fast(lx, above_ly, lz, B_MELON)
		"swamp", "mangrove_swamp":
			if roll < 0.06:   chunk.set_block_fast(lx, above_ly, lz, B_SHORT_GRASS)
			elif roll < 0.075: chunk.set_block_fast(lx, above_ly, lz, B_BROWN_MUSH)
		"mushroom_fields":
			if roll < 0.06: chunk.set_block_fast(lx, above_ly, lz,
				B_RED_MUSH if rng.randf() < 0.5 else B_BROWN_MUSH)
		_:
			if roll < 0.05: chunk.set_block_fast(lx, above_ly, lz, B_SHORT_GRASS)


const B_MELON := 193

func _pick_flower(rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	if r < 0.45:  return B_POPPY
	if r < 0.90:  return B_DANDELION
	return B_ORCHID


func _water_adjacent(wx: int, wz: int) -> bool:
	# A neighbouring column lower than sea level means water beside this block
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _compute_height(float(wx + off.x), float(wz + off.y)) < SEA_LEVEL:
			return true
	return false


func _try_place_biome_feature(chunk: Chunk, lx: int, surface_ly: int, lz: int,
		biome_id: String, _surface_bid: int, rng: RandomNumberGenerator) -> void:
	var sz := CHUNK_SIZE
	var sq := sz * sz
	match biome_id:
		"volcanic_rifts":
			if rng.randf() < 0.015 and surface_ly + 1 < sz:
				chunk.set_block_fast(lx, surface_ly + 1, lz, B_LAVA)
			elif rng.randf() < 0.008 and surface_ly + 4 < sz:
				var pillar_h := rng.randi_range(2, 4)
				for py in pillar_h:
					if surface_ly + 1 + py < sz:
						chunk.set_block_fast(lx, surface_ly + 1 + py, lz, B_OBSIDIAN)
		"crystal_mesa":
			if rng.randf() < 0.09 and surface_ly + 1 < sz:
				chunk.set_block_fast(lx, surface_ly + 1, lz, B_AMETHYST)
		"petrified_forest":
			if rng.randf() < 0.045 and surface_ly + 4 < sz:
				var trunk_h := rng.randi_range(2, 4)
				for ty in range(1, trunk_h + 1):
					if surface_ly + ty < sz:
						chunk.set_block_fast(lx, surface_ly + ty, lz, B_STONE)
		"oasis":
			if rng.randf() < 0.025 and surface_ly + 6 < sz:
				var trunk_h := rng.randi_range(4, 6)
				for ty in range(1, trunk_h + 1):
					if surface_ly + ty < sz:
						chunk.set_block_fast(lx, surface_ly + ty, lz, B_JUNGLE_LOG)
				var top_ly := surface_ly + trunk_h
				for dx in range(-2, 3):
					for dz in range(-2, 3):
						if abs(dx) == 2 and abs(dz) == 2:
							continue
						var nlx := lx + dx
						var nlz := lz + dz
						if nlx >= 0 and nlx < sz and nlz >= 0 and nlz < sz:
							if top_ly < sz and chunk.blocks[top_ly * sq + nlz * sz + nlx] == 0:
								chunk.set_block_fast(nlx, top_ly, nlz, B_JUNGLE_LEAVES)


# ── Trees ──────────────────────────────────────────────────────────────────────

## Per-biome tree species + density. Returns "" for treeless biomes.
static func tree_species_for_biome(biome_id: String) -> String:
	match biome_id:
		"forest", "plains", "meadow", "swamp", "windswept_hills", "oasis": return "oak"
		"birch_forest":                              return "birch"
		"dark_forest", "twilight_hollow":            return "dark_oak"
		"jungle", "bamboo_jungle", "vertical_jungle": return "jungle"
		"taiga", "snowy_taiga", "boreal_highlands":  return "spruce"
		"savanna":                                   return "acacia"
		"cherry_grove":                              return "cherry"
		"mangrove_swamp":                            return "mangrove"
		_: return ""


static func _tree_density(biome_id: String) -> float:
	match biome_id:
		"forest", "birch_forest":         return 0.060
		"dark_forest":                    return 0.085
		"jungle", "bamboo_jungle", "vertical_jungle": return 0.080
		"taiga", "snowy_taiga":           return 0.065
		"boreal_highlands":               return 0.035
		"cherry_grove":                   return 0.045
		"twilight_hollow":                return 0.050
		"savanna":                        return 0.012
		"swamp", "mangrove_swamp":        return 0.030
		"meadow":                         return 0.004
		"plains":                         return 0.006
		"windswept_hills":                return 0.010
		"oasis":                          return 0.0     # palms handled separately
		_:                                return 0.0


func _try_place_tree(chunk: Chunk, lx: int, surface_ly: int, lz: int,
		biome_id: String, rng: RandomNumberGenerator) -> void:
	var species := tree_species_for_biome(biome_id)
	if species.is_empty():
		return
	if rng.randf() > _tree_density(biome_id):
		return
	var blocks := build_tree(species, rng)
	var sz := CHUNK_SIZE
	var sq := sz * sz
	for b: Array in blocks:
		var nlx: int = lx + b[0]
		var nly: int = surface_ly + 1 + b[1]
		var nlz: int = lz + b[2]
		if nlx < 0 or nlx >= sz or nly < 0 or nly >= sz or nlz < 0 or nlz >= sz:
			continue
		var idx := nly * sq + nlz * sz + nlx
		# Logs always overwrite; leaves only fill air
		var bid: int = b[3]
		if _is_leaf(bid):
			if chunk.blocks[idx] == 0:
				chunk.blocks[idx] = bid
		else:
			chunk.blocks[idx] = bid


static func _is_leaf(bid: int) -> bool:
	return bid == B_OAK_LEAVES or (bid >= B_SPRUCE_LEAVES and bid <= B_JUNGLE_LEAVES) \
		or (bid >= B_ACACIA_LEAVES and bid <= 59)


## Species → list of [dx, dy, dz, block_id] relative to the block ABOVE the surface.
## Shared by generation and sapling growth.
static func build_tree(species: String, rng: RandomNumberGenerator) -> Array:
	var b: Array = []
	match species:
		"spruce":
			var h := rng.randi_range(7, 10)
			for ty in h:
				b.append([0, ty, 0, B_SPRUCE_LOG])
			# Conical leaf layers
			var layer_r := [0, 1, 2, 1, 2, 1, 1]
			var ly := h
			b.append([0, h, 0, B_SPRUCE_LEAVES])
			b.append([0, h + 1, 0, B_SPRUCE_LEAVES])
			var li := 0
			while ly > 2 and li < layer_r.size():
				var r: int = layer_r[li]
				for dx in range(-r, r + 1):
					for dz in range(-r, r + 1):
						if abs(dx) + abs(dz) > r + (1 if r > 1 else 0):
							continue
						if dx == 0 and dz == 0:
							continue
						b.append([dx, ly, dz, B_SPRUCE_LEAVES])
				ly -= 1
				li += 1
		"birch":
			var h := rng.randi_range(5, 7)
			for ty in h:
				b.append([0, ty, 0, B_BIRCH_LOG])
			_blob_leaves(b, h, 2, B_BIRCH_LEAVES)
		"jungle":
			var h := rng.randi_range(8, 12)
			for ty in h:
				b.append([0, ty, 0, B_JUNGLE_LOG])
			_blob_leaves(b, h, 3, B_JUNGLE_LEAVES)
		"acacia":
			var h := rng.randi_range(4, 6)
			for ty in h:
				b.append([0, ty, 0, B_ACACIA_LOG])
			# Flat umbrella canopy
			for dx in range(-3, 4):
				for dz in range(-3, 4):
					if abs(dx) + abs(dz) > 4:
						continue
					b.append([dx, h, dz, B_ACACIA_LEAVES])
					if abs(dx) + abs(dz) <= 2:
						b.append([dx, h + 1, dz, B_ACACIA_LEAVES])
		"dark_oak":
			var h := rng.randi_range(5, 7)
			for ty in h:
				b.append([0, ty, 0, B_DARK_LOG])
			_blob_leaves(b, h, 3, B_DARK_LEAVES)
		"cherry":
			var h := rng.randi_range(4, 6)
			for ty in h:
				b.append([0, ty, 0, B_CHERRY_LOG])
			# Wide fluffy pink canopy
			for dy in range(-1, 2):
				var r := 3 if dy <= 0 else 2
				for dx in range(-r, r + 1):
					for dz in range(-r, r + 1):
						if dx * dx + dz * dz > r * r + 1:
							continue
						if dx == 0 and dz == 0 and dy < 0:
							continue
						b.append([dx, h + dy, dz, B_CHERRY_LEAVES])
		"mangrove":
			var h := rng.randi_range(5, 7)
			for ty in h:
				b.append([0, ty, 0, B_MANGROVE_LOG])
			_blob_leaves(b, h, 2, 59)
		_:   # oak
			var h := rng.randi_range(4, 6)
			for ty in h:
				b.append([0, ty, 0, B_OAK_LOG])
			_blob_leaves(b, h, 2, B_OAK_LEAVES)
	return b


static func _blob_leaves(b: Array, trunk_h: int, radius: int, leaf_id: int) -> void:
	for dy in range(-2, 2):
		var r := radius if dy < 1 else radius - 1
		if r < 1:
			r = 1
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if dx * dx + dz * dz > r * r + 1:
					continue
				if dx == 0 and dz == 0 and dy < 0:
					continue   # trunk space
				b.append([dx, trunk_h + dy, dz, leaf_id])


## Grow a tree in the live world (sapling growth) — crosses chunk borders.
static func grow_tree_at(chunk_manager: ChunkManager, base: Vector3i, species: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(base)
	var blocks := build_tree(species, rng)
	for b: Array in blocks:
		var pos := base + Vector3i(b[0], b[1], b[2])
		var cur := chunk_manager.get_block_at(pos)
		var bid: int = b[3]
		if _is_leaf(bid):
			if cur == 0:
				chunk_manager.set_block_at(pos, bid)
		else:
			if cur == 0 or _is_leaf(cur) or pos == base:
				chunk_manager.set_block_at(pos, bid)


# ── End shrine (gateway to The End) ────────────────────────────────────────────

const SHRINE_CELL   := 700
const SHRINE_ODDS   := 62
const SHRINE_RADIUS := 2000

func _place_end_shrines(chunk: Chunk, wx0: int, wy0: int, wz0: int) -> void:
	var cx0 := floori(float(wx0 - 8) / float(SHRINE_CELL))
	var cx1 := floori(float(wx0 + 23) / float(SHRINE_CELL))
	var cz0 := floori(float(wz0 - 8) / float(SHRINE_CELL))
	var cz1 := floori(float(wz0 + 23) / float(SHRINE_CELL))
	for cx in range(cx0, cx1 + 1):
		for cz in range(cz0, cz1 + 1):
			var h: int = (((cx * 68492113) ^ (cz * 91738529) ^ (_seed * 55555333)) & 0x7FFFFFFF)
			if h % 100 >= SHRINE_ODDS:
				continue
			var ox := (h >> 6)  % (SHRINE_CELL - 40) + 20
			var oz := (h >> 16) % (SHRINE_CELL - 40) + 20
			var wx := cx * SHRINE_CELL + ox
			var wz := cz * SHRINE_CELL + oz
			var d2 := wx * wx + wz * wz
			if d2 > SHRINE_RADIUS * SHRINE_RADIUS or d2 < 300 * 300:
				continue
			var surf := _compute_height(float(wx), float(wz))
			if surf <= SEA_LEVEL:
				continue   # keep shrines on dry land
			_write_end_shrine(chunk, wx, surf + 1, wz, wx0, wy0, wz0)


func _write_end_shrine(chunk: Chunk, wx: int, wy: int, wz: int,
		wx0: int, wy0: int, wz0: int) -> void:
	var parts: Array = []
	# 7×7 end stone brick platform
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			parts.append([dx, -1, dz, E_BRICKS])
			# Clear space above the platform
			for dy in range(0, 4):
				parts.append([dx, dy, dz, 0])
	# 3×3 portal pool in the centre
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			parts.append([dx, 0, dz, B_END_PORTAL])
	# Frame ring around the pool
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			if abs(dx) == 2 or abs(dz) == 2:
				parts.append([dx, 0, dz, B_END_FRAME])
	# Corner pillars with torches
	for corner in [[-3, -3], [3, -3], [-3, 3], [3, 3]]:
		for dy in range(0, 3):
			parts.append([corner[0], dy, corner[1], E_BRICKS])
		parts.append([corner[0], 3, corner[1], B_TORCH])
	const SZ := 16
	for p: Array in parts:
		var lx: int = (wx + p[0]) - wx0
		var ly: int = (wy + p[1]) - wy0
		var lz: int = (wz + p[2]) - wz0
		if lx < 0 or lx >= SZ or ly < 0 or ly >= SZ or lz < 0 or lz >= SZ:
			continue
		chunk.set_block_fast(lx, ly, lz, p[3])


# ─── NETHER ──────────────────────────────────────────────────────────────────

## Nether biome from 2D noise: wastes / crimson / warped / soul valley / basalt.
func _nether_biome(wx: float, wz: float) -> String:
	var t := _biome_temp.get_noise_2d(wx * 3.0, wz * 3.0)
	var h := _biome_humid.get_noise_2d(wx * 3.0, wz * 3.0)
	if t > 0.40:               return "basalt_deltas"
	if t < -0.40:              return "soul_sand_valley"
	if h > 0.35:               return "crimson_forest"
	if h < -0.35:              return "warped_forest"
	return "nether_wastes"


func _gen_nether(chunk: Chunk) -> void:
	var wx0 := chunk.chunk_pos.x * CHUNK_SIZE
	var wy0 := chunk.chunk_pos.y * CHUNK_SIZE
	var wz0 := chunk.chunk_pos.z * CHUNK_SIZE
	var sz := CHUNK_SIZE
	var sq := sz * sz

	# No open sky in the Nether — block light only
	chunk.world_surface.fill(400)

	for lx in sz:
		for lz in sz:
			var wx := float(wx0 + lx)
			var wz := float(wz0 + lz)
			var biome := _nether_biome(wx, wz)
			for ly in sz:
				var wy := wy0 + ly
				var idx := ly * sq + lz * sz + lx
				if wy <= 4 or wy >= 124:
					chunk.blocks[idx] = B_BEDROCK
					continue
				var n := _continental.get_noise_3d(wx * 0.5, float(wy), wz * 0.5)
				if n > -0.1:
					chunk.blocks[idx] = _nether_stone(biome, wx, float(wy), wz)
				elif wy <= 32:
					chunk.blocks[idx] = B_LAVA

	# Surface conversion + decorations (nylium, fungi trees, glowstone)
	_nether_decorate(chunk, wx0, wy0, wz0)
	# Nether ores
	_place_nether_ores(chunk, wx0, wy0, wz0)

	chunk.rebuild_heightmap()
	# Echo Entity arena — placed deterministically in Nether
	_place_nether_echo_arenas(chunk, wx0, wy0, wz0)
	chunk.is_dirty = true


func _nether_stone(biome: String, wx: float, wy: float, wz: float) -> int:
	match biome:
		"basalt_deltas":
			var v := _detail.get_noise_3d(wx, wy, wz)
			if v > 0.35:  return N_MAGMA
			if v > -0.1:  return N_BASALT
			return N_BLACKSTONE
		"soul_sand_valley":
			return N_SOUL_SAND if _detail.get_noise_3d(wx, wy, wz) > 0.0 else N_SOUL_SOIL
		_:
			return N_RACK


func _nether_decorate(chunk: Chunk, wx0: int, wy0: int, wz0: int) -> void:
	var sz := CHUNK_SIZE
	var sq := sz * sz
	var rng := RandomNumberGenerator.new()
	for lx in sz:
		for lz in sz:
			var wx := float(wx0 + lx)
			var wz := float(wz0 + lz)
			var biome := _nether_biome(wx, wz)
			for ly in range(sz - 2, 0, -1):
				var idx := ly * sq + lz * sz + lx
				var above := (ly + 1) * sq + lz * sz + lx
				var bid: int = chunk.blocks[idx]
				# Ceiling glowstone clusters
				if bid == N_RACK and chunk.blocks[above] == N_RACK \
						and ly >= 2 and chunk.blocks[idx - sq] == 0:
					rng.seed = hash(Vector3i(wx0 + lx, wy0 + ly, wz0 + lz)) ^ _seed
					if rng.randf() < 0.006:
						var drop := rng.randi_range(1, 3)
						for dy in drop:
							if ly - dy >= 0 and chunk.blocks[(ly - dy) * sq + lz * sz + lx] == 0:
								chunk.set_block_fast(lx, ly - dy, lz, N_GLOWSTONE)
					continue
				# Surface: solid with air above
				if bid == N_RACK and chunk.blocks[above] == 0:
					rng.seed = hash(Vector3i(wx0 + lx, wy0 + ly, wz0 + lz)) ^ _seed
					match biome:
						"crimson_forest":
							chunk.blocks[idx] = N_CRIMSON_NYL
							if rng.randf() < 0.020:
								_nether_fungus(chunk, lx, ly + 1, lz, N_CRIMSON_STEM, N_WART, rng)
						"warped_forest":
							chunk.blocks[idx] = N_WARPED_NYL
							if rng.randf() < 0.020:
								_nether_fungus(chunk, lx, ly + 1, lz, N_WARPED_STEM, N_WARPED_WART, rng)
						_:
							pass


func _nether_fungus(chunk: Chunk, lx: int, base_ly: int, lz: int,
		stem_id: int, wart_id: int, rng: RandomNumberGenerator) -> void:
	var sz := CHUNK_SIZE
	var sq := sz * sz
	var h := rng.randi_range(4, 7)
	for ty in h:
		if base_ly + ty < sz:
			chunk.set_block_fast(lx, base_ly + ty, lz, stem_id)
	var top := base_ly + h
	for dy in range(-1, 2):
		var r := 2 if dy <= 0 else 1
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if dx * dx + dz * dz > r * r + 1:
					continue
				var nlx := lx + dx
				var nly := top + dy
				var nlz := lz + dz
				if nlx >= 0 and nlx < sz and nly >= 0 and nly < sz and nlz >= 0 and nlz < sz:
					if chunk.blocks[nly * sq + nlz * sz + nlx] == 0:
						chunk.set_block_fast(nlx, nly, nlz, wart_id)


## Nether ore veins: gold, quartz, ancient debris + the new ores.
const _NETHER_VEINS := [
	# ore           miny maxy tries rmin rmax
	[N_QUARTZ,       10, 117,  5,   2,   3],
	[N_GOLD,         10, 117,  4,   1,   2],
	[N_SULFUR,       28,  95,  2,   1,   2],   # new: sulfur pockets mid-height
	[N_URANIUM,       6,  38,  1,   1,   1],   # new: rare uranium near the lava sea
	[N_VOID_QUARTZ,   6,  30,  1,   1,   1],   # new: void quartz in the depths
	[N_DEBRIS,        8,  22,  1,   1,   1],   # ancient debris
]

func _place_nether_ores(chunk: Chunk, wx0: int, wy0: int, wz0: int) -> void:
	var sz := Chunk.SIZE
	var sq := Chunk.SIZE_SQ
	var rng := RandomNumberGenerator.new()
	rng.seed = abs((_seed + 7) ^ (wx0 * 2749) ^ (wy0 * 15733) ^ (wz0 * 9241))
	for vein_def in _NETHER_VEINS:
		var ore_id: int = vein_def[0]
		var min_wy: int = vein_def[1]
		var max_wy: int = vein_def[2]
		var tries:  int = vein_def[3]
		var rmin:   int = vein_def[4]
		var rmax:   int = vein_def[5]
		if wy0 + sz <= min_wy or wy0 > max_wy:
			continue
		# Ancient debris & uranium only spawn on a fraction of attempts
		if (ore_id == N_DEBRIS or ore_id == N_URANIUM) and rng.randf() > 0.45:
			continue
		for _t in tries:
			var cx: int = wx0 + rng.randi() % sz
			var cy: int = clampi(wy0 + (rng.randi() % sz), min_wy, max_wy)
			var cz: int = wz0 + rng.randi() % sz
			var radius: int = rng.randi_range(rmin, rmax)
			for dx in range(-radius, radius + 1):
				for dy in range(-radius, radius + 1):
					for dz in range(-radius, radius + 1):
						if dx*dx + dy*dy + dz*dz > radius*radius:
							continue
						var lx: int = cx + dx - wx0
						var ly: int = cy + dy - wy0
						var lz: int = cz + dz - wz0
						if lx < 0 or lx >= sz or ly < 0 or ly >= sz or lz < 0 or lz >= sz:
							continue
						var idx: int = ly * sq + lz * sz + lx
						if chunk.blocks[idx] == N_RACK:
							chunk.blocks[idx] = ore_id


func _place_nether_echo_arenas(chunk: Chunk, wx0: int, wy0: int, wz0: int) -> void:
	# One arena every 350 blocks in Nether, within 400 of spawn
	const ARENA_CELL   := 350
	const ARENA_RADIUS := 400
	const ARENA_ODDS   := 55
	const NETHER_FLOOR := 35   # approx surface y in nether
	var cx0 := floori(float(wx0 - 10) / float(ARENA_CELL))
	var cx1 := floori(float(wx0 + 15 + 10) / float(ARENA_CELL))
	var cz0 := floori(float(wz0 - 10) / float(ARENA_CELL))
	var cz1 := floori(float(wz0 + 15 + 10) / float(ARENA_CELL))
	for cx in range(cx0, cx1 + 1):
		for cz in range(cz0, cz1 + 1):
			var h: int = (((cx * 91234567) ^ (cz * 45678901) ^ (_seed * 7654321)) & 0x7FFFFFFF)
			if h % 100 >= ARENA_ODDS:
				continue
			var ox := (h >> 5)  % (ARENA_CELL - 20) + 10
			var oz := (h >> 17) % (ARENA_CELL - 20) + 10
			var wx := cx * ARENA_CELL + ox
			var wz := cz * ARENA_CELL + oz
			if wx * wx + wz * wz > ARENA_RADIUS * ARENA_RADIUS:
				continue
			_write_nether_echo_arena(chunk, wx, NETHER_FLOOR, wz, wx0, wy0, wz0)


func _write_nether_echo_arena(chunk: Chunk, wx: int, wy: int, wz: int,
		wx0: int, wy0: int, wz0: int) -> void:
	const SZ := 16
	var blocks := _build_nether_echo_arena()
	for b: Array in blocks:
		var lx: int = (wx + b[0]) - wx0
		var ly: int = (wy + b[1]) - wy0
		var lz: int = (wz + b[2]) - wz0
		if lx < 0 or lx >= SZ or ly < 0 or ly >= SZ or lz < 0 or lz >= SZ:
			continue
		chunk.set_block_fast(lx, ly, lz, b[3])


func _build_nether_echo_arena() -> Array:
	var b := []
	const B_AIR := 0
	# Circular arena walls (9-radius octagon approximation using 15×15 box)
	for dy in range(0, 4):
		for dx in range(-7, 8):
			for dz in range(-7, 8):
				if abs(dx) == 7 or abs(dz) == 7:
					b.append([dx, dy, dz, N_RACK])
	# Clear interior 13×13×3
	for dy in range(1, 4):
		for dx in range(-6, 7):
			for dz in range(-6, 7):
				b.append([dx, dy, dz, B_AIR])
	# Floor
	for dx in range(-6, 7):
		for dz in range(-6, 7):
			b.append([dx, 0, dz, B_COBBLE])
	# Glowstone pillars at corners
	for dx in [-6, 6]:
		for dz in [-6, 6]:
			for dy in [0, 1, 2, 3, 4]:
				b.append([dx, dy, dz, N_GLOWSTONE])
	# Entry gap (south)
	for dy in [1, 2, 3]:
		b.append([0, dy, -7, B_AIR])
		b.append([1, dy, -7, B_AIR])
	return b


# ─── THE END ─────────────────────────────────────────────────────────────────

func _gen_end(chunk: Chunk) -> void:
	var wx0 := chunk.chunk_pos.x * CHUNK_SIZE
	var wy0 := chunk.chunk_pos.y * CHUNK_SIZE
	var wz0 := chunk.chunk_pos.z * CHUNK_SIZE
	var sz := CHUNK_SIZE
	var sq := sz * sz
	var rng := RandomNumberGenerator.new()

	for lx in sz:
		for lz in sz:
			var wx := float(wx0 + lx)
			var wz := float(wz0 + lz)
			var dist := sqrt(wx * wx + wz * wz)
			var height := _end_height(wx, wz, dist)
			chunk.world_surface[lz * sz + lx] = height if height > 0 else -99999
			if height <= 0:
				continue
			var depth := _end_thickness(wx, wz, dist)
			for ly in sz:
				var wy := wy0 + ly
				if wy <= height and wy > height - depth:
					chunk.blocks[ly * sq + lz * sz + lx] = E_STONE

			# Chorus plants on the outer islands
			if dist > 700.0 and height > 0:
				var sly := height - wy0
				if sly >= 0 and sly + 4 < sz:
					rng.seed = hash(Vector3i(int(wx), height, int(wz))) ^ _seed
					if rng.randf() < 0.012:
						var ph := rng.randi_range(1, 3)
						for py in ph:
							chunk.set_block_fast(lx, sly + 1 + py, lz, E_CHORUS_PLANT)
						chunk.set_block_fast(lx, sly + 1 + ph, lz, E_CHORUS_FLOWER)
					elif rng.randf() < 0.004:
						chunk.set_block_fast(lx, sly + 1, lz, E_CRYSTALLINE)

	# End ores in the islands
	_place_end_ores(chunk, wx0, wy0, wz0)

	# Return portal on the central island (near origin)
	_place_end_return_portal(chunk, wx0, wy0, wz0)

	chunk.rebuild_heightmap()
	chunk.is_dirty = true


## Island surface height at a position (0 = void).
func _end_height(wx: float, wz: float, dist: float) -> int:
	if dist < 420.0:
		# Central island: big, mostly flat top
		var island_f := clampf(1.0 - dist / 420.0, 0.0, 1.0)
		var nv := _continental.get_noise_2d(wx * 0.02, wz * 0.02)
		return roundi(52.0 + island_f * 14.0 + nv * 6.0)
	if dist < 720.0:
		return 0   # the void ring
	# Outer islands: noise-gated floating masses
	var v := _continental.get_noise_2d(wx * 0.012, wz * 0.012)
	if v < 0.30:
		return 0
	var nv2 := _detail.get_noise_2d(wx * 0.06, wz * 0.06)
	return roundi(55.0 + (v - 0.30) * 40.0 + nv2 * 5.0)


func _end_thickness(wx: float, wz: float, dist: float) -> int:
	if dist < 420.0:
		return 26
	var v := _continental.get_noise_2d(wx * 0.012, wz * 0.012)
	return clampi(roundi((v - 0.28) * 60.0), 3, 22)


const _END_VEINS := [
	# ore            tries rmin rmax
	[E_VOID_CRYSTAL,  3,   1,   2],
	[E_ENDER_SHARD,   2,   1,   2],
	[E_NULLITE,       1,   1,   1],
]

func _place_end_ores(chunk: Chunk, wx0: int, wy0: int, wz0: int) -> void:
	if wy0 > 80 or wy0 + CHUNK_SIZE < 20:
		return
	var sz := Chunk.SIZE
	var sq := Chunk.SIZE_SQ
	var rng := RandomNumberGenerator.new()
	rng.seed = abs((_seed + 13) ^ (wx0 * 4483) ^ (wy0 * 27191) ^ (wz0 * 12007))
	# Only outer islands hold End ores — makes the trip worth it
	var center_dist := Vector2(wx0 + 8, wz0 + 8).length()
	if center_dist < 700.0:
		return
	for vein_def in _END_VEINS:
		var ore_id: int = vein_def[0]
		var tries:  int = vein_def[1]
		var rmin:   int = vein_def[2]
		var rmax:   int = vein_def[3]
		if ore_id == E_NULLITE and rng.randf() > 0.35:
			continue
		for _t in tries:
			var cx: int = wx0 + rng.randi() % sz
			var cy: int = wy0 + rng.randi() % sz
			var cz: int = wz0 + rng.randi() % sz
			var radius: int = rng.randi_range(rmin, rmax)
			for dx in range(-radius, radius + 1):
				for dy in range(-radius, radius + 1):
					for dz in range(-radius, radius + 1):
						if dx*dx + dy*dy + dz*dz > radius*radius:
							continue
						var lx: int = cx + dx - wx0
						var ly: int = cy + dy - wy0
						var lz: int = cz + dz - wz0
						if lx < 0 or lx >= sz or ly < 0 or ly >= sz or lz < 0 or lz >= sz:
							continue
						var idx: int = ly * sq + lz * sz + lx
						if chunk.blocks[idx] == E_STONE:
							chunk.blocks[idx] = ore_id


## Small obsidian platform + return portal at the End spawn.
func _place_end_return_portal(chunk: Chunk, wx0: int, wy0: int, wz0: int) -> void:
	# Platform spans (-2..2, 63, -2..2); portal pool at (-1..1, 64, -1..1)
	var parts: Array = []
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			parts.append([dx, 63, dz, B_OBSIDIAN])
			for dy in range(64, 70):
				parts.append([dx, dy, dz, 0])
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			parts.append([dx, 64, dz, B_END_PORTAL])
	const SZ := 16
	for p: Array in parts:
		var lx: int = p[0] + 8 - wx0        # platform centred at world (8, y, 8)
		var ly: int = p[1] - wy0
		var lz: int = p[2] + 8 - wz0
		if lx < 0 or lx >= SZ or ly < 0 or ly >= SZ or lz < 0 or lz >= SZ:
			continue
		chunk.set_block_fast(lx, ly, lz, p[3])
