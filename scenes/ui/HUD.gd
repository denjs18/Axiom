## HUD.gd
## Main game HUD: hotbar, health, hunger, XP bar, crosshair, debug info.
class_name HUD
extends CanvasLayer

var _player: Player = null
var _hotbar_selected: int = 0

@onready var hotbar_container: HBoxContainer = $Hotbar/HBoxContainer
@onready var hotbar_selector:  Panel         = $Hotbar/Selector
@onready var health_bar:       HBoxContainer = $StatsRow/HealthBar
@onready var hunger_bar:       HBoxContainer = $StatsRow/HungerBar
@onready var xp_bar:           ProgressBar   = $XPBar
@onready var crosshair:        Control       = $Crosshair
@onready var debug_label:      Label         = $DebugLabel
@onready var block_name_label: Label         = $BlockNameLabel
@onready var biome_label:      Label         = $BiomeLabel

var hotbar_slots: Array = []
var _break_bar: ProgressBar = null

const HOTBAR_SIZE := 9
var _debug_timer: float = 0.0

# Blood moon UI
var _blood_moon_label: Label = null
var _blood_moon_warning_timer: float = 0.0

# Generic message UI
var _msg_label: Label = null
var _msg_timer: float = 0.0

# Boss bar UI
var _boss_bar_root: Control   = null
var _boss_bar_fill: ColorRect = null
var _boss_name_label: Label   = null
var _boss_defeat_timer: float = -1.0

# Architect map compass UI
var _map_compass_root:  Control = null
var _map_compass_arrow: Label   = null
var _map_compass_dist:  Label   = null
var _compass_tick: float = 0.0

# Season / weather badge
var _season_badge_root: Control = null
var _season_badge_lbl:  Label   = null

# Artifact info overlay (shown briefly when selecting an artifact in hotbar)
var _artifact_overlay:       Control = null
var _artifact_name_lbl:      Label   = null
var _artifact_bonuses_lbl:   Label   = null
var _artifact_overlay_timer: float   = 0.0

# Quest tracker (bottom-right, shows active quest progress)
var _quest_tracker_root: Control = null
var _quest_tracker_desc: Label   = null
var _quest_tracker_prog: Label   = null

# XP level label (floated above the XP bar)
var _xp_level_label: Label = null


func _ready() -> void:
	if debug_label:
		debug_label.visible = false   # F3 to toggle
	EventBus.player_health_changed.connect(_on_health_changed)
	EventBus.player_hunger_changed.connect(_on_hunger_changed)
	EventBus.player_xp_changed.connect(_on_xp_changed)
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.blood_moon_warning.connect(_on_blood_moon_warning)
	EventBus.blood_moon_started.connect(_on_blood_moon_started)
	EventBus.blood_moon_ended.connect(_on_blood_moon_ended)
	EventBus.show_message.connect(_on_show_message)
	EventBus.boss_engaged.connect(_on_boss_engaged)
	EventBus.boss_health_changed.connect(_on_boss_health_changed)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.quest_accepted.connect(_on_quest_accepted)
	EventBus.quest_progress_updated.connect(_on_quest_progress_updated)
	EventBus.quest_completed.connect(_on_quest_completed)
	_setup_hotbar()
	_setup_xp_bar()
	_setup_crosshair()
	_setup_break_bar()
	_setup_biome_label()
	_setup_blood_moon_label()
	_setup_message_label()
	_setup_boss_bar()
	_setup_map_compass()
	_setup_season_badge()
	_setup_artifact_overlay()
	_setup_quest_tracker()
	_setup_guide_hint()


func _on_player_spawned(player: Player) -> void:
	_player = player
	if _player.inventory:
		_player.inventory.slot_changed.connect(_on_inventory_slot_changed)
	_player.block_targeted.connect(_on_block_targeted)
	_player.no_block_targeted.connect(_on_no_block_targeted)
	_player.block_break_progress.connect(_on_break_progress)
	_player.eating_progress.connect(_on_eating_progress)
	_update_all()


# ── Boss bar ──────────────────────────────────────────────────────────────────

func _setup_boss_bar() -> void:
	_boss_bar_root = Control.new()
	_boss_bar_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_boss_bar_root.offset_top    = 18
	_boss_bar_root.offset_bottom = 54
	_boss_bar_root.visible       = false
	add_child(_boss_bar_root)

	# Background
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.08, 0.08, 0.80)
	_boss_bar_root.add_child(bg)

	# Track (full width, anchored center)
	var track := ColorRect.new()
	track.anchor_left   = 0.15
	track.anchor_right  = 0.85
	track.anchor_top    = 0.55
	track.anchor_bottom = 0.90
	track.color = Color(0.18, 0.05, 0.05, 1.0)
	_boss_bar_root.add_child(track)

	_boss_bar_fill = ColorRect.new()
	_boss_bar_fill.anchor_left   = 0.15
	_boss_bar_fill.anchor_right  = 0.85
	_boss_bar_fill.anchor_top    = 0.55
	_boss_bar_fill.anchor_bottom = 0.90
	_boss_bar_fill.color = Color(0.82, 0.08, 0.08, 1.0)
	_boss_bar_root.add_child(_boss_bar_fill)

	_boss_name_label = Label.new()
	_boss_name_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_boss_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_boss_name_label.offset_bottom = -14
	_boss_name_label.add_theme_font_size_override("font_size", 14)
	_boss_name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.85))
	_boss_bar_root.add_child(_boss_name_label)


func _on_boss_engaged(bname: String, _boss: Node) -> void:
	_boss_defeat_timer = -1.0
	if _boss_name_label:
		_boss_name_label.text = bname
	if _boss_bar_fill:
		_boss_bar_fill.anchor_right = 0.85
	if _boss_bar_root:
		_boss_bar_root.visible = true


func _on_boss_health_changed(bname: String, hp_ratio: float) -> void:
	if _boss_name_label:
		_boss_name_label.text = bname
	if _boss_bar_fill:
		var left  := 0.15
		var right := left + (0.85 - left) * clampf(hp_ratio, 0.0, 1.0)
		_boss_bar_fill.anchor_right = right


func _on_boss_defeated(_bname: String) -> void:
	_boss_defeat_timer = 5.0
	if _boss_bar_fill:
		_boss_bar_fill.anchor_right = 0.15   # empty bar




func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).physical_keycode == KEY_F3 and debug_label:
			debug_label.visible = not debug_label.visible


func _process(delta: float) -> void:
	if _player == null:
		return
	_update_hotbar_selection()
	_tick_blood_moon_label(delta)
	_tick_message_label(delta)
	_tick_boss_bar(delta)
	_update_map_compass(delta)
	_tick_artifact_overlay(delta)
	if debug_label:
		_debug_timer += delta
		if _debug_timer >= 0.1:
			_debug_timer = 0.0
			_update_debug()


# ── Hotbar ─────────────────────────────────────────────────────────────────────

func _setup_hotbar() -> void:
	hotbar_slots.clear()
	if hotbar_container == null:
		push_error("[HUD] hotbar_container is null — check HUD.tscn node paths")
		return
	print("[HUD] _setup_hotbar() — creating %d slots" % HOTBAR_SIZE)

	# Background panel behind all slots
	var bg_panel := Panel.new()
	bg_panel.name = "HotbarBG"
	bg_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg_style := UITheme.flat(Color(0.045, 0.052, 0.075, 0.82), 12,
		Color(0.30, 0.33, 0.42, 0.45), 1)
	bg_panel.add_theme_stylebox_override("panel", bg_style)
	bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hotbar_container.get_parent().add_child(bg_panel)
	hotbar_container.get_parent().move_child(bg_panel, 0)

	for i in HOTBAR_SIZE:
		var slot := _create_hotbar_slot(i)
		hotbar_container.add_child(slot)
		hotbar_slots.append(slot)

	if hotbar_selector:
		var sel_style := UITheme.flat(Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.10),
			9, Color.WHITE, 2)
		hotbar_selector.add_theme_stylebox_override("panel", sel_style)


func _create_hotbar_slot(index: int) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(52, 52)
	panel.name = "Slot%d" % index

	var bg := UITheme.flat(Color(0.075, 0.082, 0.108, 0.90), 8,
		Color(0.32, 0.35, 0.44, 0.55), 1)
	panel.add_theme_stylebox_override("panel", bg)

	# Slot number (1-9, top-left)
	var num_lbl := Label.new()
	num_lbl.name     = "SlotNum"
	num_lbl.text     = str(index + 1) if index < 9 else ""
	num_lbl.position = Vector2(3, 1)
	num_lbl.size     = Vector2(14, 14)
	num_lbl.add_theme_font_size_override("font_size", 10)
	num_lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.75, 0.85))
	num_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.90))
	num_lbl.add_theme_constant_override("shadow_offset_x", 1)
	num_lbl.add_theme_constant_override("shadow_offset_y", 1)
	num_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(num_lbl)

	var icon := ItemIcon.new()
	icon.name         = "Icon"
	icon.size         = Vector2(34, 34)
	icon.position     = Vector2(9, 9)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)

	var lbl := Label.new()
	lbl.name                 = "Count"
	lbl.anchor_right         = 1.0
	lbl.anchor_bottom        = 1.0
	lbl.offset_top           = 32
	lbl.offset_right         = -2
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)
	return panel


func _update_hotbar_selection() -> void:
	if _player == null:
		return
	var new_sel := _player.selected_hotbar_slot
	if new_sel != _hotbar_selected:
		_hotbar_selected = new_sel
		_move_hotbar_selector()
		_show_artifact_for_slot(new_sel)


func _move_hotbar_selector() -> void:
	if hotbar_slots.is_empty() or hotbar_selector == null:
		return
	var slot: Control = hotbar_slots[_hotbar_selected]
	hotbar_selector.position = slot.position - Vector2(3, 3)
	hotbar_selector.size     = slot.size + Vector2(6, 6)


func _on_inventory_slot_changed(slot_index: int, new_stack: Dictionary) -> void:
	if slot_index >= HOTBAR_SIZE:
		return
	_update_hotbar_slot(slot_index, new_stack)


func _update_hotbar_slot(index: int, stack: Dictionary) -> void:
	if index >= hotbar_slots.size():
		return
	var slot_panel: Control = hotbar_slots[index]
	var icon       := slot_panel.get_node_or_null("Icon")  as ItemIcon
	var count_lbl  := slot_panel.get_node_or_null("Count") as Label
	if ItemRegistry.is_empty_stack(stack):
		if icon:      icon.item_id    = ""
		if count_lbl: count_lbl.text  = ""
	else:
		if icon:      icon.item_id    = stack.get("id", "")
		if count_lbl:
			var cnt: int = stack.get("count", 0)
			count_lbl.text = str(cnt) if cnt > 1 else ""


func _update_all() -> void:
	if _player == null:
		return
	_on_health_changed(_player, _player.health, _player.max_health)
	_on_hunger_changed(_player, _player.hunger, _player.saturation)
	_on_xp_changed(_player, _player.xp_points, _player.xp_level)
	for i in HOTBAR_SIZE:
		if _player.inventory:
			_update_hotbar_slot(i, _player.inventory.get_hotbar_item(i))
	_move_hotbar_selector()


# ── Health / Hunger ────────────────────────────────────────────────────────────

func _on_health_changed(player: Player, new_health: float, max_health: float) -> void:
	if player != _player or health_bar == null:
		return
	_update_icon_bar(health_bar, new_health, max_health, "health")


func _on_hunger_changed(player: Player, new_hunger: float, _sat: float) -> void:
	if player != _player or hunger_bar == null:
		return
	_update_icon_bar(hunger_bar, new_hunger, 20.0, "hunger")


# Icon textures (hearts from assets, hunger shanks generated once)
static var _heart_tex: Array = []    # [full, half, empty]
static var _shank_tex: Array = []

func _ensure_icon_textures() -> void:
	# Icons are generated procedurally: PNG resources fail to load on the web
	# export (no ResourceImporter → "expected CompressedTexture2D").
	if _heart_tex.is_empty():
		_heart_tex = [_draw_heart(1.0), _draw_heart(0.5), _draw_heart(0.0)]
	if _shank_tex.is_empty():
		_shank_tex = [_draw_shank(1.0), _draw_shank(0.5), _draw_shank(0.0)]


## 16×16 pixel-art heart (Minecraft-style health icon). fill: 1=full, .5=half, 0=empty.
func _draw_heart(fill: float) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var red   := Color8(220, 40, 48)
	var red2  := Color8(178, 26, 36)
	var shine := Color8(255, 150, 150)
	var dark  := Color8(70, 12, 16)
	var empty := Color8(48, 22, 24)
	var empty2 := Color8(36, 16, 18)
	# Heart mask: two lobes on top, tapering to a point at the bottom.
	for y in 16:
		for x in 16:
			var inside := _heart_pixel(x, y)
			if not inside:
				continue
			var col: Color
			if fill <= 0.0:
				col = empty if (x + y) % 2 == 0 else empty2
			elif fill < 1.0 and x >= 8:
				# Right half drained (half heart)
				col = empty if (x + y) % 2 == 0 else empty2
			else:
				col = red if (x + y) % 4 != 0 else red2
			img.set_pixel(x, y, col)
	# Outline + highlight only on the lit portion
	for y in 16:
		for x in 16:
			if not _heart_pixel(x, y):
				continue
			# Outline where a neighbour is outside the mask
			if not _heart_pixel(x - 1, y) or not _heart_pixel(x + 1, y) \
					or not _heart_pixel(x, y - 1) or not _heart_pixel(x, y + 1):
				img.set_pixel(x, y, dark)
	# Specular sparkle on the top-left lobe (full / left-half only)
	if fill > 0.0:
		img.set_pixel(4, 4, shine)
		img.set_pixel(5, 4, shine)
		img.set_pixel(4, 5, shine.darkened(0.15))
	return ImageTexture.create_from_image(img)


## Classic 16×16 heart silhouette test.
func _heart_pixel(x: int, y: int) -> bool:
	if x < 0 or x > 15 or y < 0 or y > 15:
		return false
	# Per-row spans (inclusive) describing the heart shape.
	var spans := [
		[],                # 0
		[[3, 6], [9, 12]], # 1
		[[2, 7], [8, 13]], # 2
		[[2, 13]],         # 3
		[[2, 13]],         # 4
		[[2, 13]],         # 5
		[[2, 13]],         # 6
		[[3, 12]],         # 7
		[[3, 12]],         # 8
		[[4, 11]],         # 9
		[[5, 10]],         # 10
		[[6, 9]],          # 11
		[[7, 8]],          # 12
		[], [], [],        # 13-15
	]
	for span in spans[y]:
		if x >= span[0] and x <= span[1]:
			return true
	return false


## 16×16 pixel-art meat shank (Minecraft-style hunger icon).
func _draw_shank(fill: float) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var meat  := Color8(188, 100, 40)
	var meat2 := Color8(150, 74, 28)
	var bone  := Color8(228, 224, 210)
	var dark  := Color8(60, 38, 20)
	if fill < 0.25:
		meat = Color8(52, 52, 56); meat2 = Color8(40, 40, 44)
		bone = Color8(70, 70, 74); dark = Color8(30, 30, 34)
	elif fill < 0.75:
		meat = meat.darkened(0.35); meat2 = meat2.darkened(0.35)
	# Meat blob (top-right)
	for y in range(2, 9):
		for x in range(6, 13):
			var dx := x - 9.0; var dy := y - 5.0
			if dx * dx + dy * dy <= 11.0:
				img.set_pixel(x, y, meat if (x + y) % 3 != 0 else meat2)
	# Outline bottom of meat
	for x in range(6, 12):
		img.set_pixel(x, 8, dark)
	# Bone diagonal (bottom-left)
	for i in range(0, 6):
		var bx := 3 + i; var by := 12 - i
		img.set_pixel(bx, by, bone)
		if bx + 1 < 16:
			img.set_pixel(bx + 1, by, bone.darkened(0.15))
	# Bone knob
	img.set_pixel(2, 12, bone); img.set_pixel(3, 13, bone)
	img.set_pixel(2, 13, bone.darkened(0.1))
	return ImageTexture.create_from_image(img)


func _update_icon_bar(container: HBoxContainer, value: float, max_val: float, type: String) -> void:
	_ensure_icon_textures()
	var full_icons  := floori(value / 2.0)
	var half        := (fmod(value, 2.0) >= 1.0)
	var total_icons := floori(max_val / 2.0)
	var texs: Array = _heart_tex if type == "health" else _shank_tex

	while container.get_child_count() < total_icons:
		var t := TextureRect.new()
		t.custom_minimum_size = Vector2(20, 20)
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(t)
	while container.get_child_count() > total_icons:
		var last := container.get_child(container.get_child_count() - 1)
		container.remove_child(last)
		last.queue_free()

	for i in total_icons:
		var t := container.get_child(i) as TextureRect
		if t == null:
			continue
		if i < full_icons:
			t.texture = texs[0]
		elif i == full_icons and half:
			t.texture = texs[1]
		else:
			t.texture = texs[2]


# ── XP bar ─────────────────────────────────────────────────────────────────────

func _setup_xp_bar() -> void:
	if xp_bar == null:
		return
	xp_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.35, 0.90, 0.10)
	xp_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.05, 0.75)
	xp_bar.add_theme_stylebox_override("background", bg)

	# Level label centred over the XP bar
	_xp_level_label = Label.new()
	_xp_level_label.name = "XPLevelLabel"
	_xp_level_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_xp_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_level_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_xp_level_label.text = "Niv. 0"
	_xp_level_label.add_theme_font_size_override("font_size", 11)
	_xp_level_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	_xp_level_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_xp_level_label.add_theme_constant_override("shadow_offset_x", 1)
	_xp_level_label.add_theme_constant_override("shadow_offset_y", 1)
	_xp_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_bar.add_child(_xp_level_label)


func _on_xp_changed(player: Player, points: int, level: int) -> void:
	if player != _player or xp_bar == null:
		return
	var next := _xp_for_next_level(level)
	xp_bar.value = float(points) / float(next) if next > 0 else 0.0
	if _xp_level_label:
		_xp_level_label.text = "Niv. %d" % level


func _xp_for_next_level(level: int) -> int:
	if level <= 16:   return 2 * level + 7
	elif level <= 31: return 5 * level - 38
	else:             return 9 * level - 158


# ── Block name label ───────────────────────────────────────────────────────────

func _on_block_targeted(block_pos: Vector3i, block_id: int) -> void:
	if block_name_label == null:
		return
	var block := BlockRegistry.get_block(block_id)
	block_name_label.text    = block.display_name if block else ""
	block_name_label.visible = true


func _on_no_block_targeted() -> void:
	if block_name_label:
		block_name_label.visible = false


# ── Debug ──────────────────────────────────────────────────────────────────────

func _update_debug() -> void:
	if _player == null or debug_label == null:
		return
	var pos       := _player.global_position
	var chunk_pos := Vector2i(floori(pos.x / 16), floori(pos.z / 16))
	var lod_info  := ""
	var world     := GameManager.world_node
	if world and world.get("lod_manager") != null and world.lod_manager != null:
		lod_info = "\n" + world.lod_manager.get_debug_info()
	debug_label.text = "XYZ: %.1f / %.1f / %.1f\nChunk: %d, %d\nFPS: %d\nDim: %s%s" % [
		pos.x, pos.y, pos.z,
		chunk_pos.x, chunk_pos.y,
		Engine.get_frames_per_second(),
		GameManager.current_dimension,
		lod_info
	]
	_update_biome_display(pos)


# ── Biome display ──────────────────────────────────────────────────────────────

func _setup_biome_label() -> void:
	if biome_label == null:
		return
	biome_label.add_theme_font_size_override("font_size", 13)
	biome_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.85))
	biome_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	biome_label.add_theme_constant_override("shadow_offset_x", 1)
	biome_label.add_theme_constant_override("shadow_offset_y", 1)


var _last_biome_id: String = ""
var _biome_fade_timer: float = 0.0

func _update_biome_display(pos: Vector3) -> void:
	if biome_label == null:
		return
	var world := GameManager.world_node
	if world == null:
		return
	var wg = world.get("world_generator")
	if wg == null:
		return
	var biome_id: String = wg.get_biome_at(pos.x, pos.z)
	if biome_id != _last_biome_id:
		_last_biome_id = biome_id
		_biome_fade_timer = 5.0   # show for 5 seconds when entering new biome
		var biome := BiomeRegistry.get_biome(biome_id)
		biome_label.text = biome.display_name if biome else biome_id.split(":")[-1].capitalize()
	_biome_fade_timer -= 0.1    # decremented each debug tick (every 0.1s)
	if _biome_fade_timer > 0.0:
		biome_label.modulate.a = minf(1.0, _biome_fade_timer)
		biome_label.visible = true
	else:
		biome_label.visible = false


# ── Crosshair ──────────────────────────────────────────────────────────────────

func _setup_crosshair() -> void:
	if crosshair == null:
		return
	var h := ColorRect.new()
	h.color        = Color(1, 1, 1, 0.85)
	h.size         = Vector2(14, 2)
	h.position     = Vector2(1, 7)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.add_child(h)
	var v := ColorRect.new()
	v.color        = Color(1, 1, 1, 0.85)
	v.size         = Vector2(2, 14)
	v.position     = Vector2(7, 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.add_child(v)


# ── Break progress bar ─────────────────────────────────────────────────────────

func _setup_break_bar() -> void:
	_break_bar               = ProgressBar.new()
	_break_bar.anchor_left   = 0.5
	_break_bar.anchor_right  = 0.5
	_break_bar.anchor_top    = 0.5
	_break_bar.anchor_bottom = 0.5
	_break_bar.offset_left   = -60
	_break_bar.offset_right  = 60
	_break_bar.offset_top    = 22
	_break_bar.offset_bottom = 34
	_break_bar.min_value     = 0.0
	_break_bar.max_value     = 1.0
	_break_bar.value         = 0.0
	_break_bar.visible       = false
	_break_bar.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(_break_bar)


func _on_break_progress(progress: float) -> void:
	if _break_bar == null:
		return
	_break_bar.modulate = Color.WHITE
	_break_bar.value    = progress
	_break_bar.visible  = progress > 0.01


func _on_eating_progress(progress: float) -> void:
	if _break_bar == null:
		return
	_break_bar.modulate = Color(1.0, 0.75, 0.35)   # amber while eating
	_break_bar.value    = progress
	_break_bar.visible  = progress > 0.01


# ── Blood Moon UI ──────────────────────────────────────────────────────────────

func _setup_blood_moon_label() -> void:
	_blood_moon_label = Label.new()
	_blood_moon_label.name             = "BloodMoonLabel"
	_blood_moon_label.anchor_left      = 0.5
	_blood_moon_label.anchor_right     = 0.5
	_blood_moon_label.anchor_top       = 0.0
	_blood_moon_label.anchor_bottom    = 0.0
	_blood_moon_label.offset_left      = -250
	_blood_moon_label.offset_right     = 250
	_blood_moon_label.offset_top       = 55
	_blood_moon_label.offset_bottom    = 95
	_blood_moon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_blood_moon_label.add_theme_font_size_override("font_size", 22)
	_blood_moon_label.add_theme_color_override("font_color", Color(0.90, 0.10, 0.10))
	_blood_moon_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_blood_moon_label.add_theme_constant_override("shadow_offset_x", 2)
	_blood_moon_label.add_theme_constant_override("shadow_offset_y", 2)
	_blood_moon_label.visible = false
	add_child(_blood_moon_label)


func _on_blood_moon_warning() -> void:
	if _blood_moon_label == null:
		return
	_blood_moon_label.text    = "La lune semble d'un rouge inquietant..."
	_blood_moon_label.visible = true
	_blood_moon_warning_timer = 7.0


func _on_blood_moon_started(_day: int) -> void:
	if _blood_moon_label == null:
		return
	_blood_moon_warning_timer = 0.0
	_blood_moon_label.text    = "LUNE DE SANG"
	_blood_moon_label.visible = true


func _on_blood_moon_ended() -> void:
	if _blood_moon_label:
		_blood_moon_label.visible = false


func _tick_blood_moon_label(delta: float) -> void:
	if _blood_moon_warning_timer <= 0.0:
		return
	_blood_moon_warning_timer -= delta
	if _blood_moon_warning_timer <= 0.0 and not TimeManager.is_blood_moon:
		if _blood_moon_label:
			_blood_moon_label.visible = false


# ── Generic message label ──────────────────────────────────────────────────────

func _setup_message_label() -> void:
	_msg_label = Label.new()
	_msg_label.name             = "MessageLabel"
	_msg_label.anchor_left      = 0.5
	_msg_label.anchor_right     = 0.5
	_msg_label.anchor_top       = 0.0
	_msg_label.anchor_bottom    = 0.0
	_msg_label.offset_left      = -300
	_msg_label.offset_right     = 300
	_msg_label.offset_top       = 100
	_msg_label.offset_bottom    = 135
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_label.add_theme_font_size_override("font_size", 18)
	_msg_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.20))
	_msg_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_msg_label.add_theme_constant_override("shadow_offset_x", 2)
	_msg_label.add_theme_constant_override("shadow_offset_y", 2)
	_msg_label.visible = false
	add_child(_msg_label)


func _on_show_message(text: String, duration: float) -> void:
	if _msg_label == null:
		return
	_msg_label.text    = text
	_msg_label.visible = true
	_msg_timer = duration


func _tick_message_label(delta: float) -> void:
	if _msg_timer <= 0.0:
		return
	_msg_timer -= delta
	if _msg_timer <= 0.0 and _msg_label != null:
		_msg_label.visible = false


# ── Season / weather badge ─────────────────────────────────────────────────────

func _setup_season_badge() -> void:
	_season_badge_root = Control.new()
	_season_badge_root.name           = "SeasonBadge"
	_season_badge_root.anchor_left    = 0.0
	_season_badge_root.anchor_right   = 0.0
	_season_badge_root.anchor_top     = 1.0
	_season_badge_root.anchor_bottom  = 1.0
	_season_badge_root.offset_left    = 10
	_season_badge_root.offset_right   = 230
	_season_badge_root.offset_top     = -144
	_season_badge_root.offset_bottom  = -118
	_season_badge_root.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	add_child(_season_badge_root)

	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg_s := StyleBoxFlat.new()
	bg_s.bg_color                    = Color(0.06, 0.06, 0.08, 0.78)
	bg_s.corner_radius_top_left      = 4
	bg_s.corner_radius_top_right     = 4
	bg_s.corner_radius_bottom_left   = 4
	bg_s.corner_radius_bottom_right  = 4
	bg.add_theme_stylebox_override("panel", bg_s)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_season_badge_root.add_child(bg)

	_season_badge_lbl = Label.new()
	_season_badge_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_season_badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_season_badge_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_season_badge_lbl.add_theme_font_size_override("font_size", 13)
	_season_badge_lbl.add_theme_color_override("font_color", Color.WHITE)
	_season_badge_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_season_badge_root.add_child(_season_badge_lbl)

	EventBus.season_changed.connect(func(_s: int) -> void: _refresh_season_badge())
	EventBus.weather_changed.connect(func(_w: int) -> void: _refresh_season_badge())
	_refresh_season_badge()


func _refresh_season_badge() -> void:
	if _season_badge_lbl == null:
		return
	var day  := SeasonManager.day_in_season + 1
	_season_badge_lbl.text = "%s %s  J.%d/5  %s" % [
		SeasonManager.get_season_icon(),
		SeasonManager.get_season_name(),
		day,
		SeasonManager.get_weather_icon(),
	]
	var col: Color
	match SeasonManager.current_season:
		SeasonManager.Season.SPRING:  col = Color(0.70, 1.00, 0.70)
		SeasonManager.Season.SUMMER:  col = Color(1.00, 0.95, 0.50)
		SeasonManager.Season.AUTUMN:  col = Color(1.00, 0.65, 0.22)
		SeasonManager.Season.WINTER:  col = Color(0.75, 0.88, 1.00)
		_:                            col = Color.WHITE
	_season_badge_lbl.add_theme_color_override("font_color", col)


# ── Artifact info overlay ──────────────────────────────────────────────────────

func _setup_artifact_overlay() -> void:
	_artifact_overlay = Control.new()
	_artifact_overlay.name           = "ArtifactOverlay"
	_artifact_overlay.anchor_left    = 0.5
	_artifact_overlay.anchor_right   = 0.5
	_artifact_overlay.anchor_top     = 1.0
	_artifact_overlay.anchor_bottom  = 1.0
	_artifact_overlay.offset_left    = -210
	_artifact_overlay.offset_right   = 210
	_artifact_overlay.offset_top     = -202
	_artifact_overlay.offset_bottom  = -114
	_artifact_overlay.visible        = false
	_artifact_overlay.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	add_child(_artifact_overlay)

	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg_s := StyleBoxFlat.new()
	bg_s.bg_color                    = Color(0.05, 0.04, 0.10, 0.88)
	bg_s.border_width_left           = 1
	bg_s.border_width_right          = 1
	bg_s.border_width_top            = 1
	bg_s.border_width_bottom         = 1
	bg_s.border_color                = Color(0.70, 0.55, 0.10, 0.95)
	bg_s.corner_radius_top_left      = 5
	bg_s.corner_radius_top_right     = 5
	bg_s.corner_radius_bottom_left   = 5
	bg_s.corner_radius_bottom_right  = 5
	bg.add_theme_stylebox_override("panel", bg_s)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_artifact_overlay.add_child(bg)

	_artifact_name_lbl = Label.new()
	_artifact_name_lbl.anchor_left           = 0.0
	_artifact_name_lbl.anchor_right          = 1.0
	_artifact_name_lbl.anchor_top            = 0.0
	_artifact_name_lbl.anchor_bottom         = 0.0
	_artifact_name_lbl.offset_top            = 6
	_artifact_name_lbl.offset_bottom         = 28
	_artifact_name_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	_artifact_name_lbl.add_theme_font_size_override("font_size", 15)
	_artifact_name_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.20))
	_artifact_name_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_artifact_name_lbl.add_theme_constant_override("shadow_offset_x", 1)
	_artifact_name_lbl.add_theme_constant_override("shadow_offset_y", 1)
	_artifact_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_artifact_overlay.add_child(_artifact_name_lbl)

	_artifact_bonuses_lbl = Label.new()
	_artifact_bonuses_lbl.anchor_left           = 0.0
	_artifact_bonuses_lbl.anchor_right          = 1.0
	_artifact_bonuses_lbl.anchor_top            = 0.0
	_artifact_bonuses_lbl.anchor_bottom         = 1.0
	_artifact_bonuses_lbl.offset_top            = 30
	_artifact_bonuses_lbl.offset_bottom         = -4
	_artifact_bonuses_lbl.offset_left           = 8
	_artifact_bonuses_lbl.offset_right          = -8
	_artifact_bonuses_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	_artifact_bonuses_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_TOP
	_artifact_bonuses_lbl.autowrap_mode         = TextServer.AUTOWRAP_WORD_SMART
	_artifact_bonuses_lbl.add_theme_font_size_override("font_size", 12)
	_artifact_bonuses_lbl.add_theme_color_override("font_color", Color(0.78, 0.92, 0.78))
	_artifact_bonuses_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_artifact_overlay.add_child(_artifact_bonuses_lbl)


func _show_artifact_for_slot(slot: int) -> void:
	if _artifact_overlay == null or _player == null or _player.inventory == null:
		return
	var stack := _player.inventory.get_hotbar_item(slot)
	if not stack.has("artifact_name"):
		_artifact_overlay.visible = false
		_artifact_overlay_timer   = 0.0
		return

	var rarity_name: String = stack.get("artifact_rarity_name", "Rare")
	var rarity_col := Color(0.72, 0.40, 1.0)   # purple — Rare default
	match stack.get("artifact_rarity", 1):
		2: rarity_col = Color(0.40, 0.60, 1.0)  # blue — Épique
		3: rarity_col = Color(1.0, 0.85, 0.20)  # gold — Légendaire

	_artifact_name_lbl.text = stack["artifact_name"]
	_artifact_name_lbl.add_theme_color_override("font_color", rarity_col)

	var bonus_lines := "[%s]\n" % rarity_name
	for b in stack.get("artifact_bonuses", []):
		bonus_lines += "· %s\n" % ArtifactGenerator.format_bonus(b)
	_artifact_bonuses_lbl.text = bonus_lines.strip_edges()

	_artifact_overlay.modulate.a = 1.0
	_artifact_overlay.visible   = true
	_artifact_overlay_timer     = 4.0


func _tick_artifact_overlay(delta: float) -> void:
	if _artifact_overlay == null or not _artifact_overlay.visible:
		return
	_artifact_overlay_timer -= delta
	if _artifact_overlay_timer <= 0.0:
		_artifact_overlay.visible = false
	elif _artifact_overlay_timer < 1.0:
		_artifact_overlay.modulate.a = _artifact_overlay_timer   # fade out last second


# ── Architect map compass ──────────────────────────────────────────────────────

func _setup_map_compass() -> void:
	_map_compass_root = Control.new()
	_map_compass_root.name           = "MapCompass"
	_map_compass_root.anchor_left    = 1.0
	_map_compass_root.anchor_right   = 1.0
	_map_compass_root.anchor_top     = 0.0
	_map_compass_root.anchor_bottom  = 0.0
	_map_compass_root.offset_left    = -220
	_map_compass_root.offset_right   = -20
	_map_compass_root.offset_top     = 20
	_map_compass_root.offset_bottom  = 90
	_map_compass_root.visible        = false
	_map_compass_root.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	add_child(_map_compass_root)

	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color                    = Color(0.06, 0.04, 0.10, 0.84)
	bg_style.border_width_left           = 1
	bg_style.border_width_right          = 1
	bg_style.border_width_top            = 1
	bg_style.border_width_bottom         = 1
	bg_style.border_color                = Color(0.55, 0.30, 0.85, 0.90)
	bg_style.corner_radius_top_left      = 5
	bg_style.corner_radius_top_right     = 5
	bg_style.corner_radius_bottom_left   = 5
	bg_style.corner_radius_bottom_right  = 5
	bg.add_theme_stylebox_override("panel", bg_style)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_compass_root.add_child(bg)

	_map_compass_arrow = Label.new()
	_map_compass_arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_compass_arrow.offset_bottom        = -26
	_map_compass_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_compass_arrow.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_map_compass_arrow.add_theme_font_size_override("font_size", 30)
	_map_compass_arrow.add_theme_color_override("font_color", Color(0.78, 0.55, 1.0))
	_map_compass_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_compass_root.add_child(_map_compass_arrow)

	_map_compass_dist = Label.new()
	_map_compass_dist.anchor_left           = 0.0
	_map_compass_dist.anchor_right          = 1.0
	_map_compass_dist.anchor_top            = 1.0
	_map_compass_dist.anchor_bottom         = 1.0
	_map_compass_dist.offset_top            = -24
	_map_compass_dist.offset_bottom         = -2
	_map_compass_dist.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	_map_compass_dist.add_theme_font_size_override("font_size", 12)
	_map_compass_dist.add_theme_color_override("font_color", Color(0.85, 0.80, 1.0, 0.92))
	_map_compass_dist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_compass_root.add_child(_map_compass_dist)


func _update_map_compass(delta: float) -> void:
	if _map_compass_root == null or _player == null:
		return

	var holding_map := false
	if _player.inventory:
		var stack := _player.inventory.get_hotbar_item(_player.selected_hotbar_slot)
		holding_map = not ItemRegistry.is_empty_stack(stack) and stack.get("id", "") == "axiom:architect_map"

	_map_compass_root.visible = holding_map
	if not holding_map:
		_compass_tick = 0.0
		return

	_compass_tick += delta
	if _compass_tick < 0.5:
		return
	_compass_tick = 0.0

	var archives := GameManager.get_archives_location()
	var ppos     := _player.global_position
	var dx       := float(archives.x) - ppos.x
	var dz       := float(archives.y) - ppos.z

	var dist := int(Vector2(dx, dz).length())

	# atan2(dz,dx): east=0, north=-PI/2. Adding PI/2 rotates north→0.
	# Sectors: 0=↑N  1=↗NE  2=→E  3=↘SE  4=↓S  5=↙SW  6=←W  7=↖NW
	var arrows    := ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]
	var angle     := atan2(dz, dx)
	var norm      := fmod(angle + PI * 0.5 + TAU, TAU)
	var sector    := int(round(norm / (TAU / 8.0))) % 8

	_map_compass_arrow.text = arrows[sector]
	_map_compass_dist.text  = "Archives : %dm" % dist


func _tick_boss_bar(delta: float) -> void:
	if _boss_defeat_timer < 0.0:
		return
	_boss_defeat_timer -= delta
	if _boss_defeat_timer <= 0.0 and _boss_bar_root != null:
		_boss_bar_root.visible = false
		_boss_defeat_timer = -1.0


# ── Quest tracker ──────────────────────────────────────────────────────────────

func _setup_quest_tracker() -> void:
	_quest_tracker_root = Control.new()
	_quest_tracker_root.name           = "QuestTracker"
	_quest_tracker_root.anchor_left    = 1.0
	_quest_tracker_root.anchor_right   = 1.0
	_quest_tracker_root.anchor_top     = 1.0
	_quest_tracker_root.anchor_bottom  = 1.0
	_quest_tracker_root.offset_left    = -264
	_quest_tracker_root.offset_right   = -10
	_quest_tracker_root.offset_top     = -234   # above hotbar + XP bar
	_quest_tracker_root.offset_bottom  = -126
	_quest_tracker_root.visible        = false
	_quest_tracker_root.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	add_child(_quest_tracker_root)

	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var s := StyleBoxFlat.new()
	s.bg_color                   = Color(0.06, 0.06, 0.04, 0.80)
	s.border_width_left          = 2; s.border_width_right  = 2
	s.border_width_top           = 2; s.border_width_bottom = 2
	s.border_color               = Color(0.65, 0.50, 0.15, 0.90)
	s.corner_radius_top_left     = 4; s.corner_radius_top_right    = 4
	s.corner_radius_bottom_left  = 4; s.corner_radius_bottom_right = 4
	bg.add_theme_stylebox_override("panel", s)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quest_tracker_root.add_child(bg)

	var title_lbl := Label.new()
	title_lbl.anchor_left  = 0.0; title_lbl.anchor_right  = 1.0
	title_lbl.offset_left  = 8;   title_lbl.offset_top    = 6
	title_lbl.offset_bottom = 24
	title_lbl.text = "⚑ Quête active"
	title_lbl.add_theme_font_size_override("font_size", 11)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.20))
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quest_tracker_root.add_child(title_lbl)

	_quest_tracker_desc = Label.new()
	_quest_tracker_desc.anchor_left  = 0.0; _quest_tracker_desc.anchor_right  = 1.0
	_quest_tracker_desc.offset_left  = 8;   _quest_tracker_desc.offset_top    = 26
	_quest_tracker_desc.offset_right = -8;  _quest_tracker_desc.offset_bottom = 58
	_quest_tracker_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_tracker_desc.add_theme_font_size_override("font_size", 12)
	_quest_tracker_desc.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	_quest_tracker_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quest_tracker_root.add_child(_quest_tracker_desc)

	_quest_tracker_prog = Label.new()
	_quest_tracker_prog.anchor_left  = 0.0; _quest_tracker_prog.anchor_right  = 1.0
	_quest_tracker_prog.offset_left  = 8;   _quest_tracker_prog.offset_top    = 60
	_quest_tracker_prog.offset_bottom = 80
	_quest_tracker_prog.add_theme_font_size_override("font_size", 12)
	_quest_tracker_prog.add_theme_color_override("font_color", Color(0.55, 0.92, 0.55))
	_quest_tracker_prog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quest_tracker_root.add_child(_quest_tracker_prog)


func _on_quest_accepted(quest: Dictionary) -> void:
	if _quest_tracker_root == null:
		return
	# Reset progress label color in case previous quest was "ready to turn in"
	_quest_tracker_prog.add_theme_color_override("font_color", Color(0.55, 0.92, 0.55))
	var raw: String = quest.get("desc", "")
	_quest_tracker_desc.text = raw.replace("{count}", str(quest.get("count", 1)))
	_quest_tracker_prog.text = "0 / %d" % quest.get("count", 1)
	_quest_tracker_root.visible = true


func _on_quest_progress_updated(quest: Dictionary) -> void:
	if _quest_tracker_prog == null:
		return
	var current: int = quest.get("progress", 0)
	var needed:  int = quest.get("count", 1)
	_quest_tracker_prog.text = "%d / %d" % [current, needed]
	if current >= needed:
		_quest_tracker_prog.add_theme_color_override("font_color", Color(0.30, 1.00, 0.30))
		_quest_tracker_prog.text = "%d / %d  ✓ Prêt !" % [current, needed]


func _on_quest_completed(_quest: Dictionary, _rewards: Dictionary) -> void:
	if _quest_tracker_root == null:
		return
	_quest_tracker_root.visible = false
	_quest_tracker_prog.add_theme_color_override("font_color", Color(0.55, 0.92, 0.55))


# ── Guide hint button ──────────────────────────────────────────────────────────

func _setup_guide_hint() -> void:
	var hint := Label.new()
	hint.name            = "GuideHint"
	hint.text            = "G  Guide"
	hint.anchor_left     = 1.0
	hint.anchor_right    = 1.0
	hint.anchor_top      = 0.0
	hint.anchor_bottom   = 0.0
	hint.offset_left     = -82
	hint.offset_right    = -8
	hint.offset_top      = 8
	hint.offset_bottom   = 24
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.45, 0.50, 0.60, 0.80))
	hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	hint.add_theme_constant_override("shadow_offset_x", 1)
	hint.add_theme_constant_override("shadow_offset_y", 1)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
