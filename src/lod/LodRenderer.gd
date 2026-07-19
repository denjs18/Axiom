## LodRenderer.gd — Async height-field mesh with top faces, side faces, and boundary skirts.
## Mesh arrays are built on a WorkerThreadPool thread; only the GPU upload is on the main thread.
class_name LodRenderer
extends MeshInstance3D

const SEA_LEVEL   := 63.0
const SKIRT_DEPTH := 64.0
const SHADE_NS    := 0.80
const SHADE_EW    := 0.65

var _tile:         LodTile
var _mat_opaque:   StandardMaterial3D
var _mat_water:    StandardMaterial3D
var _skip_skirts:  int = 0

# Async mesh build state
var _mutex:        Mutex = Mutex.new()
var _result:       Array = []   # holds surface dicts when ready
var _building:     bool  = false


func setup(tile: LodTile, skip_skirts: int = 0) -> void:
	_tile        = tile
	_skip_skirts = skip_skirts
	_mat_opaque  = _make_mat(false)
	_mat_water   = _make_mat(true)
	var ox := tile.get_world_origin_xz()
	position = Vector3(float(ox.x), 0.0, float(ox.y))
	_schedule_build()
	set_process(true)


func _process(_delta: float) -> void:
	_mutex.lock()
	var done := not _result.is_empty()
	var surfaces: Array = _result.duplicate() if done else []
	if done:
		_result.clear()
	_mutex.unlock()

	if done:
		_building = false
		_apply_surfaces(surfaces)
		set_process(false)


# ── Async scheduling ───────────────────────────────────────────────────────────

func _schedule_build() -> void:
	if _building:
		return
	_building = true

	# Snapshot tile data (thread-safe primitives only)
	var heights  := _tile.heights.duplicate()
	var colors   := _tile.surface_colors.duplicate()
	var water    := _tile.water_mask.duplicate()
	var col_w    := _tile.get_col_width()
	var skip     := _skip_skirts
	var mtx      := _mutex
	var res      := _result

	WorkerThreadPool.add_task(func() -> void:
		var surfaces := LodRenderer._build_all(heights, colors, water, col_w, skip)
		mtx.lock()
		res.clear()
		res.append_array(surfaces)
		mtx.unlock()
	)


func _apply_surfaces(surfaces: Array) -> void:
	var arr_mesh := ArrayMesh.new()
	for s in surfaces:
		var verts: PackedVector3Array = s["v"]
		if verts.is_empty():
			continue
		var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR]  = s["c"]
		arrays[Mesh.ARRAY_NORMAL] = s["n"]
		arrays[Mesh.ARRAY_INDEX]  = s["i"]
		var si := arr_mesh.get_surface_count()
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		arr_mesh.surface_set_material(si, _mat_water if s["water"] else _mat_opaque)
	mesh = arr_mesh if arr_mesh.get_surface_count() > 0 else null


# ── Static mesh builders (run on worker thread) ───────────────────────────────

static func _build_all(
		heights: PackedInt32Array, colors: PackedColorArray,
		water: PackedByteArray, col_w: int, skip: int) -> Array:
	var results: Array = []
	results.append(_build_top(heights, colors, col_w))
	results.append(_build_sides(heights, colors, col_w))
	results.append(_build_skirts(heights, colors, col_w, skip))
	results.append(_build_water(water, col_w))
	return results


static func _build_top(heights: PackedInt32Array, colors: PackedColorArray, col_w: int) -> Dictionary:
	var v := PackedVector3Array(); var c := PackedColorArray()
	var n := PackedVector3Array(); var idx := PackedInt32Array()
	var up := Vector3(0, 1, 0)
	var cw := float(col_w)
	var cols := 16
	for z in cols:
		for x in cols:
			var i   := z * cols + x
			var h   := float(heights[i]) + 0.996
			var col := colors[i]
			_hq(v, c, n, idx, float(x)*cw, h, float(z)*cw, cw, col, up)
	return {"v": v, "c": c, "n": n, "i": idx, "water": false}


static func _build_sides(heights: PackedInt32Array, colors: PackedColorArray, col_w: int) -> Dictionary:
	var v := PackedVector3Array(); var c := PackedColorArray()
	var n := PackedVector3Array(); var idx := PackedInt32Array()
	var cols := 16
	var cw   := float(col_w)

	for z in cols:
		for x in cols:
			var i  := z * cols + x
			var hA := float(heights[i]) + 0.996
			var cA := colors[i]

			# East edge
			if x + 1 < cols:
				var j  := z * cols + (x + 1)
				var hB := float(heights[j]) + 0.996
				var dh := hA - hB
				if absf(dh) > 0.1:
					var ht := maxf(hA, hB)
					var hb := minf(hA, hB) - 8.0
					var wx := float(x + 1) * cw
					var z0 := float(z) * cw;  var z1 := float(z + 1) * cw
					if dh > 0.0:
						var sc := Color(cA.r*SHADE_EW, cA.g*SHADE_EW, cA.b*SHADE_EW)
						_vq(v,c,n,idx, Vector3(wx,ht,z0),Vector3(wx,ht,z1),Vector3(wx,hb,z1),Vector3(wx,hb,z0), Vector3(1,0,0),sc)
					else:
						var cB := colors[j]
						var sc := Color(cB.r*SHADE_EW, cB.g*SHADE_EW, cB.b*SHADE_EW)
						_vq(v,c,n,idx, Vector3(wx,ht,z1),Vector3(wx,ht,z0),Vector3(wx,hb,z0),Vector3(wx,hb,z1), Vector3(-1,0,0),sc)

			# South edge
			if z + 1 < cols:
				var j  := (z + 1) * cols + x
				var hB := float(heights[j]) + 0.996
				var dh := hA - hB
				if absf(dh) > 0.1:
					var ht := maxf(hA, hB)
					var hb := minf(hA, hB) - 8.0
					var zw := float(z + 1) * cw
					var x0 := float(x) * cw;  var x1 := float(x + 1) * cw
					if dh > 0.0:
						var sc := Color(cA.r*SHADE_NS, cA.g*SHADE_NS, cA.b*SHADE_NS)
						_vq(v,c,n,idx, Vector3(x1,ht,zw),Vector3(x0,ht,zw),Vector3(x0,hb,zw),Vector3(x1,hb,zw), Vector3(0,0,1),sc)
					else:
						var cB := colors[j]
						var sc := Color(cB.r*SHADE_NS, cB.g*SHADE_NS, cB.b*SHADE_NS)
						_vq(v,c,n,idx, Vector3(x0,ht,zw),Vector3(x1,ht,zw),Vector3(x1,hb,zw),Vector3(x0,hb,zw), Vector3(0,0,-1),sc)

	return {"v": v, "c": c, "n": n, "i": idx, "water": false}


static func _build_skirts(
		heights: PackedInt32Array, colors: PackedColorArray,
		col_w: int, skip: int) -> Dictionary:
	var v := PackedVector3Array(); var c := PackedColorArray()
	var n := PackedVector3Array(); var idx := PackedInt32Array()
	var cols := 16
	var cw   := float(col_w)
	var tw   := float(cols) * cw

	for k in cols:
		var z0 := float(k) * cw;  var z1 := float(k + 1) * cw
		var x0 := float(k) * cw;  var x1 := float(k + 1) * cw

		if not (skip & 1):   # west
			var i := k * cols + 0
			var h := float(heights[i]) + 0.996
			var sc := Color(colors[i].r*SHADE_EW, colors[i].g*SHADE_EW, colors[i].b*SHADE_EW)
			_vq(v,c,n,idx, Vector3(0,h,z1),Vector3(0,h,z0),Vector3(0,h-SKIRT_DEPTH,z0),Vector3(0,h-SKIRT_DEPTH,z1), Vector3(-1,0,0),sc)

		if not (skip & 2):   # east
			var i := k * cols + (cols - 1)
			var h := float(heights[i]) + 0.996
			var sc := Color(colors[i].r*SHADE_EW, colors[i].g*SHADE_EW, colors[i].b*SHADE_EW)
			_vq(v,c,n,idx, Vector3(tw,h,z0),Vector3(tw,h,z1),Vector3(tw,h-SKIRT_DEPTH,z1),Vector3(tw,h-SKIRT_DEPTH,z0), Vector3(1,0,0),sc)

		if not (skip & 4):   # north
			var i := 0 * cols + k
			var h := float(heights[i]) + 0.996
			var sc := Color(colors[i].r*SHADE_NS, colors[i].g*SHADE_NS, colors[i].b*SHADE_NS)
			_vq(v,c,n,idx, Vector3(x0,h,0),Vector3(x1,h,0),Vector3(x1,h-SKIRT_DEPTH,0),Vector3(x0,h-SKIRT_DEPTH,0), Vector3(0,0,-1),sc)

		if not (skip & 8):   # south
			var i := (cols - 1) * cols + k
			var h := float(heights[i]) + 0.996
			var sc := Color(colors[i].r*SHADE_NS, colors[i].g*SHADE_NS, colors[i].b*SHADE_NS)
			_vq(v,c,n,idx, Vector3(x1,h,tw),Vector3(x0,h,tw),Vector3(x0,h-SKIRT_DEPTH,tw),Vector3(x1,h-SKIRT_DEPTH,tw), Vector3(0,0,1),sc)

	return {"v": v, "c": c, "n": n, "i": idx, "water": false}


static func _build_water(water: PackedByteArray, col_w: int) -> Dictionary:
	var v := PackedVector3Array(); var c := PackedColorArray()
	var n := PackedVector3Array(); var idx := PackedInt32Array()
	var up  := Vector3(0, 1, 0)
	var cw  := float(col_w)
	var wc  := Color(0.16, 0.34, 0.72, 0.65)
	var cols := 16
	for z in cols:
		for x in cols:
			var i := z * cols + x
			if water[i] == 0:
				continue
			_hq(v, c, n, idx, float(x)*cw, SEA_LEVEL - 0.12, float(z)*cw, cw, wc, up)
	return {"v": v, "c": c, "n": n, "i": idx, "water": true}


# ── Quad primitives (static) ──────────────────────────────────────────────────

static func _hq(v: PackedVector3Array, c: PackedColorArray,
		n: PackedVector3Array, idx: PackedInt32Array,
		x: float, y: float, z: float, w: float, col: Color, nrm: Vector3) -> void:
	var vi := v.size()
	v.append(Vector3(x,   y, z  )); v.append(Vector3(x+w, y, z  ))
	v.append(Vector3(x+w, y, z+w)); v.append(Vector3(x,   y, z+w))
	c.append(col); c.append(col); c.append(col); c.append(col)
	n.append(nrm); n.append(nrm); n.append(nrm); n.append(nrm)
	idx.append(vi); idx.append(vi+1); idx.append(vi+2)
	idx.append(vi); idx.append(vi+2); idx.append(vi+3)


static func _vq(v: PackedVector3Array, c: PackedColorArray,
		n: PackedVector3Array, idx: PackedInt32Array,
		p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		nrm: Vector3, col: Color) -> void:
	var vi := v.size()
	v.append(p0); v.append(p1); v.append(p2); v.append(p3)
	c.append(col); c.append(col); c.append(col); c.append(col)
	n.append(nrm); n.append(nrm); n.append(nrm); n.append(nrm)
	idx.append(vi); idx.append(vi+1); idx.append(vi+2)
	idx.append(vi); idx.append(vi+2); idx.append(vi+3)


# ── Material ──────────────────────────────────────────────────────────────────

func _make_mat(transparent: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness    = 0.95
	mat.metallic     = 0.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode    = BaseMaterial3D.CULL_BACK
	return mat
