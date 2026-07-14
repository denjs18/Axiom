## ChestUI.gd — Storage container interface (chest / barrel).
## 27 container slots on top, full player inventory below.
## Opens on EventBus.block_interacted for any block with an inventory.
extends CanvasLayer

const ItemIconScript = preload("res://scenes/ui/ItemIcon.gd")

const SLOT_SIZE   := 44
const SLOT_GAP    := 3
const HOTBAR_SIZE := 9
const MAIN_SIZE   := 27

const CHEST_BLOCK_NAMES := ["chest", "trapped_chest", "barrel"]

var _player:    Player      = null
var _inventory: Inventory   = null
var _entity:    ChestEntity = null
var _bpos:      Vector3i

var _slot_panels:  Array = []   # 36 player inventory slots
var _chest_panels: Array = []   # 27 chest slots
var _title_label:  Label = null

var _held_stack:   Dictionary = {}
var _cursor_icon               = null
var _cursor_label: Label       = null


func _ready() -> void:
	visible = false
	layer   = 6
	_slot_panels.resize(36)
	_slot_panels.fill(null)
	_chest_panels.resize(ChestEntity.SLOT_COUNT)
	_chest_panels.fill(null)
	_build_ui()
	EventBus.block_interacted.connect(_on_block_interacted)


# ── Open / Close ───────────────────────────────────────────────────────────────

func _on_block_interacted(bpos: Vector3i, block_id: int, player: Node) -> void:
	var block := BlockRegistry.get_block(block_id)
	if block == null or not block.name in CHEST_BLOCK_NAMES:
		return
	if visible:
		_close()
		return
	_player    = player as Player
	_inventory = _player.inventory if _player else null
	_bpos      = bpos
	if _title_label != null:
		_title_label.text = block.display_name
	var bem = _player._block_entity_manager if _player else null
	if bem != null:
		_entity = bem.get_entity(bpos) as ChestEntity
		if _entity == null:
			_entity = bem.create_entity(bpos, block_id) as ChestEntity
	if _entity == null:
		return
	if _inventory != null and not _inventory.slot_changed.is_connected(_on_inv_slot_changed):
		_inventory.slot_changed.connect(_on_inv_slot_changed)
	_refresh_all()
	visible = true
	GameManager.ui_open()


func _close() -> void:
	if not ItemRegistry.is_empty_stack(_held_stack) and _inventory != null:
		_inventory.add_items(_held_stack.get("id", ""), _held_stack.get("count", 0), _held_stack.get("meta", {}))
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


func _process(_delta: float) -> void:
	if not visible:
		return
	var mp := get_viewport().get_mouse_position()
	if _cursor_icon:  _cursor_icon.position  = mp - Vector2(16, 16)
	if _cursor_label: _cursor_label.position = mp - Vector2(16, 16)


# ── UI construction ────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.50)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	var panel_w := 9 * (SLOT_SIZE + SLOT_GAP) - SLOT_GAP + 24
	var panel_h := 560
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -panel_w / 2
	panel.offset_right  =  panel_w / 2
	panel.offset_top    = -panel_h / 2
	panel.offset_bottom =  panel_h / 2
	panel.add_theme_stylebox_override("panel", UITheme.card())
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 12; vbox.offset_right  = -12
	vbox.offset_top  = 10; vbox.offset_bottom = -10
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	_title_label = UITheme.heading("Coffre", 17)
	vbox.add_child(_title_label)

	# Chest grid — 9×3
	var chest_grid := GridContainer.new()
	chest_grid.columns = 9
	chest_grid.add_theme_constant_override("h_separation", SLOT_GAP)
	chest_grid.add_theme_constant_override("v_separation", SLOT_GAP)
	vbox.add_child(chest_grid)
	for i in ChestEntity.SLOT_COUNT:
		var s := _make_slot()
		s.gui_input.connect(_on_chest_slot_input.bind(i))
		chest_grid.add_child(s)
		_chest_panels[i] = s

	vbox.add_child(HSeparator.new())

	var inv_lbl := UITheme.caption("Inventaire")
	vbox.add_child(inv_lbl)

	var main_grid := GridContainer.new()
	main_grid.columns = 9
	main_grid.add_theme_constant_override("h_separation", SLOT_GAP)
	main_grid.add_theme_constant_override("v_separation", SLOT_GAP)
	vbox.add_child(main_grid)
	for i in range(HOTBAR_SIZE, HOTBAR_SIZE + MAIN_SIZE):
		var s := _make_slot()
		s.gui_input.connect(_on_inv_slot_input.bind(i))
		main_grid.add_child(s)
		_slot_panels[i] = s

	vbox.add_child(HSeparator.new())

	var hotbar_row := HBoxContainer.new()
	hotbar_row.add_theme_constant_override("separation", SLOT_GAP)
	vbox.add_child(hotbar_row)
	for i in range(0, HOTBAR_SIZE):
		var s := _make_slot()
		s.gui_input.connect(_on_inv_slot_input.bind(i))
		hotbar_row.add_child(s)
		_slot_panels[i] = s

	var hint := UITheme.caption("E / Échap = fermer   •   Maj+Clic = transférer", 10)
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


func _make_slot() -> Panel:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.add_theme_stylebox_override("panel", UITheme.slot_style())
	slot.mouse_entered.connect(func() -> void:
		slot.add_theme_stylebox_override("panel", UITheme.slot_style(true)))
	slot.mouse_exited.connect(func() -> void:
		slot.add_theme_stylebox_override("panel", UITheme.slot_style()))
	var ir = ItemIconScript.new(); ir.name = "ItemColor"
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
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(lbl)
	return slot


# ── Chest slot interactions ────────────────────────────────────────────────────

func _on_chest_slot_input(event: InputEvent, idx: int) -> void:
	if not (event is InputEventMouseButton and event.pressed) or _entity == null:
		return
	var mb := event as InputEventMouseButton
	var stack: Dictionary = _entity.get_slot(idx)
	if mb.shift_pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		# Move all to player inventory
		if not ItemRegistry.is_empty_stack(stack) and _inventory != null:
			var leftover := _inventory.add_items(stack.get("id", ""), stack.get("count", 0), stack.get("meta", {}))
			if leftover <= 0:
				_entity.set_slot(idx, {})
			else:
				stack["count"] = leftover
				_entity.set_slot(idx, stack)
	elif mb.button_index == MOUSE_BUTTON_LEFT:
		_entity.set_slot(idx, _swap_stack(stack))
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_entity.set_slot(idx, _right_click_stack(stack))
	_update_chest_slot(idx)
	_update_cursor()


## Generic left-click logic against an arbitrary stack. Returns the new
## content of the clicked slot (held stack is updated in place).
func _swap_stack(current: Dictionary) -> Dictionary:
	if ItemRegistry.is_empty_stack(_held_stack):
		if not ItemRegistry.is_empty_stack(current):
			_held_stack = current.duplicate()
			return {}
		return current
	if ItemRegistry.is_empty_stack(current):
		var placed := _held_stack.duplicate()
		_held_stack = {}
		return placed
	if ItemRegistry.stacks_can_merge(_held_stack, current):
		var item := ItemRegistry.get_item(_held_stack.get("id", ""))
		var max_s := item.max_stack if item else 64
		var total: int = _held_stack.get("count", 0) + current.get("count", 0)
		if total <= max_s:
			current["count"] = total
			_held_stack = {}
		else:
			current["count"] = max_s
			_held_stack["count"] = total - max_s
		return current
	var old := current.duplicate()
	var placed2 := _held_stack.duplicate()
	_held_stack = old
	return placed2


## Right-click: place one item / split half.
func _right_click_stack(current: Dictionary) -> Dictionary:
	if ItemRegistry.is_empty_stack(_held_stack):
		if not ItemRegistry.is_empty_stack(current):
			var cnt: int = current.get("count", 0)
			if cnt <= 1:
				_held_stack = current.duplicate()
				return {}
			var take := cnt / 2
			_held_stack = current.duplicate()
			_held_stack["count"] = take
			current["count"] = cnt - take
		return current
	var item := ItemRegistry.get_item(_held_stack.get("id", ""))
	var max_s := item.max_stack if item else 64
	if ItemRegistry.is_empty_stack(current):
		var one := _held_stack.duplicate()
		one["count"] = 1
		_held_stack["count"] -= 1
		if _held_stack.get("count", 0) <= 0:
			_held_stack = {}
		return one
	if ItemRegistry.stacks_can_merge(_held_stack, current) and current.get("count", 0) < max_s:
		current["count"] += 1
		_held_stack["count"] -= 1
		if _held_stack.get("count", 0) <= 0:
			_held_stack = {}
	return current


# ── Player inventory slot interactions ─────────────────────────────────────────

func _on_inv_slot_input(event: InputEvent, slot_index: int) -> void:
	if not (event is InputEventMouseButton and event.pressed) or _inventory == null:
		return
	var mb := event as InputEventMouseButton
	if mb.shift_pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_shift_inv_to_chest(slot_index)
		return
	var current := _inventory.get_slot(slot_index)
	if mb.button_index == MOUSE_BUTTON_LEFT:
		_inventory.set_slot(slot_index, _swap_stack(current))
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_inventory.set_slot(slot_index, _right_click_stack(current))
	_update_inv_slot(slot_index)
	_update_cursor()


func _shift_inv_to_chest(slot_index: int) -> void:
	if _entity == null or _inventory == null:
		return
	var stack := _inventory.get_slot(slot_index)
	if ItemRegistry.is_empty_stack(stack):
		return
	var leftover: int = _entity.add_items(stack.get("id", ""), stack.get("count", 0))
	if leftover <= 0:
		_inventory.set_slot(slot_index, {})
	else:
		stack["count"] = leftover
		_inventory.set_slot(slot_index, stack)
	_refresh_chest()
	_update_inv_slot(slot_index)


# ── Display helpers ────────────────────────────────────────────────────────────

func _on_inv_slot_changed(slot_index: int, _stack: Dictionary) -> void:
	if visible:
		_update_inv_slot(slot_index)


func _refresh_all() -> void:
	for i in 36:
		_update_inv_slot(i)
	_refresh_chest()
	_update_cursor()


func _refresh_chest() -> void:
	for i in ChestEntity.SLOT_COUNT:
		_update_chest_slot(i)


func _update_chest_slot(idx: int) -> void:
	if _entity == null or _chest_panels[idx] == null:
		return
	_apply_stack(_chest_panels[idx] as Panel, _entity.get_slot(idx))


func _update_inv_slot(index: int) -> void:
	if index < 0 or index >= _slot_panels.size() or _slot_panels[index] == null:
		return
	var stack := _inventory.get_slot(index) if _inventory else {}
	_apply_stack(_slot_panels[index] as Panel, stack)


func _apply_stack(panel: Panel, stack: Dictionary) -> void:
	if panel == null:
		return
	var ir = panel.get_node_or_null("ItemColor")
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
	if _cursor_icon == null:
		return
	if ItemRegistry.is_empty_stack(_held_stack):
		_cursor_icon.item_id = ""
		if _cursor_label: _cursor_label.text = ""
	else:
		_cursor_icon.item_id = _held_stack.get("id", "")
		if _cursor_label:
			var cnt: int = _held_stack.get("count", 0)
			_cursor_label.text = str(cnt) if cnt > 1 else ""
