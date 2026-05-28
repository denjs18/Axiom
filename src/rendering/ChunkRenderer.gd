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
	var flags_snap  := BlockRegistry._block_flags.duplicate()
	var uvs_snap    := _uv_cache.duplicate()
	var nb_snaps: Array = []
	if _manager != null:
		for i in 6:
			var nb := _manager.get_chunk(_chunk.chunk_pos + FACE_OFFSETS[i])
			nb_snaps.append(nb.blocks.duplicate() if nb != null else PackedInt32Array())
	else:
		for _i in 6:
			nb_snaps.append(PackedInt32Array())

	_mesh_building = true
	_dirty         = false

	var mtx  := _mesh_mutex
	var pend := _mesh_result

	WorkerThreadPool.add_task(func() -> void:
		var result := ChunkRenderer._compute_surfaces(blocks_snap, nb_snaps, flags_snap, uvs_snap)
		mtx.lock()
		pend.clear()
		pend.append_array(result)
		mtx.unlock()
	)


func _apply_mesh_data(surfaces: Array) -> void:
	var arr_mesh := ArrayMesh.new()
	for sd in surfaces:
		var arrays: Array = sd["arrays"]
		if arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue
		var si := arr_mesh.get_surface_count()
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		arr_mesh.surface_set_material(si, _trans_mat if sd["transparent"] else _opaque_mat)

	if arr_mesh.get_surface_count() == 0:
		mesh = null
		_col_dirty          = false
		_col_faces_snapshot = PackedVector3Array()
	else:
		mesh = arr_mesh
		_col_faces_snapshot = _extract_collision_faces(arr_mesh)
		_col_dirty          = true
	set_process(true)


# ── Static mesh computation (worker thread) ────────────────────────────────────

static func _compute_surfaces(
		blocks: PackedInt32Array,
		nb_blocks: Array,
		flags: PackedByteArray,
		uv_table: PackedVector2Array) -> Array:
	var result: Array = []
	for pass_idx in 2:
		var transparent_pass: bool = pass_idx == 1
		var arrays := _build_surface_data(blocks, nb_blocks, flags, uv_table, transparent_pass)
		result.append({"arrays": arrays, "transparent": transparent_pass})
	return result


static func _build_surface_data(
		blocks: PackedInt32Array,
		nb_blocks: Array,
		flags: PackedByteArray,
		uv_table: PackedVector2Array,
		transparent_pass: bool) -> Array:

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
	# Face shading constants (same as FACE_SHADE above — duplicated for static fn)
	const FS: Array[Color] = [
		Color(1.00, 1.00, 1.00), Color(0.50, 0.50, 0.50),
		Color(0.80, 0.80, 0.80), Color(0.80, 0.80, 0.80),
		Color(0.65, 0.65, 0.65), Color(0.65, 0.65, 0.65),
	]

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

	for face in 6:
		var normal: Vector3      = FNORMALS[face]
		var off:    Vector3i     = FOFFSETS[face]
		var nb:     PackedInt32Array = nb_blocks[face]
		var nb_empty := nb.is_empty()
		var shade := FS[face]

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
					var is_tf := bid < flags_size and (flags[bid] != 0)
					if is_tf != transparent_pass: continue

					var lx: int; var ly: int; var lz: int
					if face <= 1:   lx = u; ly = d; lz = v
					elif face <= 3: lx = u; ly = v; lz = d
					else:           lx = d; ly = v; lz = u

					var nx := lx + off.x; var ny := ly + off.y; var nz := lz + off.z
					var nbid: int
					if nx < 0 or nx >= CS or ny < 0 or ny >= CS or nz < 0 or nz >= CS:
						nbid = 0 if nb_empty else nb[posmod(ny,CS)*SQ + posmod(nz,CS)*CS + posmod(nx,CS)]
					else:
						nbid = blocks[ny*SQ + nz*CS + nx]

					var visible: bool
					if nbid == 0:
						visible = true
					elif nbid >= flags_size:
						visible = true
					else:
						var f := flags[nbid]
						visible = (f != 0) if not transparent_pass else ((f & 1) == 0)

					if visible:
						mask[u * CS + v] = bid

			# Greedy merge
			processed.fill(0)
			for u in CS:
				for v in CS:
					var idx := u * CS + v
					if processed[idx] or mask[idx] == 0: continue
					var bid: int = mask[idx]

					# Atlas UV for this block+face
					var uv_idx := bid * 6 + face
					var atlas_uv := uv_table[uv_idx] if uv_idx < uv_table_size else Vector2.ZERO

					var w := 1
					while u + w < CS and mask[(u+w)*CS+v] == bid and not processed[(u+w)*CS+v]:
						w += 1
					var h := 1; var expand := true
					while v + h < CS and expand:
						for uw in range(u, u+w):
							if mask[uw*CS+(v+h)] != bid or processed[uw*CS+(v+h)]:
								expand = false; break
						if expand: h += 1
					for uw in range(u, u+w):
						for vh in range(v, v+h):
							processed[uw*CS+vh] = 1

					_emit_quad(verts, cols, uvs, uv2s, norms, indices,
						face, d, u, v, w, h, atlas_uv, shade, normal)

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


func _extract_collision_faces(arr_mesh: ArrayMesh) -> PackedVector3Array:
	if arr_mesh.get_surface_count() == 0:
		return PackedVector3Array()
	var ma: Array = arr_mesh.surface_get_arrays(0)
	if ma[Mesh.ARRAY_VERTEX] == null or ma[Mesh.ARRAY_INDEX] == null:
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
	var flags_snap  := BlockRegistry._block_flags.duplicate()
	var uvs_snap    := _uv_cache.duplicate()
	var nb_snaps: Array = []
	if _manager != null:
		for i in 6:
			var nb := _manager.get_chunk(_chunk.chunk_pos + FACE_OFFSETS[i])
			nb_snaps.append(nb.blocks.duplicate() if nb != null else PackedInt32Array())
	else:
		for _i in 6: nb_snaps.append(PackedInt32Array())

	var surfaces := _compute_surfaces(blocks_snap, nb_snaps, flags_snap, uvs_snap)
	_apply_mesh_data(surfaces)
	_dirty = false

	if not _col_faces_snapshot.is_empty():
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(_col_faces_snapshot)
		_apply_collision_shape(shape)
		_col_dirty    = false
		_col_building = false
