## MainMenu.gd — Modern landing screen: animated voxel backdrop, hero title,
## modal cards for creating and loading worlds.
extends Control

var _new_world_card: Panel = null
var _load_world_card: Panel = null
var _world_name_edit: LineEdit = null
var _seed_edit: LineEdit = null
var _world_list: ItemList = null
var _modules_box: VBoxContainer = null
var _module_checkboxes: Dictionary = {}
var _creative_check: CheckBox = null
var _flat_check: CheckBox = null

# Drifting decorative cubes in the background
var _cubes: Array = []   # [{node, speed, spin, drift}]


func _ready() -> void:
	UITheme.apply_to_root(self)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_background()
	_build_hero()
	_new_world_card = _build_new_world_card()
	_load_world_card = _build_load_world_card()
	add_child(_new_world_card)
	add_child(_load_world_card)
	_populate_modules()
	_populate_world_list()


func _process(delta: float) -> void:
	var h := size.y
	for c in _cubes:
		var node := c["node"] as Panel
		node.position.y -= c["speed"] * delta
		node.rotation += c["spin"] * delta
		node.position.x += sin(Time.get_ticks_msec() * 0.0002 + c["drift"]) * 0.15
		if node.position.y < -160.0:
			node.position.y = h + 80.0


# ── Background ─────────────────────────────────────────────────────────────────

func _build_background() -> void:
	# Deep vertical gradient
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.030, 0.045, 0.080), Color(0.055, 0.075, 0.115), Color(0.085, 0.110, 0.150)])
	grad.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill_from = Vector2(0, 0)
	grad_tex.fill_to = Vector2(0, 1)
	var bg := TextureRect.new()
	bg.texture = grad_tex
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Drifting translucent voxels
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260714
	var palette := [
		Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.05),
		Color(UITheme.INFO.r, UITheme.INFO.g, UITheme.INFO.b, 0.045),
		Color(1, 1, 1, 0.03),
		Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.04),
	]
	for i in 14:
		var cube := Panel.new()
		var s := rng.randf_range(26.0, 120.0)
		cube.size = Vector2(s, s)
		cube.position = Vector2(rng.randf_range(0, 1900), rng.randf_range(0, 1080))
		cube.rotation = rng.randf_range(0, TAU)
		cube.pivot_offset = cube.size / 2.0
		var style := UITheme.flat(palette[i % palette.size()], int(s * 0.14),
			Color(1, 1, 1, 0.05), 1)
		cube.add_theme_stylebox_override("panel", style)
		cube.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cube)
		_cubes.append({
			"node": cube,
			"speed": rng.randf_range(6.0, 22.0),
			"spin": rng.randf_range(-0.12, 0.12),
			"drift": rng.randf() * TAU,
		})

	# Soft horizon glow band
	var glow := ColorRect.new()
	glow.color = Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.045)
	glow.anchor_top = 0.72
	glow.anchor_bottom = 0.78
	glow.anchor_right = 1.0
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)


# ── Hero (title + main actions) ────────────────────────────────────────────────

func _build_hero() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 110
	col.offset_top = -240
	col.offset_bottom = 240
	col.offset_right = 560
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	# Accent chip + eyebrow
	var eyebrow := HBoxContainer.new()
	eyebrow.add_theme_constant_override("separation", 10)
	col.add_child(eyebrow)
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(26, 26)
	chip.add_theme_stylebox_override("panel", UITheme.flat(UITheme.ACCENT, 7))
	eyebrow.add_child(chip)
	var eb_label := UITheme.caption("SURVIE VOXEL — NOUVELLE GÉNÉRATION", 13)
	eb_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	eyebrow.add_child(eb_label)

	var title := Label.new()
	title.text = "AXIOM"
	title.add_theme_font_size_override("font_size", 108)
	title.add_theme_color_override("font_color", Color(0.97, 0.98, 1.0))
	title.add_theme_constant_override("outline_size", 0)
	col.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Un monde infini. Quatre saisons. Trois dimensions.\nMinez, bâtissez, survivez — puis allez plus loin."
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	col.add_child(subtitle)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	col.add_child(gap)

	var btn_new := UITheme.primary_button("➕  Nouveau monde", Vector2(360, 58))
	btn_new.pressed.connect(func() -> void: _show_card(_new_world_card))
	col.add_child(btn_new)

	var btn_load := Button.new()
	btn_load.text = "🗂  Charger un monde"
	btn_load.custom_minimum_size = Vector2(360, 50)
	btn_load.add_theme_font_size_override("font_size", 16)
	btn_load.pressed.connect(func() -> void:
		_populate_world_list()
		_show_card(_load_world_card))
	col.add_child(btn_load)

	var btn_quit := Button.new()
	btn_quit.text = "Quitter"
	btn_quit.custom_minimum_size = Vector2(360, 42)
	btn_quit.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	btn_quit.pressed.connect(func() -> void: get_tree().quit())
	col.add_child(btn_quit)

	# Version badge (bottom-right)
	var version := UITheme.caption("Axiom 0.2 — fondation vanilla+ : saisons, nouveaux minerais, Nether & End", 11)
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.offset_left = -560
	version.offset_top = -34
	version.offset_right = -16
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(version)


# ── Modal helpers ──────────────────────────────────────────────────────────────

func _make_card(width: float, height: float, title_text: String) -> Panel:
	var card := Panel.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -width / 2
	card.offset_right = width / 2
	card.offset_top = -height / 2
	card.offset_bottom = height / 2
	card.add_theme_stylebox_override("panel", UITheme.card())
	card.visible = false

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 26; vbox.offset_right = -26
	vbox.offset_top = 20;  vbox.offset_bottom = -20
	vbox.add_theme_constant_override("separation", 10)
	card.add_child(vbox)

	var title := UITheme.heading(title_text, 24)
	vbox.add_child(title)
	var sep := HSeparator.new()
	vbox.add_child(sep)
	return card


func _show_card(card: Panel) -> void:
	_new_world_card.visible = card == _new_world_card
	_load_world_card.visible = card == _load_world_card


func _hide_cards() -> void:
	_new_world_card.visible = false
	_load_world_card.visible = false


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_hide_cards()


# ── New world card ─────────────────────────────────────────────────────────────

func _build_new_world_card() -> Panel:
	var card := _make_card(520, 640, "Créer un nouveau monde")
	var vbox := card.get_node("VBox") as VBoxContainer

	vbox.add_child(UITheme.caption("NOM DU MONDE"))
	_world_name_edit = LineEdit.new()
	_world_name_edit.placeholder_text = "Mon Monde"
	_world_name_edit.custom_minimum_size = Vector2(0, 44)
	vbox.add_child(_world_name_edit)

	vbox.add_child(UITheme.caption("GRAINE (VIDE = ALÉATOIRE)"))
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "Aléatoire"
	_seed_edit.custom_minimum_size = Vector2(0, 44)
	vbox.add_child(_seed_edit)

	var opts := UITheme.caption("OPTIONS")
	vbox.add_child(opts)
	_creative_check = CheckBox.new()
	_creative_check.text = "Mode créatif — vol, casse instantanée, blocs illimités"
	vbox.add_child(_creative_check)
	_flat_check = CheckBox.new()
	_flat_check.text = "Monde plat — superflat, idéal pour construire et tester"
	vbox.add_child(_flat_check)

	vbox.add_child(UITheme.caption("MODULES OPTIONNELS (EXPÉRIMENTAL)"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 120)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_modules_box = VBoxContainer.new()
	_modules_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_modules_box)

	var start := UITheme.primary_button("Créer et jouer", Vector2(0, 54))
	start.pressed.connect(_on_start_new_world)
	vbox.add_child(start)

	var cancel := Button.new()
	cancel.text = "Annuler"
	cancel.custom_minimum_size = Vector2(0, 40)
	cancel.pressed.connect(_hide_cards)
	vbox.add_child(cancel)
	return card


# ── Load world card ────────────────────────────────────────────────────────────

func _build_load_world_card() -> Panel:
	var card := _make_card(520, 520, "Charger un monde")
	var vbox := card.get_node("VBox") as VBoxContainer

	_world_list = ItemList.new()
	_world_list.custom_minimum_size = Vector2(0, 290)
	_world_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_world_list.item_activated.connect(func(_i: int) -> void: _on_load_selected_world())
	vbox.add_child(_world_list)

	var load_btn := UITheme.primary_button("Charger le monde sélectionné", Vector2(0, 52))
	load_btn.pressed.connect(_on_load_selected_world)
	vbox.add_child(load_btn)

	var cancel := Button.new()
	cancel.text = "Annuler"
	cancel.custom_minimum_size = Vector2(0, 40)
	cancel.pressed.connect(_hide_cards)
	vbox.add_child(cancel)
	return card


# ── Data ───────────────────────────────────────────────────────────────────────

func _populate_modules() -> void:
	if _modules_box == null:
		return
	for child in _modules_box.get_children():
		child.queue_free()
	_module_checkboxes.clear()
	for mod in ModuleManager.get_all_modules():
		var cb := CheckBox.new()
		cb.text = mod.display_name
		cb.tooltip_text = mod.description
		_modules_box.add_child(cb)
		_module_checkboxes[mod.id] = cb


func _populate_world_list() -> void:
	if _world_list == null:
		return
	_world_list.clear()
	var dir := DirAccess.open("user://worlds/")
	if dir == null:
		return
	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while entry_name != "":
		if dir.current_is_dir() and not entry_name.begins_with("."):
			_world_list.add_item("🌍  " + entry_name)
			_world_list.set_item_metadata(_world_list.item_count - 1, entry_name)
		entry_name = dir.get_next()


func _on_start_new_world() -> void:
	var wname := _world_name_edit.text.strip_edges()
	if wname.is_empty():
		wname = "Monde %d" % (Time.get_unix_time_from_system() as int % 10000)
	var wseed := 0
	if not _seed_edit.text.is_empty():
		wseed = _seed_edit.text.hash()
	var active_mods := []
	for mod_id in _module_checkboxes:
		if _module_checkboxes[mod_id].button_pressed:
			active_mods.append(mod_id)
	var creative: bool = _creative_check.button_pressed
	var gen_type := "flat" if _flat_check.button_pressed else ""
	GameManager.start_new_world(wname, wseed, active_mods, creative, gen_type)


func _on_load_selected_world() -> void:
	var selected := _world_list.get_selected_items()
	if selected.is_empty():
		return
	var meta = _world_list.get_item_metadata(selected[0])
	var wname: String = meta if meta != null else _world_list.get_item_text(selected[0])
	GameManager.load_existing_world(wname)
