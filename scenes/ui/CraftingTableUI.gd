## CraftingTableUI.gd — 3×3 crafting table interface.
## Opened when the player right-clicks a crafting table block.
extends CanvasLayer

const ItemIconScript = preload("res://scenes/ui/ItemIcon.gd")

const SLOT_SIZE   := 44
const SLOT_GAP    := 3
const COLS        := 9
const MAIN_ROWS   := 3
const HOTBAR_SIZE := 9
const MAIN_SIZE   := 27

var _inventory: Inventory = null
var _player: Player = null

var _slot_panels:  Array = []
var _craft_panels: Array = []
var _result_panel: Panel = null
var _crafting_engine: CraftingEngine = null

var _held_stack:   Dictionary = {}
var _cursor_icon               = null
var _cursor_label: Label       = null


func _ready() -> void:
	visible = false
	layer = 5
	_slot_panels.resize(36)
	_slot_panels.fill(null)

	_crafting_engine = CraftingEngine.new()
	add_child(_crafting_engine)
	_crafting_engine.recipe_found.connect(_on_recipe_found)
	_crafting_engine.recipe_cleared.connect(_on_recipe_cleared)

	_build_ui()
	EventBus.open_crafting_table_with_recipe.connect(_on_open_with_recipe)


# ── Open / Close ───────────────────────────────────────────────────────────────

func _on_open_with_recipe(recipe, player: Player) -> void:
	if visible: _close()
	_player    = player
	_inventory = player.inventory if player else null
	_crafting_engine.setup(_inventory, 3)
	_connect_inventory()
	_clear_grid()
	if recipe != null:
		_prefill_recipe(recipe)
	_update_craft_ui()
	_refresh_all()
	visible = true
	GameManager.ui_open()
	EventBus.crafting_context_opened.emit(_crafting_engine, _inventory)


func _close() -> void:
	if _inventory != null:
		for row in 3:
			for col in 3:
				var stack: Dictionary = _crafting_engine.get_grid_slot(row, col)
				if not ItemRegistry.is_empty_stack(stack):
					_inventory.add_items(stack.get("id",""), stack.get("count",1), stack.get("meta",{}))
					_crafting_engine.set_grid_slot(row, col, {})
	_update_craft_ui()

	if not ItemRegistry.is_empty_stack(_held_stack) and _inventory != null:
		_inventory.add_items(_held_stack.get("id",""), _held_stack.get("count",0), _held_stack.get("meta",{}))
		_held_stack = {}
		_update_cursor()
	visible = false
	GameManager.ui_close()
	EventBus.crafting_context_closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("open_inventory") or event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


# ── UI construction ────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.50)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	var panel_w := COLS * (SLOT_SIZE + SLOT_GAP) - SLOT_GAP + 24
	var panel_h := 490
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -panel_w / 2
	panel.offset_right  =  panel_w / 2
	panel.offset_top    = -panel_h / 2
	panel.offset_bottom =  panel_h / 2

	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.14, 0.14, 0.17, 0.97)
	ps.border_width_left = 1; ps.border_width_right  = 1
	ps.border_width_top  = 1; ps.border_width_bottom = 1
	ps.border_color = Color(0.40, 0.40, 0.42)
	ps.corner_radius_top_left     = 4; ps.corner_radius_top_right    = 4
	ps.corner_radius_bottom_left  = 4; ps.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 12; vbox.offset_right  = -12
	vbox.offset_top  = 10; vbox.offset_bottom = -10
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	vbox.add_child(title_row)
	var title := Label.new()
	title.text = "Table de craft"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var book_btn := Button.new()
	book_btn.text = "Recettes"
	book_btn.add_theme_font_size_override("font_size", 11)
	book_btn.pressed.connect(func(): EventBus.recipe_book_requested.emit())
	title_row.add_child(book_btn)

	_build_craft_section(vbox)

	var sep1 := HSeparator.new()
	vbox.add_child(sep1)

	var inv_lbl := Label.new()
	inv_lbl.text = "Objets"
	inv_lbl.add_theme_font_size_override("font_size", 11)
	inv_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	vbox.add_child(inv_lbl)

	var main_grid := GridContainer.new()
	main_grid.columns = COLS
	main_grid.add_theme_constant_override("h_separation", SLOT_GAP)
	main_grid.add_theme_constant_override("v_separation", SLOT_GAP)
	vbox.add_child(main_grid)
	for i in range(HOTBAR_SIZE, HOTBAR_SIZE + MAIN_SIZE):
		var s := _make_inv_slot(i)
		main_grid.add_child(s)
		_slot_panels[i] = s

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

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


func _build_craft_section(parent: VBoxContainer) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	parent.add_child(hbox)

	var lbl := Label.new()
	lbl.text = "Fabrication (3×3)"
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(lbl)

	var craft_grid := GridContainer.new()
	craft_grid.columns = 3
	craft_grid.add_theme_constant_override("h_separation", SLOT_GAP)
	craft_grid.add_theme_constant_override("v_separation", SLOT_GAP)
	hbox.add_child(craft_grid)
	_craft_panels.clear()
	for i in 9:
		var s := _make_craft_slot(i)
		craft_grid.add_child(s)
		_craft_panels.append(s)

	var arrow := Label.new()
	arrow.text = "➜"
	arrow.add_theme_font_size_override("font_size", 22)
	arrow.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	arrow.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.custom_minimum_size  = Vector2(32, SLOT_SIZE * 3 + SLOT_GAP * 2)
	hbox.add_child(arrow)

	_result_panel = _make_result_slot()
	hbox.add_child(_result_panel)


# ── Slot factories ─────────────────────────────────────────────────────────────

func _make_inv_slot(index: int) -> Panel:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.set_meta("slot_index", index)
	_style_slot(slot, Color(0.10, 0.10, 0.10, 0.90), Color(0.35, 0.35, 0.35))

	var ir := ItemIconScript.new(); ir.name = "ItemColor"
	ir.size = Vector2(32, 32)
	ir.position = Vector2(6, 6); ir.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

	slot.gui_input.connect(_on_slot_input.bind(index))
	return slot


func _make_craft_slot(craft_idx: int) -> Panel:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	_style_slot(slot, Color(0.10, 0.12, 0.10, 0.90), Color(0.32, 0.38, 0.32))

	var ir := ItemIconScript.new(); ir.name = "ItemColor"
	ir.size = Vector2(32, 32)
	ir.position = Vector2(6, 6); ir.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(ir)

	var lbl := Label.new(); lbl.name = "Count"
	lbl.anchor_right = 1.0; lbl.anchor_bottom = 1.0
	lbl.offset_top = SLOT_SIZE - 16; lbl.offset_right = -2
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(lbl)

	slot.gui_input.connect(_on_craft_slot_input.bind(craft_idx))
	return slot


func _make_result_slot() -> Panel:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE * 3 + SLOT_GAP * 2)
	_style_slot(slot, Color(0.18, 0.16, 0.05, 0.95), Color(0.60, 0.55, 0.15))

	var ir := ItemIconScript.new(); ir.name = "ItemColor"
	ir.size = Vector2(32, 32)
	ir.position = Vector2(6, (SLOT_SIZE * 3 + SLOT_GAP * 2) / 2 - 16)
	ir.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(ir)

	var lbl := Label.new(); lbl.name = "Count"
	lbl.anchor_right = 1.0; lbl.anchor_bottom = 1.0
	lbl.offset_bottom = -4; lbl.offset_right = -4
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(lbl)

	slot.gui_input.connect(_on_result_slot_input)
	return slot


func _style_slot(slot: Panel, bg: Color, border: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color          = bg
	s.border_width_left = 1; s.border_width_right  = 1
	s.border_width_top  = 1; s.border_width_bottom = 1
	s.border_color      = border
	slot.add_theme_stylebox_override("panel", s)


# ── Inventory slot input ───────────────────────────────────────────────────────

func _on_slot_input(event: InputEvent, slot_index: int) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if _inventory == null:
		return
	var mb := event as InputEventMouseButton
	if mb.shift_pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_shift_click(slot_index); return
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
	_update_slot_ui(slot_index); _update_cursor()


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
	_update_slot_ui(slot_index); _update_cursor()


func _shift_click(slot_index: int) -> void:
	var stack := _inventory.get_slot(slot_index)
	if ItemRegistry.is_empty_stack(stack): return
	var item := ItemRegistry.get_item(stack.get("id",""))
	var max_s := item.max_stack if item else 64
	var target_start := HOTBAR_SIZE if slot_index < HOTBAR_SIZE else 0
	var target_end   := HOTBAR_SIZE + MAIN_SIZE if slot_index < HOTBAR_SIZE else HOTBAR_SIZE
	var remaining: int = stack.get("count",0)
	for i in range(target_start, target_end):
		if remaining <= 0: break
		var s := _inventory.get_slot(i)
		if not ItemRegistry.stacks_can_merge(stack, s): continue
		var can_add: int = max_s - int(s.get("count",0))
		if can_add <= 0: continue
		var add := mini(can_add, remaining)
		s["count"] += add; remaining -= add; _inventory.set_slot(i, s)
	for i in range(target_start, target_end):
		if remaining <= 0: break
		if not ItemRegistry.is_empty_stack(_inventory.get_slot(i)): continue
		var put := mini(max_s, remaining)
		_inventory.set_slot(i, {"id": stack["id"], "count": put, "meta": stack.get("meta",{}).duplicate()})
		remaining -= put
	if remaining <= 0: _inventory.set_slot(slot_index, {})
	else: stack["count"] = remaining; _inventory.set_slot(slot_index, stack)
	_update_slot_ui(slot_index)


# ── Craft slot input ───────────────────────────────────────────────────────────

func _on_craft_slot_input(event: InputEvent, craft_idx: int) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var mb  := event as InputEventMouseButton
	var row := craft_idx / 3
	var col := craft_idx % 3
	var current: Dictionary = _crafting_engine.get_grid_slot(row, col)

	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			if ItemRegistry.is_empty_stack(_held_stack):
				if not ItemRegistry.is_empty_stack(current):
					_held_stack = current.duplicate()
					_crafting_engine.set_grid_slot(row, col, {})
			else:
				if ItemRegistry.is_empty_stack(current):
					_crafting_engine.set_grid_slot(row, col, _held_stack.duplicate())
					_held_stack = {}
				elif ItemRegistry.stacks_can_merge(_held_stack, current):
					var item := ItemRegistry.get_item(_held_stack.get("id",""))
					var max_s := item.max_stack if item else 64
					var total: int = _held_stack.get("count",0) + current.get("count",0)
					if total <= max_s:
						current["count"] = total
						_crafting_engine.set_grid_slot(row, col, current)
						_held_stack = {}
					else:
						current["count"] = max_s
						_held_stack["count"] = total - max_s
						_crafting_engine.set_grid_slot(row, col, current)
				else:
					var old := current.duplicate()
					_crafting_engine.set_grid_slot(row, col, _held_stack.duplicate())
					_held_stack = old

		MOUSE_BUTTON_RIGHT:
			if ItemRegistry.is_empty_stack(_held_stack):
				if not ItemRegistry.is_empty_stack(current):
					var half_count := ceili(current.get("count",1) / 2.0)
					_held_stack = current.duplicate()
					_held_stack["count"] = current.get("count",1) - half_count
					current["count"] = half_count
					if _held_stack.get("count",0) <= 0: _held_stack = {}
					_crafting_engine.set_grid_slot(row, col, current)
			else:
				if ItemRegistry.is_empty_stack(current):
					var one := _held_stack.duplicate(); one["count"] = 1
					_crafting_engine.set_grid_slot(row, col, one)
					_held_stack["count"] -= 1
					if _held_stack.get("count",0) <= 0: _held_stack = {}
				elif ItemRegistry.stacks_can_merge(_held_stack, current):
					var item := ItemRegistry.get_item(_held_stack.get("id",""))
					var max_s := item.max_stack if item else 64
					if current.get("count",0) < max_s:
						current["count"] += 1
						_crafting_engine.set_grid_slot(row, col, current)
						_held_stack["count"] -= 1
						if _held_stack.get("count",0) <= 0: _held_stack = {}

	_update_craft_slot_ui(craft_idx)
	_update_cursor()


func _on_result_slot_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _crafting_engine == null or _inventory == null:
		return

	var result := _crafting_engine.get_result()
	if ItemRegistry.is_empty_stack(result):
		return

	if mb.shift_pressed:
		_crafting_engine.craft_all()
	else:
		if ItemRegistry.is_empty_stack(_held_stack):
			var crafted := _crafting_engine.craft_one()
			if not ItemRegistry.is_empty_stack(crafted):
				_held_stack = crafted
		elif ItemRegistry.stacks_can_merge(_held_stack, result):
			var item := ItemRegistry.get_item(result.get("id",""))
			var max_s := item.max_stack if item else 64
			var total: int = _held_stack.get("count",0) + result.get("count",1)
			if total <= max_s:
				_crafting_engine.craft_one()
				_held_stack["count"] = total

	_update_craft_ui()
	_update_cursor()


# ── Recipe signals ─────────────────────────────────────────────────────────────

func _on_recipe_found(_recipe) -> void:
	_update_result_ui()


func _on_recipe_cleared() -> void:
	_update_result_ui()


# ── Per-frame ──────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not visible: return
	var mp := get_viewport().get_mouse_position()
	if _cursor_icon:  _cursor_icon.position  = mp - Vector2(16, 16)
	if _cursor_label: _cursor_label.position = mp - Vector2(16, 16)


# ── Display helpers ────────────────────────────────────────────────────────────

func _connect_inventory() -> void:
	if _inventory == null: return
	if not _inventory.slot_changed.is_connected(_on_slot_changed):
		_inventory.slot_changed.connect(_on_slot_changed)


func _on_slot_changed(slot_index: int, _new_stack: Dictionary) -> void:
	_update_slot_ui(slot_index)


func _refresh_all() -> void:
	for i in 36: _update_slot_ui(i)
	_update_craft_ui()
	_update_cursor()


func _update_slot_ui(index: int) -> void:
	if index < 0 or index >= _slot_panels.size() or _slot_panels[index] == null:
		return
	var panel := _slot_panels[index] as Panel
	var stack := _inventory.get_slot(index) if _inventory else {}
	_apply_stack_to_panel(panel, stack)


func _update_craft_slot_ui(craft_idx: int) -> void:
	if craft_idx < 0 or craft_idx >= _craft_panels.size():
		return
	var row := craft_idx / 3; var col := craft_idx % 3
	var stack: Dictionary = _crafting_engine.get_grid_slot(row, col)
	_apply_stack_to_panel(_craft_panels[craft_idx] as Panel, stack)


func _update_craft_ui() -> void:
	for i in 9: _update_craft_slot_ui(i)
	_update_result_ui()


func _update_result_ui() -> void:
	if _result_panel == null: return
	var result := _crafting_engine.get_result() if _crafting_engine else {}
	_apply_stack_to_panel(_result_panel, result)


func _apply_stack_to_panel(panel: Panel, stack: Dictionary) -> void:
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


# ── Recipe prefill (called from RecipeCatalogUI via EventBus) ──────────────────

func _clear_grid() -> void:
	for row in 3:
		for col in 3:
			var stack: Dictionary = _crafting_engine.get_grid_slot(row, col)
			if not ItemRegistry.is_empty_stack(stack):
				if _inventory:
					_inventory.add_items(stack.get("id",""), stack.get("count",1), {})
				_crafting_engine.set_grid_slot(row, col, {})
			var idx := row * 3 + col
			if idx < _craft_panels.size() and _craft_panels[idx] != null:
				_style_slot(_craft_panels[idx] as Panel,
					Color(0.10, 0.12, 0.10, 0.90), Color(0.32, 0.38, 0.32))
				var ir = (_craft_panels[idx] as Panel).get_node_or_null("ItemColor")
				if ir: ir.modulate = Color.WHITE


func _prefill_recipe(recipe) -> void:
	if recipe.raw.get("type", "shaped") != "shaped" or not "grid" in recipe:
		return
	for row in 3:
		for col in 3:
			var ing = recipe.grid[row][col]
			if ing == null: continue
			var item_id := ""
			if ing is String:
				item_id = ing
			elif ing is Dictionary and ing.has("tag"):
				item_id = _find_item_with_tag(ing["tag"])
			if item_id != "" and _take_one_item(item_id):
				_crafting_engine.set_grid_slot(row, col, {"id": item_id, "count": 1})
			else:
				_mark_slot_missing(row * 3 + col, ing)


func _mark_slot_missing(craft_idx: int, ing) -> void:
	if craft_idx < 0 or craft_idx >= _craft_panels.size(): return
	var slot := _craft_panels[craft_idx] as Panel
	var sbf := StyleBoxFlat.new()
	sbf.bg_color     = Color(0.20, 0.05, 0.05, 0.90)
	sbf.border_color = Color(0.80, 0.20, 0.20)
	sbf.border_width_left = 1; sbf.border_width_right  = 1
	sbf.border_width_top  = 1; sbf.border_width_bottom = 1
	slot.add_theme_stylebox_override("panel", sbf)
	var ir = slot.get_node_or_null("ItemColor")
	if ir:
		var display_id: String = ing if ing is String else _find_item_with_tag(ing.get("tag",""))
		ir.item_id  = display_id
		ir.modulate = Color(0.7, 0.4, 0.4, 0.6)


func _take_one_item(item_id: String) -> bool:
	if _inventory == null or item_id == "": return false
	for i in 36:
		var stack := _inventory.get_slot(i)
		if stack.get("id", "") != item_id: continue
		stack["count"] -= 1
		if stack["count"] <= 0: _inventory.set_slot(i, {})
		else:                   _inventory.set_slot(i, stack)
		return true
	return false


func _find_item_with_tag(tag: String) -> String:
	if _inventory == null: return ""
	for i in 36:
		var stack := _inventory.get_slot(i)
		if ItemRegistry.is_empty_stack(stack): continue
		var item := ItemRegistry.get_item(stack.get("id", ""))
		if item != null and tag in item.tags:
			return stack.get("id", "")
	return ""
