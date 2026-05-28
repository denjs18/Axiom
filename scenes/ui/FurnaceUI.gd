## FurnaceUI.gd — Furnace interface (input / fuel / output + inventory).
## Opens on right-click of any furnace, blast_furnace or smoker block.
extends CanvasLayer

const ItemIconScript = preload("res://scenes/ui/ItemIcon.gd")

const SLOT_SIZE   := 44
const SLOT_GAP    := 3
const HOTBAR_SIZE := 9
const MAIN_SIZE   := 27

const FURNACE_BLOCK_NAMES := ["furnace", "blast_furnace", "smoker"]

var _player:    Player       = null
var _inventory: Inventory    = null
var _entity:    FurnaceEntity = null
var _bpos:      Vector3i

# UI nodes
var _slot_panels:    Array = []  # 36 inv slots
var _input_panel:    Panel = null
var _fuel_panel:     Panel = null
var _output_panel:   Panel = null
var _flame_fill:     ColorRect = null
var _arrow_fill:     ColorRect = null
var _flame_max_h:    float = 0.0
var _arrow_max_w:    float = 0.0

var _held_stack:  Dictionary = {}
var _cursor_icon              = null
var _cursor_label: Label      = null


func _ready() -> void:
	visible = false
	layer   = 6
	_slot_panels.resize(36)
	_slot_panels.fill(null)
	_build_ui()
	EventBus.block_interacted.connect(_on_block_interacted)


# ── Open / Close ───────────────────────────────────────────────────────────────

func _on_block_interacted(bpos: Vector3i, block_id: int, player: Node) -> void:
	var block := BlockRegistry.get_block(block_id)
	if block == null or not block.name in FURNACE_BLOCK_NAMES:
		return
	if visible:
		_close()
		return
	_player    = player as Player
	_inventory = _player.inventory if _player else null
	_bpos      = bpos
	# Get or create entity
	var bem = _player._block_entity_manager if _player else null
	if bem != null:
		_entity = bem.get_entity(bpos) as FurnaceEntity
		if _entity == null:
			_entity = bem.create_entity(bpos, block_id) as FurnaceEntity
	if _inventory != null and not _inventory.slot_changed.is_connected(_on_inv_slot_changed):
		_inventory.slot_changed.connect(_on_inv_slot_changed)
	_refresh_all()
	visible = true
	GameManager.ui_open()


func _close() -> void:
	# Return held stack to inventory
	if not ItemRegistry.is_empty_stack(_held_stack) and _inventory != null:
		_inventory.add_items(_held_stack.get("id",""), _held_stack.get("count",0), _held_stack.get("meta",{}))
		_held_stack = {}
		_update_cursor()
	visible = false
	GameManager.ui_close()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("open_inventory") or event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


# ── Per-frame: update flame / arrow ───────────────────────────────────────────

func _process(_delta: float) -> void:
	if not visible:
		return
	# Cursor follow
	var mp := get_viewport().get_mouse_position()
	if _cursor_icon:  _cursor_icon.position  = mp - Vector2(16, 16)
	if _cursor_label: _cursor_label.position = mp - Vector2(16, 16)

	if _entity == null:
		return
	# Flame (fuel progress) — grows upward
	if _flame_fill != null and _flame_max_h > 0.0:
		var fp: float = _entity.get_fuel_progress()
		_flame_fill.size.y  = _flame_max_h * fp
		_flame_fill.position.y = _flame_max_h * (1.0 - fp)
	# Arrow (cook progress) — grows rightward
	if _arrow_fill != null and _arrow_max_w > 0.0:
		_arrow_fill.size.x = _arrow_max_w * _entity.get_cook_progress()
	# Refresh furnace slot icons each frame (entity changes them)
	_update_furnace_slots()


# ── UI construction ────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.50)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	var panel_w := 9 * (SLOT_SIZE + SLOT_GAP) - SLOT_GAP + 24
	var panel_h := 460
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -panel_w / 2
	panel.offset_right  =  panel_w / 2
	panel.offset_top    = -panel_h / 2
	panel.offset_bottom =  panel_h / 2
	var ps := StyleBoxFlat.new()
	ps.bg_color       = Color(0.14, 0.14, 0.17, 0.97)
	ps.border_width_left = 1; ps.border_width_right  = 1
	ps.border_width_top  = 1; ps.border_width_bottom = 1
	ps.border_color   = Color(0.40, 0.40, 0.42)
	ps.corner_radius_top_left    = 4; ps.corner_radius_top_right    = 4
	ps.corner_radius_bottom_left = 4; ps.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 12; vbox.offset_right  = -12
	vbox.offset_top  = 10; vbox.offset_bottom = -10
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Four"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(title)

	_build_furnace_section(vbox)

	var sep1 := HSeparator.new(); vbox.add_child(sep1)

	var inv_lbl := Label.new()
	inv_lbl.text = "Objets"
	inv_lbl.add_theme_font_size_override("font_size", 11)
	inv_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	vbox.add_child(inv_lbl)

	var main_grid := GridContainer.new()
	main_grid.columns = 9
	main_grid.add_theme_constant_override("h_separation", SLOT_GAP)
	main_grid.add_theme_constant_override("v_separation", SLOT_GAP)
	vbox.add_child(main_grid)
	for i in range(HOTBAR_SIZE, HOTBAR_SIZE + MAIN_SIZE):
		var s := _make_inv_slot(i)
		main_grid.add_child(s)
		_slot_panels[i] = s

	var sep2 := HSeparator.new(); vbox.add_child(sep2)

	var hotbar_row := HBoxContainer.new()
	hotbar_row.add_theme_constant_override("separation", SLOT_GAP)
	vbox.add_child(hotbar_row)
	for i in range(0, HOTBAR_SIZE):
		var s := _make_inv_slot(i)
		hotbar_row.add_child(s)
		_slot_panels[i] = s

	var hint := Label.new()
	hint.text = "E / Échap = fermer   •   Maj+Clic = déplacer tout"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.50, 0.50, 0.50))
	vbox.add_child(hint)

	# Cursor icon
	_cursor_icon = ItemIconScript.new()
	_cursor_icon.size = Vector2(32, 32)
	_cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_icon.z_index = 100
	add_child(_cursor_icon)
	_cursor_label = Label.new()
	_cursor_label.size = Vector2(32, 16)
	_cursor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cursor_label.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	_cursor_label.add_theme_font_size_override("font_size", 10)
	_cursor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_label.z_index = 101
	add_child(_cursor_label)


func _build_furnace_section(parent: VBoxContainer) -> void:
	# Centered HBox: [input+fuel column] [flame+arrow] [output]
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)
	parent.add_child(hbox)

	# Left column: input slot (top) + fuel slot (bottom)
	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 4)
	hbox.add_child(left_col)

	var in_lbl := Label.new()
	in_lbl.text = "Entrée"
	in_lbl.add_theme_font_size_override("font_size", 10)
	in_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	in_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_col.add_child(in_lbl)

	_input_panel = _make_furnace_slot(Color(0.10, 0.12, 0.10, 0.90), Color(0.30, 0.50, 0.30))
	_input_panel.gui_input.connect(_on_furnace_input_clicked)
	left_col.add_child(_input_panel)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	left_col.add_child(spacer)

	var fuel_lbl := Label.new()
	fuel_lbl.text = "Combustible"
	fuel_lbl.add_theme_font_size_override("font_size", 10)
	fuel_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	fuel_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_col.add_child(fuel_lbl)

	_fuel_panel = _make_furnace_slot(Color(0.18, 0.10, 0.05, 0.90), Color(0.70, 0.35, 0.10))
	_fuel_panel.gui_input.connect(_on_furnace_fuel_clicked)
	left_col.add_child(_fuel_panel)

	# Center: flame + arrow stacked
	var center_col := VBoxContainer.new()
	center_col.alignment = BoxContainer.ALIGNMENT_CENTER
	center_col.custom_minimum_size = Vector2(60, SLOT_SIZE * 2 + 4 + 30)
	center_col.add_theme_constant_override("separation", 4)
	hbox.add_child(center_col)

	var flame_bg := Panel.new()
	flame_bg.custom_minimum_size = Vector2(20, 24)
	_style_slot(flame_bg, Color(0.08, 0.08, 0.08, 0.80), Color(0.40, 0.25, 0.10))
	flame_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_col.add_child(flame_bg)
	_flame_max_h = 22.0
	_flame_fill = ColorRect.new()
	_flame_fill.color = Color(1.0, 0.55, 0.10, 0.90)
	_flame_fill.size = Vector2(16, _flame_max_h)
	_flame_fill.position = Vector2(2, 1)
	_flame_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flame_bg.add_child(_flame_fill)

	var arrow_bg := Panel.new()
	arrow_bg.custom_minimum_size = Vector2(56, 20)
	_style_slot(arrow_bg, Color(0.08, 0.08, 0.08, 0.80), Color(0.25, 0.40, 0.25))
	arrow_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_col.add_child(arrow_bg)
	_arrow_max_w = 52.0
	_arrow_fill = ColorRect.new()
	_arrow_fill.color = Color(0.40, 0.80, 0.40, 0.85)
	_arrow_fill.size = Vector2(0, 16)
	_arrow_fill.position = Vector2(2, 2)
	_arrow_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow_bg.add_child(_arrow_fill)

	# Right: output slot
	var out_col := VBoxContainer.new()
	out_col.alignment = BoxContainer.ALIGNMENT_CENTER
	out_col.add_theme_constant_override("separation", 4)
	hbox.add_child(out_col)

	var out_lbl := Label.new()
	out_lbl.text = "Résultat"
	out_lbl.add_theme_font_size_override("font_size", 10)
	out_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	out_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	out_col.add_child(out_lbl)

	_output_panel = _make_furnace_slot(Color(0.18, 0.16, 0.05, 0.95), Color(0.60, 0.55, 0.15))
	_output_panel.gui_input.connect(_on_furnace_output_clicked)
	out_col.add_child(_output_panel)


# ── Slot factories ─────────────────────────────────────────────────────────────

func _make_furnace_slot(bg: Color, border: Color) -> Panel:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	_style_slot(slot, bg, border)
	var ir := ItemIconScript.new(); ir.name = "ItemColor"
	ir.size = Vector2(32, 32); ir.position = Vector2(6, 6)
	ir.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(ir)
	var lbl := Label.new(); lbl.name = "Count"
	lbl.anchor_right = 1.0; lbl.anchor_bottom = 1.0
	lbl.offset_top = SLOT_SIZE - 16; lbl.offset_right = -2
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_shadow_color", Color(0,0,0,0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(lbl)
	return slot


func _make_inv_slot(index: int) -> Panel:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.set_meta("slot_index", index)
	_style_slot(slot, Color(0.10, 0.10, 0.10, 0.90), Color(0.35, 0.35, 0.35))
	var ir := ItemIconScript.new(); ir.name = "ItemColor"
	ir.size = Vector2(32, 32); ir.position = Vector2(6, 6)
	ir.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(ir)
	var lbl := Label.new(); lbl.name = "Count"
	lbl.anchor_right = 1.0; lbl.anchor_bottom = 1.0
	lbl.offset_top = SLOT_SIZE - 16; lbl.offset_right = -2
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_shadow_color", Color(0,0,0,0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(lbl)
	slot.gui_input.connect(_on_inv_slot_input.bind(index))
	return slot


func _style_slot(slot: Panel, bg: Color, border: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_left = 1; s.border_width_right  = 1
	s.border_width_top  = 1; s.border_width_bottom = 1
	s.border_color = border
	slot.add_theme_stylebox_override("panel", s)


# ── Furnace slot interactions ──────────────────────────────────────────────────

func _on_furnace_input_clicked(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed) or _entity == null:
		return
	var mb := event as InputEventMouseButton
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			if mb.shift_pressed:
				_move_furnace_to_inv(_entity.input_slot)
				_entity.input_slot = {}
			else:
				_swap_with_furnace_slot(_entity.input_slot)
	_update_furnace_slots(); _update_cursor()


func _on_furnace_fuel_clicked(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed) or _entity == null:
		return
	var mb := event as InputEventMouseButton
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			if mb.shift_pressed:
				_move_furnace_to_inv(_entity.fuel_slot)
				_entity.fuel_slot = {}
			else:
				_swap_with_furnace_slot(_entity.fuel_slot)
	_update_furnace_slots(); _update_cursor()


func _on_furnace_output_clicked(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed) or _entity == null:
		return
	var mb := event as InputEventMouseButton
	if not ItemRegistry.is_empty_stack(_entity.output_slot):
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.shift_pressed:
					_move_furnace_to_inv(_entity.output_slot)
					_entity.output_slot = {}
				else:
					_take_from_output()
	_update_furnace_slots(); _update_cursor()


func _swap_with_furnace_slot(slot: Dictionary) -> void:
	if ItemRegistry.is_empty_stack(_held_stack):
		if not ItemRegistry.is_empty_stack(slot):
			_held_stack = slot.duplicate()
			slot.clear()
	else:
		if ItemRegistry.is_empty_stack(slot):
			slot.merge(_held_stack.duplicate(), true)
			_held_stack = {}
		elif ItemRegistry.stacks_can_merge(_held_stack, slot):
			var item := ItemRegistry.get_item(_held_stack.get("id",""))
			var max_s := item.max_stack if item else 64
			var total: int = _held_stack.get("count",0) + slot.get("count",0)
			if total <= max_s:
				slot["count"] = total; _held_stack = {}
			else:
				slot["count"] = max_s; _held_stack["count"] = total - max_s
		else:
			var old := slot.duplicate(); slot.clear(); slot.merge(_held_stack.duplicate(), true)
			_held_stack = old


func _take_from_output() -> void:
	var out := _entity.output_slot
	if ItemRegistry.is_empty_stack(out):
		return
	if ItemRegistry.is_empty_stack(_held_stack):
		_held_stack = out.duplicate()
		_entity.output_slot = {}
	elif ItemRegistry.stacks_can_merge(_held_stack, out):
		var item := ItemRegistry.get_item(_held_stack.get("id",""))
		var max_s := item.max_stack if item else 64
		var total: int = _held_stack.get("count",0) + out.get("count",0)
		if total <= max_s:
			_held_stack["count"] = total; _entity.output_slot = {}
		else:
			_held_stack["count"] = max_s; out["count"] = total - max_s


func _move_furnace_to_inv(slot: Dictionary) -> void:
	if ItemRegistry.is_empty_stack(slot) or _inventory == null:
		return
	_inventory.add_items(slot.get("id",""), slot.get("count",0), slot.get("meta",{}))


# ── Inventory slot interactions ────────────────────────────────────────────────

func _on_inv_slot_input(event: InputEvent, slot_index: int) -> void:
	if not (event is InputEventMouseButton and event.pressed) or _inventory == null:
		return
	var mb := event as InputEventMouseButton
	if mb.shift_pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_shift_inv_to_furnace(slot_index); return
	match mb.button_index:
		MOUSE_BUTTON_LEFT:  _left_click_inv(slot_index)
		MOUSE_BUTTON_RIGHT: _right_click_inv(slot_index)


func _left_click_inv(slot_index: int) -> void:
	var current := _inventory.get_slot(slot_index)
	if ItemRegistry.is_empty_stack(_held_stack):
		if not ItemRegistry.is_empty_stack(current):
			_held_stack = current.duplicate()
			_inventory.set_slot(slot_index, {})
	else:
		if ItemRegistry.is_empty_stack(current):
			_inventory.set_slot(slot_index, _held_stack.duplicate()); _held_stack = {}
		elif ItemRegistry.stacks_can_merge(_held_stack, current):
			var item := ItemRegistry.get_item(_held_stack.get("id",""))
			var max_s := item.max_stack if item else 64
			var total: int = _held_stack.get("count",0) + current.get("count",0)
			if total <= max_s:
				current["count"] = total; _inventory.set_slot(slot_index, current); _held_stack = {}
			else:
				current["count"] = max_s; _held_stack["count"] = total - max_s
				_inventory.set_slot(slot_index, current)
		else:
			var old := current.duplicate()
			_inventory.set_slot(slot_index, _held_stack.duplicate()); _held_stack = old
	_update_inv_slot(slot_index); _update_cursor()


func _right_click_inv(slot_index: int) -> void:
	var current := _inventory.get_slot(slot_index)
	if ItemRegistry.is_empty_stack(_held_stack):
		if not ItemRegistry.is_empty_stack(current):
			_held_stack = _inventory.split_stack(slot_index)
	else:
		var item := ItemRegistry.get_item(_held_stack.get("id",""))
		var max_s := item.max_stack if item else 64
		if ItemRegistry.is_empty_stack(current):
			var one := _held_stack.duplicate(); one["count"] = 1
			_inventory.set_slot(slot_index, one)
			_held_stack["count"] -= 1
			if _held_stack.get("count",0) <= 0: _held_stack = {}
		elif ItemRegistry.stacks_can_merge(_held_stack, current) and current.get("count",0) < max_s:
			current["count"] += 1; _inventory.set_slot(slot_index, current)
			_held_stack["count"] -= 1
			if _held_stack.get("count",0) <= 0: _held_stack = {}
	_update_inv_slot(slot_index); _update_cursor()


func _shift_inv_to_furnace(slot_index: int) -> void:
	if _entity == null or _inventory == null: return
	var stack := _inventory.get_slot(slot_index)
	if ItemRegistry.is_empty_stack(stack): return
	var iid: String = stack.get("id","")
	# Fuel if it has fuel_time, otherwise input
	if _entity.is_fuel(iid) and ItemRegistry.is_empty_stack(_entity.fuel_slot):
		_entity.fuel_slot = stack.duplicate()
		_inventory.set_slot(slot_index, {})
	elif ItemRegistry.is_empty_stack(_entity.input_slot):
		_entity.input_slot = stack.duplicate()
		_inventory.set_slot(slot_index, {})
	elif _entity.is_fuel(iid) and ItemRegistry.stacks_can_merge(stack, _entity.fuel_slot):
		var item := ItemRegistry.get_item(iid)
		var max_s := item.max_stack if item else 64
		var total: int = stack.get("count",0) + _entity.fuel_slot.get("count",0)
		_entity.fuel_slot["count"] = mini(total, max_s)
		var leftover: int = total - _entity.fuel_slot.get("count",0)
		if leftover <= 0: _inventory.set_slot(slot_index, {})
		else: stack["count"] = leftover; _inventory.set_slot(slot_index, stack)
	elif ItemRegistry.stacks_can_merge(stack, _entity.input_slot):
		var item := ItemRegistry.get_item(iid)
		var max_s := item.max_stack if item else 64
		var total: int = stack.get("count",0) + _entity.input_slot.get("count",0)
		_entity.input_slot["count"] = mini(total, max_s)
		var leftover: int = total - _entity.input_slot.get("count",0)
		if leftover <= 0: _inventory.set_slot(slot_index, {})
		else: stack["count"] = leftover; _inventory.set_slot(slot_index, stack)
	_update_inv_slot(slot_index)
	_update_furnace_slots()
	_update_cursor()


# ── Display helpers ────────────────────────────────────────────────────────────

func _on_inv_slot_changed(slot_index: int, _stack: Dictionary) -> void:
	_update_inv_slot(slot_index)


func _refresh_all() -> void:
	for i in 36: _update_inv_slot(i)
	_update_furnace_slots()
	_update_cursor()


func _update_inv_slot(index: int) -> void:
	if index < 0 or index >= _slot_panels.size() or _slot_panels[index] == null:
		return
	var stack := _inventory.get_slot(index) if _inventory else {}
	_apply_stack(_slot_panels[index] as Panel, stack)


func _update_furnace_slots() -> void:
	if _entity == null: return
	_apply_stack(_input_panel,  _entity.input_slot)
	_apply_stack(_fuel_panel,   _entity.fuel_slot)
	_apply_stack(_output_panel, _entity.output_slot)


func _apply_stack(panel: Panel, stack: Dictionary) -> void:
	if panel == null: return
	var ir  = panel.get_node_or_null("ItemColor")
	var lbl := panel.get_node_or_null("Count") as Label
	if ItemRegistry.is_empty_stack(stack):
		if ir:  ir.item_id = ""
		if lbl: lbl.text   = ""
	else:
		if ir:  ir.item_id = stack.get("id", "")
		if lbl:
			var cnt: int = stack.get("count", 0)
			lbl.text = str(cnt) if cnt > 1 else ""


func _update_cursor() -> void:
	if _cursor_icon == null: return
	if ItemRegistry.is_empty_stack(_held_stack):
		_cursor_icon.item_id = ""
		if _cursor_label: _cursor_label.text = ""
	else:
		_cursor_icon.item_id = _held_stack.get("id", "")
		if _cursor_label:
			var cnt: int = _held_stack.get("count", 0)
			_cursor_label.text = str(cnt) if cnt > 1 else ""
