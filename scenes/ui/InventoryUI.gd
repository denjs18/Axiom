## InventoryUI.gd — Player inventory with 2×2 crafting grid.
## Recipes are defined in data/recipes/recipes_crafting.json and matched by CraftingEngine.
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

var _slot_panels:  Array = []   # 36 inventory slots
var _craft_panels: Array = []   # 4 craft slots (2×2)
var _armor_panels: Array = []   # 4 armor slots (head/chest/legs/feet)
var _result_panel: Panel = null
var _crafting_engine: CraftingEngine = null

const _ARMOR_ICONS  := ["🪖", "🥋", "👖", "👢"]
const _ARMOR_LABELS := ["Casque", "Plastron", "Jambières", "Bottes"]

var _held_stack:   Dictionary = {}
var _cursor_icon               = null
var _cursor_label: Label       = null


func _ready() -> void:
	visible = false
	_slot_panels.resize(36)
	_slot_panels.fill(null)

	_crafting_engine = CraftingEngine.new()
	add_child(_crafting_engine)
	_crafting_engine.recipe_found.connect(_on_recipe_found)
	_crafting_engine.recipe_cleared.connect(_on_recipe_cleared)

	_build_ui()
	EventBus.inventory_opened.connect(_on_inventory_opened)
	EventBus.inventory_closed.connect(func(_p): EventBus.crafting_context_closed.emit())


# ── Open / Close ───────────────────────────────────────────────────────────────

func _on_inventory_opened(player: Player) -> void:
	if visible:
		_close()
		return
	_player    = player
	_inventory = player.inventory if player else null
	_crafting_engine.setup(_inventory, 2)
	_connect_inventory()
	_refresh_all()
	visible = true
	GameManager.ui_open()
	EventBus.crafting_context_opened.emit(_crafting_engine, _inventory)


func _close() -> void:
	# Return craft grid contents to inventory
	if _inventory != null:
		for row in 2:
			for col in 2:
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
	EventBus.inventory_closed.emit(_player)


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
	var panel_h := 530
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

	# Title row
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	vbox.add_child(title_row)
	var title := Label.new()
	title.text = "Inventaire"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var book_btn := Button.new()
	book_btn.text = "Recettes"
	book_btn.add_theme_font_size_override("font_size", 11)
	book_btn.pressed.connect(func(): EventBus.recipe_book_requested.emit())
	title_row.add_child(book_btn)

	_build_armor_row(vbox)

	var sep_armor := HSeparator.new()
	vbox.add_child(sep_armor)

	_build_craft_section(vbox)

	var sep1 := HSeparator.new()
	vbox.add_child(sep1)

	var inv_lbl := Label.new()
	inv_lbl.text = "Objets"
	inv_lbl.add_theme_font_size_override("font_size", 11)
	inv_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	vbox.add_child(inv_lbl)

	# Main inventory (slots 9–35)
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

	# Hotbar (slots 0–8)
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

	# Floating cursor for drag-drop
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


func _build_armor_row(parent: VBoxContainer) -> void:
	var hdr := Label.new()
	hdr.text = "🛡  Armure équipée  (clic pour retirer)"
	hdr.add_theme_font_size_override("font_size", 11)
	hdr.add_theme_color_override("font_color", Color(0.55, 0.75, 1.00))
	parent.add_child(hdr)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	_armor_panels.clear()
	for i in 4:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		row.add_child(col)

		var icon_lbl := Label.new()
		icon_lbl.text = _ARMOR_ICONS[i]
		icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_lbl.add_theme_font_size_override("font_size", 11)
		icon_lbl.add_theme_color_override("font_color", Color(0.60, 0.72, 0.90))
		col.add_child(icon_lbl)

		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		_style_slot(slot, Color(0.08, 0.10, 0.14, 0.92), Color(0.35, 0.48, 0.72, 0.90))
		col.add_child(slot)

		var ir := ItemIconScript.new()
		ir.name = "ItemColor"
		ir.size = Vector2(32, 32)
		ir.position = Vector2(6, 6)
		ir.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(ir)

		var lbl := Label.new()
		lbl.name = "Count"
		lbl.anchor_right = 1.0; lbl.anchor_bottom = 1.0
		lbl.offset_top = SLOT_SIZE - 16; lbl.offset_right = -2
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(lbl)

		var empty_lbl := Label.new()
		empty_lbl.name = "EmptyHint"
		empty_lbl.text = _ARMOR_LABELS[i]
		empty_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 9)
		empty_lbl.add_theme_color_override("font_color", Color(0.30, 0.38, 0.55, 0.80))
		empty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(empty_lbl)

		var armor_idx := i
		slot.gui_input.connect(func(event: InputEvent) -> void:
			if not (event is InputEventMouseButton and event.pressed): return
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_unequip_armor(armor_idx)
		)
		_armor_panels.append(slot)


func _build_craft_section(parent: VBoxContainer) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	parent.add_child(hbox)

	var lbl := Label.new()
	lbl.text = "Fabrication (2×2)"
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(lbl)

	# 2×2 craft grid
	var craft_grid := GridContainer.new()
	craft_grid.columns = 2
	craft_grid.add_theme_constant_override("h_separation", SLOT_GAP)
	craft_grid.add_theme_constant_override("v_separation", SLOT_GAP)
	hbox.add_child(craft_grid)
	_craft_panels.clear()
	for i in 4:
		var s := _make_craft_slot(i)
		craft_grid.add_child(s)
		_craft_panels.append(s)

	var arrow := Label.new()
	arrow.text = "➜"
	arrow.add_theme_font_size_override("font_size", 22)
	arrow.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	arrow.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.custom_minimum_size  = Vector2(32, SLOT_SIZE * 2 + SLOT_GAP)
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
	_style_slot(slot, Color(0.12, 0.10, 0.10, 0.90), Color(0.38, 0.32, 0.32))

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
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE * 2 + SLOT_GAP)
	_style_slot(slot, Color(0.18, 0.16, 0.05, 0.95), Color(0.60, 0.55, 0.15))

	var ir := ItemIconScript.new(); ir.name = "ItemColor"
	ir.size = Vector2(32, 32)
	ir.position = Vector2(6, (SLOT_SIZE * 2 + SLOT_GAP) / 2 - 16)
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

	# Armor items: shift+click equips to the correct armor slot via EquipmentUI
	if item != null and item.raw.get("slot", "") in ["head", "chest", "legs", "feet"]:
		var equip_ui := get_tree().current_scene.get_node_or_null("EquipmentUI") as EquipmentUI
		if equip_ui == null:
			equip_ui = get_tree().current_scene.find_child("EquipmentUI", true, false) as EquipmentUI
		if equip_ui != null:
			equip_ui.equip_item(stack.get("id",""), slot_index)
			_update_slot_ui(slot_index)
			return

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
	var row := craft_idx / 2
	var col := craft_idx % 2
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
		# Craft as many times as possible
		_crafting_engine.craft_all()
	else:
		# Merge result with held stack or pick it up
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
	if not _inventory.armor_changed.is_connected(_on_armor_changed):
		_inventory.armor_changed.connect(_on_armor_changed)


func _on_armor_changed(slot_index: int, _new_stack: Dictionary) -> void:
	_update_armor_slot_ui(slot_index)


func _on_slot_changed(slot_index: int, _new_stack: Dictionary) -> void:
	_update_slot_ui(slot_index)


func _refresh_all() -> void:
	for i in 36: _update_slot_ui(i)
	_update_armor_ui()
	_update_craft_ui()
	_update_cursor()


func _update_armor_ui() -> void:
	for i in 4: _update_armor_slot_ui(i)


func _update_armor_slot_ui(index: int) -> void:
	if index < 0 or index >= _armor_panels.size() or _armor_panels[index] == null:
		return
	var panel := _armor_panels[index] as Panel
	var stack: Dictionary = _inventory.get_armor_slot(index) if _inventory else {}
	var ir    = panel.get_node_or_null("ItemColor")
	var lbl   := panel.get_node_or_null("Count") as Label
	var hint  := panel.get_node_or_null("EmptyHint") as Label

	var equipped := not ItemRegistry.is_empty_stack(stack)
	if hint: hint.visible = not equipped

	if not equipped:
		if ir:  ir.item_id = ""
		if lbl: lbl.text   = ""
		_style_slot(panel, Color(0.08, 0.10, 0.14, 0.92), Color(0.35, 0.48, 0.72, 0.90))
	else:
		if ir:  ir.item_id = stack.get("id", "")
		if lbl: lbl.text   = ""
		_style_slot(panel, Color(0.10, 0.14, 0.10, 0.92), Color(0.38, 0.70, 0.38, 0.95))


func _unequip_armor(armor_idx: int) -> void:
	if _inventory == null: return
	var stack: Dictionary = _inventory.get_armor_slot(armor_idx)
	if ItemRegistry.is_empty_stack(stack): return
	var leftover := _inventory.add_items(stack.get("id",""), stack.get("count",1), stack.get("meta",{}))
	if leftover > 0:
		EventBus.show_message.emit("Inventaire plein — impossible de retirer l'armure.", 2.5)
		return
	_inventory.set_armor_slot(armor_idx, {})
	var item_def := ItemRegistry.get_item(stack.get("id",""))
	var name: String = item_def.display_name if item_def else stack.get("id","?")
	EventBus.show_message.emit("%s retiré → inventaire" % name, 2.0)


func _update_slot_ui(index: int) -> void:
	if index < 0 or index >= _slot_panels.size() or _slot_panels[index] == null:
		return
	var panel := _slot_panels[index] as Panel
	var stack := _inventory.get_slot(index) if _inventory else {}
	_apply_stack_to_panel(panel, stack)


func _update_craft_slot_ui(craft_idx: int) -> void:
	if craft_idx < 0 or craft_idx >= _craft_panels.size():
		return
	var row := craft_idx / 2; var col := craft_idx % 2
	var stack: Dictionary = _crafting_engine.get_grid_slot(row, col)
	_apply_stack_to_panel(_craft_panels[craft_idx] as Panel, stack)


func _update_craft_ui() -> void:
	for i in 4: _update_craft_slot_ui(i)
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
