## RecipeBookUI.gd — Recipe browser with availability checking and auto-fill.
## Opens via EventBus.recipe_book_requested (button in inventory / crafting table UIs).
## Green border = craftable now, amber = partial, grey = missing materials.
extends CanvasLayer

const ItemIconScript = preload("res://scenes/ui/ItemIcon.gd")

const CARD_W     := 58
const CARD_H     := 70
const CARD_GAP   := 4
const COLS       := 7
const SIDEBAR_W  := 128
const PANEL_H    := 490

const CATEGORIES: Dictionary = {
	"all":          "Tous",
	"outils":       "Outils",
	"combat":       "Combat",
	"construction": "Blocs",
	"redstone":     "Redstone",
	"cuisine":      "Cuisine",
	"misc":         "Divers",
}

var _inventory: Inventory          = null
var _active_engine: CraftingEngine = null

var _all_recipes: Array = []
var _category    := "all"
var _search_text := ""
var _selected: RecipeRegistry.RecipeDef = null

var _scroll:      ScrollContainer
var _card_grid:   GridContainer
var _card_view:   Control
var _detail_view: Control
var _det_title:   Label
var _det_slots:   Array = []
var _det_result:  Panel
var _det_status:  Label
var _fill_btn:    Button
var _fill_hint:   Label
var _search:      LineEdit
var _cat_btns:    Dictionary = {}

var _cards: Array  = []
var _cards_built   := false


func _ready() -> void:
	visible = false
	layer   = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	_all_recipes = RecipeRegistry._crafting_shaped + RecipeRegistry._crafting_shapeless
	_build_ui()
	EventBus.player_spawned.connect(func(p: Node):
		_inventory = (p as Player).inventory if p else null)
	EventBus.crafting_context_opened.connect(_on_context_opened)
	EventBus.crafting_context_closed.connect(_on_context_closed)
	EventBus.recipe_book_requested.connect(_toggle)


# ── Open / Close ──────────────────────────────────────────────────────────────

func _toggle() -> void:
	if visible: _close()
	else:       _open()


func _open() -> void:
	if not _cards_built:
		_build_all_cards()
		_cards_built = true
	_apply_filter()
	visible = true
	GameManager.ui_open()


func _close() -> void:
	visible = false
	GameManager.ui_close()


func _on_context_opened(engine: CraftingEngine, inv: Inventory) -> void:
	_active_engine = engine
	_inventory     = inv
	_update_all_cards()
	if _selected != null:
		_update_detail_status()


func _on_context_closed() -> void:
	_active_engine = null
	_update_fill_btn()


func _input(event: InputEvent) -> void:
	if not visible: return
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


# ── UI Construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.40)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	var panel_w := SIDEBAR_W + 12 + COLS * (CARD_W + CARD_GAP) + 24
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -panel_w / 2
	panel.offset_right  =  panel_w / 2
	panel.offset_top    = -PANEL_H / 2
	panel.offset_bottom =  PANEL_H / 2
	var ps := StyleBoxFlat.new()
	ps.bg_color     = Color(0.12, 0.12, 0.16, 0.97)
	ps.border_color = Color(0.38, 0.38, 0.42)
	ps.border_width_left   = 1; ps.border_width_right  = 1
	ps.border_width_top    = 1; ps.border_width_bottom = 1
	ps.corner_radius_top_left    = 5; ps.corner_radius_top_right    = 5
	ps.corner_radius_bottom_left = 5; ps.corner_radius_bottom_right = 5
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left  = 10; root.offset_right  = -10
	root.offset_top   = 8;  root.offset_bottom = -8
	root.add_theme_constant_override("separation", 6)
	panel.add_child(root)

	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)

	var title_lbl := Label.new()
	title_lbl.text = "Livre de recettes"
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color.WHITE)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_lbl)

	_search = LineEdit.new()
	_search.placeholder_text = "Rechercher..."
	_search.custom_minimum_size = Vector2(190, 26)
	_search.add_theme_font_size_override("font_size", 12)
	_search.text_changed.connect(_on_search_changed)
	header.add_child(_search)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(28, 26)
	close_btn.add_theme_font_size_override("font_size", 13)
	close_btn.pressed.connect(_close)
	header.add_child(close_btn)

	root.add_child(HSeparator.new())

	# Body
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	# Sidebar
	var sidebar := _build_sidebar()
	body.add_child(sidebar)
	body.add_child(VSeparator.new())

	# Content area (card view + detail view, overlapping)
	var content := Control.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	body.add_child(content)

	_card_view = Control.new()
	_card_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_child(_card_view)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_view.add_child(_scroll)

	_card_grid = GridContainer.new()
	_card_grid.columns = COLS
	_card_grid.add_theme_constant_override("h_separation", CARD_GAP)
	_card_grid.add_theme_constant_override("v_separation", CARD_GAP)
	_scroll.add_child(_card_grid)

	_detail_view = Control.new()
	_detail_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_detail_view.visible = false
	content.add_child(_detail_view)
	_build_detail_panel()


func _build_sidebar() -> VBoxContainer:
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(SIDEBAR_W, 0)
	sidebar.add_theme_constant_override("separation", 3)

	var cat_lbl := Label.new()
	cat_lbl.text = "Catégories"
	cat_lbl.add_theme_font_size_override("font_size", 11)
	cat_lbl.add_theme_color_override("font_color", Color(0.50, 0.50, 0.55))
	sidebar.add_child(cat_lbl)

	for cat_id in CATEGORIES:
		var btn := Button.new()
		btn.text = CATEGORIES[cat_id]
		btn.toggle_mode = true
		btn.button_pressed = (cat_id == "all")
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(_on_category_pressed.bind(cat_id, btn))
		_cat_btns[cat_id] = btn
		sidebar.add_child(btn)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(spacer)

	# Legend
	var legend := VBoxContainer.new()
	legend.add_theme_constant_override("separation", 2)
	sidebar.add_child(legend)
	_add_legend_row(legend, Color(0.20, 0.78, 0.20), "Fabricable")
	_add_legend_row(legend, Color(0.90, 0.65, 0.10), "Partiel")
	_add_legend_row(legend, Color(0.40, 0.40, 0.44), "Manquant")
	return sidebar


func _add_legend_row(parent: Control, color: Color, text: String) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	parent.add_child(hb)
	var dot := ColorRect.new()
	dot.color = color; dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(dot)
	var lbl := Label.new(); lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.60, 0.60, 0.62))
	hb.add_child(lbl)


func _build_detail_panel() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 8; vbox.offset_right = -8
	vbox.add_theme_constant_override("separation", 8)
	_detail_view.add_child(vbox)

	# Back + title row
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	vbox.add_child(top_row)
	var back := Button.new()
	back.text = "< Retour"
	back.add_theme_font_size_override("font_size", 12)
	back.pressed.connect(_show_cards)
	top_row.add_child(back)
	_det_title = Label.new()
	_det_title.add_theme_font_size_override("font_size", 14)
	_det_title.add_theme_color_override("font_color", Color.WHITE)
	_det_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(_det_title)

	vbox.add_child(HSeparator.new())

	# Craft preview row: 3x3 grid + arrow + result
	var craft_row := HBoxContainer.new()
	craft_row.add_theme_constant_override("separation", 14)
	vbox.add_child(craft_row)

	var ing_grid := GridContainer.new()
	ing_grid.columns = 3
	ing_grid.add_theme_constant_override("h_separation", 3)
	ing_grid.add_theme_constant_override("v_separation", 3)
	craft_row.add_child(ing_grid)
	_det_slots.clear()
	for _i in 9:
		var s := _make_det_slot(44)
		ing_grid.add_child(s)
		_det_slots.append(s)

	var arrow := Label.new()
	arrow.text = ">"
	arrow.add_theme_font_size_override("font_size", 24)
	arrow.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	arrow.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.custom_minimum_size  = Vector2(28, 44 * 3 + 3 * 2)
	craft_row.add_child(arrow)

	_det_result = _make_det_slot(56)
	craft_row.add_child(_det_result)

	# Spacing
	var sp := Control.new(); sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(sp)

	# Status
	_det_status = Label.new()
	_det_status.add_theme_font_size_override("font_size", 12)
	_det_status.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_det_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_det_status)

	# Fill button
	_fill_btn = Button.new()
	_fill_btn.text = "Remplir la grille de craft"
	_fill_btn.add_theme_font_size_override("font_size", 13)
	_fill_btn.pressed.connect(_on_fill_clicked)
	vbox.add_child(_fill_btn)

	_fill_hint = Label.new()
	_fill_hint.add_theme_font_size_override("font_size", 10)
	_fill_hint.add_theme_color_override("font_color", Color(0.50, 0.50, 0.52))
	_fill_hint.text = ""
	vbox.add_child(_fill_hint)


func _make_det_slot(size: int) -> Panel:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(size, size)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.10, 0.10, 0.13, 0.90)
	s.border_color = Color(0.30, 0.30, 0.34)
	s.border_width_left  = 1; s.border_width_right  = 1
	s.border_width_top   = 1; s.border_width_bottom = 1
	slot.add_theme_stylebox_override("panel", s)
	slot.set_meta("base_style", s)

	var ir := ItemIconScript.new(); ir.name = "ItemColor"
	ir.size = Vector2(size - 12, size - 12)
	ir.position = Vector2(6, 6)
	ir.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(ir)

	var lbl := Label.new(); lbl.name = "Count"
	lbl.anchor_right = 1.0; lbl.anchor_bottom = 1.0
	lbl.offset_top = size - 16; lbl.offset_right = -2
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(lbl)
	return slot


# ── Cards ─────────────────────────────────────────────────────────────────────

func _build_all_cards() -> void:
	for entry in _cards:
		(entry["panel"] as Panel).queue_free()
	_cards.clear()
	for recipe in _all_recipes:
		var entry := _make_card(recipe)
		_card_grid.add_child(entry["panel"])
		_cards.append(entry)


func _make_card(recipe: RecipeRegistry.RecipeDef) -> Dictionary:
	var card := Panel.new()
	card.custom_minimum_size = Vector2(CARD_W, CARD_H)

	var s := StyleBoxFlat.new()
	s.bg_color     = Color(0.14, 0.14, 0.18, 0.95)
	s.border_color = Color(0.30, 0.30, 0.35)
	s.border_width_left  = 1; s.border_width_right  = 1
	s.border_width_top   = 1; s.border_width_bottom = 1
	s.corner_radius_top_left    = 3; s.corner_radius_top_right    = 3
	s.corner_radius_bottom_left = 3; s.corner_radius_bottom_right = 3
	card.add_theme_stylebox_override("panel", s)
	card.set_meta("base_style", s)

	var result_id: String = recipe.result.get("id", "")
	var ir := ItemIconScript.new()
	ir.item_id = result_id
	ir.size = Vector2(32, 32)
	ir.position = Vector2((CARD_W - 32) / 2.0, 5)
	ir.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(ir)

	var name_lbl := Label.new()
	var short := result_id.replace("axiom:", "").replace("_", " ")
	name_lbl.text = short
	name_lbl.add_theme_font_size_override("font_size", 9)
	name_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.78))
	name_lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_lbl.offset_top = -22; name_lbl.offset_bottom = -3
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.clip_text = true
	card.add_child(name_lbl)

	# Availability dot (top-right corner)
	var dot := ColorRect.new()
	dot.size = Vector2(7, 7)
	dot.position = Vector2(CARD_W - 9, 2)
	dot.color = Color(0.40, 0.40, 0.44)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(dot)

	# Result count badge (top-left if > 1)
	var cnt: int = recipe.result.get("count", 1)
	if cnt > 1:
		var cnt_lbl := Label.new()
		cnt_lbl.text = str(cnt)
		cnt_lbl.position = Vector2(2, 1)
		cnt_lbl.add_theme_font_size_override("font_size", 9)
		cnt_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.50))
		cnt_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(cnt_lbl)

	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_show_detail(recipe)
	)
	card.mouse_entered.connect(func():
		var hs := (card.get_meta("base_style") as StyleBoxFlat).duplicate() as StyleBoxFlat
		hs.bg_color = hs.bg_color.lightened(0.10)
		card.add_theme_stylebox_override("panel", hs)
	)
	card.mouse_exited.connect(func():
		card.add_theme_stylebox_override("panel", card.get_meta("base_style"))
	)

	return {"panel": card, "recipe": recipe, "dot": dot, "style": s}


# ── Filtering ─────────────────────────────────────────────────────────────────

func _apply_filter() -> void:
	var search := _search_text.strip_edges().to_lower()
	for entry in _cards:
		var recipe: RecipeRegistry.RecipeDef = entry["recipe"]
		var name: String = str(recipe.result.get("id", "")).replace("axiom:", "").replace("_", " ")
		var cat_match    := _category == "all" or _get_category(recipe) == _category
		var search_match := search.is_empty() or name.contains(search)
		entry["panel"].visible = cat_match and search_match
	_update_all_cards()


func _update_all_cards() -> void:
	if _inventory == null: return
	for entry in _cards:
		if entry["panel"].visible:
			_update_card_style(entry)


func _update_card_style(entry: Dictionary) -> void:
	var avail := _check_availability(entry["recipe"])
	var dot  := entry["dot"]  as ColorRect
	var s    := entry["style"] as StyleBoxFlat
	if avail["craftable"]:
		s.border_color = Color(0.15, 0.68, 0.15)
		dot.color      = Color(0.20, 0.85, 0.20)
	elif avail["partial"]:
		s.border_color = Color(0.72, 0.50, 0.08)
		dot.color      = Color(0.92, 0.65, 0.10)
	else:
		s.border_color = Color(0.30, 0.30, 0.35)
		dot.color      = Color(0.40, 0.40, 0.44)
	entry["panel"].add_theme_stylebox_override("panel", s)


# ── Detail view ───────────────────────────────────────────────────────────────

func _show_detail(recipe: RecipeRegistry.RecipeDef) -> void:
	_selected = recipe
	_card_view.visible   = false
	_detail_view.visible = true

	# Title
	var result_id: String = recipe.result.get("id", "")
	_det_title.text = result_id.replace("axiom:", "").replace("_", " ").capitalize()
	if recipe.result.get("count", 1) > 1:
		_det_title.text += "  x%d" % recipe.result["count"]

	# Reset slots
	for i in 9:
		_apply_to_slot(_det_slots[i], "", 0, Color.TRANSPARENT, false)

	if recipe is RecipeRegistry.ShapedRecipe:
		_populate_shaped(recipe as RecipeRegistry.ShapedRecipe)
	elif recipe is RecipeRegistry.ShapelessRecipe:
		_populate_shapeless(recipe as RecipeRegistry.ShapelessRecipe)

	# Result slot
	_apply_to_slot(_det_result, recipe.result.get("id", ""), int(recipe.result.get("count", 1)), Color.WHITE, true)

	_update_detail_status()


func _populate_shaped(recipe: RecipeRegistry.ShapedRecipe) -> void:
	for y in 3:
		for x in 3:
			var ing = null
			if y < recipe.grid.size() and x < recipe.grid[y].size():
				ing = recipe.grid[y][x]
			if ing == null: continue
			var slot: Panel = _det_slots[y * 3 + x]
			var ex_id := _find_example(ing)
			var have  := _count_ingredient(_inventory, ing)
			_apply_to_slot(slot, ex_id, 0, Color.WHITE, have >= 1)
			_set_slot_border(slot, have >= 1)


func _populate_shapeless(recipe: RecipeRegistry.ShapelessRecipe) -> void:
	for i in mini(recipe.ingredients.size(), 9):
		var ing = recipe.ingredients[i]
		var slot: Panel = _det_slots[i]
		var ex_id := _find_example(ing)
		var have  := _count_ingredient(_inventory, ing)
		_apply_to_slot(slot, ex_id, 0, Color.WHITE, have >= 1)
		_set_slot_border(slot, have >= 1)


func _apply_to_slot(slot: Panel, item_id: String, count: int, _color: Color, _has: bool) -> void:
	var ir  = slot.get_node_or_null("ItemColor")
	var lbl := slot.get_node_or_null("Count") as Label
	if ir:  ir.item_id = item_id
	if lbl: lbl.text = str(count) if count > 1 else ""


func _set_slot_border(slot: Panel, has_item: bool) -> void:
	var s := (slot.get_meta("base_style") as StyleBoxFlat).duplicate() as StyleBoxFlat
	s.border_color = Color(0.20, 0.68, 0.20) if has_item else Color(0.72, 0.22, 0.22)
	s.border_width_left  = 1; s.border_width_right  = 1
	s.border_width_top   = 1; s.border_width_bottom = 1
	slot.add_theme_stylebox_override("panel", s)


func _update_detail_status() -> void:
	if _selected == null: return
	var avail := _check_availability(_selected)

	if avail["craftable"]:
		_det_status.text = "Vous avez tous les materiaux."
		_det_status.add_theme_color_override("font_color", Color(0.25, 0.85, 0.25))
	else:
		var lines := []
		for m in avail["missing"]:
			var ing = m["ingredient"]
			var name: String = _ingredient_display_name(ing)
			lines.append("  %s  (%d/%d)" % [name, m["have"], m["need"]])
		var status := "Manquants :\n" + "\n".join(lines) if lines else "Certains materiaux sont insuffisants."
		_det_status.text = status
		_det_status.add_theme_color_override("font_color", Color(0.90, 0.55, 0.18))

	_update_fill_btn()


func _update_fill_btn() -> void:
	if _selected == null:
		_fill_btn.disabled = true
		_fill_hint.text = ""
		return

	if _active_engine == null:
		_fill_btn.disabled = true
		_fill_hint.text = "Ouvrez l'inventaire ou la table de craft."
		return

	if _selected is RecipeRegistry.ShapedRecipe:
		var sr := _selected as RecipeRegistry.ShapedRecipe
		if sr.width > _active_engine.grid_size or sr.height > _active_engine.grid_size:
			_fill_btn.disabled = true
			_fill_hint.text = "Necessite une table de craft 3x3."
			return

	var avail := _check_availability(_selected)
	_fill_btn.disabled = not avail["craftable"]
	_fill_hint.text = "" if avail["craftable"] else "Il vous manque des materiaux."


func _show_cards() -> void:
	_selected            = null
	_card_view.visible   = true
	_detail_view.visible = false


# ── Fill action ───────────────────────────────────────────────────────────────

func _on_fill_clicked() -> void:
	if _selected == null or _active_engine == null or _inventory == null:
		return

	_active_engine.return_items_to_inventory()

	if _selected is RecipeRegistry.ShapedRecipe:
		var sr := _selected as RecipeRegistry.ShapedRecipe
		for y in sr.grid.size():
			for x in 3:
				var ing = sr.grid[y][x]
				if ing == null: continue
				if y >= _active_engine.grid_size or x >= _active_engine.grid_size: continue
				var item_id := _pull_from_inventory(_inventory, ing)
				if item_id != "":
					_active_engine.set_grid_slot(y, x, {"id": item_id, "count": 1})

	elif _selected is RecipeRegistry.ShapelessRecipe:
		var idx := 0
		for ing in (_selected as RecipeRegistry.ShapelessRecipe).ingredients:
			if idx >= _active_engine.grid_size * _active_engine.grid_size: break
			var item_id := _pull_from_inventory(_inventory, ing)
			if item_id != "":
				_active_engine.set_grid_slot(idx / _active_engine.grid_size,
											 idx % _active_engine.grid_size,
											 {"id": item_id, "count": 1})
				idx += 1

	_update_detail_status()
	_update_all_cards()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _check_availability(recipe: RecipeRegistry.RecipeDef) -> Dictionary:
	if _inventory == null:
		return {"craftable": false, "partial": false, "missing": []}

	var needed := {}
	if recipe is RecipeRegistry.ShapedRecipe:
		for row in (recipe as RecipeRegistry.ShapedRecipe).grid:
			for ing in row:
				if ing == null: continue
				var k := _ing_key(ing)
				if not needed.has(k): needed[k] = {"ingredient": ing, "need": 0, "have": 0}
				needed[k]["need"] += 1
	elif recipe is RecipeRegistry.ShapelessRecipe:
		for ing in (recipe as RecipeRegistry.ShapelessRecipe).ingredients:
			var k := _ing_key(ing)
			if not needed.has(k): needed[k] = {"ingredient": ing, "need": 0, "have": 0}
			needed[k]["need"] += 1

	for i in 36:
		var stack := _inventory.get_slot(i)
		if ItemRegistry.is_empty_stack(stack): continue
		var item_id: String = stack.get("id", "")
		var cnt: int        = stack.get("count", 0)
		for k in needed:
			var e: Dictionary = needed[k]
			if _matches(e["ingredient"], item_id):
				e["have"] = mini(e["have"] + cnt, e["need"])

	var total_need := 0; var total_have := 0; var missing := []
	for k in needed:
		var e: Dictionary = needed[k]
		total_need += e["need"]; total_have += e["have"]
		if e["have"] < e["need"]:
			missing.append({"ingredient": e["ingredient"], "need": e["need"], "have": e["have"]})

	return {"craftable": total_have >= total_need and total_need > 0,
			"partial":   total_have > 0 and total_have < total_need,
			"missing":   missing}


func _pull_from_inventory(inv: Inventory, ing) -> String:
	for i in 36:
		var stack := inv.get_slot(i)
		if ItemRegistry.is_empty_stack(stack): continue
		var id: String = stack.get("id", "")
		if _matches(ing, id):
			stack["count"] -= 1
			if stack["count"] <= 0: inv.set_slot(i, {})
			else:                   inv.set_slot(i, stack)
			return id
	return ""


func _count_ingredient(inv: Inventory, ing) -> int:
	if inv == null: return 0
	var total := 0
	for i in 36:
		var stack := inv.get_slot(i)
		if ItemRegistry.is_empty_stack(stack): continue
		if _matches(ing, stack.get("id", "")):
			total += stack.get("count", 0)
	return total


func _find_example(ing) -> String:
	if ing is String: return ing
	if ing is Dictionary and ing.has("tag") and _inventory:
		for i in 36:
			var stack := _inventory.get_slot(i)
			if not ItemRegistry.is_empty_stack(stack):
				if _matches(ing, stack.get("id", "")): return stack.get("id", "")
	return ""


func _matches(ing, item_id: String) -> bool:
	if ing is String: return ing == item_id
	if ing is Dictionary and ing.has("tag"):
		var tag: String = ing["tag"]
		var item := ItemRegistry.get_item(item_id)
		if item != null and tag in item.tags: return true
		var bid := ItemRegistry.get_block_id_for_item(item_id)
		if bid >= 0: return BlockRegistry.get_blocks_by_tag(tag).has(bid)
	return false


func _ing_key(ing) -> String:
	if ing is String:     return ing
	if ing is Dictionary: return "tag:" + str(ing.get("tag", ""))
	return "?"


func _ingredient_display_name(ing) -> String:
	if ing is String:
		return ing.replace("axiom:", "").replace("_", " ")
	if ing is Dictionary and ing.has("tag"):
		return ing["tag"].replace("axiom:", "").replace("_", " ") + " (tag)"
	return "?"


func _get_category(recipe: RecipeRegistry.RecipeDef) -> String:
	var n: String = str(recipe.result.get("id", "")).replace("axiom:", "")
	for kw in ["pickaxe", "shovel", "hoe", "shears", "fishing_rod", "flint_and_steel",
			   "spyglass", "bucket", "lead", "name_tag", "saddle", "compass", "clock", "brush"]:
		if n.contains(kw): return "outils"
	for kw in ["_axe"]:  # axe after pickaxe to avoid false match
		if n.contains(kw): return "outils"
	for kw in ["sword", "bow", "crossbow", "arrow", "shield",
			   "helmet", "chestplate", "leggings", "boots", "trident"]:
		if n.contains(kw): return "combat"
	for kw in ["bread", "cake", "cookie", "stew", "soup", "apple", "sugar",
			   "pumpkin_pie", "honey", "golden_carrot", "glistering", "rabbit_stew", "beetroot_soup"]:
		if n.contains(kw): return "cuisine"
	for kw in ["redstone_", "lever", "repeater", "comparator", "observer",
			   "dispenser", "dropper", "hopper", "rail", "minecart",
			   "piston", "daylight", "tripwire", "target", "note_block", "jukebox"]:
		if n.contains(kw): return "redstone"
	for kw in ["slab", "stairs", "door", "trapdoor", "fence", "wall", "planks",
			   "bricks", "brick", "glass", "ladder", "scaffolding", "_block",
			   "sandstone", "stone", "polished", "deepslate", "blackstone",
			   "quartz", "cobblestone", "anvil", "furnace", "beacon",
			   "chest", "barrel", "bookshelf", "tnt", "crafting_table"]:
		if n.contains(kw): return "construction"
	return "misc"


# ── Event handlers ────────────────────────────────────────────────────────────

func _on_category_pressed(cat_id: String, btn: Button) -> void:
	for k in _cat_btns:
		(_cat_btns[k] as Button).button_pressed = false
	btn.button_pressed = true
	_category = cat_id
	if _selected != null: _show_cards()
	_apply_filter()


func _on_search_changed(text: String) -> void:
	_search_text = text
	if _selected != null: _show_cards()
	_apply_filter()
