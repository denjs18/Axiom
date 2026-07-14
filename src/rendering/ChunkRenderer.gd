## ChunkRenderer.gd — Greedy-meshed chunk renderer with async mesh building.
## Uses a procedural texture atlas (BlockTextureAtlas) for Minecraft-style block visuals.
## UV channel 0: tiling coordinates [0..w, 0..h] for greedy quads.
## UV channel 1: atlas tile UV top-left for the block face texture.
## Vertex color: face-direction shading (top=1.0, sides=0.65-0.80, bottom=0.50).
class_name ChunkRenderer
extends MeshInstance3D

const CHUNK_SIZE := 16

const FACE_NORMALS: Array[Vector3] = [
	Vector3(0, 1, 0), Vector3(0, -1, 0),
	Vector3(0, 0, 1), Vector3(0, 0, -1),
	Vector3(1, 0, 0), Vector3(-1, 0, 0),
]
const FACE_NAMES: Array[String] = ["top","bottom","north","south","east","west"]
const FACE_OFFSETS: Array[Vector3i] = [
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
]

# Face shading: top bright, bottom dark, sides intermediate
const FACE_SHADE: Array[Color] = [
	Color(1.00, 1.00, 1.00),   # 0 top
	Color(0.50, 0.50, 0.50),   # 1 bottom
	Color(0.80, 0.80, 0.80),   # 2 north
	Color(0.80, 0.80, 0.80),   # 3 south
	Color(0.65, 0.65, 0.65),   # 4 east
	Color(0.65, 0.65, 0.65),   # 5 west
]

var _chunk: Chunk
var _manager: ChunkManager
var _dirty: bool = true
var _col_dirty: bool = true
var _opaque_mat: ShaderMaterial
var _trans_mat: ShaderMaterial

const VOXEL_OPAQUE_SHADER  := preload("res://assets/shaders/voxel_opaque.gdshader")
const VOXEL_TRANS_SHADER   := preload("res://assets/shaders/voxel_transparent.gdshader")

# All chunks share two materials so DayNightCycle can drive the light uniforms
# (sky_energy / sky_tint) once per frame instead of per chunk.
static var _shared_opaque: ShaderMaterial = null
static var _shared_trans:  ShaderMaterial = null

static func get_shared_materials() -> Array:
	return [_shared_opaque, _shared_trans]

# ── Async mesh build ───────────────────────────────────────────────────────────
var _mesh_mutex:    Mutex = Mutex.new()
var _mesh_result:   Array = []
var _mesh_building: bool  = false

# ── Async collision build ──────────────────────────────────────────────────────
var _col_mutex:         Mutex = Mutex.new()
var _col_shape_ready:   ConcavePolygonShape3D = null
var _col_building:      bool = false
var _col_faces_snapshot: PackedVector3Array = PackedVector3Array()

# Per-frame budgets
static var _rebuilds_this_frame:  int = 0
static var _colliders_this_frame: int = 0
static var _last_budget_frame:    int = -1
const MAX_MESH_SUBMITS_PER_FRAME  := 4
const MAX_COLLIDERS_PER_FRAME     := 4

# UV atlas cache: index = block_id * 6 + face_idx → atlas UV top-left (Vector2)
static var _uv_cache:       PackedVector2Array = PackedVector2Array()
static var _uv_cache_built: bool = false


func setup(chunk: Chunk, manager: ChunkManager) -> void:
	_chunk   = chunk
	_manager = manager
	var origin := chunk.get_world_origin()
	position   = Vector3(origin.x, origin.y, origin.z)
	_opaque_mat = _make_mat(false)
	_trans_mat  = _make_mat(true)
	_dirty     = true
	_col_dirty = true
	set_process(true)


func mark_dirty(rebuild_collision: bool = false) -> void:
	_dirty = true
	if rebuild_collision:
		_col_dirty = true
	set_process(true)


func request_collision() -> void:
	if not _col_dirty and not _col_building:
		_col_dirty = true
	set_process(true)


func _process(_delta: float) -> void:
	var frame := Engine.get_process_frames()
	if frame != _last_budget_frame:
		_last_budget_frame    = frame
		_rebuilds_this_frame  = 0
		_colliders_this_frame = 0

	# ── Poll async mesh result ─────────────────────────────────────────────────
	_mesh_mutex.lock()
	var mesh_ready := not _mesh_result.is_empty()
	var surface_data: Array = _mesh_result.duplicate() if mesh_ready else []
	if mesh_ready:
		_mesh_result.clear()
	_mesh_mutex.unlock()
	if mesh_ready:
		_mesh_building = false
		_apply_mesh_data(surface_data)

	# ── Poll async collision result ────────────────────────────────────────────
	_col_mutex.lock()
	var ready_shape: ConcavePolygonShape3D = _col_shape_ready
	if ready_shape != null:
		_col_shape_ready = null
	_col_mutex.unlock()
	if ready_shape != null:
		_col_building = false
		_apply_collision_shape(ready_shape)

	# ── Submit async mesh build ────────────────────────────────────────────────
	if _dirty and not _mesh_building:
		if _rebuilds_this_frame >= MAX_MESH_SUBMITS_PER_FRAME:
			return
		_rebuilds_this_frame += 1
		_rebuild_mesh()

	# ── Submit async collision build ───────────────────────────────────────────
	if _col_dirty and not _col_building:
		if _is_near_player():
			if _col_faces_snapshot.is_empty():
				_col_dirty = false
			elif _colliders_this_frame >= MAX_COLLIDERS_PER_FRAME:
				return
			else:
				_colliders_this_frame += 1
				_col_building = true
				_col_dirty    = false
				var faces: PackedVector3Array = _col_faces_snapshot.duplicate()
				var mtx := _col_mutex
				WorkerThreadPool.add_task(func() -> void:
					var shape := ConcavePolygonShape3D.new()
					shape.set_faces(faces)
					mtx.lock()
					_col_shape_ready = shape
					mtx.unlock()
				)
		else:
			_col_dirty = false

	if not _dirty and not _mesh_building and not _col_dirty and not _col_building:
		set_process(false)


# ── Async mesh build ───────────────────────────────────────────────────────────

func _rebuild_mesh() -> void:
	if _chunk == null:
		return
	if _chunk.is_all_air:
		mesh = null
		_col_dirty           = false
		_col_faces_snapshot  = PackedVector3Array()
		_dirty               = false
		return

	_ensure_uv_cache()

	var blocks_snap := _chunk.blocks.duplicate()
	var light_snap  := _chunk.light_data.duplicate()
	var flags_snap  := BlockRegistry._block_flags.duplicate()
	var shapes_snap := BlockRegistry._block_shape.duplicate()
	var uvs_snap    := _uv_cache.duplicate()
	var nb_snaps: Array = []
	var nb_lights: Array = []
	if _manager != null:
		for i in 6:
			var nb := _manager.get_chunk(_chunk.chunk_pos + FACE_OFFSETS[i])
			nb_snaps.append(nb.blocks.duplicate() if nb != null else PackedInt32Array())
			nb_lights.append(nb.light_data.duplicate() if nb != null else PackedByteArray())
	else:
		for _i in 6:
			nb_snaps.append(PackedInt32Array())
			nb_lights.append(PackedByteArray())

	_mesh_building = true
	_dirty         = false

	var mtx  := _mesh_mutex
	var pend := _mesh_result

	WorkerThreadPool.add_task(func() -> void:
		var result := ChunkRenderer._compute_surfaces(
			blocks_snap, nb_snaps, flags_snap, uvs_snap, shapes_snap, light_snap, nb_lights)
		mtx.lock()
		pend.clear()
		pend.append_array(result)
		mtx.unlock()
	)


func _apply_mesh_data(surfaces: Array) -> void:
	var arr_mesh := ArrayMesh.new()
	var col_faces := PackedVector3Array()
	for sd in surfaces:
		var arrays: Array = sd["arrays"]
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue
		var si := arr_mesh.get_surface_count()
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		arr_mesh.surface_set_material(si, _trans_mat if sd["transparent"] else _opaque_mat)
		# Only solid geometry contributes to collision (never water/plants/torches)
		if sd.get("collide", false):
			col_faces.append_array(_faces_from_arrays(arrays))

	if arr_mesh.get_surface_count() == 0:
		mesh = null
		_col_dirty          = false
		_col_faces_snapshot = PackedVector3Array()
	else:
		mesh = arr_mesh
		_col_faces_snapshot = col_faces
		_col_dirty          = true
	set_process(true)


# ── Static mesh computation (worker thread) ────────────────────────────────────

static func _compute_surfaces(
		blocks: PackedInt32Array,
		nb_blocks: Array,
		flags: PackedByteArray,
		uv_table: PackedVector2Array,
		shapes: PackedByteArray = PackedByteArray(),
		lights: PackedByteArray = PackedByteArray(),
		nb_lights: Array = []) -> Array:
	var result: Array = []
	for pass_idx in 2:
		var transparent_pass: bool = pass_idx == 1
		var arrays := _build_surface_data(
			blocks, nb_blocks, flags, uv_table, transparent_pass, shapes, lights, nb_lights)
		result.append({
			"arrays": arrays,
			"transparent": transparent_pass,
			"collide": not transparent_pass,   # opaque cubes carry collision
		})
	# Custom-shaped blocks (plants, torches, slabs) — emitted individually
	var custom := _build_custom_shapes(blocks, uv_table, shapes, lights)
	if not custom.is_empty():
		if custom.has("deco"):
			result.append({"arrays": custom["deco"], "transparent": true, "collide": false})
		if custom.has("solid"):
			result.append({"arrays": custom["solid"], "transparent": false, "collide": true})
	return result


## Convert a 0-15 combined light value into a brightness multiplier.
## Full daylight = 1.0; pitch dark caves stay faintly readable at 0.16.
static func _light_curve(light: int) -> float:
	var t := float(light) / 15.0
	return 0.16 + 0.84 * t * t * (3.0 - 2.0 * t)   # smoothstep for gentle falloff


static func _build_surface_data(
		blocks: PackedInt32Array,
		nb_blocks: Array,
		flags: PackedByteArray,
		uv_table: PackedVector2Array,
		transparent_pass: bool,
		shapes: PackedByteArray = PackedByteArray(),
		lights: PackedByteArray = PackedByteArray(),
		nb_lights: Array = []) -> Array:

	const CS  := 16
	const SQ  := 256
	const FNORMALS: Array[Vector3] = [
		Vector3(0,1,0), Vector3(0,-1,0),
		Vector3(0,0,1), Vector3(0,0,-1),
		Vector3(1,0,0), Vector3(-1,0,0),
	]
	const FOFFSETS: Array[Vector3i] = [
		Vector3i(0,1,0), Vector3i(0,-1,0),
		Vector3i(0,0,1), Vector3i(0,0,-1),
		Vector3i(1,0,0), Vector3i(-1,0,0),
	]
	# Per-face brightness (stored in COLOR.r; COLOR.g = sky light, COLOR.b = block light)
	const FS: Array[float] = [1.00, 0.55, 0.82, 0.82, 0.68, 0.68]

	var verts    := PackedVector3Array()
	var cols     := PackedColorArray()
	var uvs      := PackedVector2Array()   # tiling coords [0..w, 0..h]
	var uv2s     := PackedVector2Array()   # atlas tile UV top-left
	var norms    := PackedVector3Array()
	var indices  := PackedInt32Array()
	var mask      := PackedInt32Array(); mask.resize(SQ)
	var processed := PackedByteArray();  processed.resize(SQ)
	var flags_size    := flags.size()
	var uv_table_size := uv_table.size()
	var shapes_size   := shapes.size()
	var has_light     := not lights.is_empty()

	for face in 6:
		var normal: Vector3      = FNORMALS[face]
		var off:    Vector3i     = FOFFSETS[face]
		var nb:     PackedInt32Array = nb_blocks[face]
		var nb_empty := nb.is_empty()
		var nb_lt: PackedByteArray = nb_lights[face] if nb_lights.size() == 6 else PackedByteArray()
		var nb_lt_empty := nb_lt.is_empty()
		var shade: float = FS[face]

		var d_stride: int; var u_stride: int; var v_stride: int
		if face <= 1:   d_stride = SQ; u_stride = 1;  v_stride = CS
		elif face <= 3: d_stride = CS; u_stride = 1;  v_stride = SQ
		else:           d_stride = 1;  u_stride = CS; v_stride = SQ

		for d in CS:
			mask.fill(0)
			var d_base := d * d_stride
			for u in CS:
				var uv_base := d_base + u * u_stride
				for v in CS:
					var bid := blocks[uv_base + v * v_stride]
					if bid == 0: continue
					# Non-cube shapes are meshed separately in _build_custom_shapes
					if bid < shapes_size and shapes[bid] != 0: continue
					var is_tf := bid < flags_size and (flags[bid] != 0)
					if is_tf != transparent_pass: continue

					var lx: int; var ly: int; var lz: int
					if face <= 1:   lx = u; ly = d; lz = v
					elif face <= 3: lx = u; ly = v; lz = d
					else:           lx = d; ly = v; lz = u

					var nx := lx + off.x; var ny := ly + off.y; var nz := lz + off.z
					var nbid: int
					var nlight: int = 0xF0   # default: full sky, no block light
					var outside := nx < 0 or nx >= CS or ny < 0 or ny >= CS or nz < 0 or nz >= CS
					if outside:
						var nidx := posmod(ny,CS)*SQ + posmod(nz,CS)*CS + posmod(nx,CS)
						nbid = 0 if nb_empty else nb[nidx]
						if has_light and not nb_lt_empty:
							nlight = nb_lt[nidx]
					else:
						var nidx := ny*SQ + nz*CS + nx
						nbid = blocks[nidx]
						if has_light:
							nlight = lights[nidx]

					var visible: bool
					if nbid == 0:
						visible = true
					elif nbid >= flags_size:
						visible = true
					else:
						var f := flags[nbid]
						visible = (f != 0) if not transparent_pass else ((f & 1) == 0)

					if visible:
						# Pack block id + light nibbles so greedy merge only joins
						# faces with identical lighting.
						mask[u * CS + v] = bid | (nlight << 16)

			# Greedy merge
			processed.fill(0)
			for u in CS:
				for v in CS:
					var idx := u * CS + v
					if processed[idx] or mask[idx] == 0: continue
					var packed: int = mask[idx]
					var bid: int = packed & 0xFFFF
					var sky_l: float   = float((packed >> 20) & 0xF) / 15.0
					var block_l: float = float((packed >> 16) & 0xF) / 15.0

					# Atlas UV for this block+face
					var uv_idx := bid * 6 + face
					var atlas_uv := uv_table[uv_idx] if uv_idx < uv_table_size else Vector2.ZERO

					var w := 1
					while u + w < CS and mask[(u+w)*CS+v] == packed and not processed[(u+w)*CS+v]:
						w += 1
					var h := 1; var expand := true
					while v + h < CS and expand:
						for uw in range(u, u+w):
							if mask[uw*CS+(v+h)] != packed or processed[uw*CS+(v+h)]:
								expand = false; break
						if expand: h += 1
					for uw in range(u, u+w):
						for vh in range(v, v+h):
							processed[uw*CS+vh] = 1

					var col := Color(shade, sky_l, block_l)
					_emit_quad(verts, cols, uvs, uv2s, norms, indices,
						face, d, u, v, w, h, atlas_uv, col, normal)

	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
	if verts.is_empty():
		return arrays
	arrays[Mesh.ARRAY_VERTEX]   = verts
	arrays[Mesh.ARRAY_COLOR]    = cols
	arrays[Mesh.ARRAY_TEX_UV]   = uvs
	arrays[Mesh.ARRAY_TEX_UV2]  = uv2s
	arrays[Mesh.ARRAY_NORMAL]   = norms
	arrays[Mesh.ARRAY_INDEX]    = indices
	return arrays


# ── Custom shapes: cross plants, torches, slabs ────────────────────────────────

## Builds individual geometry for every non-cube block in the chunk.
## Returns {"deco": arrays, "solid": arrays} — deco has no collision.
static func _build_custom_shapes(
		blocks: PackedInt32Array,
		uv_table: PackedVector2Array,
		shapes: PackedByteArray,
		lights: PackedByteArray = PackedByteArray()) -> Dictionary:
	if shapes.is_empty():
		return {}
	const CS := 16
	const SQ := 256
	var shapes_size := shapes.size()
	var uv_table_size := uv_table.size()
	var has_light := not lights.is_empty()

	# Two vertex streams: decoration (no collision) and solid (slabs)
	var d_verts := PackedVector3Array(); var d_cols := PackedColorArray()
	var d_uvs   := PackedVector2Array(); var d_uv2s := PackedVector2Array()
	var d_norms := PackedVector3Array(); var d_idx  := PackedInt32Array()
	var s_verts := PackedVector3Array(); var s_cols := PackedColorArray()
	var s_uvs   := PackedVector2Array(); var s_uv2s := PackedVector2Array()
	var s_norms := PackedVector3Array(); var s_idx  := PackedInt32Array()

	var found := false
	for idx in blocks.size():
		var bid := blocks[idx]
		if bid == 0 or bid >= shapes_size:
			continue
		var shape := shapes[bid]
		if shape == 0:
			continue
		found = true
		var ly := idx / SQ
		var rem := idx % SQ
		var lz := rem / CS
		var lx := rem % CS
		var uv_idx := bid * 6   # use the "top" face texture slot
		var tile: Vector2 = uv_table[uv_idx] if uv_idx < uv_table_size else Vector2.ZERO
		# Light sampled at the shape's own cell (plants/torches live in air cells)
		var lt: int = lights[idx] if has_light else 0xF0
		var sky_l: float   = float((lt >> 4) & 0xF) / 15.0
		var block_l: float = float(lt & 0xF) / 15.0
		match shape:
			1:   # cross plant
				_emit_cross(d_verts, d_cols, d_uvs, d_uv2s, d_norms, d_idx, lx, ly, lz, tile,
					Color(0.95, sky_l, block_l))
			2:   # torch — always self-lit (block channel forced to full)
				_emit_torch(d_verts, d_cols, d_uvs, d_uv2s, d_norms, d_idx, lx, ly, lz, tile,
					Color(1.0, sky_l, 1.0))
			3:   # bottom slab (solid)
				var side_idx := bid * 6 + 2
				var side_tile: Vector2 = uv_table[side_idx] if side_idx < uv_table_size else tile
				_emit_slab(s_verts, s_cols, s_uvs, s_uv2s, s_norms, s_idx, lx, ly, lz, tile, side_tile,
					sky_l, block_l)

	if not found:
		return {}
	var out := {}
	if not d_verts.is_empty():
		var da: Array = []; da.resize(Mesh.ARRAY_MAX)
		da[Mesh.ARRAY_VERTEX] = d_verts; da[Mesh.ARRAY_COLOR]  = d_cols
		da[Mesh.ARRAY_TEX_UV] = d_uvs;   da[Mesh.ARRAY_TEX_UV2] = d_uv2s
		da[Mesh.ARRAY_NORMAL] = d_norms; da[Mesh.ARRAY_INDEX]  = d_idx
		out["deco"] = da
	if not s_verts.is_empty():
		var sa: Array = []; sa.resize(Mesh.ARRAY_MAX)
		sa[Mesh.ARRAY_VERTEX] = s_verts; sa[Mesh.ARRAY_COLOR]  = s_cols
		sa[Mesh.ARRAY_TEX_UV] = s_uvs;   sa[Mesh.ARRAY_TEX_UV2] = s_uv2s
		sa[Mesh.ARRAY_NORMAL] = s_norms; sa[Mesh.ARRAY_INDEX]  = s_idx
		out["solid"] = sa
	return out


## One textured quad given 4 corners + UV sub-rect of the tile [0..1].
static func _emit_free_quad(
		verts: PackedVector3Array, cols: PackedColorArray,
		uvs: PackedVector2Array, uv2s: PackedVector2Array,
		norms: PackedVector3Array, indices: PackedInt32Array,
		p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		uv_min: Vector2, uv_max: Vector2,
		tile: Vector2, shade: Color, normal: Vector3) -> void:
	var vi := verts.size()
	verts.append(p0); verts.append(p1); verts.append(p2); verts.append(p3)
	for _i in 4:
		cols.append(shade)
		uv2s.append(tile)
		norms.append(normal)
	uvs.append(Vector2(uv_min.x, uv_min.y))
	uvs.append(Vector2(uv_max.x, uv_min.y))
	uvs.append(Vector2(uv_max.x, uv_max.y))
	uvs.append(Vector2(uv_min.x, uv_max.y))
	indices.append(vi); indices.append(vi + 1); indices.append(vi + 2)
	indices.append(vi); indices.append(vi + 2); indices.append(vi + 3)


static func _emit_cross(
		verts: PackedVector3Array, cols: PackedColorArray,
		uvs: PackedVector2Array, uv2s: PackedVector2Array,
		norms: PackedVector3Array, indices: PackedInt32Array,
		lx: int, ly: int, lz: int, tile: Vector2,
		shade: Color = Color(0.95, 1.0, 0.0)) -> void:
	# Deterministic jitter so plants don't sit on a perfect grid
	var h := (lx * 73856093) ^ (ly * 19349663) ^ (lz * 83492791)
	var jx := float((h >> 3) & 7) / 7.0 * 0.30 - 0.15
	var jz := float((h >> 7) & 7) / 7.0 * 0.30 - 0.15
	var cx := lx + 0.5 + jx
	var cz := lz + 0.5 + jz
	var y0 := float(ly)
	var y1 := y0 + 0.85
	const E := 0.35   # half-extent of each diagonal plane
	var n := Vector3(0, 1, 0)
	# Plane A (\) — both windings so it's visible from both sides with cull_back
	var a0 := Vector3(cx - E, y1, cz - E); var a1 := Vector3(cx + E, y1, cz + E)
	var a2 := Vector3(cx + E, y0, cz + E); var a3 := Vector3(cx - E, y0, cz - E)
	_emit_free_quad(verts, cols, uvs, uv2s, norms, indices, a0, a1, a2, a3,
		Vector2(0.001, 0.001), Vector2(0.999, 0.999), tile, shade, n)
	_emit_free_quad(verts, cols, uvs, uv2s, norms, indices, a1, a0, a3, a2,
		Vector2(0.999, 0.001), Vector2(0.001, 0.999), tile, shade, n)
	# Plane B (/)
	var b0 := Vector3(cx - E, y1, cz + E); var b1 := Vector3(cx + E, y1, cz - E)
	var b2 := Vector3(cx + E, y0, cz - E); var b3 := Vector3(cx - E, y0, cz + E)
	_emit_free_quad(verts, cols, uvs, uv2s, norms, indices, b0, b1, b2, b3,
		Vector2(0.001, 0.001), Vector2(0.999, 0.999), tile, shade, n)
	_emit_free_quad(verts, cols, uvs, uv2s, norms, indices, b1, b0, b3, b2,
		Vector2(0.999, 0.001), Vector2(0.001, 0.999), tile, shade, n)


static func _emit_torch(
		verts: PackedVector3Array, cols: PackedColorArray,
		uvs: PackedVector2Array, uv2s: PackedVector2Array,
		norms: PackedVector3Array, indices: PackedInt32Array,
		lx: int, ly: int, lz: int, tile: Vector2,
		shade: Color = Color(1.0, 1.0, 1.0)) -> void:
	# Small 2/16-wide stick, 10/16 tall, centred in the cell.
	const HW := 1.0 / 16.0        # half width
	const H  := 10.0 / 16.0       # height
	var cx := lx + 0.5
	var cz := lz + 0.5
	var y0 := float(ly)
	var y1 := y0 + H
	# Texture: MC torch occupies x 7..9, y 6..16 (v measured from top)
	var u_min := Vector2(7.0 / 16.0, 6.0 / 16.0)
	var u_max := Vector2(9.0 / 16.0, 0.999)
	# 4 side faces
	_emit_free_quad(verts, cols, uvs, uv2s, norms, indices,
		Vector3(cx - HW, y1, cz + HW), Vector3(cx + HW, y1, cz + HW),
		Vector3(cx + HW, y0, cz + HW), Vector3(cx - HW, y0, cz + HW),
		u_min, u_max, tile, shade, Vector3(0, 0, 1))
	_emit_free_quad(verts, cols, uvs, uv2s, norms, indices,
		Vector3(cx + HW, y1, cz - HW), Vector3(cx - HW, y1, cz - HW),
		Vector3(cx - HW, y0, cz - HW), Vector3(cx + HW, y0, cz - HW),
		u_min, u_max, tile, shade, Vector3(0, 0, -1))
	_emit_free_quad(verts, cols, uvs, uv2s, norms, indices,
		Vector3(cx + HW, y1, cz + HW), Vector3(cx + HW, y1, cz - HW),
		Vector3(cx + HW, y0, cz - HW), Vector3(cx + HW, y0, cz + HW),
		u_min, u_max, tile, shade, Vector3(1, 0, 0))
	_emit_free_quad(verts, cols, uvs, uv2s, norms, indices,
		Vector3(cx - HW, y1, cz - HW), Vector3(cx - HW, y1, cz + HW),
		Vector3(cx - HW, y0, cz + HW), Vector3(cx - HW, y0, cz - HW),
		u_min, u_max, tile, shade, Vector3(-1, 0, 0))
	# Top face (glowing tip): x 7..9, y 6..8 of the texture
	_emit_free_quad(verts, cols, uvs, uv2s, norms, indices,
		Vector3(cx - HW, y1, cz - HW), Vector3(cx + HW, y1, cz - HW),
		Vector3(cx + HW, y1, cz + HW), Vector3(cx - HW, y1, cz + HW),
		Vector2(7.0 / 16.0, 6.0 / 16.0), Vector2(9.0 / 16.0, 8.0 / 16.0),
		tile, shade, Vector3(0, 1, 0))


static func _emit_slab(
		verts: PackedVector3Array, cols: PackedColorArray,
		uvs: PackedVector2Array, uv2s: PackedVector2Array,
		norms: PackedVector3Array, indices: PackedInt32Array,
		lx: int, ly: int, lz: int, top_tile: Vector2, side_tile: Vector2,
		sky_l: float = 1.0, block_l: float = 0.0) -> void:
	var x0 := float(lx);     var x1 := x0 + 1.0
	var y0 := float(ly);     var y1 := y0 + 0.5
	var z0 := float(lz);     var z1 := z0 + 1.0
	var full := Vector2(0.001, 0.001)
	var full2 := Vector2(0.999, 0.999)
	var half_v := Vector2(0.999, 0.5)
	# Top
	_emit_free_quad(verts, cols, uvs, uv2s, norms, indices,
		Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1),
		full, full2, top_tile, Color(1.0, sky_l, block_l), Vector3(0, 1, 0))
	# Bottom
	_emit_free_quad(verts, cols, uvs, uv2s, norms, indices,
		Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x0, y0, z0),
		full, full2, top_tile, Color(0.5, sky_l, block_l), Vector3(0, -1, 0))
	# Sides (half-height texture region)
	var s := Color(0.78, sky_l, block_l)
	_emit_free_quad(verts, cols, uvs, uv2s, norms, indices,
		Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y0, z1), Vector3(x0, y0, z1),
		full, half_v, side_tile, s, Vector3(0, 0, 1))
	_emit_free_quad(verts, cols, uvs, uv2s, norms, indices,
		Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3(x0, y0, z0), Vector3(x1, y0, z0),
		full, half_v, side_tile, s, Vector3(0, 0, -1))
	_emit_free_quad(verts, cols, uvs, uv2s, norms, indices,
		Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1),
		full, half_v, side_tile, s, Vector3(1, 0, 0))
	_emit_free_quad(verts, cols, uvs, uv2s, norms, indices,
		Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x0, y0, z1), Vector3(x0, y0, z0),
		full, half_v, side_tile, s, Vector3(-1, 0, 0))


static func _emit_quad(
		verts: PackedVector3Array, cols: PackedColorArray,
		uvs: PackedVector2Array, uv2s: PackedVector2Array,
		norms: PackedVector3Array, indices: PackedInt32Array,
		face: int, d: int, u0: int, v0: int, w: int, h: int,
		atlas_uv: Vector2, shade: Color, normal: Vector3) -> void:
	var p0: Vector3; var p1: Vector3; var p2: Vector3; var p3: Vector3
	match face:
		0: p0=Vector3(u0,d+1,v0);    p1=Vector3(u0+w,d+1,v0);   p2=Vector3(u0+w,d+1,v0+h); p3=Vector3(u0,d+1,v0+h)
		1: p0=Vector3(u0,d,v0+h);    p1=Vector3(u0+w,d,v0+h);   p2=Vector3(u0+w,d,v0);     p3=Vector3(u0,d,v0)
		2: p0=Vector3(u0,v0+h,d+1);  p1=Vector3(u0+w,v0+h,d+1); p2=Vector3(u0+w,v0,d+1);   p3=Vector3(u0,v0,d+1)
		3: p0=Vector3(u0+w,v0+h,d);  p1=Vector3(u0,v0+h,d);     p2=Vector3(u0,v0,d);         p3=Vector3(u0+w,v0,d)
		4: p0=Vector3(d+1,v0+h,u0+w);p1=Vector3(d+1,v0+h,u0);   p2=Vector3(d+1,v0,u0);    p3=Vector3(d+1,v0,u0+w)
		5: p0=Vector3(d,v0+h,u0);    p1=Vector3(d,v0+h,u0+w);   p2=Vector3(d,v0,u0+w);     p3=Vector3(d,v0,u0)
	var vi := verts.size()
	verts.append(p0); verts.append(p1); verts.append(p2); verts.append(p3)
	cols.append(shade); cols.append(shade); cols.append(shade); cols.append(shade)
	# UV0: tiling coordinates — shader uses fract(UV) to tile within atlas tile
	uvs.append(Vector2(0.0, 0.0));        uvs.append(Vector2(float(w), 0.0))
	uvs.append(Vector2(float(w), float(h))); uvs.append(Vector2(0.0, float(h)))
	# UV2: atlas tile top-left — same for all 4 verts of this quad
	uv2s.append(atlas_uv); uv2s.append(atlas_uv); uv2s.append(atlas_uv); uv2s.append(atlas_uv)
	norms.append(normal); norms.append(normal); norms.append(normal); norms.append(normal)
	indices.append(vi); indices.append(vi+1); indices.append(vi+2)
	indices.append(vi); indices.append(vi+2); indices.append(vi+3)


# ── UV atlas cache ─────────────────────────────────────────────────────────────

static func _ensure_uv_cache() -> void:
	if _uv_cache_built:
		return
	var flags    := BlockRegistry._block_flags
	var max_bid  := flags.size()
	_uv_cache.resize(max_bid * 6)

	const FACE_N: Array[String] = ["top", "bottom", "north", "south", "east", "west"]
	for bid in max_bid:
		var b = BlockRegistry.get_block(bid)
		for f in 6:
			var tex: String = b.get_texture_for_face(FACE_N[f]) if b else "missing"
			_uv_cache[bid * 6 + f] = BlockTextureAtlas.get_face_uv(tex)

	_uv_cache_built = true


# ── Material ───────────────────────────────────────────────────────────────────

func _make_mat(transparent: bool) -> ShaderMaterial:
	if transparent:
		if _shared_trans == null:
			_shared_trans = _new_voxel_mat(true)
		return _shared_trans
	if _shared_opaque == null:
		_shared_opaque = _new_voxel_mat(false)
	return _shared_opaque


static func _new_voxel_mat(transparent: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = VOXEL_TRANS_SHADER if transparent else VOXEL_OPAQUE_SHADER
	mat.set_shader_parameter("atlas", BlockTextureAtlas.texture)
	mat.set_shader_parameter("tile_size", BlockTextureAtlas.tile_uv_size)
	return mat


# ── Helpers ────────────────────────────────────────────────────────────────────

func _is_near_player() -> bool:
	if _manager == null or _chunk == null:
		return true
	var pc := _manager._player_chunk
	var cc := _chunk.chunk_pos
	return abs(cc.x - pc.x) <= 2 and abs(cc.y - pc.y) <= 1 and abs(cc.z - pc.z) <= 2


func _faces_from_arrays(ma: Array) -> PackedVector3Array:
	if ma.is_empty() or ma[Mesh.ARRAY_VERTEX] == null or ma[Mesh.ARRAY_INDEX] == null:
		return PackedVector3Array()
	var sv: PackedVector3Array = ma[Mesh.ARRAY_VERTEX]
	var si: PackedInt32Array   = ma[Mesh.ARRAY_INDEX]
	var faces := PackedVector3Array(); faces.resize(si.size())
	var i := 0
	while i < si.size():
		faces[i]     = sv[si[i]]
		faces[i + 1] = sv[si[i + 1]]
		faces[i + 2] = sv[si[i + 2]]
		i += 3
	return faces


func _apply_collision_shape(shape: ConcavePolygonShape3D) -> void:
	for child in get_children():
		if child is StaticBody3D:
			child.queue_free()
	var sb  := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = shape
	sb.add_child(col)
	add_child(sb)


func force_initial_build() -> void:
	if _chunk == null or _chunk.is_all_air:
		return
	_ensure_uv_cache()
	var blocks_snap := _chunk.blocks.duplicate()
	var light_snap  := _chunk.light_data.duplicate()
	var flags_snap  := BlockRegistry._block_flags.duplicate()
	var shapes_snap := BlockRegistry._block_shape.duplicate()
	var uvs_snap    := _uv_cache.duplicate()
	var nb_snaps: Array = []
	var nb_lights: Array = []
	if _manager != null:
		for i in 6:
			var nb := _manager.get_chunk(_chunk.chunk_pos + FACE_OFFSETS[i])
			nb_snaps.append(nb.blocks.duplicate() if nb != null else PackedInt32Array())
			nb_lights.append(nb.light_data.duplicate() if nb != null else PackedByteArray())
	else:
		for _i in 6:
			nb_snaps.append(PackedInt32Array())
			nb_lights.append(PackedByteArray())

	var surfaces := _compute_surfaces(
		blocks_snap, nb_snaps, flags_snap, uvs_snap, shapes_snap, light_snap, nb_lights)
	_apply_mesh_data(surfaces)
	_dirty = false

	if not _col_faces_snapshot.is_empty():
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(_col_faces_snapshot)
		_apply_collision_shape(shape)
		_col_dirty    = false
		_col_building = false
