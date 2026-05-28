## SkillTreeUI.gd — RPG skill tree panel, toggled with K.
## Added as a child of Player at runtime via Player._ready().
## Call init(skill_tree) after add_child to populate the UI.
class_name SkillTreeUI
extends CanvasLayer

const CLASSES := [
	{"id": "mineur",    "label": "⛏  MINEUR",    "color": Color(0.95, 0.80, 0.25)},
	{"id": "guerrier",  "label": "⚔  GUERRIER",  "color": Color(0.95, 0.30, 0.30)},
	{"id": "ingenieur", "label": "⚙  INGÉNIEUR", "color": Color(0.35, 0.75, 0.95)},
	{"id": "mage",      "label": "✦  MAGE",       "color": Color(0.80, 0.35, 0.95)},
	{"id": "fermier",   "label": "🌿  FERMIER",   "color": Color(0.30, 0.90, 0.45)},
]

var _skill_tree: SkillTree   = null
var _point_label: Label      = null
var _btn_map: Dictionary     = {}   # skill_id → Button


func _ready() -> void:
	layer   = 15
	visible = false


func init(st: SkillTree) -> void:
	_skill_tree = st
	_build_ui()
	refresh()
	EventBus.skill_unlocked.connect(func(_id: String):   refresh())
	EventBus.skill_point_gained.connect(func(_n: int):   refresh())


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()
		GameManager.ui_open()
	else:
		GameManager.ui_close()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("open_skill_tree") or event.is_action_pressed("ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	if _skill_tree == null or _point_label == null:
		return
	var pts := _skill_tree.available_points
	_point_label.text = "Points disponibles : %d" % pts
	_point_label.add_theme_color_override("font_color",
		Color(0.40, 1.00, 0.50) if pts > 0 else Color(0.70, 0.70, 0.75))
	for skill_id in _btn_map:
		var btn: Button = _btn_map[skill_id]
		var def: Dictionary = _skill_tree.get_skill_def(skill_id)
		_apply_button_style(btn, def, skill_id)


# ── UI construction ────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Dim overlay (click-through)
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	# Main panel
	var panel := PanelContainer.new()
	var sb_panel := StyleBoxFlat.new()
	sb_panel.bg_color    = Color(0.07, 0.07, 0.09, 0.97)
	sb_panel.border_color = Color(0.30, 0.30, 0.40)
	sb_panel.set_border_width_all(2)
	sb_panel.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", sb_panel)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(1080, 660)
	panel.offset_left   = -540
	panel.offset_top    = -330
	panel.offset_right  =  540
	panel.offset_bottom =  330
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   18)
	margin.add_theme_constant_override("margin_right",  18)
	margin.add_theme_constant_override("margin_top",    14)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# ── Header ─────────────────────────────────────────────────────────────────
	var hdr := HBoxContainer.new()
	vbox.add_child(hdr)

	var title := Label.new()
	title.text = "ARBRE DE COMPÉTENCES"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.65))
	hdr.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(spacer)

	_point_label = Label.new()
	_point_label.text = "Points disponibles : 0"
	_point_label.add_theme_font_size_override("font_size", 17)
	hdr.add_child(_point_label)

	# Thin separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# ── Class columns ──────────────────────────────────────────────────────────
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 8)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(cols)

	for cls in CLASSES:
		_build_class_column(cols, cls)

	# ── Footer ─────────────────────────────────────────────────────────────────
	var footer := Label.new()
	footer.text = "K  ou  Echap  pour fermer  —  Cliquer sur un nœud disponible pour débloquer"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color", Color(0.48, 0.48, 0.54))
	footer.add_theme_font_size_override("font_size", 12)
	vbox.add_child(footer)


func _build_class_column(parent: HBoxContainer, cls: Dictionary) -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	parent.add_child(col)

	# Class header
	var lbl := Label.new()
	lbl.text = cls["label"]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", cls["color"])
	col.add_child(lbl)

	# Separator under header
	var sep := HSeparator.new()
	col.add_child(sep)

	var skills := _skill_tree.get_skills_for_class(cls["id"])
	for def in skills:
		col.add_child(_build_skill_button(def))


func _build_skill_button(def: Dictionary) -> Button:
	var skill_id: String = def.get("id", "")
	var btn := Button.new()
	btn.custom_minimum_size    = Vector2(0, 82)
	btn.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	btn.autowrap_mode          = TextServer.AUTOWRAP_WORD_SMART
	btn.alignment              = HORIZONTAL_ALIGNMENT_LEFT

	var tier_tag := "T%d" % def.get("tier", 1)
	var impl: bool = def.get("implemented", false)
	var stub_tag := "" if impl else "  [En développement]"
	btn.text = "%s  %s\n%s%s" % [
		tier_tag,
		def.get("name", skill_id),
		def.get("description", ""),
		stub_tag
	]
	btn.add_theme_font_size_override("font_size", 11)

	_apply_button_style(btn, def, skill_id)

	if impl:
		btn.pressed.connect(_on_skill_pressed.bind(skill_id))
	else:
		btn.focus_mode = Control.FOCUS_NONE

	_btn_map[skill_id] = btn
	return btn


func _apply_button_style(btn: Button, def: Dictionary, skill_id: String) -> void:
	var impl: bool = def.get("implemented", false)

	var bg_col:     Color
	var border_col: Color
	var font_col:   Color
	var is_disabled := false

	if not impl:
		# Stub — always shown as "En développement"
		bg_col     = Color(0.09, 0.09, 0.10)
		border_col = Color(0.22, 0.22, 0.26)
		font_col   = Color(0.38, 0.38, 0.42)
		is_disabled = true
	elif _skill_tree != null and _skill_tree.has_skill(skill_id):
		# Unlocked — green
		bg_col     = Color(0.05, 0.22, 0.08)
		border_col = Color(0.25, 0.82, 0.32)
		font_col   = Color(0.60, 1.00, 0.65)
	elif _skill_tree != null and _skill_tree.can_unlock(skill_id):
		# Available — bright green border
		bg_col     = Color(0.09, 0.15, 0.10)
		border_col = Color(0.28, 0.75, 0.35)
		font_col   = Color(0.92, 1.00, 0.92)
	elif _skill_tree != null and def.get("tier", 1) > 1:
		# Locked — tier prerequisite not yet met
		bg_col     = Color(0.07, 0.07, 0.09)
		border_col = Color(0.20, 0.20, 0.25)
		font_col   = Color(0.45, 0.45, 0.50)
	else:
		# Tier 1 available but no skill points
		bg_col     = Color(0.08, 0.10, 0.08)
		border_col = Color(0.22, 0.30, 0.23)
		font_col   = Color(0.55, 0.65, 0.56)

	var sb_n  := _make_sb(bg_col, border_col, 1)
	var sb_h  := _make_sb(bg_col.lightened(0.05), border_col.lightened(0.12), 2)
	var sb_p  := _make_sb(bg_col.darkened(0.08), border_col, 2)

	btn.add_theme_stylebox_override("normal",   sb_n)
	btn.add_theme_stylebox_override("hover",    sb_h)
	btn.add_theme_stylebox_override("pressed",  sb_p)
	btn.add_theme_stylebox_override("disabled", sb_n)
	btn.add_theme_stylebox_override("focus",    sb_n)

	btn.add_theme_color_override("font_color",          font_col)
	btn.add_theme_color_override("font_hover_color",    font_col.lightened(0.10))
	btn.add_theme_color_override("font_pressed_color",  font_col)
	btn.add_theme_color_override("font_disabled_color", font_col)

	btn.disabled = is_disabled


func _make_sb(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color    = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(4)
	sb.content_margin_left   = 6.0
	sb.content_margin_right  = 6.0
	sb.content_margin_top    = 4.0
	sb.content_margin_bottom = 4.0
	return sb


# ── Input handling ─────────────────────────────────────────────────────────────

func _on_skill_pressed(skill_id: String) -> void:
	if _skill_tree == null:
		return
	if _skill_tree.has_skill(skill_id):
		return
	_skill_tree.unlock(skill_id)
	# refresh() is triggered automatically via skill_unlocked signal
