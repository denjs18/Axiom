## RecipeCatalogUI.gd — Primary crafting interface: searchable catalog with one-click craft.
## Opens when the player interacts with a crafting table.
## Also openable from anywhere when the player carries an Établi Compact (C key).
extends CanvasLayer

const ItemIconScript = preload("res://scenes/ui/ItemIcon.gd")

const CARD_SIZE     := 52
const CARD_GAP      := 4
const CARDS_PER_ROW := 6

const CATEGORIES := ["Tout", "Outils", "Armes", "Armures", "Nourriture", "Construction", "Matériaux"]

var _player:   Player    = null
var _inventory: Inventory = null

var _all_recipes:      Array  = []
var _filtered_recipes: Array  = []
var _selected_recipe          = null
var _current_category: String = "Tout"
var _search_text:      String = ""

# UI nodes
var _recipe_grid:        GridContainer   = null
var _search_bar:         LineEdit        = null
var _count_label:        Label           = null
var _empty_hint:         Label           = null
var _detail_icon                         = null
var _detail_name:        Label           = null
var _ingredients_box:    VBoxContainer   = null
var _craft_btn:          Button          = null
var _table_btn:          Button          = null
var _category_btns:      Dictionary      = {}
var _card_panels:        Array           = []


func _ready() -> void:
	visible = false
	layer   = 6
	_build_ui()
	EventBus.block_interacted.connect(_on_block_interacted)
	if not InputMap.has_action("open_catalog"):
		InputMap.add_action("open_catalog")
		var ev := InputEventKey.new()
		ev.keycode = KEY_C
		InputMap.action_add_event("open_catalog", ev)


func _input(event: InputEvent) -> void:
	if not visible:
		if event.is_action_pressed("open_catalog"):
			if GameManager.current_state != GameManager.GameState.PLAYING:
				return
			var p := GameManager.local_player as Player
			if p != null and p.can_craft_anywhere():
				_open(p)
				get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("open_inventory") or event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


# ── Open / Close ───────────────────────────────────────────────────────────────

func _on_block_interacted(_bpos: Vector3i, block_id: int, player: Node) -> void:
	var block := BlockRegistry.get_block(block_id)
	if block == null or block.name != "crafting_table":
		return
	if visible:
		_close()
		return
	_open(player as Player)


func _open(player: Player) -> void:
	_player        = player
	_inventory     = player.inventory if player else null
	_all_recipes   = RecipeRegistry.get_all_crafting_recipes()
	_current_category = "Tout"
	_search_text      = ""
	if _search_bar:
		_search_bar.text = ""
	_set_category("Tout")
	visible = true
	GameManager.ui_open()
	if _table_btn:
		_table_btn.disabled = false


func _close() -> void:
	visible = false
	GameManager.ui_close()
	_selected_recipe = null
	_clear_detail()


# ── UI Construction ────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.45)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	var W := 760; var H := 500
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -W / 2;  panel.offset_right  = W / 2
	panel.offset_top    = -H / 2;  panel.offset_bottom = H / 2
	var ps := StyleBoxFlat.new()
	ps.bg_color             = Color(0.12, 0.12, 0.15, 0.97)
	ps.border_width_left    = 1; ps.border_width_right  = 1
	ps.border_width_top     = 1; ps.border_width_bottom = 1
	ps.border_color         = Color(0.38, 0.38, 0.42)
	ps.corner_radius_top_left     = 4; ps.corner_radius_top_right    = 4
	ps.corner_radius_bottom_left  = 4; ps.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 12; root.offset_right  = -12
	root.offset_top  = 10; root.offset_bottom = -10
	root.add_theme_constant_override("separation", 6)
	panel.add_child(root)

	# Title bar
	var title_row := HBoxContainer.new()
	root.add_child(title_row)
	var title_lbl := Label.new()
	title_lbl.text = "Catalogue de Craft"
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color.WHITE)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_lbl)
	var hint_lbl := Label.new()
	hint_lbl.text = "E / Échap = fermer"
	hint_lbl.add_theme_font_size_override("font_size", 10)
	hint_lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	hint_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(hint_lbl)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.pressed.connect(_close)
	title_row.add_child(close_btn)

	root.add_child(HSeparator.new())

	# 3-column body
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	_build_left_col(body)
	body.add_child(VSeparator.new())
	_build_center_col(body)
	body.add_child(VSeparator.new())
	_build_right_col(body)


func _build_left_col(parent: HBoxContainer) -> void:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(148, 0)
	vbox.add_theme_constant_override("separation", 3)
	parent.add_child(vbox)

	_search_bar = LineEdit.new()
	_search_bar.placeholder_text = "Rechercher..."
	_search_bar.add_theme_font_size_override("font_size", 12)
	_search_bar.text_changed.connect(_on_search_changed)
	vbox.add_child(_search_bar)

	vbox.add_child(HSeparator.new())

	for cat in CATEGORIES:
		var btn := Button.new()
		btn.text = cat
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(_set_category.bind(cat))
		_category_btns[cat] = btn
		vbox.add_child(btn)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)


func _build_center_col(parent: HBoxContainer) -> void:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	parent.add_child(vbox)

	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 10)
	_count_label.add_theme_color_override("font_color", Color(0.50, 0.50, 0.50))
	vbox.add_child(_count_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_recipe_grid = GridContainer.new()
	_recipe_grid.columns = CARDS_PER_ROW
	_recipe_grid.add_theme_constant_override("h_separation", CARD_GAP)
	_recipe_grid.add_theme_constant_override("v_separation", CARD_GAP)
	_recipe_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_recipe_grid)

	_empty_hint = Label.new()
	_empty_hint.text = "Aucune recette trouvée."
	_empty_hint.add_theme_font_size_override("font_size", 12)
	_empty_hint.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	_empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_hint.visible = false
	vbox.add_child(_empty_hint)


func _build_right_col(parent: HBoxContainer) -> void:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(188, 0)
	vbox.add_theme_constant_override("separation", 6)
	parent.add_child(vbox)

	# Result row
	var icon_row := HBoxContainer.new()
	icon_row.add_theme_constant_override("separation", 8)
	vbox.add_child(icon_row)

	_detail_icon = ItemIconScript.new()
	_detail_icon.custom_minimum_size = Vector2(48, 48)
	_detail_icon.size = Vector2(48, 48)
	icon_row.add_child(_detail_icon)

	var name_vbox := VBoxContainer.new()
	name_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_vbox.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	icon_row.add_child(name_vbox)

	_detail_name = Label.new()
	_detail_name.text = "Sélectionnez une recette"
	_detail_name.add_theme_font_size_override("font_size", 13)
	_detail_name.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_name.size_flags_vertical = Control.SIZE_EXPAND_FILL
	name_vbox.add_child(_detail_name)

	vbox.add_child(HSeparator.new())

	var ing_lbl := Label.new()
	ing_lbl.text = "Ingrédients"
	ing_lbl.add_theme_font_size_override("font_size", 11)
	ing_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	vbox.add_child(ing_lbl)

	_ingredients_box = VBoxContainer.new()
	_ingredients_box.add_theme_constant_override("separation", 3)
	vbox.add_child(_ingredients_box)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	vbox.add_child(HSeparator.new())

	_craft_btn = Button.new()
	_craft_btn.text = "CRAFT"
	_craft_btn.add_theme_font_size_override("font_size", 13)
	_craft_btn.disabled = true
	_craft_btn.pressed.connect(_on_craft_pressed)
	vbox.add_child(_craft_btn)

	_table_btn = Button.new()
	_table_btn.text = "Ouvrir dans la table"
	_table_btn.add_theme_font_size_override("font_size", 11)
	_table_btn.disabled = true
	_table_btn.pressed.connect(_on_table_pressed)
	vbox.add_child(_table_btn)


# ── Filtering ──────────────────────────────────────────────────────────────────

func _on_search_changed(text: String) -> void:
	_search_text = text.strip_edges().to_lower()
	_apply_filter()


func _set_category(cat: String) -> void:
	_current_category = cat
	for c: String in _category_btns:
		var btn := _category_btns[c] as Button
		var sbf := StyleBoxFlat.new()
		sbf.bg_color = Color(0.18, 0.38, 0.18, 0.85) if c == cat else Color(0.14, 0.14, 0.17, 0.0)
		btn.add_theme_stylebox_override("normal", sbf)
	_apply_filter()


func _apply_filter() -> void:
	_filtered_recipes = []
	for recipe in _all_recipes:
		if _current_category != "Tout" and _get_category(recipe) != _current_category:
			continue
		if _search_text != "":
			var rid: String = recipe.result.get("id", "")
			var item := ItemRegistry.get_item(rid)
			var disp := (item.display_name if item else rid).to_lower()
			if _search_text not in disp and _search_text not in rid.to_lower():
				continue
		_filtered_recipes.append(recipe)
	_refresh_recipe_grid()


func _get_category(recipe) -> String:
	var tags: Array = recipe.raw.get("tags", [])
	if "weapon"     in tags:                             return "Armes"
	if "armor"      in tags or "style_armor" in tags:   return "Armures"
	if "food"       in tags:                             return "Nourriture"
	if "building"   in tags:                             return "Construction"
	if "tool"       in tags:                             return "Outils"
	var item := ItemRegistry.get_item(recipe.result.get("id", ""))
	if item:
		if "weapon" in item.tags: return "Armes"
		if "armor"  in item.tags: return "Armures"
		if "food"   in item.tags: return "Nourriture"
		if item.tool != "":       return "Outils"
	return "Matériaux"


# ── Recipe grid ────────────────────────────────────────────────────────────────

func _refresh_recipe_grid() -> void:
	for child in _recipe_grid.get_children():
		child.queue_free()
	_card_panels.clear()

	_empty_hint.visible = _filtered_recipes.is_empty()
	var n := _filtered_recipes.size()
	_count_label.text   = "%d recette%s" % [n, "s" if n != 1 else ""]

	for recipe in _filtered_recipes:
		var card := _make_recipe_card(recipe)
		_recipe_grid.add_child(card)
		_card_panels.append(card)


func _make_recipe_card(recipe) -> Panel:
	var craftable := _can_craft(recipe)
	var card := Panel.new()
	card.custom_minimum_size = Vector2(CARD_SIZE, CARD_SIZE)
	card.set_meta("recipe", recipe)
	_style_card(card, false, craftable)

	var icon = ItemIconScript.new()
	icon.size         = Vector2(36, 36)
	icon.position     = Vector2(8, 8)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.item_id      = recipe.result.get("id", "")
	if not craftable:
		icon.modulate = Color(0.55, 0.55, 0.55)
	card.add_child(icon)

	var cnt: int = recipe.result.get("count", 1)
	if cnt > 1:
		var lbl := Label.new()
		lbl.text   = str(cnt)
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.anchor_right  = 1.0; lbl.anchor_bottom  = 1.0
		lbl.offset_right  = -2;  lbl.offset_bottom  = -2
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(lbl)

	card.gui_input.connect(_on_card_input.bind(recipe))
	return card


func _style_card(card: Panel, selected: bool, craftable: bool) -> void:
	var sbf := StyleBoxFlat.new()
	sbf.border_width_left = 1; sbf.border_width_right  = 1
	sbf.border_width_top  = 1; sbf.border_width_bottom = 1
	if selected:
		sbf.bg_color     = Color(0.20, 0.42, 0.20, 0.95)
		sbf.border_color = Color(0.35, 0.85, 0.35)
	elif craftable:
		sbf.bg_color     = Color(0.10, 0.20, 0.10, 0.90)
		sbf.border_color = Color(0.22, 0.52, 0.22)
	else:
		sbf.bg_color     = Color(0.09, 0.09, 0.11, 0.85)
		sbf.border_color = Color(0.28, 0.28, 0.30)
	card.add_theme_stylebox_override("panel", sbf)


func _on_card_input(event: InputEvent, recipe) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_select_recipe(recipe)


# ── Detail panel ───────────────────────────────────────────────────────────────

func _select_recipe(recipe) -> void:
	# Refresh card borders
	for card in _card_panels:
		if not is_instance_valid(card): continue
		var r = card.get_meta("recipe") if card.has_meta("recipe") else null
		_style_card(card, r == recipe, _can_craft(r) if r else false)
		var icon = card.get_child(0)
		if icon and icon.has_method("get"):
			icon.modulate = Color.WHITE if (r == recipe or _can_craft(r)) else Color(0.55, 0.55, 0.55)

	_selected_recipe = recipe

	if recipe == null:
		_clear_detail()
		return
	_refresh_detail()


func _clear_detail() -> void:
	if _detail_icon: _detail_icon.item_id = ""
	if _detail_name: _detail_name.text    = "Sélectionnez une recette"
	_detail_name.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	for child in _ingredients_box.get_children(): child.queue_free()
	if _craft_btn: _craft_btn.disabled = true
	if _table_btn: _table_btn.disabled = not visible


func _refresh_detail() -> void:
	if _selected_recipe == null:
		_clear_detail(); return

	var recipe = _selected_recipe
	var rid: String = recipe.result.get("id", "")
	var item := ItemRegistry.get_item(rid)
	if _detail_icon: _detail_icon.item_id = rid
	if _detail_name:
		var cnt: int = recipe.result.get("count", 1)
		_detail_name.text = (item.display_name if item else rid) + (" ×%d" % cnt if cnt > 1 else "")
		_detail_name.add_theme_color_override("font_color", Color.WHITE)

	for child in _ingredients_box.get_children(): child.queue_free()
	for entry in _collect_ingredients(recipe):
		_add_ingredient_row(entry)

	var craftable := _can_craft(recipe)
	if _craft_btn:
		_craft_btn.disabled = not craftable
		_craft_btn.modulate = Color.WHITE if craftable else Color(0.6, 0.6, 0.6)
	if _table_btn:
		_table_btn.disabled = false


func _add_ingredient_row(entry: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_ingredients_box.add_child(row)

	var icon = ItemIconScript.new()
	icon.custom_minimum_size = Vector2(20, 20)
	icon.size = Vector2(20, 20)
	var spec = entry.get("spec")
	if spec is String:
		icon.item_id = spec
	elif spec is Dictionary and spec.has("tag"):
		icon.item_id = _find_any_with_tag(spec["tag"])
	row.add_child(icon)

	var lbl := Label.new()
	var needed: int = entry.get("count", 1)
	var have: int   = _count_in_inventory(spec)
	var ok          := have >= needed
	var name_str := ""
	if spec is String:
		var it := ItemRegistry.get_item(spec)
		name_str = (it.display_name if it else spec.replace("axiom:", ""))
	elif spec is Dictionary and spec.has("tag"):
		name_str = "[%s]" % spec["tag"]
	lbl.text = "%s  %d/%d" % [name_str, have, needed]
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.25, 0.85, 0.25) if ok else Color(0.90, 0.30, 0.30))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)


# ── Ingredient helpers ─────────────────────────────────────────────────────────

func _collect_ingredients(recipe) -> Array:
	var counts: Dictionary = {}
	var order:  Array      = []
	if recipe.raw.get("type", "shaped") == "shaped" and "grid" in recipe:
		for grid_row in recipe.grid:
			for ing in grid_row:
				if ing == null: continue
				var key: String = JSON.stringify(ing) if ing is Dictionary else str(ing)
				if key not in counts:
					counts[key] = {"spec": ing, "count": 0}
					order.append(key)
				counts[key]["count"] += 1
	else:
		for ing in recipe.raw.get("ingredients", []):
			var key: String = JSON.stringify(ing) if ing is Dictionary else str(ing)
			if key not in counts:
				counts[key] = {"spec": ing, "count": 0}
				order.append(key)
			counts[key]["count"] += 1
	var result: Array = []
	for key in order:
		result.append(counts[key])
	return result


func _count_in_inventory(spec) -> int:
	if _inventory == null: return 0
	var total := 0
	for i in 36:
		var stack := _inventory.get_slot(i)
		if ItemRegistry.is_empty_stack(stack): continue
		if _spec_matches(spec, stack.get("id", "")):
			total += stack.get("count", 0)
	return total


func _spec_matches(spec, item_id: String) -> bool:
	if spec is String:
		return spec == item_id
	if spec is Dictionary and spec.has("tag"):
		var item := ItemRegistry.get_item(item_id)
		return item != null and spec["tag"] in item.tags
	return false


func _find_any_with_tag(tag: String) -> String:
	if _inventory == null: return ""
	for i in 36:
		var stack := _inventory.get_slot(i)
		if ItemRegistry.is_empty_stack(stack): continue
		var item := ItemRegistry.get_item(stack.get("id", ""))
		if item != null and tag in item.tags:
			return stack.get("id", "")
	return ""


func _can_craft(recipe) -> bool:
	if recipe == null or _inventory == null: return false
	for entry in _collect_ingredients(recipe):
		if _count_in_inventory(entry.get("spec")) < entry.get("count", 1):
			return false
	return true


# ── Craft action ───────────────────────────────────────────────────────────────

func _on_craft_pressed() -> void:
	if _selected_recipe == null or not _can_craft(_selected_recipe): return
	_do_craft(_selected_recipe)


func _do_craft(recipe) -> void:
	for entry in _collect_ingredients(recipe):
		var remaining: int = entry.get("count", 1)
		var spec           = entry.get("spec")
		for i in 36:
			if remaining <= 0: break
			var stack := _inventory.get_slot(i)
			if ItemRegistry.is_empty_stack(stack): continue
			if not _spec_matches(spec, stack.get("id", "")): continue
			var take: int = mini(remaining, stack.get("count", 0))
			stack["count"] -= take
			remaining      -= take
			if stack["count"] <= 0: _inventory.set_slot(i, {})
			else:                   _inventory.set_slot(i, stack)

	var res: Dictionary = recipe.result
	_inventory.add_items(res.get("id", ""), res.get("count", 1), {})
	EventBus.item_crafted.emit(res, _player)

	var saved = _selected_recipe
	_apply_filter()
	_select_recipe(saved)


func _on_table_pressed() -> void:
	if _player == null: return
	var recipe = _selected_recipe
	_close()
	EventBus.open_crafting_table_with_recipe.emit(recipe, _player)
