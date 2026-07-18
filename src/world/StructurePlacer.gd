## StructurePlacer.gd — Deterministic placement of exploration structures containing skill altars.
## Called per-chunk during world generation; places only the blocks that fall within the
## current 16×16×16 chunk bounds (multi-chunk structures fill in naturally as neighbours generate).
class_name StructurePlacer
extends RefCounted

const CELL_SIZE   := 200   # XZ grid cell size in blocks
const MAX_RADIUS  := 500   # structures only within this distance from spawn (0,0)
const PLACE_ODDS  := 50    # % chance a cell contains a structure (out of 100)
const HALF_FOOT   := 7     # max half-footprint of any structure (determines cell overlap check)

# Boss fortress constants (one per larger cell, rarer)
const FORT_CELL   := 400   # one fortress every ~400 blocks
const FORT_ODDS   := 60    # % chance a cell has a fortress
const FORT_RADIUS := 900   # fortresses within this distance from spawn
const FORT_MIN_RADIUS := 260  # ...but never right on top of the spawn point
const FORT_HALF   := 8     # half-footprint of fortress

# Biome castle constants
const CASTLE_CELL   := 600   # one castle per ~600-block cell
const CASTLE_ODDS   := 60    # % chance a cell has a castle
const CASTLE_RADIUS := 900   # castles within this distance from spawn
const CASTLE_HALF   := 10    # half-footprint (largest castle is ~19×15)

# Road network constants
const ROUTE_CELL  := 160   # road node grid cell (denser than structure grid)
const ROUTE_PROB  := 75    # % chance a cell has a road node
const ROUTE_REACH := 450   # roads only within this distance from spawn
const PATH_HALF   := 1.6   # half-width of path in blocks (~3 blocks wide total)
const SEA_LEVEL_R := 63    # sea level reference (matches WorldGenerator.SEA_LEVEL)

# Block ID constants used in structure layouts
const B_AIR     :=   0
const B_STONE   :=   1
const B_COBBLE  :=   6
const B_COARSE  :=   4   # coarse_dirt — path surface material
const B_OAK_LOG :=  10
const B_OAK_PLK :=  11
const B_GLASS   :=  80
const B_IRON_BAR:=  82
const B_BOOK    := 124
const B_RDST_BLK:= 150
const B_GLOWST  := 110
const B_LANTERN := 113
const B_IRON_BLK:= 230
const B_COPPER  := 232
const B_IRON_ORE:=  32
const B_COAL_ORE:=  30
const B_ALT_MIN := 250   # Skill altar — Mineur
const B_ALT_GUE := 251   # Skill altar — Guerrier
const B_ALT_ING := 252   # Skill altar — Ingénieur
const B_ALT_MAG := 253   # Skill altar — Mage
const B_ALT_FER := 254   # Skill altar — Fermier
const B_QUEST   := 258   # Quest board

var _seed: int = 0
var _height_fn: Callable   # WorldGenerator._compute_height(wx: float, wz: float) -> int


func setup(world_seed: int, height_fn: Callable) -> void:
	_seed      = world_seed
	_height_fn = height_fn


# ── Public entry point ────────────────────────────────────────────────────────

func try_place_structures(chunk: Chunk, wx0: int, wy0: int, wz0: int) -> void:
	if not _height_fn.is_valid():
		return
	# Find all cells whose structure footprint could overlap this chunk
	var cx0 := floori(float(wx0 - HALF_FOOT) / float(CELL_SIZE))
	var cx1 := floori(float(wx0 + 15 + HALF_FOOT) / float(CELL_SIZE))
	var cz0 := floori(float(wz0 - HALF_FOOT) / float(CELL_SIZE))
	var cz1 := floori(float(wz0 + 15 + HALF_FOOT) / float(CELL_SIZE))
	for cx in range(cx0, cx1 + 1):
		for cz in range(cz0, cz1 + 1):
			_try_place_cell(chunk, wx0, wy0, wz0, cx, cz)


# ── Cell evaluation ───────────────────────────────────────────────────────────

func _cell_hash(cx: int, cz: int) -> int:
	# Stable hash — same result regardless of generation order
	return ((cx * 73856093) ^ (cz * 19349663) ^ _seed) & 0x7FFFFFFF


func _try_place_cell(chunk: Chunk, wx0: int, wy0: int, wz0: int, cx: int, cz: int) -> void:
	var h := _cell_hash(cx, cz)
	if h % 100 >= PLACE_ODDS:
		return
	# Deterministic offset within cell, keeping 10 blocks from cell edge
	var ox := (h >> 8)  % 180 + 10
	var oz := (h >> 16) % 180 + 10
	var wx := cx * CELL_SIZE + ox
	var wz := cz * CELL_SIZE + oz
	# Only within MAX_RADIUS of spawn
	if wx * wx + wz * wz > MAX_RADIUS * MAX_RADIUS:
		return
	var wy: int = _height_fn.call(float(wx), float(wz))
	var struct_type := h % 5
	var blocks := _get_structure_blocks(struct_type)
	_write_blocks(chunk, wx, wy, wz, wx0, wy0, wz0, blocks)
	# Draw a short dirt path from this structure to the nearest road node
	_connect_structure_to_road(chunk, wx0, wy0, wz0, wx, wz)


func _write_blocks(chunk: Chunk, wx: int, wy: int, wz: int,
		wx0: int, wy0: int, wz0: int, blocks: Array) -> void:
	const SZ := 16
	for b: Array in blocks:
		var lx: int = (wx + b[0]) - wx0
		var ly: int = (wy + b[1]) - wy0
		var lz: int = (wz + b[2]) - wz0
		if lx < 0 or lx >= SZ or ly < 0 or ly >= SZ or lz < 0 or lz >= SZ:
			continue
		chunk.set_block_fast(lx, ly, lz, b[3])


# ── Structure dispatch ────────────────────────────────────────────────────────

# ── Waypoint structures on road nodes ────────────────────────────────────────

const WAYPOINT_PROB := 20   # % of road nodes that get a small stall

func try_place_waypoints(chunk: Chunk, wx0: int, wy0: int, wz0: int) -> void:
	if not _height_fn.is_valid():
		return
	var margin := 1
	var cx0 := floori(float(wx0) / float(ROUTE_CELL)) - margin
	var cx1 := floori(float(wx0 + 15) / float(ROUTE_CELL)) + margin
	var cz0 := floori(float(wz0) / float(ROUTE_CELL)) - margin
	var cz1 := floori(float(wz0 + 15) / float(ROUTE_CELL)) + margin
	for cx in range(cx0, cx1 + 1):
		for cz in range(cz0, cz1 + 1):
			if not _road_has_node(cx, cz):
				continue
			var h := _road_hash(cx, cz)
			if h % 100 >= WAYPOINT_PROB:
				continue
			var node := _road_node_pos(cx, cz)
			var wy: int = _height_fn.call(float(node.x), float(node.y))
			_write_blocks(chunk, node.x, wy, node.y, wx0, wy0, wz0, _build_waypoint_stall())
			# 30% of waypoints double as a village quest board — centred on back wall, ground level
			if h % 10 < 3:
				_write_blocks(chunk, node.x, wy, node.y, wx0, wy0, wz0,
					[[0, 1, 1, B_QUEST]])


func _build_waypoint_stall() -> Array:
	var b := []
	# 4 oak-log corner posts, 3 tall
	for dy in range(0, 3):
		for dx in [-1, 1]:
			for dz in [-1, 1]:
				b.append([dx, dy, dz, B_OAK_LOG])
	# Oak plank roof 3×3 at dy=3
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			b.append([dx, 3, dz, B_OAK_PLK])
	# Cobble floor 1×1 center
	b.append([0, 0, 0, B_COBBLE])
	# Lantern under roof center
	b.append([0, 2, 0, B_LANTERN])
	return b


func _nearest_road_node(wx: int, wz: int) -> Vector2i:
	# Search a 3×3 grid of cells around the given world position
	var best_dist := INF
	var best := Vector2i(wx, wz)
	var base_cx := roundi(float(wx) / float(ROUTE_CELL))
	var base_cz := roundi(float(wz) / float(ROUTE_CELL))
	for cx in range(base_cx - 1, base_cx + 2):
		for cz in range(base_cz - 1, base_cz + 2):
			if not _road_has_node(cx, cz):
				continue
			var node := _road_node_pos(cx, cz)
			var d := Vector2(wx - node.x, wz - node.y).length_squared()
			if d < best_dist:
				best_dist = d
				best = node
	return best


func _connect_structure_to_road(chunk: Chunk, wx0: int, wy0: int, wz0: int,
		struct_wx: int, struct_wz: int) -> void:
	var node := _nearest_road_node(struct_wx, struct_wz)
	# Skip if the nearest node is more than 1.5 cells away — too far to look natural
	var max_d := int(ROUTE_CELL * 1.5)
	if abs(node.x - struct_wx) > max_d or abs(node.y - struct_wz) > max_d:
		return
	# Reuse the existing segment placer (same coarse_dirt width)
	var a := Vector2i(struct_wx, struct_wz)
	var b := node
	var seg_x0 := mini(a.x, b.x) - ceili(PATH_HALF) - 1
	var seg_x1 := maxi(a.x, b.x) + ceili(PATH_HALF) + 1
	var seg_z0 := mini(a.y, b.y) - ceili(PATH_HALF) - 1
	var seg_z1 := maxi(a.y, b.y) + ceili(PATH_HALF) + 1
	if wx0 + 15 < seg_x0 or wx0 > seg_x1:
		return
	if wz0 + 15 < seg_z0 or wz0 > seg_z1:
		return
	var lx0 := clampi(seg_x0 - wx0, 0, 15)
	var lx1 := clampi(seg_x1 - wx0, 0, 15)
	var lz0 := clampi(seg_z0 - wz0, 0, 15)
	var lz1 := clampi(seg_z1 - wz0, 0, 15)
	for lx in range(lx0, lx1 + 1):
		for lz in range(lz0, lz1 + 1):
			var wx := wx0 + lx
			var wz := wz0 + lz
			var d := _dist_to_segment(wx, wz, a.x, a.y, b.x, b.y)
			if d <= PATH_HALF:
				_place_path_at(chunk, lx, lz, wx, wz, wy0)


# ── Road network ─────────────────────────────────────────────────────────────

func try_place_routes(chunk: Chunk, wx0: int, wy0: int, wz0: int) -> void:
	if not _height_fn.is_valid():
		return
	# Margin: a path segment between two cells can extend PATH_HALF blocks past the
	# node, so one extra cell of overlap is enough.
	var margin := 1
	var cx0 := floori(float(wx0) / float(ROUTE_CELL)) - margin
	var cx1 := floori(float(wx0 + 15) / float(ROUTE_CELL)) + margin
	var cz0 := floori(float(wz0) / float(ROUTE_CELL)) - margin
	var cz1 := floori(float(wz0 + 15) / float(ROUTE_CELL)) + margin
	for cx in range(cx0, cx1 + 1):
		for cz in range(cz0, cz1 + 1):
			if not _road_has_node(cx, cz):
				continue
			# Connect east neighbour
			if _road_has_node(cx + 1, cz):
				_place_route_segment(chunk, wx0, wy0, wz0, cx, cz, cx + 1, cz)
			# Connect south neighbour
			if _road_has_node(cx, cz + 1):
				_place_route_segment(chunk, wx0, wy0, wz0, cx, cz, cx, cz + 1)


func _road_hash(cx: int, cz: int) -> int:
	return ((cx * 374761393) ^ (cz * 668265261) ^ (_seed * 2654435761)) & 0x7FFFFFFF


func _road_has_node(cx: int, cz: int) -> bool:
	var nx := cx * ROUTE_CELL + ROUTE_CELL / 2
	var nz := cz * ROUTE_CELL + ROUTE_CELL / 2
	if nx * nx + nz * nz > ROUTE_REACH * ROUTE_REACH:
		return false
	return _road_hash(cx, cz) % 100 < ROUTE_PROB


func _road_node_pos(cx: int, cz: int) -> Vector2i:
	var h := _road_hash(cx, cz)
	var jitter := int(ROUTE_CELL * 0.25)
	var ox := (h >> 4)  % (ROUTE_CELL - 2 * jitter) + jitter
	var oz := (h >> 14) % (ROUTE_CELL - 2 * jitter) + jitter
	return Vector2i(cx * ROUTE_CELL + ox, cz * ROUTE_CELL + oz)


func _place_route_segment(chunk: Chunk, wx0: int, wy0: int, wz0: int,
		cax: int, caz: int, cbx: int, cbz: int) -> void:
	var a := _road_node_pos(cax, caz)
	var b := _road_node_pos(cbx, cbz)
	# Bounding box cull — skip if segment can't touch this chunk
	var seg_x0 := mini(a.x, b.x) - ceili(PATH_HALF) - 1
	var seg_x1 := maxi(a.x, b.x) + ceili(PATH_HALF) + 1
	var seg_z0 := mini(a.y, b.y) - ceili(PATH_HALF) - 1
	var seg_z1 := maxi(a.y, b.y) + ceili(PATH_HALF) + 1
	if wx0 + 15 < seg_x0 or wx0 > seg_x1:
		return
	if wz0 + 15 < seg_z0 or wz0 > seg_z1:
		return
	# Iterate over local columns that overlap the segment bounding box
	var lx0 := clampi(seg_x0 - wx0, 0, 15)
	var lx1 := clampi(seg_x1 - wx0, 0, 15)
	var lz0 := clampi(seg_z0 - wz0, 0, 15)
	var lz1 := clampi(seg_z1 - wz0, 0, 15)
	for lx in range(lx0, lx1 + 1):
		for lz in range(lz0, lz1 + 1):
			var wx := wx0 + lx
			var wz := wz0 + lz
			var d := _dist_to_segment(wx, wz, a.x, a.y, b.x, b.y)
			if d <= PATH_HALF:
				_place_path_at(chunk, lx, lz, wx, wz, wy0)


func _dist_to_segment(px: int, pz: int, ax: int, az: int, bx: int, bz: int) -> float:
	var dx := float(bx - ax)
	var dz := float(bz - az)
	var len_sq := dx * dx + dz * dz
	if len_sq < 0.0001:
		return Vector2(px - ax, pz - az).length()
	var t := clampf(((px - ax) * dx + (pz - az) * dz) / len_sq, 0.0, 1.0)
	var cx_f := ax + t * dx
	var cz_f := az + t * dz
	return Vector2(px - cx_f, pz - cz_f).length()


func _place_path_at(chunk: Chunk, lx: int, lz: int, wx: int, wz: int, wy0: int) -> void:
	var surface_y: int = _height_fn.call(float(wx), float(wz))
	# Bridge over water: if surface is at or below sea level, raise path up to sea level
	var path_y := surface_y
	if path_y <= SEA_LEVEL_R:
		path_y = SEA_LEVEL_R
		# Fill bridge supports down to the true surface with cobble
		for y in range(surface_y + 1, path_y):
			var ly := y - wy0
			if ly >= 0 and ly < 16:
				chunk.set_block_fast(lx, ly, lz, B_COBBLE)
	var ly := path_y - wy0
	if ly >= 0 and ly < 16:
		# Don't overwrite existing structure floors (altars etc.) — only replace terrain
		var existing := chunk.get_block(lx, ly, lz)
		if existing != B_AIR:
			chunk.set_block_fast(lx, ly, lz, B_COARSE)


# ── Biome castles ─────────────────────────────────────────────────────────────
# Type 0=plains (stone), 1=desert (sandstone), 2=forest (wood), 3=taiga (stone+wood)

const B_SAND    :=   3   # sand / coarse_dirt proxy — actual sandstone if defined
const B_SANDST  := 200   # sandstone block ID (must match blocks_overworld.json)
const B_SPRUCE  :=  14   # spruce_log

func try_place_castles(chunk: Chunk, wx0: int, wy0: int, wz0: int) -> void:
	if not _height_fn.is_valid():
		return
	var cx0 := floori(float(wx0 - CASTLE_HALF) / float(CASTLE_CELL))
	var cx1 := floori(float(wx0 + 15 + CASTLE_HALF) / float(CASTLE_CELL))
	var cz0 := floori(float(wz0 - CASTLE_HALF) / float(CASTLE_CELL))
	var cz1 := floori(float(wz0 + 15 + CASTLE_HALF) / float(CASTLE_CELL))
	for cx in range(cx0, cx1 + 1):
		for cz in range(cz0, cz1 + 1):
			_try_place_castle(chunk, wx0, wy0, wz0, cx, cz)


func _castle_hash(cx: int, cz: int) -> int:
	return ((cx * 29484329) ^ (cz * 81652903) ^ (_seed * 1234567)) & 0x7FFFFFFF


func _try_place_castle(chunk: Chunk, wx0: int, wy0: int, wz0: int, cx: int, cz: int) -> void:
	var h := _castle_hash(cx, cz)
	if h % 100 >= CASTLE_ODDS:
		return
	var ox := (h >> 7)  % (CASTLE_CELL - 20) + 10
	var oz := (h >> 19) % (CASTLE_CELL - 20) + 10
	var wx := cx * CASTLE_CELL + ox
	var wz := cz * CASTLE_CELL + oz
	if wx * wx + wz * wz > CASTLE_RADIUS * CASTLE_RADIUS:
		return
	var wy: int = _height_fn.call(float(wx), float(wz))
	var castle_type := h % 4
	var blocks: Array
	match castle_type:
		0: blocks = _build_castle_plains()
		1: blocks = _build_castle_desert()
		2: blocks = _build_castle_forest()
		_: blocks = _build_castle_taiga()
	_write_blocks(chunk, wx, wy, wz, wx0, wy0, wz0, blocks)


# ── Castle: Château des Plaines (pierre) ──────────────────────────────────────
# 19×15 outer stone walls, 5 tall, 4 corner towers, inner keep 7×5

func _build_castle_plains() -> Array:
	var b := []
	# Outer walls 19×15, 5 tall
	for dy in range(0, 5):
		for dx in range(-9, 10):
			for dz in range(-7, 8):
				if abs(dx) == 9 or abs(dz) == 7:
					b.append([dx, dy, dz, B_STONE])
	# Battlements on top
	for dx in range(-9, 10, 2):
		b.append([dx, 5, -7, B_COBBLE])
		b.append([dx, 5,  7, B_COBBLE])
	for dz in range(-7, 8, 2):
		b.append([-9, 5, dz, B_COBBLE])
		b.append([ 9, 5, dz, B_COBBLE])
	# Corner towers +2 blocks higher
	for dx in [-9, 9]:
		for dz in [-7, 7]:
			for dy in range(5, 8):
				b.append([dx, dy, dz, B_STONE])
			b.append([dx, 7, dz, B_GLOWST])
	# Clear courtyard
	for dy in range(1, 5):
		for dx in range(-8, 9):
			for dz in range(-6, 7):
				b.append([dx, dy, dz, B_AIR])
	# Cobble courtyard floor
	for dx in range(-8, 9):
		for dz in range(-6, 7):
			b.append([dx, 0, dz, B_COBBLE])
	# Inner keep 7×5, 4 tall, stone, at back
	for dy in range(0, 4):
		for dx in range(-3, 4):
			for dz in range(2, 7):
				if abs(dx) == 3 or abs(dz) == 6 or dz == 2:
					b.append([dx, dy, dz, B_STONE])
	# Keep interior clear
	for dy in range(1, 4):
		for dx in range(-2, 3):
			for dz in range(3, 6):
				b.append([dx, dy, dz, B_AIR])
	# Keep entrance
	b.append([0, 1, 2, B_AIR])
	b.append([0, 2, 2, B_AIR])
	# Gate opening in front wall
	for dy in [1, 2, 3]:
		b.append([0, dy, -7, B_AIR])
		b.append([1, dy, -7, B_AIR])
	# Lanterns on inner keep
	b.append([0, 3, 4, B_LANTERN])
	return b


# ── Castle: Palais du Désert (grès) ───────────────────────────────────────────
# 15×15 sandstone, arches ouvertes, dôme central

func _build_castle_desert() -> Array:
	var b := []
	var SS := B_SANDST if B_SANDST > 0 else B_STONE   # fallback if sandstone undefined
	# Outer walls 15×15, 4 tall
	for dy in range(0, 4):
		for dx in range(-7, 8):
			for dz in range(-7, 8):
				if abs(dx) == 7 or abs(dz) == 7:
					b.append([dx, dy, dz, SS])
	# Ornamental top: alternating crenels
	for dx in range(-7, 8, 2):
		b.append([dx, 4, -7, SS])
		b.append([dx, 4,  7, SS])
	for dz in range(-7, 8, 2):
		b.append([-7, 4, dz, SS])
		b.append([ 7, 4, dz, SS])
	# Arched windows in each wall (1-wide gaps at dy=1,2 every 4 blocks)
	for dx in [-4, 0, 4]:
		b.append([dx, 1, -7, B_AIR])
		b.append([dx, 2, -7, B_AIR])
		b.append([dx, 1,  7, B_AIR])
		b.append([dx, 2,  7, B_AIR])
	for dz in [-4, 0, 4]:
		b.append([-7, 1, dz, B_AIR])
		b.append([-7, 2, dz, B_AIR])
		b.append([ 7, 1, dz, B_AIR])
		b.append([ 7, 2, dz, B_AIR])
	# Clear interior 13×13×3
	for dy in range(1, 4):
		for dx in range(-6, 7):
			for dz in range(-6, 7):
				b.append([dx, dy, dz, B_AIR])
	# Sand floor
	for dx in range(-6, 7):
		for dz in range(-6, 7):
			b.append([dx, 0, dz, SS])
	# Central 3×3 raised platform (throne area)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			b.append([dx, 1, dz, SS])
	b.append([0, 2, 0, B_GLOWST])
	# 4 glowstone corner pillars inside
	for dx in [-4, 4]:
		for dz in [-4, 4]:
			for dy in range(1, 4):
				b.append([dx, dy, dz, SS])
			b.append([dx, 4, dz, B_GLOWST])
	return b


# ── Castle: Camp fortifié de Forêt (bois) ─────────────────────────────────────
# 15×13 palisade en oak_log, tours rondes aux coins, cabane centrale

func _build_castle_forest() -> Array:
	var b := []
	# Palisade walls: oak log stakes 3 tall, 15×13
	for dy in range(0, 3):
		for dx in range(-7, 8):
			for dz in range(-6, 7):
				if abs(dx) == 7 or abs(dz) == 6:
					b.append([dx, dy, dz, B_OAK_LOG])
	# Pointed top: every other stake is 1 taller
	for dx in range(-7, 8, 2):
		b.append([dx, 3, -6, B_OAK_LOG])
		b.append([dx, 3,  6, B_OAK_LOG])
	for dz in range(-6, 7, 2):
		b.append([-7, 3, dz, B_OAK_LOG])
		b.append([ 7, 3, dz, B_OAK_LOG])
	# Clear interior 13×11×2
	for dy in range(1, 3):
		for dx in range(-6, 7):
			for dz in range(-5, 6):
				b.append([dx, dy, dz, B_AIR])
	# Dirt floor
	for dx in range(-6, 7):
		for dz in range(-5, 6):
			b.append([dx, 0, dz, B_COBBLE])
	# Central cabin 5×5, oak plank, 3 tall
	for dy in range(0, 3):
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				if abs(dx) == 2 or abs(dz) == 2:
					b.append([dx, dy, dz, B_OAK_PLK])
	# Cabin interior
	for dy in range(1, 3):
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				b.append([dx, dy, dz, B_AIR])
	# Cabin door
	b.append([0, 1, -2, B_AIR])
	b.append([0, 2, -2, B_AIR])
	# Cabin roof (plank) + lantern
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			b.append([dx, 3, dz, B_OAK_PLK])
	b.append([0, 4, 0, B_LANTERN])
	# Gate opening (south palisade)
	b.append([0, 1, -6, B_AIR])
	b.append([0, 2, -6, B_AIR])
	# Campfire proxy (glowstone) in front of cabin
	b.append([0, 1, -4, B_GLOWST])
	return b


# ── Castle: Fortin de Taïga (pierre + sapin) ──────────────────────────────────
# 13×11 mixed stone/spruce, bas profil, tours aux coins, mur épais

func _build_castle_taiga() -> Array:
	var b := []
	# Stone base walls, 4 tall 13×11
	for dy in range(0, 4):
		for dx in range(-6, 7):
			for dz in range(-5, 6):
				if abs(dx) == 6 or abs(dz) == 5:
					var mat := B_STONE if dy < 2 else B_OAK_PLK
					b.append([dx, dy, dz, mat])
	# Spruce log corner posts, full height +2
	for dy in range(0, 6):
		for dx in [-6, 6]:
			for dz in [-5, 5]:
				b.append([dx, dy, dz, B_SPRUCE if B_SPRUCE > 0 else B_OAK_LOG])
	# Plank walkway on top of walls
	for dx in range(-5, 6):
		b.append([dx, 4, -5, B_OAK_PLK])
		b.append([dx, 4,  5, B_OAK_PLK])
	for dz in range(-4, 5):
		b.append([-6, 4, dz, B_OAK_PLK])
		b.append([ 6, 4, dz, B_OAK_PLK])
	# Clear interior 11×9×3
	for dy in range(1, 4):
		for dx in range(-5, 6):
			for dz in range(-4, 5):
				b.append([dx, dy, dz, B_AIR])
	# Cobble floor
	for dx in range(-5, 6):
		for dz in range(-4, 5):
			b.append([dx, 0, dz, B_COBBLE])
	# Gate (south)
	for dy in [1, 2, 3]:
		b.append([0, dy, -5, B_AIR])
		b.append([1, dy, -5, B_AIR])
	# Glowstone braziers near corners
	for dx in [-4, 4]:
		b.append([dx, 1, -3, B_GLOWST])
		b.append([dx, 1,  3, B_GLOWST])
	# Small spruce-plank barracks (5×3) at back
	for dy in range(0, 3):
		for dx in range(-2, 3):
			for dz in range(2, 5):
				if abs(dx) == 2 or dz == 4 or dz == 2:
					b.append([dx, dy, dz, B_OAK_PLK])
	for dy in range(1, 3):
		for dx in range(-1, 2):
			for dz in range(3, 4):
				b.append([dx, dy, dz, B_AIR])
	b.append([0, 1, 2, B_AIR])
	b.append([0, 2, 2, B_AIR])
	b.append([0, 2, 3, B_LANTERN])
	return b


# ── Boss fortresses (Stone Guardian, Overworld) ───────────────────────────────

func try_place_boss_fortresses(chunk: Chunk, wx0: int, wy0: int, wz0: int) -> void:
	if not _height_fn.is_valid():
		return
	var cx0 := floori(float(wx0 - FORT_HALF) / float(FORT_CELL))
	var cx1 := floori(float(wx0 + 15 + FORT_HALF) / float(FORT_CELL))
	var cz0 := floori(float(wz0 - FORT_HALF) / float(FORT_CELL))
	var cz1 := floori(float(wz0 + 15 + FORT_HALF) / float(FORT_CELL))
	for cx in range(cx0, cx1 + 1):
		for cz in range(cz0, cz1 + 1):
			_try_place_fortress(chunk, wx0, wy0, wz0, cx, cz)


func _fortress_hash(cx: int, cz: int) -> int:
	return ((cx * 57654319) ^ (cz * 34521961) ^ (_seed * 3141592)) & 0x7FFFFFFF


func _try_place_fortress(chunk: Chunk, wx0: int, wy0: int, wz0: int, cx: int, cz: int) -> void:
	var h := _fortress_hash(cx, cz)
	if h % 100 >= FORT_ODDS:
		return
	var ox := (h >> 6)  % (FORT_CELL - 20) + 10
	var oz := (h >> 18) % (FORT_CELL - 20) + 10
	var wx := cx * FORT_CELL + ox
	var wz := cz * FORT_CELL + oz
	var d2 := wx * wx + wz * wz
	if d2 > FORT_RADIUS * FORT_RADIUS or d2 < FORT_MIN_RADIUS * FORT_MIN_RADIUS:
		return
	var wy: int = _height_fn.call(float(wx), float(wz))
	_write_blocks(chunk, wx, wy, wz, wx0, wy0, wz0, _build_stone_fortress())


func _build_stone_fortress() -> Array:
	var b := []
	# Outer stone walls 13×11, 5 tall
	for dy in range(0, 5):
		for dx in range(-6, 7):
			for dz in range(-5, 6):
				if abs(dx) == 6 or abs(dz) == 5:
					b.append([dx, dy, dz, B_STONE])
	# Battlements (raised sections every 2 blocks on top of walls)
	for dx in range(-6, 7, 2):
		b.append([dx, 5, -5, B_COBBLE])
		b.append([dx, 5,  5, B_COBBLE])
	for dz in range(-5, 6, 2):
		b.append([-6, 5, dz, B_COBBLE])
		b.append([ 6, 5, dz, B_COBBLE])
	# Clear interior 11×9×4
	for dy in range(1, 5):
		for dx in range(-5, 6):
			for dz in range(-4, 5):
				b.append([dx, dy, dz, B_AIR])
	# Stone floor 11×9
	for dx in range(-5, 6):
		for dz in range(-4, 5):
			b.append([dx, 0, dz, B_COBBLE])
	# Gate opening (front, south wall) — 2×3
	for dy in [1, 2, 3]:
		b.append([0, dy, -5, B_AIR])
		b.append([1, dy, -5, B_AIR])
	# Corner towers: extra 2 blocks high
	for dx in [-6, 6]:
		for dz in [-5, 5]:
			b.append([dx, 5, dz, B_STONE])
			b.append([dx, 6, dz, B_STONE])
	# Glowstone torches on inner walls
	for dz in [-4, 4]:
		b.append([-4, 3, dz, B_GLOWST])
		b.append([ 4, 3, dz, B_GLOWST])
	# Stone slab altar platform in center (boss spawn marker)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			b.append([dx, 1, dz, B_STONE])
	# Lantern above platform
	b.append([0, 2, 0, B_LANTERN])
	return b


# ── Structure dispatch ────────────────────────────────────────────────────────

func _get_structure_blocks(type: int) -> Array:
	match type:
		0: return _build_mine_mineur()
		1: return _build_arena_guerrier()
		2: return _build_workshop_ingenieur()
		3: return _build_lab_mage()
		_: return _build_manor_fermier()


# ── Structure: Mine abandonnée (Mineur, altar 250) ────────────────────────────
# 5×5 surface frame + vertical shaft -10 blocks + bottom chamber 5×3.

func _build_mine_mineur() -> Array:
	var b := []
	# Surface frame — oak planks, 3 tall, 5×5 outline
	for dy in range(0, 3):
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				if abs(dx) == 2 or abs(dz) == 2:
					b.append([dx, dy, dz, B_OAK_PLK])
	# Clear interior air 3×3×2
	for dy in range(1, 3):
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				b.append([dx, dy, dz, B_AIR])
	# Cobblestone floor inside
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			b.append([dx, 0, dz, B_COBBLE])
	# Lantern above entrance
	b.append([0, 2, 0, B_LANTERN])
	# Shaft: 3×3 air going down, oak support every 3 levels
	for dy in range(-1, -11, -1):
		b.append([0, dy, 0, B_AIR])
		b.append([1, dy, 0, B_AIR])
		b.append([0, dy, 1, B_AIR])
		b.append([1, dy, 1, B_AIR])
		# Oak plank support frames at -3, -6, -9
		if dy % 3 == 0:
			for dx in [-1, 2]:
				b.append([dx, dy, 0, B_OAK_PLK])
				b.append([dx, dy, 1, B_OAK_PLK])
			for dz in [-1, 2]:
				b.append([0, dy, dz, B_OAK_PLK])
				b.append([1, dy, dz, B_OAK_PLK])
	# Bottom chamber 5×3 stone, dy=-10..-12
	for dy in range(-10, -13, -1):
		for dx in range(-2, 3):
			for dz in range(-1, 2):
				if abs(dx) == 2 or dy == -12 or dz == 1 or dz == -1:
					b.append([dx, dy, dz, B_STONE])
				else:
					b.append([dx, dy, dz, B_AIR])
	# Coal and iron ore veins in chamber walls for atmosphere
	for dz in [-1, 1]:
		b.append([-2, -11, dz, B_COAL_ORE])
		b.append([2,  -11, dz, B_IRON_ORE])
	# Glowstone ceiling of chamber
	for dx in range(-1, 2):
		b.append([dx, -10, 0, B_GLOWST])
	# Altar at chamber floor center
	b.append([0, -12, 0, B_ALT_MIN])
	return b


# ── Structure: Arène de combat (Guerrier, altar 251) ──────────────────────────
# 11×11 stone walls, 4 tall, open sky, gravel floor, lanterns on corner pillars.

func _build_arena_guerrier() -> Array:
	var b := []
	# Walls: outer perimeter 11×11, 4 tall (dy=0..3)
	for dy in range(0, 4):
		for dx in range(-5, 6):
			for dz in range(-5, 6):
				if abs(dx) == 5 or abs(dz) == 5:
					b.append([dx, dy, dz, B_STONE])
	# Clear interior 9×9 up to dy=3 (overrides terrain)
	for dy in range(1, 4):
		for dx in range(-4, 5):
			for dz in range(-4, 5):
				b.append([dx, dy, dz, B_AIR])
	# Cobblestone floor interior 9×9
	for dx in range(-4, 5):
		for dz in range(-4, 5):
			b.append([dx, 0, dz, B_COBBLE])
	# Lanterns on 4 corner pillars
	for dx in [-5, 5]:
		for dz in [-5, 5]:
			b.append([dx, 4, dz, B_LANTERN])
	# Window openings in walls (remove 2 blocks center of each wall side, dy=1..2)
	for dy in [1, 2]:
		b.append([-5, dy, 0, B_AIR])
		b.append([5,  dy, 0, B_AIR])
		b.append([0,  dy, -5, B_AIR])
		b.append([0,  dy, 5,  B_AIR])
	# Altar at center of arena
	b.append([0, 0, 0, B_ALT_GUE])
	return b


# ── Structure: Atelier redstone (Ingénieur, altar 252) ────────────────────────
# 9×5 iron/copper building, 4 tall, glass roof, redstone decoration inside.

func _build_workshop_ingenieur() -> Array:
	var b := []
	# Iron block walls: 9×5 perimeter, 3 tall
	for dy in range(0, 3):
		for dx in range(-4, 5):
			for dz in range(-2, 3):
				if abs(dx) == 4 or abs(dz) == 2:
					var wall_id := B_COPPER if dy == 1 else B_IRON_BLK
					b.append([dx, dy, dz, wall_id])
	# Glass roof 7×3 interior at dy=3
	for dx in range(-3, 4):
		for dz in range(-1, 2):
			b.append([dx, 3, dz, B_GLASS])
	# Clear interior 7×3×2
	for dy in range(1, 3):
		for dx in range(-3, 4):
			for dz in range(-1, 2):
				b.append([dx, dy, dz, B_AIR])
	# Copper floor inside
	for dx in range(-3, 4):
		for dz in range(-1, 2):
			b.append([dx, 0, dz, B_COPPER])
	# Redstone block pillars (2 pairs)
	for dx in [-2, 2]:
		b.append([dx, 0, 0, B_RDST_BLK])
		b.append([dx, 1, 0, B_RDST_BLK])
	# Iron bars windows: 2 on each long wall
	for dz in [-2, 2]:
		b.append([-2, 1, dz, B_IRON_BAR])
		b.append([2,  1, dz, B_IRON_BAR])
	# Door opening (front wall)
	b.append([-4, 1, 0, B_AIR])
	b.append([-4, 2, 0, B_AIR])
	# Glowstone lamp inside
	b.append([0, 2, 0, B_GLOWST])
	# Altar
	b.append([0, 0, 0, B_ALT_ING])
	return b


# ── Structure: Laboratoire alchimique (Mage, altar 253) ───────────────────────
# 7×7 stone building, bookshelves lining interior, glowstone ceiling.

func _build_lab_mage() -> Array:
	var b := []
	# Stone outer walls 7×7, 3 tall
	for dy in range(0, 3):
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				if abs(dx) == 3 or abs(dz) == 3:
					b.append([dx, dy, dz, B_STONE])
	# Glowstone ceiling 5×5 at dy=3
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			b.append([dx, 3, dz, B_GLOWST])
	# Clear interior 5×5×2
	for dy in range(1, 3):
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				b.append([dx, dy, dz, B_AIR])
	# Cobblestone floor 5×5
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			b.append([dx, 0, dz, B_COBBLE])
	# Bookshelf lining on inner walls at dy=1
	for dx in range(-2, 3):
		b.append([dx, 1, -2, B_BOOK])
		b.append([dx, 1,  2, B_BOOK])
	for dz in range(-1, 2):
		b.append([-2, 1, dz, B_BOOK])
		b.append([2,  1, dz, B_BOOK])
	# Door opening (south wall)
	b.append([0, 1, -3, B_AIR])
	b.append([0, 2, -3, B_AIR])
	# Altar
	b.append([0, 0, 0, B_ALT_MAG])
	return b


# ── Structure: Manoir agricole (Fermier, altar 254) ───────────────────────────
# 9×7 oak building, log pillars, glowstone ceiling, dirt garden patches outside.

func _build_manor_fermier() -> Array:
	var b := []
	# Oak log corner pillars, 4 tall
	for dy in range(0, 5):
		for dx in [-4, 4]:
			for dz in [-3, 3]:
				b.append([dx, dy, dz, B_OAK_LOG])
	# Oak plank walls 9×7, 3 tall (between pillars)
	for dy in range(0, 3):
		for dx in range(-4, 5):
			for dz in range(-3, 4):
				if abs(dx) == 4 or abs(dz) == 3:
					if not (abs(dx) == 4 and abs(dz) == 3):  # skip corners (already logs)
						b.append([dx, dy, dz, B_OAK_PLK])
	# Glowstone ceiling 7×5 at dy=4
	for dx in range(-3, 4):
		for dz in range(-2, 3):
			b.append([dx, 4, dz, B_GLOWST])
	# Clear interior 7×5×3
	for dy in range(1, 4):
		for dx in range(-3, 4):
			for dz in range(-2, 3):
				b.append([dx, dy, dz, B_AIR])
	# Oak plank floor 7×5
	for dx in range(-3, 4):
		for dz in range(-2, 3):
			b.append([dx, 0, dz, B_OAK_PLK])
	# Door opening (front)
	b.append([-4, 1, 0, B_AIR])
	b.append([-4, 2, 0, B_AIR])
	# Garden dirt patches outside (north side, dy=0 replacing surface)
	for dx in range(-3, 4):
		for dz in range(-5, -3):
			b.append([dx, 0, dz, B_COBBLE])
	# Altar
	b.append([0, 0, 0, B_ALT_FER])
	return b


# ── Archives des Architectes ──────────────────────────────────────────────────

const B_ARCHIVES_CORE := 255
const B_LORE_TABLET   := 256
const B_NEXUS_PORTAL  := 257
const ARCHIVES_HALF   := 13
const NEXUS_Y         := 250   # Nexus room floats at this absolute Y


func get_archives_world_pos() -> Vector2i:
	var angle := fmod(float(_seed) * 1.6180339, TAU)
	var dist  := 1500 + (_seed % 1000)
	return Vector2i(int(cos(angle) * dist), int(sin(angle) * dist))


func try_place_archives(chunk: Chunk, wx0: int, wy0: int, wz0: int) -> void:
	if not _height_fn.is_valid():
		return
	var apos := get_archives_world_pos()
	var ax := apos.x;  var az := apos.y
	# XZ overlap check
	if ax + ARCHIVES_HALF < wx0 or ax - ARCHIVES_HALF >= wx0 + 16: return
	if az + ARCHIVES_HALF < wz0 or az - ARCHIVES_HALF >= wz0 + 16: return
	var wy: int = _height_fn.call(float(ax), float(az))
	# Y overlap: Archives spans dy=-38 (wy-38) to dy=1 (wy+1)
	if wy0 + 16 < wy - 38 or wy0 > wy + 1: return
	_write_blocks(chunk, ax, wy, az, wx0, wy0, wz0, _build_archives_blocks())


func _build_archives_blocks() -> Array:
	var b := []
	# ── Floor (25×25) ──
	for dx in range(-12, 13):
		for dz in range(-12, 13):
			b.append([dx, -38, dz, B_COBBLE])
	# Glowstone under central platform area
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			b.append([dx, -38, dz, B_GLOWST])
	# ── Ceiling (25×25) with glowstone nodes ──
	for dx in range(-12, 13):
		for dz in range(-12, 13):
			var glow := (dx % 4 == 0 and dz % 4 == 0)
			b.append([dx, -15, dz, B_GLOWST if glow else B_STONE])
	# ── Outer walls (perimeter, full height) ──
	for dy in range(-37, -15):
		for dx in range(-12, 13):
			b.append([dx, dy, -12, B_STONE])
			b.append([dx, dy,  12, B_STONE])
		for dz in range(-11, 12):
			b.append([-12, dy, dz, B_STONE])
			b.append([ 12, dy, dz, B_STONE])
	# ── Clear interior ──
	for dy in range(-37, -15):
		for dx in range(-11, 12):
			for dz in range(-11, 12):
				b.append([dx, dy, dz, B_AIR])
	# ── 4 Pillars (2×2) at (±7, ±7) — placed AFTER air clear ──
	for pdx in [-8, 6]:
		for pdz in [-8, 6]:
			for dy in range(-37, -15):
				b.append([pdx,     dy, pdz,     B_COBBLE])
				b.append([pdx + 1, dy, pdz,     B_COBBLE])
				b.append([pdx,     dy, pdz + 1, B_COBBLE])
				b.append([pdx + 1, dy, pdz + 1, B_COBBLE])
	# ── Entry shaft (5×5 air, dy=-14 to dy=0) ──
	for dy in range(-14, 1):
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				b.append([dx, dy, dz, B_AIR])
		for dx in range(-3, 4):
			b.append([dx, dy, -3, B_STONE])
			b.append([dx, dy,  3, B_STONE])
		for dz in range(-2, 3):
			b.append([-3, dy, dz, B_STONE])
			b.append([ 3, dy, dz, B_STONE])
	# Surface ring frame
	for dx in range(-3, 4):
		b.append([dx, 0, -3, B_COBBLE])
		b.append([dx, 0,  3, B_COBBLE])
	for dz in range(-2, 3):
		b.append([-3, 0, dz, B_COBBLE])
		b.append([ 3, 0, dz, B_COBBLE])
	# ── Central altar platform (7×7, raised 2 blocks) ──
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			b.append([dx, -37, dz, B_COBBLE])
			b.append([dx, -36, dz, B_STONE])
	# ── Special blocks ──
	b.append([0, -35,  0, B_ARCHIVES_CORE])   # Central altar
	b.append([2, -35,  0, B_NEXUS_PORTAL])    # Portal to Nexus (beside altar)
	# 4 Lore tablets on walls
	b.append([ 0, -28, -12, B_LORE_TABLET])   # North wall
	b.append([ 0, -28,  12, B_LORE_TABLET])   # South wall
	b.append([-12, -28,  0, B_LORE_TABLET])   # West wall
	b.append([ 12, -28,  0, B_LORE_TABLET])   # East wall
	# Glowstone lanterns at pillar bases
	for pdx in [-7, 7]:
		for pdz in [-7, 7]:
			b.append([pdx, -37, pdz, B_GLOWST])
	return b


# ── Le Nexus (pocket dimension room) ─────────────────────────────────────────

const NEXUS_HALF := 15


func try_place_nexus_room(chunk: Chunk, wx0: int, wy0: int, wz0: int) -> void:
	var nx := 100000;  var nz := 100000
	if nx + NEXUS_HALF < wx0 or nx - NEXUS_HALF >= wx0 + 16: return
	if nz + NEXUS_HALF < wz0 or nz - NEXUS_HALF >= wz0 + 16: return
	if wy0 + 16 < NEXUS_Y or wy0 > NEXUS_Y + 10: return
	_write_blocks(chunk, nx, NEXUS_Y, nz, wx0, wy0, wz0, _build_nexus_blocks())


func _build_nexus_blocks() -> Array:
	var b := []
	# ── Floor (30×30) ──
	for dx in range(-15, 15):
		for dz in range(-15, 15):
			var edge: bool = abs(dx) >= 13 or abs(dz) >= 13
			b.append([dx, 0, dz, B_COBBLE if edge else B_IRON_BLK])
	# Glowstone floor pattern
	for dx in [-9, -6, -3, 0, 3, 6, 9]:
		for dz in [-9, -6, -3, 0, 3, 6, 9]:
			b.append([dx, 0, dz, B_GLOWST])
	# ── Walls (perimeter, 8 blocks tall) ──
	for dy in range(1, 9):
		for dx in range(-15, 15):
			b.append([dx, dy, -15, B_STONE])
			b.append([dx, dy,  14, B_STONE])
		for dz in range(-14, 14):
			b.append([-15, dy, dz, B_STONE])
			b.append([ 14, dy, dz, B_STONE])
	# ── Clear interior ──
	for dy in range(1, 9):
		for dx in range(-14, 14):
			for dz in range(-14, 14):
				b.append([dx, dy, dz, B_AIR])
	# ── Ceiling ──
	for dx in range(-15, 15):
		for dz in range(-15, 15):
			var glow := (dx % 5 == 0 and dz % 5 == 0)
			b.append([dx, 9, dz, B_GLOWST if glow else B_IRON_BLK])
	# ── 4 Corner pillars (2×2, full height) — placed AFTER air clear ──
	for pdx in [-13, 12]:
		for pdz in [-13, 12]:
			for dy in range(1, 9):
				b.append([pdx,     dy, pdz,     B_RDST_BLK])
				b.append([pdx + 1, dy, pdz,     B_RDST_BLK])
				b.append([pdx,     dy, pdz + 1, B_RDST_BLK])
				b.append([pdx + 1, dy, pdz + 1, B_RDST_BLK])
	# ── Special blocks ──
	b.append([ 0, 1,  0, B_ARCHIVES_CORE])  # Final inscription altar
	b.append([ 0, 1,  2, B_NEXUS_PORTAL])   # Return portal
	b.append([ 0, 4, -14, B_LORE_TABLET])   # Final lore text on north wall
	return b
