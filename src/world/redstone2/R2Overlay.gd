## R2Overlay.gd — Debug overlay for Redstone 2.0 networks.
## Shows topology, signal values, latency, conversions, errors, channel colors.
## Attach as a child of the main 3D scene. Toggle with R2Engine.toggle_debug().
class_name R2Overlay
extends Node3D

const CHANNEL_COLORS := [
	Color(1.0, 0.2, 0.2),   # 0 red
	Color(0.2, 0.6, 1.0),   # 1 blue
	Color(0.2, 1.0, 0.2),   # 2 green
	Color(1.0, 0.8, 0.1),   # 3 yellow
	Color(1.0, 0.4, 0.0),   # 4 orange
	Color(0.8, 0.2, 1.0),   # 5 purple
	Color(0.0, 0.9, 0.9),   # 6 cyan
	Color(1.0, 0.4, 0.8),   # 7 pink
	Color(0.5, 1.0, 0.5),   # 8 lime
	Color(0.4, 0.2, 0.0),   # 9 brown
	Color(0.7, 0.7, 0.7),   # 10 gray
	Color(0.3, 0.3, 0.3),   # 11 dark gray
	Color(0.6, 0.8, 1.0),   # 12 light blue
	Color(0.6, 0.0, 0.0),   # 13 dark red
	Color(0.0, 0.4, 0.0),   # 14 dark green
	Color(1.0, 1.0, 1.0),   # 15 white
]

const ERROR_COLOR   := Color(1.0, 0.0, 0.0)
const OK_COLOR      := Color(0.2, 1.0, 0.2)
const BOOL_ON_COL   := Color(1.0, 0.9, 0.2)
const BOOL_OFF_COL  := Color(0.3, 0.3, 0.3)
const ANALOG_COL    := Color(0.4, 0.8, 1.0)
const EVENT_COL     := Color(1.0, 0.5, 0.0)

var view_radius:   int  = 16      # blocks around player to draw
var show_values:   bool = true
var show_channels: bool = true
var show_errors:   bool = true
var show_topology: bool = true

var _label_pool:   Array[Label3D] = []
var _line_pool:    Array[MeshInstance3D] = []
var _pool_label_idx: int = 0
var _pool_line_idx:  int = 0

var _player_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	R2Engine.r2_block_error.connect(_on_block_error)
	set_process(false)   # driven by R2Engine debug toggle


func enable(player_pos: Vector3) -> void:
	_player_pos = player_pos
	set_process(true)
	_rebuild()


func disable() -> void:
	set_process(false)
	_hide_all()


func _process(_delta: float) -> void:
	_rebuild()


func _rebuild() -> void:
	_pool_label_idx = 0
	_pool_line_idx  = 0

	if not R2Engine.debug_enabled:
		_hide_all()
		return

	var player_ipos := Vector3i(int(_player_pos.x), int(_player_pos.y), int(_player_pos.z))
	var blocks := R2Engine.get_blocks_near(player_ipos, view_radius)

	for bpos in blocks:
		var ent := R2Engine.get_block(bpos)
		if ent == null: continue
		_draw_block(ent, bpos)

	# Hide unused pool items
	for i in range(_pool_label_idx, _label_pool.size()):
		_label_pool[i].visible = false
	for i in range(_pool_line_idx, _line_pool.size()):
		_line_pool[i].visible = false


func _draw_block(ent: R2BlockEntity, bpos: Vector3i) -> void:
	var center := Vector3(bpos) + Vector3(0.5, 0.5, 0.5)

	# Error indicator
	if show_errors and ent.error != "":
		_get_label(center + Vector3(0, 0.8, 0), "⚠ " + ent.error, ERROR_COLOR, 0.06)

	if not show_values: return

	# Output channel labels
	var debug := ent.get_debug_dict()
	var outputs: Dictionary = debug.get("outputs", {})
	var color_override: int = ent.get_meta("r2_network_color", -1) if ent.has_meta("r2_network_color") else -1

	var offset := Vector3(0, 0.55, 0)
	for ch in outputs:
		var sig: R2Signal = outputs[ch]
		if sig == null: continue
		var col := _sig_color(sig, color_override)
		var txt := _sig_text(sig)
		_get_label(center + offset, txt, col, 0.05)
		offset += Vector3(0, 0.14, 0)

	# Facing arrow (topology)
	if show_topology and "facing" in debug:
		var fv := debug["facing"] as Vector3i
		_draw_arrow(center, center + Vector3(fv) * 0.6, OK_COLOR)


func _sig_color(sig: R2Signal, override: int) -> Color:
	if override >= 0 and override < CHANNEL_COLORS.size():
		return CHANNEL_COLORS[override]
	if sig.channel < CHANNEL_COLORS.size():
		var base := CHANNEL_COLORS[sig.channel]
		if sig.type == R2Signal.Type.BOOLEAN:
			return BOOL_ON_COL if sig.bool_value else BOOL_OFF_COL
		if sig.type == R2Signal.Type.EVENT:
			return EVENT_COL
		return base
	return ANALOG_COL


func _sig_text(sig: R2Signal) -> String:
	match sig.type:
		R2Signal.Type.BOOLEAN: return "B:" + ("1" if sig.bool_value else "0")
		R2Signal.Type.EVENT:   return "E!"
		R2Signal.Type.ANALOG:  return "A:" + str(sig.analog_value)
	return "?"


func _get_label(pos: Vector3, text: String, col: Color, size: float) -> Label3D:
	var lbl: Label3D
	if _pool_label_idx < _label_pool.size():
		lbl = _label_pool[_pool_label_idx]
	else:
		lbl = Label3D.new()
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		add_child(lbl)
		_label_pool.append(lbl)
	lbl.position     = pos
	lbl.text         = text
	lbl.modulate     = col
	lbl.pixel_size   = size
	lbl.visible      = true
	_pool_label_idx += 1
	return lbl


func _draw_arrow(from: Vector3, to: Vector3, col: Color) -> void:
	if _pool_line_idx >= _line_pool.size():
		var mi := MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.no_depth_test = true
		mi.material_override = mat
		add_child(mi)
		_line_pool.append(mi)

	var mi: MeshInstance3D = _line_pool[_pool_line_idx]
	var mesh := mi.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_set_color(col)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()
	mi.visible = true
	_pool_line_idx += 1


func _hide_all() -> void:
	for l in _label_pool: l.visible = false
	for m in _line_pool:  m.visible = false


func _on_block_error(bpos: Vector3i, err: String) -> void:
	if not show_errors: return
	var center := Vector3(bpos) + Vector3(0.5, 0.5, 0.5)
	_get_label(center + Vector3(0, 1.0, 0), "ERR:" + err, ERROR_COLOR, 0.07)
