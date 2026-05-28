## GameGuideUI.gd  —  Guide du joueur intégré
## Touche G ou F1 pour ouvrir/fermer.
## Design dark navy, cards avec accent bar gauche, 2 colonnes sur onglet Nouveautés.
## Layout fix : ScrollContainer.horizontal_scroll_mode = DISABLED + MarginContainer enfant.
class_name GameGuideUI
extends CanvasLayer

var _player: Player = null
var _tab:    TabContainer = null

# Palette
const C_BG      := Color(0.055, 0.070, 0.110, 0.98)  # fond principal
const C_PANEL   := Color(0.090, 0.115, 0.175, 1.00)  # fond carte
const C_BORDER  := Color(0.18,  0.24,  0.38,  0.80)  # bordure subtile
const C_HDR     := Color(0.88,  0.92,  1.00,  1.00)  # titre carte blanc
const C_BODY    := Color(0.62,  0.67,  0.78,  1.00)  # texte corps
const C_MUTED   := Color(0.38,  0.42,  0.52,  1.00)  # texte discret


func _ready() -> void:
	layer   = 14
	visible = false
	_player = GameManager.local_player as Player
	EventBus.player_spawned.connect(func(p: Node) -> void: _player = p as Player)
	_register_input()
	_build_ui()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("open_guide"):
		if GameManager.current_state != GameManager.GameState.PLAYING and not visible:
			return
		visible = not visible
		if visible:
			GameManager.ui_open()
			_refresh_quest_status()
		else:
			GameManager.ui_close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and visible:
		visible = false
		GameManager.ui_close()
		get_viewport().set_input_as_handled()


func _register_input() -> void:
	if not InputMap.has_action("open_guide"):
		InputMap.add_action("open_guide")
		var ev1 := InputEventKey.new(); ev1.keycode = KEY_G
		var ev2 := InputEventKey.new(); ev2.keycode = KEY_F1
		InputMap.action_add_event("open_guide", ev1)
		InputMap.action_add_event("open_guide", ev2)


# ── Style helpers ──────────────────────────────────────────────────────────────

func _sb(bg: Color, border: Color = C_BORDER, radius: int = 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	return s


# Card with a 3px left accent bar (StyleBoxFlat has one border_color — left is thicker for visual accent)
func _card_sb(accent: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = C_PANEL
	s.border_color = accent
	s.border_width_left = 3; s.border_width_right = 1
	s.border_width_top  = 1; s.border_width_bottom = 1
	s.set_corner_radius_all(5)
	s.content_margin_left   = 14
	s.content_margin_right  = 14
	s.content_margin_top    = 10
	s.content_margin_bottom = 10
	return s


func _lbl(text: String, size: int, col: Color, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _sep_line(col: Color = C_BORDER) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.custom_minimum_size = Vector2(0, 1)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Returns inner VBoxContainer — call add_child on it to populate the tab.
func _make_tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.size_flags_vertical       = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode    = ScrollContainer.SCROLL_MODE_DISABLED
	_tab.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left",   18)
	margin.add_theme_constant_override("margin_right",  18)
	margin.add_theme_constant_override("margin_top",    14)
	margin.add_theme_constant_override("margin_bottom", 14)
	scroll.add_child(margin)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)
	return vb


## Generic card panel — returns inner VBoxContainer
func _card(accent: Color, parent: VBoxContainer) -> VBoxContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", _card_sb(accent))
	parent.add_child(p)

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 5)
	p.add_child(inner)
	return inner


## Section header with accent dot + horizontal rule below
func _section(vb: VBoxContainer, text: String, accent: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)

	var dot := ColorRect.new()
	dot.color = accent
	dot.custom_minimum_size = Vector2(4, 18)
	dot.size_flags_vertical  = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dot)

	var h := _lbl(text, 15, C_HDR)
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(h)

	vb.add_child(_sep_line(Color(accent.r, accent.g, accent.b, 0.25)))


## Keybinding pill widget
func _key_pill(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color      = Color(0.16, 0.20, 0.28)
	s.border_color  = Color(0.40, 0.50, 0.68)
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = 8; s.content_margin_right  = 8
	s.content_margin_top  = 3; s.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_PASS

	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.88, 0.92, 1.00))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


# ── Main window ────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	# Window — 78% wide, 88% tall
	var win := Control.new()
	win.anchor_left   = 0.11; win.anchor_right  = 0.89
	win.anchor_top    = 0.06; win.anchor_bottom = 0.94
	add_child(win)

	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", _sb(C_BG, C_BORDER, 8))
	win.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	vbox.offset_left = 0; vbox.offset_right  = 0
	vbox.offset_top  = 0; vbox.offset_bottom = 0
	win.add_child(vbox)

	# ── Header bar
	var hdr_panel := Panel.new()
	hdr_panel.custom_minimum_size = Vector2(0, 48)
	var hdr_sb := StyleBoxFlat.new()
	hdr_sb.bg_color = Color(0.07, 0.09, 0.14, 1.0)
	hdr_sb.border_color = C_BORDER
	hdr_sb.border_width_bottom = 1
	hdr_sb.corner_radius_top_left = 8; hdr_sb.corner_radius_top_right = 8
	hdr_panel.add_theme_stylebox_override("panel", hdr_sb)
	vbox.add_child(hdr_panel)

	var hdr_row := HBoxContainer.new()
	hdr_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hdr_row.offset_left = 18; hdr_row.offset_right = -12
	hdr_row.add_theme_constant_override("separation", 12)
	hdr_panel.add_child(hdr_row)

	# Lightning icon + title
	var icon_lbl := Label.new()
	icon_lbl.text = "⚡"
	icon_lbl.add_theme_font_size_override("font_size", 20)
	icon_lbl.add_theme_color_override("font_color", Color(0.50, 0.72, 1.00))
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdr_row.add_child(icon_lbl)

	var title_lbl := Label.new()
	title_lbl.text = "AXIOM"
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(0.88, 0.92, 1.00))
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdr_row.add_child(title_lbl)

	var sub := Label.new()
	sub.text = "Guide du joueur"
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", C_MUTED)
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdr_row.add_child(sub)

	var hint_lbl := Label.new()
	hint_lbl.text = "G / F1 pour fermer"
	hint_lbl.add_theme_font_size_override("font_size", 11)
	hint_lbl.add_theme_color_override("font_color", C_MUTED)
	hint_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdr_row.add_child(hint_lbl)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.add_theme_color_override("font_color", C_MUTED)
	close_btn.pressed.connect(func() -> void:
		visible = false
		GameManager.ui_close()
	)
	hdr_row.add_child(close_btn)

	# ── Tab container (fills rest of window)
	_tab = TabContainer.new()
	_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab.add_theme_font_size_override("font_size", 13)
	# Style the tab bar
	var tab_panel_sb := StyleBoxFlat.new()
	tab_panel_sb.bg_color = Color(0, 0, 0, 0)
	_tab.add_theme_stylebox_override("panel", tab_panel_sb)
	vbox.add_child(_tab)

	_build_nouveautes()
	_build_equipement()
	_build_quetes()
	_build_dimensions()
	_build_controles()


# ══════════════════════════════════════════════════════════════════════════════
# TAB 1 — NOUVEAUTÉS
# ══════════════════════════════════════════════════════════════════════════════

func _build_nouveautes() -> void:
	var vb := _make_tab("Nouveautés")
	_section(vb, "Ce qui change par rapport à Minecraft vanilla", Color(0.45, 0.65, 1.00))

	# 2-column grid of feature cards
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	vb.add_child(grid)

	var features := [
		[Color(0.55, 0.40, 0.90), "Arbre RPG",
			"Touche  K\n5 classes, 30 compétences.\n+1 point tous les 5 niveaux."],
		[Color(0.35, 0.60, 1.00), "Équipement par style",
			"Touche  O\n4 sets d'armure (Mineur / Guerrier /\nIngénieur / Mage), bonus uniques."],
		[Color(0.55, 0.85, 0.45), "Saisons dynamiques",
			"4 saisons × 5 jours.\nL'hiver gèle les cultures.\nBadge en bas à gauche du HUD."],
		[Color(1.00, 0.35, 0.35), "Lune de Sang",
			"Toutes 10–15 nuits.\nCiel rouge, mobs élites.\nMeilleur loot à la clé."],
		[Color(0.50, 0.80, 0.55), "Vein Miner",
			"Enchantement de pioche.\nBrise toute la veine d'un coup.\nI = 32 blocs, III = 64+ blocs."],
		[Color(1.00, 0.80, 0.20), "Artefacts légendaires",
			"Bonus procéduraux sur armes/outils.\nDrops de boss uniques.\nSélectionnez pour voir les stats."],
		[Color(1.00, 0.60, 0.20), "Quêtes de village",
			"Touche  E  → village → panneau ⚑\nKill / Bring / Explore.\nXP + Émeraudes + Réputation."],
		[Color(0.70, 0.50, 1.00), "Arc des Architectes",
			"Quête narrative cachée.\n4 Soul Fragments → Carte →\nArchives → Nexus (dimension secrète)."],
	]

	for feat in features:
		var accent: Color = feat[0]
		var card_panel := PanelContainer.new()
		card_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_panel.add_theme_stylebox_override("panel", _card_sb(accent))
		grid.add_child(card_panel)

		var inner := VBoxContainer.new()
		inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		inner.add_theme_constant_override("separation", 5)
		card_panel.add_child(inner)

		var title_row := HBoxContainer.new()
		title_row.add_theme_constant_override("separation", 8)
		inner.add_child(title_row)

		var dot := ColorRect.new()
		dot.color = accent
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_row.add_child(dot)

		var tl := Label.new()
		tl.text = feat[1] as String
		tl.add_theme_font_size_override("font_size", 14)
		tl.add_theme_color_override("font_color", accent.lightened(0.35))
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_row.add_child(tl)

		var dl := _lbl(feat[2] as String, 12, C_BODY, true)
		inner.add_child(dl)


# ══════════════════════════════════════════════════════════════════════════════
# TAB 2 — ÉQUIPEMENT
# ══════════════════════════════════════════════════════════════════════════════

func _build_equipement() -> void:
	var vb := _make_tab("Équipement")
	var ACC := Color(0.40, 0.65, 1.00)
	_section(vb, "Comment équiper de l'armure", ACC)

	var steps := [
		["1", "Obtenir des pièces",
			"Craftez ou utilisez le debug F12 → \"Set Mineur complet\".\n4 styles : Mineur, Guerrier, Ingénieur, Mage."],
		["2", "Équiper depuis l'inventaire  (touche E)",
			"En haut de l'inventaire : 4 slots d'armure.\nShift + Clic sur une pièce → s'équipe automatiquement dans le bon slot.\nClic sur un slot occupé → retire la pièce dans l'inventaire."],
		["3", "Écran d'équipement  (touche O)",
			"Vue complète : chaque slot, armure totale, bonus actifs.\nDétection de set : bonus supplémentaires si 2 ou 4 pièces du même style."],
		["4", "Bonus de set",
			"Mineur  ×4  →  +40% vitesse minage + Fortune\nGuerrier  ×4  →  +30% dégâts + réduction 15%\nIngénieur  ×4  →  Sprint + sauts renforcés\nMage  ×4  →  Régén. faim + résistance chute"],
	]

	for step in steps:
		var card := _card(ACC, vb)
		var hrow := HBoxContainer.new()
		hrow.add_theme_constant_override("separation", 12)
		hrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_child(hrow)

		var num_p := Panel.new()
		num_p.custom_minimum_size = Vector2(28, 28)
		var num_sb := StyleBoxFlat.new()
		num_sb.bg_color = Color(ACC.r * 0.3, ACC.g * 0.3, ACC.b * 0.3, 0.9)
		num_sb.border_color = ACC
		num_sb.set_border_width_all(1)
		num_sb.set_corner_radius_all(14)
		num_p.add_theme_stylebox_override("panel", num_sb)
		num_p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hrow.add_child(num_p)

		var nl := Label.new()
		nl.text = step[0]
		nl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		nl.add_theme_font_size_override("font_size", 13)
		nl.add_theme_color_override("font_color", ACC.lightened(0.3))
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		num_p.add_child(nl)

		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 4)
		hrow.add_child(col)

		col.add_child(_lbl(step[1] as String, 13, C_HDR))
		col.add_child(_lbl(step[2] as String, 12, C_BODY, true))

	# Slot reference table
	vb.add_child(_lbl("", 4, C_MUTED))  # spacer
	_section(vb, "Slots disponibles", Color(0.55, 0.80, 0.55))

	var slot_grid := GridContainer.new()
	slot_grid.columns = 4
	slot_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_grid.add_theme_constant_override("h_separation", 8)
	slot_grid.add_theme_constant_override("v_separation", 6)
	vb.add_child(slot_grid)

	var slots_data := [
		["🪖", "Casque",    "head",  Color(0.60, 0.70, 0.90)],
		["🥋", "Plastron",  "chest", Color(0.50, 0.80, 0.60)],
		["👖", "Jambières", "legs",  Color(0.80, 0.65, 0.40)],
		["👢", "Bottes",    "feet",  Color(0.70, 0.50, 0.85)],
	]
	for s in slots_data:
		var sp := PanelContainer.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sp_sb := StyleBoxFlat.new()
		sp_sb.bg_color = Color((s[3] as Color).r * 0.10, (s[3] as Color).g * 0.10, (s[3] as Color).b * 0.10, 0.80)
		sp_sb.border_color = s[3] as Color
		sp_sb.set_border_width_all(1)
		sp_sb.set_corner_radius_all(4)
		sp_sb.content_margin_left = 10; sp_sb.content_margin_right  = 10
		sp_sb.content_margin_top  = 8;  sp_sb.content_margin_bottom = 8
		sp.add_theme_stylebox_override("panel", sp_sb)
		slot_grid.add_child(sp)

		var sv := VBoxContainer.new()
		sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sv.add_theme_constant_override("separation", 2)
		sp.add_child(sv)

		var icon_row := HBoxContainer.new()
		icon_row.add_theme_constant_override("separation", 6)
		sv.add_child(icon_row)

		var il := Label.new()
		il.text = s[0] as String
		il.add_theme_font_size_override("font_size", 18)
		il.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_row.add_child(il)

		icon_row.add_child(_lbl(s[1] as String, 13, C_HDR))
		sv.add_child(_lbl("slot  %s" % s[2], 11, C_MUTED))


# ══════════════════════════════════════════════════════════════════════════════
# TAB 3 — QUÊTES  (statut dynamique)
# ══════════════════════════════════════════════════════════════════════════════

func _build_quetes() -> void:
	var vb := _make_tab("Quêtes")
	var ACC := Color(1.00, 0.68, 0.25)
	_section(vb, "Système de quêtes de village", ACC)

	var steps := [
		["Trouver un village",    "Explorez l'Overworld. Les villages génèrent dans les plaines et savanes."],
		["Trouver le panneau ⚑", "Interagissez avec le bloc de panneau de quêtes  (touche E  sur le bloc)."],
		["Accepter une quête",    "3 quêtes disponibles par village, 3 types :\n  Kill — tuez X mobs spécifiques\n  Bring — rapportez X items\n  Explore — découvrez une zone"],
		["Récompenses",           "XP  •  Émeraudes  •  Réputation (−100 → +100)\nLa réputation améliore les prix des marchands."],
		["Tracker HUD",           "Quête acceptée → tracker visible en bas à droite.\nMise à jour en temps réel."],
	]

	for step in steps:
		var card := _card(ACC, vb)
		card.add_theme_constant_override("separation", 4)

		var hrow := HBoxContainer.new()
		hrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hrow.add_theme_constant_override("separation", 12)
		card.add_child(hrow)

		var num_r := ColorRect.new()
		num_r.color = ACC
		num_r.custom_minimum_size = Vector2(4, 0)
		num_r.size_flags_vertical  = Control.SIZE_EXPAND_FILL
		num_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hrow.add_child(num_r)

		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 4)
		hrow.add_child(col)

		col.add_child(_lbl(step[0] as String, 13, ACC.lightened(0.3)))
		col.add_child(_lbl(step[1] as String, 12, C_BODY, true))

	# Dynamic status
	vb.add_child(_lbl("", 2, C_MUTED))
	_section(vb, "Statut actuel", Color(0.50, 0.90, 0.55))

	var status_panel := PanelContainer.new()
	status_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_panel.add_theme_stylebox_override("panel", _card_sb(Color(0.50, 0.90, 0.55)))
	vb.add_child(status_panel)

	var status_lbl := Label.new()
	status_lbl.name = "QuestStatusLabel"
	status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_lbl.add_theme_font_size_override("font_size", 13)
	status_lbl.add_theme_color_override("font_color", C_BODY)
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_panel.add_child(status_lbl)


# ══════════════════════════════════════════════════════════════════════════════
# TAB 4 — DIMENSIONS
# ══════════════════════════════════════════════════════════════════════════════

func _build_dimensions() -> void:
	var vb := _make_tab("Dimensions")
	_section(vb, "Dimensions disponibles et à venir", Color(0.70, 0.55, 1.00))

	var dims := [
		[Color(0.40, 0.85, 0.45), "Overworld",    "DISPONIBLE",
			"Biomes variés, villages, minerais, structures.\ny = −128 → +320  |  mer = y 63\nNouveaux biomes : Oasis, Jungle Verticale, Volcanic Rifts..."],
		[Color(1.00, 0.42, 0.18), "Nether",        "DISPONIBLE  —  portail obsidienne",
			"Portail en cadre d'obsidienne allumé au silex.\nBiome bonus : Nether Roof Limbo (y > 128)."],
		[Color(0.60, 0.50, 0.95), "The End",       "DISPONIBLE  —  Forteresse + Yeux de l'Ender",
			"Ender Dragon Phase 1 (vanilla) + Phase 2 (Ominous Bottle).\nCouches : Central → Outer → Upper → Abyss."],
		[Color(0.78, 0.58, 1.00), "Le Nexus",      "QUÊTE  —  Arc des Architectes",
			"Dimension secrète, accès par la quête narrative :\n4 Soul Fragments → Carte des Architectes → Archives → Autel."],
		[Color(0.70, 0.88, 1.00), "Aether",        "MODULE OPTIONNEL  (à venir)",
			"Ciels lumineux et îles flottantes végétalisées.\nMinerais : Zanite (minage), Gravitite (anti-gravité)."],
		[Color(0.22, 0.50, 0.90), "Ocean Abyss",   "MODULE OPTIONNEL  (à venir)",
			"Monde sous-marin, profondeur infinie.\nBoss : Abyss Leviathan. Armure : Pressure Suit."],
	]

	for dim in dims:
		var accent: Color = dim[0]
		var card := _card(accent, vb)

		var title_row := HBoxContainer.new()
		title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_row.add_theme_constant_override("separation", 10)
		card.add_child(title_row)

		title_row.add_child(_lbl(dim[1] as String, 15, accent.lightened(0.30)))

		var status_str: String = dim[2] as String
		var status_col: Color
		if status_str.begins_with("DISPONIBLE"):   status_col = Color(0.35, 1.00, 0.45)
		elif status_str.begins_with("QUÊTE"):       status_col = Color(0.90, 0.72, 1.00)
		else:                                        status_col = Color(0.45, 0.50, 0.60)

		var sl := _lbl(status_str, 10, status_col)
		sl.size_flags_horizontal = Control.SIZE_SHRINK_END
		sl.vertical_alignment    = VERTICAL_ALIGNMENT_BOTTOM
		title_row.add_child(sl)

		card.add_child(_lbl(dim[3] as String, 12, C_BODY, true))


# ══════════════════════════════════════════════════════════════════════════════
# TAB 5 — CONTRÔLES
# ══════════════════════════════════════════════════════════════════════════════

func _build_controles() -> void:
	var vb := _make_tab("Contrôles")
	_section(vb, "Touches du jeu", Color(0.60, 0.75, 0.95))

	var groups := [
		["Mouvement & Combat", Color(0.45, 0.65, 1.00), [
			["ZQSD / WASD",         "Se déplacer"],
			["Espace",              "Sauter"],
			["Shift gauche",        "Se baisser (sneak)"],
			["Ctrl gauche",         "Sprinter"],
			["1–9",                 "Sélectionner slot raccourcis"],
			["Molette",             "Changer de slot"],
			["Clic gauche",         "Miner / Attaquer"],
			["Clic droit",          "Placer / Interagir"],
		]],
		["Nouvelles interfaces", Color(0.75, 0.52, 1.00), [
			["E",                   "Inventaire  (slots d'armure intégrés)"],
			["O",                   "Équipement  (stats armure + sets)"],
			["K",                   "Arbre de compétences RPG"],
			["G  /  F1",            "Ce guide (ouvrir / fermer)"],
			["C",                   "Catalogue de craft + recettes"],
			["F12",                 "Panneau de test développeur"],
			["Échap",               "Fermer toute interface"],
		]],
		["Gameplay avancé", Color(0.45, 0.88, 0.60), [
			["Shift + Clic",        "Déplacer tout le stack / Équiper armure"],
			["Shift + Clic (craft)","Fabriquer le maximum possible"],
		]],
	]

	for grp in groups:
		var acc: Color = grp[1]
		_section(vb, grp[0] as String, acc)

		for binding in (grp[2] as Array):
			var row := HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_theme_constant_override("separation", 6)
			vb.add_child(row)

			# Key pills
			var keys_row := HBoxContainer.new()
			keys_row.add_theme_constant_override("separation", 4)
			keys_row.custom_minimum_size = Vector2(185, 0)
			row.add_child(keys_row)

			for key in (binding[0] as String).split("  /  "):
				keys_row.add_child(_key_pill(key.strip_edges()))

			# Description
			row.add_child(_lbl(binding[1] as String, 12, C_BODY))

		vb.add_child(_lbl("", 2, C_MUTED))  # small spacer between groups


# ── Dynamic data ───────────────────────────────────────────────────────────────

func _refresh_quest_status() -> void:
	# Navigate: _tab → "Quêtes" scroll → MarginContainer → VBoxContainer → ... → QuestStatusLabel
	var scroll := _tab.get_node_or_null("Quêtes") as ScrollContainer
	if scroll == null:
		return
	var status_lbl := scroll.find_child("QuestStatusLabel", true, false) as Label
	if status_lbl == null:
		return

	var lines: Array[String] = []
	lines.append("Réputation : %d  (%s)" % [QuestManager.reputation, QuestManager.get_reputation_label()])
	if QuestManager.has_active_quest():
		var q := QuestManager.get_active_quest()
		lines.append("Quête active : " + (q.get("desc", "?") as String).replace("{count}", str(q.get("count", 1))))
		lines.append("Progression : %d / %d" % [q.get("progress", 0), q.get("count", 1)])
	else:
		lines.append("Aucune quête active.\nTrouvez un panneau ⚑ dans un village.")
	status_lbl.text = "\n".join(lines)
