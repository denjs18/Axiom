## EquipmentUI.gd
## RPG character equipment screen — press O to toggle.
## Shows 4 armor slots, weapon slots, active stats and set bonuses.
## Shift+click on armor in inventory to equip; click an equipped slot to unequip.
class_name EquipmentUI
extends CanvasLayer

const SLOT_LABELS := ["🪖  Casque", "🥋  Plastron", "👖  Jambières", "👢  Bottes"]
const SLOT_KEYS   := ["head", "chest", "legs", "feet"]

var _player: Player = null
var _slot_panels: Array[Panel] = []
var _stats_label: Label = null


func _ready() -> void:
	layer   = 13
	visible = false
	_player = GameManager.local_player as Player
	EventBus.player_spawned.connect(func(p: Node) -> void: _player = p as Player)
	_register_input()
	_build_ui()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("open_equipment"):
		if GameManager.current_state != GameManager.GameState.PLAYING:
			return
		visible = not visible
		if visible:
			GameManager.ui_open()
			_refresh()
		else:
			GameManager.ui_close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and visible:
		visible = false
		GameManager.ui_close()
		get_viewport().set_input_as_handled()


func _register_input() -> void:
	if not InputMap.has_action("open_equipment"):
		InputMap.add_action("open_equipment")
		var ev := InputEventKey.new()
		ev.keycode = KEY_O
		InputMap.action_add_event("open_equipment", ev)


# ── UI construction ────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Dim overlay (click-through)
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.45)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	# Main panel — centered, 40% width
	var root := Control.new()
	root.anchor_left   = 0.30; root.anchor_right  = 0.70
	root.anchor_top    = 0.10; root.anchor_bottom = 0.90
	add_child(root)

	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.11, 0.97)
	sb.border_color = Color(0.50, 0.62, 0.92, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	bg.add_theme_stylebox_override("panel", sb)
	root.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("margin_left",   20)
	vbox.add_theme_constant_override("margin_right",  20)
	vbox.add_theme_constant_override("margin_top",    14)
	vbox.add_theme_constant_override("margin_bottom", 14)
	vbox.add_theme_constant_override("separation",     8)
	root.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "⚔   ÉQUIPEMENT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.45))
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	# Two-column layout
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	vbox.add_child(cols)

	_build_armor_column(cols)
	_build_stats_column(cols)

	vbox.add_child(HSeparator.new())

	# Footer hint
	var hint := Label.new()
	hint.text = "O / Échap = fermer  •  Shift+Clic sur l'armure dans l'inventaire (E) pour équiper"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.50, 0.50, 0.56))
	vbox.add_child(hint)

	var close_btn := Button.new()
	close_btn.text = "Fermer  [O]"
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.pressed.connect(func() -> void:
		visible = false
		GameManager.ui_close()
	)
	vbox.add_child(close_btn)


func _build_armor_column(parent: HBoxContainer) -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	parent.add_child(col)

	var lbl := Label.new()
	lbl.text = "🛡  ARMURE ÉQUIPÉE"
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.65, 0.85, 1.00))
	col.add_child(lbl)

	_slot_panels.clear()
	for i in 4:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		col.add_child(row)

		# Label slot name
		var name_lbl := Label.new()
		name_lbl.text = SLOT_LABELS[i]
		name_lbl.custom_minimum_size = Vector2(105, 0)
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.add_theme_color_override("font_color", Color(0.68, 0.72, 0.82))
		row.add_child(name_lbl)

		# Item display panel
		var sp := Panel.new()
		sp.custom_minimum_size = Vector2(0, 40)
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var slot_sb := StyleBoxFlat.new()
		slot_sb.bg_color      = Color(0.11, 0.13, 0.18)
		slot_sb.border_color  = Color(0.32, 0.38, 0.55, 0.90)
		slot_sb.set_border_width_all(1)
		slot_sb.set_corner_radius_all(4)
		sp.add_theme_stylebox_override("panel", slot_sb)
		row.add_child(sp)

		var item_lbl := Label.new()
		item_lbl.name = "ItemLabel"
		item_lbl.text = "— vide —"
		item_lbl.add_theme_font_size_override("font_size", 11)
		item_lbl.add_theme_color_override("font_color", Color(0.35, 0.35, 0.40))
		item_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		item_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		sp.add_child(item_lbl)

		# Unequip button
		var rm := Button.new()
		rm.text = "✕"
		rm.custom_minimum_size = Vector2(30, 30)
		rm.tooltip_text = "Déséquiper (retour dans l'inventaire)"
		rm.add_theme_font_size_override("font_size", 11)
		var slot_i := i
		rm.pressed.connect(func() -> void: _unequip(slot_i))
		row.add_child(rm)

		_slot_panels.append(sp)


func _build_stats_column(parent: HBoxContainer) -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	parent.add_child(col)

	var lbl := Label.new()
	lbl.text = "📊  STATISTIQUES"
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.60, 1.00, 0.65))
	col.add_child(lbl)

	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 12)
	_stats_label.add_theme_color_override("font_color", Color(0.82, 0.88, 0.82))
	_stats_label.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	_stats_label.size_flags_vertical  = Control.SIZE_EXPAND_FILL
	col.add_child(_stats_label)


# ── Data refresh ───────────────────────────────────────────────────────────────

func _refresh() -> void:
	if _player == null: _player = GameManager.local_player as Player
	if _player == null or _player.inventory == null:
		return

	var inv := _player.inventory

	# Update slot panels
	for i in 4:
		var stack: Dictionary = inv.get_armor_slot(i)
		var lbl := _slot_panels[i].get_node("ItemLabel") as Label
		var slot_sb := _slot_panels[i].get_theme_stylebox("panel") as StyleBoxFlat

		if stack.is_empty() or not stack.has("id"):
			lbl.text = "— vide —"
			lbl.add_theme_color_override("font_color", Color(0.35, 0.35, 0.40))
			if slot_sb: slot_sb.border_color = Color(0.32, 0.38, 0.55, 0.90)
		else:
			var item_def := ItemRegistry.get_item(stack["id"])
			var disp: String = item_def.display_name if item_def else stack["id"]
			var armor_val: int = item_def.raw.get("armor", 0) if item_def else 0
			lbl.text = "%s  (+%d 🛡)" % [disp, armor_val]
			lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.45))
			if slot_sb: slot_sb.border_color = Color(0.72, 0.60, 0.20, 0.95)

	# Update stats
	var lines: Array[String] = []

	# Total armor
	lines.append("🛡 Défense totale : %d" % int(_player.armor_value))

	# Per-slot armor
	lines.append("")
	lines.append("Détail par pièce :")
	for i in 4:
		var stack: Dictionary = inv.get_armor_slot(i)
		if stack.is_empty():
			lines.append("  %s  —" % SLOT_LABELS[i])
		else:
			var item_def := ItemRegistry.get_item(stack.get("id", ""))
			var armor_val: int = item_def.raw.get("armor", 0) if item_def else 0
			var name: String = item_def.display_name if item_def else stack.get("id","?")
			lines.append("  %s  %s  (+%d)" % [SLOT_LABELS[i], name, armor_val])

	# Skill bonuses from armor pieces
	var bonus_keys := ["attack_damage", "damage_reduction", "move_speed",
		"sprint_speed", "mining_speed", "jump_mult", "food_regen",
		"fall_damage_mult", "execute_threshold"]
	var bonus_labels := {
		"attack_damage": "Attaque +",   "damage_reduction": "Réduction dégâts +",
		"move_speed":    "Vitesse +",   "sprint_speed": "Sprint +",
		"mining_speed":  "Minage +",    "jump_mult": "Saut +",
		"food_regen":    "Régén. faim +", "fall_damage_mult": "Anti-chute +",
		"execute_threshold": "Exécution seuil +"
	}
	var has_bonus := false
	var bonus_lines: Array[String] = []
	for key in bonus_keys:
		var val := _player._get_armor_bonus(key)
		if val != 0.0:
			has_bonus = true
			bonus_lines.append("  %s%.0f%%" % [bonus_labels.get(key, key), val * 100.0])
	if has_bonus:
		lines.append("")
		lines.append("✦ Bonus actifs :")
		lines.append_array(bonus_lines)

	# Set detection
	var set_name := _detect_active_set(inv)
	if not set_name.is_empty():
		var pieces_on := _count_set_pieces(inv, set_name)
		lines.append("")
		lines.append("🎽 Set '%s' : %d/4 pièces" % [set_name, pieces_on])
		if pieces_on >= 2: lines.append("  ✓ Bonus 2 pièces actif")
		if pieces_on >= 4: lines.append("  ✓ Bonus 4 pièces actif")

	_stats_label.text = "\n".join(lines)


func _detect_active_set(inv: Inventory) -> String:
	var counts: Dictionary = {}
	for i in 4:
		var stack: Dictionary = inv.get_armor_slot(i)
		if stack.is_empty(): continue
		var item_def := ItemRegistry.get_item(stack.get("id", ""))
		if item_def == null: continue
		var set_id: String = item_def.raw.get("set", "")
		if set_id.is_empty(): continue
		counts[set_id] = counts.get(set_id, 0) + 1
	var best := ""
	var best_n := 0
	for s in counts:
		if counts[s] > best_n:
			best_n = counts[s]; best = s
	return best


func _count_set_pieces(inv: Inventory, set_id: String) -> int:
	var n := 0
	for i in 4:
		var stack: Dictionary = inv.get_armor_slot(i)
		if stack.is_empty(): continue
		var item_def := ItemRegistry.get_item(stack.get("id", ""))
		if item_def and item_def.raw.get("set", "") == set_id:
			n += 1
	return n


# ── Equip / unequip ────────────────────────────────────────────────────────────

## Called externally (e.g. from InventoryUI shift+click) to equip an item.
func equip_item(item_id: String, inv_slot: int) -> bool:
	if _player == null: _player = GameManager.local_player as Player
	if _player == null or _player.inventory == null: return false
	var item_def := ItemRegistry.get_item(item_id)
	if item_def == null: return false
	var slot_key: String = item_def.raw.get("slot", "")
	var armor_idx := SLOT_KEYS.find(slot_key)
	if armor_idx < 0: return false   # not an armor item

	var inv := _player.inventory
	var current_equipped: Dictionary = inv.get_armor_slot(armor_idx)

	# Swap: put current armor piece back in inventory if any
	if not current_equipped.is_empty():
		var leftover := inv.add_items(
			current_equipped.get("id",""), current_equipped.get("count",1),
			current_equipped.get("meta",{}))
		if leftover > 0:
			EventBus.show_message.emit("Inventaire plein — impossible d'échanger l'armure.", 3.0)
			return false

	# Equip the new piece and clear its inventory slot
	inv.set_armor_slot(armor_idx, {"id": item_id, "count": 1, "meta": {}})
	inv.set_slot(inv_slot, {})

	if visible: _refresh()
	EventBus.show_message.emit("%s équipé !" % (item_def.display_name if item_def else item_id), 2.5)
	return true


func _unequip(armor_idx: int) -> void:
	if _player == null: _player = GameManager.local_player as Player
	if _player == null or _player.inventory == null: return
	var inv := _player.inventory
	var stack: Dictionary = inv.get_armor_slot(armor_idx)
	if stack.is_empty(): return

	var leftover := inv.add_items(
		stack.get("id",""), stack.get("count",1), stack.get("meta",{}))
	if leftover > 0:
		EventBus.show_message.emit("Inventaire plein — impossible de déséquiper.", 3.0)
		return

	inv.set_armor_slot(armor_idx, {})
	_refresh()
	var item_def := ItemRegistry.get_item(stack.get("id",""))
	var name: String = item_def.display_name if item_def else stack.get("id","?")
	EventBus.show_message.emit("%s retiré → inventaire" % name, 2.0)
