## WorldGenerator.gd — Procedural world generation (per 16x16x16 chunk).
class_name WorldGenerator
extends RefCounted

const CHUNK_SIZE := 16
const WORLD_MIN_Y := -128
const SEA_LEVEL := 63

var _seed: int = 0
var _dimension: String = "overworld"

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
	match _dimension:
		"overworld": _gen_overworld(chunk)
		"nether":    _gen_nether(chunk)
		"the_end":   _gen_end(chunk)
		_:           _gen_overworld(chunk)


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

	# Single-pass ore placement (replaces 9 separate passes)
	_place_ores_fast(chunk, wx0, wy0, wz0)

	# Surface features — pass cached data to avoid re-sampling biomes
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
			chunk.set_block_fast(lx, ly, lz, 100)
		return

	var stone_id := 50 if wy < 0 else 1
	if wy < height - 3:
		chunk.set_block_fast(lx, ly, lz, stone_id)
	elif wy < height:
		chunk.set_block_fast(lx, ly, lz, 3)
	elif wy == height:
		chunk.set_block_fast(lx, ly, lz, _surface_block(biome_id, height))
	elif wy <= SEA_LEVEL:
		if wy == height + 1 and height < SEA_LEVEL - 3:
			chunk.set_block_fast(lx, ly, lz, 9)
		else:
			chunk.set_block_fast(lx, ly, lz, 90)


func _surface_block(biome_id: String, height: int) -> int:
	if height < SEA_LEVEL:
		return 8  # sand (underwater surface)
	match biome_id:
		"desert", "badlands", "beach", "oasis": return 8    # sand
		"gravel_beach":                return 9              # gravel (red_sand used as gravel here)
		"mushroom_fields":             return 197            # mycelium
		"swamp", "mangrove_swamp":     return 2              # grass (wet)
		"volcanic_rifts":              return 240            # basalt
		"boreal_highlands":            return 241            # snow_block
		"petrified_forest":            return 4              # coarse_dirt
		"crystal_mesa":                return 242            # orange_terracotta
		"twilight_hollow":             return 196            # moss_block
		_:                             return 2              # grass_block


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
				if bid != 1 and bid != 50 and bid != 3:
					continue
				if absf(_cave_3d.get_noise_3d(wx, wyfloat, wz)) < 0.05:
					chunk.blocks[idx] = 0
				elif bid != 3 and _cave_cheese.get_noise_3d(wx*0.7, wyfloat*0.5, wz*0.7) > 0.55 and wy < 50:
					chunk.blocks[idx] = 0


## Ore placement: blob-based veins for satisfying vein mining.
## Each chunk rolls for several veins per ore type; blobs are 3-D spheres.
func _place_ores_fast(chunk: Chunk, wx0: int, wy0: int, wz0: int) -> void:
	_place_ore_veins(chunk, wx0, wy0, wz0)


## Vein table: {ore_id, min_y, max_y, tries, size_min, size_max}
const _ORE_VEINS := [
	# ore   miny  maxy  tries  rmin  rmax
	[30,    5,   120,    6,    2,    4 ],   # coal    (common,   big)
	[32,    5,    80,    4,    2,    4 ],   # iron    (common)
	[36,    5,    32,    2,    2,    3 ],   # gold    (uncommon)
	[42,    5,    16,    1,    1,    3 ],   # diamond (rare,     small)
]

func _place_ore_veins(chunk: Chunk, wx0: int, wy0: int, wz0: int) -> void:
	var sz := Chunk.SIZE
	var sq := Chunk.SIZE_SQ
	var rng := RandomNumberGenerator.new()
	# Seed per-chunk so veins are deterministic
	rng.seed = abs(_seed ^ (wx0 * 1619) ^ (wy0 * 31337) ^ (wz0 * 6271))

	for vein_def in _ORE_VEINS:
		var ore_id:  int = vein_def[0]
		var min_wy:  int = vein_def[1]
		var max_wy:  int = vein_def[2]
		var tries:   int = vein_def[3]
		var rmin:    int = vein_def[4]
		var rmax:    int = vein_def[5]

		# Skip entirely if this chunk's Y range doesn't overlap the ore's range
		if wy0 + sz <= min_wy or wy0 > max_wy:
			continue

		for _t in tries:
			# Pick a random world-space centre inside the valid Y band
			var cx: int = wx0 + rng.randi() % sz
			var cy: int = clampi(rng.randi_range(min_wy, max_wy), min_wy, max_wy)
			var cz: int = wz0 + rng.randi() % sz
			var radius: int = rng.randi_range(rmin, rmax)

			# Fill the sphere — only touch blocks that belong to this chunk
			for dx in range(-radius, radius + 1):
				for dy in range(-radius, radius + 1):
					for dz in range(-radius, radius + 1):
						if dx*dx + dy*dy + dz*dz > radius*radius:
							continue
						var wx: int = cx + dx
						var wy: int = cy + dy
						var wz: int = cz + dz
						# Must be inside this chunk
						var lx: int = wx - wx0
						var ly: int = wy - wy0
						var lz: int = wz - wz0
						if lx < 0 or lx >= sz or ly < 0 or ly >= sz or lz < 0 or lz >= sz:
							continue
						var idx: int = ly * sq + lz * sz + lx
						# Only replace stone/deepslate
						if chunk.blocks[idx] == 1 or chunk.blocks[idx] == 50:
							chunk.blocks[idx] = ore_id


func _place_surface_features(chunk: Chunk, wx0: int, wy0: int, wz0: int,
		heights: PackedInt32Array, biomes: Array) -> void:
	var rng := RandomNumberGenerator.new()
	var sz := Chunk.SIZE
	var sq := Chunk.SIZE_SQ
	for lx in sz:
		for lz in sz:
			var world_height: int = heights[lx * sz + lz]
			var surface_ly := world_height - wy0
			# Need at least 6 blocks headroom for trees; shorter features checked per-biome
			if surface_ly < 0 or surface_ly + 6 >= sz:
				continue
			var surface_bid: int = chunk.blocks[surface_ly * sq + lz * sz + lx]
			# Skip air, fluids — all solid surfaces are eligible for features
			if surface_bid == 0 or surface_bid == 90 or surface_bid == 91:
				continue
			rng.seed = hash(Vector3i(wx0 + lx, world_height, wz0 + lz)) ^ _seed
			var biome_id: String = biomes[lx * sz + lz]
			_try_place_tree(chunk, lx, surface_ly, lz, biome_id, rng)
			_try_place_biome_feature(chunk, lx, surface_ly, lz, biome_id, surface_bid, rng)


func _try_place_biome_feature(chunk: Chunk, lx: int, surface_ly: int, lz: int,
		biome_id: String, _surface_bid: int, rng: RandomNumberGenerator) -> void:
	var sz := CHUNK_SIZE
	var sq := sz * sz
	match biome_id:
		"volcanic_rifts":
			if rng.randf() < 0.015 and surface_ly + 1 < sz:
				chunk.set_block_fast(lx, surface_ly + 1, lz, 91)  # lava surface pool
			elif rng.randf() < 0.008 and surface_ly + 4 < sz:
				var pillar_h := rng.randi_range(2, 4)
				for py in pillar_h:
					if surface_ly + 1 + py < sz:
						chunk.set_block_fast(lx, surface_ly + 1 + py, lz, 101)  # obsidian pillar
		"crystal_mesa":
			if rng.randf() < 0.09 and surface_ly + 1 < sz:
				chunk.set_block_fast(lx, surface_ly + 1, lz, 222)  # amethyst_cluster
		"petrified_forest":
			if rng.randf() < 0.045 and surface_ly + 4 < sz:
				var trunk_h := rng.randi_range(2, 4)
				for ty in range(1, trunk_h + 1):
					if surface_ly + ty < sz:
						chunk.set_block_fast(lx, surface_ly + ty, lz, 1)  # stone "petrified log"
		"oasis":
			if rng.randf() < 0.025 and surface_ly + 6 < sz:
				var trunk_h := rng.randi_range(4, 6)
				for ty in range(1, trunk_h + 1):
					if surface_ly + ty < sz:
						chunk.set_block_fast(lx, surface_ly + ty, lz, 17)  # jungle_log as palm trunk
				var top_ly := surface_ly + trunk_h
				for dx in range(-2, 3):
					for dz in range(-2, 3):
						if abs(dx) == 2 and abs(dz) == 2:
							continue
						var nlx := lx + dx
						var nlz := lz + dz
						if nlx >= 0 and nlx < sz and nlz >= 0 and nlz < sz:
							if top_ly < sz and chunk.blocks[top_ly * sq + nlz * sz + nlx] == 0:
								chunk.set_block_fast(nlx, top_ly, nlz, 12)  # oak_leaves crown


func _try_place_tree(chunk: Chunk, lx: int, surface_ly: int, lz: int,
		biome_id: String, rng: RandomNumberGenerator) -> void:
	# Biomes with no conventional trees (handled by _try_place_biome_feature or feature-less)
	if biome_id in ["desert", "badlands", "beach", "frozen_ocean", "snowy_plains",
			"volcanic_rifts", "crystal_mesa", "petrified_forest", "oasis"]:
		return
	if rng.randf() > 0.05:
		return
	# Tree height
	var trunk_h := rng.randi_range(4, 6)
	var sz := CHUNK_SIZE
	var sq := sz * sz
	# Trunk
	for ty in trunk_h:
		var tly := surface_ly + 1 + ty
		if tly < sz:
			chunk.set_block_fast(lx, tly, lz, _wood_log(biome_id))
	# Leaves
	var leaf_id := _leaf_block(biome_id)
	var top_ly := surface_ly + 1 + trunk_h
	for leaf_y in range(top_ly - 2, top_ly + 2):
		if leaf_y < 0 or leaf_y >= sz:
			continue
		var radius := 2 if leaf_y < top_ly else 1
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if dx == 0 and dz == 0 and leaf_y < top_ly:
					continue
				var nlx := lx + dx
				var nlz := lz + dz
				if nlx >= 0 and nlx < sz and nlz >= 0 and nlz < sz:
					if chunk.blocks[leaf_y * sq + nlz * sz + nlx] == 0:
						chunk.set_block_fast(nlx, leaf_y, nlz, leaf_id)


func _wood_log(biome_id: String) -> int:
	match biome_id:
		"birch_forest":                              return 15  # birch_log
		"jungle", "bamboo_jungle":                   return 17  # jungle_log
		"taiga", "snowy_taiga", "boreal_highlands":  return 13  # spruce_log
		"dark_forest", "twilight_hollow":            return 21  # dark_oak_log
		_:                                           return 10  # oak_log


func _leaf_block(_biome_id: String) -> int:
	return 12  # oak_leaves (only leaf type currently defined)


# ─── NETHER ──────────────────────────────────────────────────────────────────

func _gen_nether(chunk: Chunk) -> void:
	var wx0 := chunk.chunk_pos.x * CHUNK_SIZE
	var wy0 := chunk.chunk_pos.y * CHUNK_SIZE
	var wz0 := chunk.chunk_pos.z * CHUNK_SIZE
	var sz := CHUNK_SIZE
	var sq := sz * sz
	for lx in sz:
		for lz in sz:
			var wx := float(wx0 + lx)
			var wz := float(wz0 + lz)
			for ly in sz:
				var wy := wy0 + ly
				var idx := ly * sq + lz * sz + lx
				if wy <= 4 or wy >= 124:
					chunk.blocks[idx] = 100
					continue
				var n := _continental.get_noise_3d(wx * 0.5, float(wy), wz * 0.5)
				if n > -0.1:
					chunk.blocks[idx] = 1000
					if _ore.get_noise_3d(wx, float(wy), wz) > 0.7:
						chunk.blocks[idx] = 1002
				elif wy <= 32:
					chunk.blocks[idx] = 91
	chunk.rebuild_heightmap()
	# Echo Entity arena — placed deterministically in Nether
	_place_nether_echo_arenas(chunk, wx0, wy0, wz0)
	chunk.is_dirty = true


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
	const B_NRCK := 1000   # netherrack
	const B_SLSND := 1003  # soul sand (if defined, else netherrack)
	const B_GLOWST := 110
	const B_COBBLE := 6
	# Circular arena walls (9-radius octagon approximation using 15×15 box)
	for dy in range(0, 4):
		for dx in range(-7, 8):
			for dz in range(-7, 8):
				if abs(dx) == 7 or abs(dz) == 7:
					b.append([dx, dy, dz, B_NRCK])
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
				b.append([dx, dy, dz, B_GLOWST])
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
	for lx in sz:
		for lz in sz:
			var wx := float(wx0 + lx)
			var wz := float(wz0 + lz)
			var dist := sqrt(wx * wx + wz * wz)
			if dist > 1000.0:
				continue
			var island_f := clampf(1.0 - dist / 700.0, 0.0, 1.0)
			var nv := _continental.get_noise_2d(wx * 0.02, wz * 0.02)
			var height := roundi(50.0 + island_f * 30.0 + nv * 15.0)
			for ly in sz:
				if wy0 + ly <= height:
					chunk.blocks[ly * sq + lz * sz + lx] = 2000
	chunk.rebuild_heightmap()
	chunk.is_dirty = true
