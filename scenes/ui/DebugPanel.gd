## DebugPanel.gd
## Developer test panel — toggle with F12.
## Lets you test all 14 implemented features without normal gameplay.
## Added as a child of World at runtime (see World.gd _ready).
class_name DebugPanel
extends CanvasLayer

var _player: Player = null
var _world:  Node   = null
var _status: Label  = null
var _tab:    TabContainer = null


func _ready() -> void:
	layer        = 99
	visible      = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_world       = GameManager.world_node
	# Player is already spawned before DebugPanel is added — grab it now.
	_player = GameManager.local_player as Player
	# Also listen for future respawns.
	EventBus.player_spawned.connect(func(p: Node) -> void: _player = p as Player)
	_register_input()
	_build_ui()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_panel"):
		visible = not visible
		if visible:
			GameManager.ui_open()
			_refresh_status()
		else:
			GameManager.ui_close()
		get_viewport().set_input_as_handled()


# ── Input action ───────────────────────────────────────────────────────────────

func _register_input() -> void:
	if not InputMap.has_action("debug_panel"):
		InputMap.add_action("debug_panel")
		var ev := InputEventKey.new()
		ev.keycode = KEY_F12
		InputMap.action_add_event("debug_panel", ev)


# ── UI Construction ────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Full-screen dim overlay
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	# Main panel — 80% of screen
	var root := Control.new()
	root.anchor_left   = 0.1;  root.anchor_right  = 0.9
	root.anchor_top    = 0.05; root.anchor_bottom = 0.95
	add_child(root)

	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.08, 0.97)
	sb.border_color = Color(0.40, 0.80, 0.40, 0.90)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	bg.add_theme_stylebox_override("panel", sb)
	root.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	root.add_child(vbox)

	# Header
	var hdr := _make_label("🛠  AXIOM — PANNEAU DE TEST  [F12 pour fermer]", 16,
		Color(0.40, 1.00, 0.45))
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.add_theme_constant_override("margin_top", 6)
	vbox.add_child(hdr)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Status bar
	_status = _make_label("Prêt.", 12, Color(0.80, 0.80, 0.80))
	_status.add_theme_constant_override("margin_left", 10)
	vbox.add_child(_status)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# Tab container
	_tab = TabContainer.new()
	_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_tab)

	_build_tab_temps()
	_build_tab_progression()
	_build_tab_quetes()
	_build_tab_monde()
	_build_tab_inventaire()
	_build_tab_status()

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Fermer  [F12]"
	close_btn.add_theme_font_size_override("font_size", 13)
	close_btn.pressed.connect(func() -> void:
		visible = false
		GameManager.ui_close()
	)
	vbox.add_child(close_btn)


# ── Tab helpers ────────────────────────────────────────────────────────────────

func _make_scroll_tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 6)
	scroll.add_child(vb)
	return vb


func _make_section(parent: VBoxContainer, title: String) -> HFlowContainer:
	var lbl := _make_label("── %s" % title, 13, Color(1.0, 0.85, 0.20))
	lbl.add_theme_constant_override("margin_left", 8)
	lbl.add_theme_constant_override("margin_top",  8)
	parent.add_child(lbl)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 4)
	parent.add_child(row)
	return row


func _btn(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _make_label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _ok(msg: String) -> void:
	_status.text = "✓  " + msg
	_status.add_theme_color_override("font_color", Color(0.40, 1.00, 0.45))


func _err(msg: String) -> void:
	_status.text = "✗  " + msg
	_status.add_theme_color_override("font_color", Color(1.00, 0.40, 0.35))


func _info(msg: String) -> void:
	_status.text = "ℹ  " + msg
	_status.add_theme_color_override("font_color", Color(0.70, 0.85, 1.00))


# ═══════════════════════════════════════════════════════════════════════════════
# TAB 1 — TEMPS & MONDE
# ═══════════════════════════════════════════════════════════════════════════════

func _build_tab_temps() -> void:
	var vb := _make_scroll_tab("⏱ Temps & Monde")

	# Time control
	var r1 := _make_section(vb, "Contrôle du temps")
	_btn(r1, "→ Aube (0.25)",  func(): TimeManager.skip_to_dawn();              _ok("Aube"))
	_btn(r1, "→ Midi (0.50)",  func(): TimeManager.set_time(0.50);              _ok("Midi"))
	_btn(r1, "→ Crépuscule",   func(): TimeManager.set_time(0.73);              _ok("Crépuscule"))
	_btn(r1, "→ Minuit",       func(): TimeManager.set_time(0.0);               _ok("Minuit"))
	_btn(r1, "+ 1 Jour",       func(): TimeManager.current_day += 1;            _ok("Jour %d" % TimeManager.current_day))
	_btn(r1, "+ 7 Jours",      func(): TimeManager.current_day += 7;            _ok("Jour %d" % TimeManager.current_day))

	# Blood Moon (Idée #1)
	var r2 := _make_section(vb, "🌑 Lune de Sang  [Idée #1]")
	_btn(r2, "Déclencher maintenant", func() -> void:
		TimeManager.is_blood_moon  = true
		TimeManager._bm_triggered  = true
		TimeManager._blood_moon_day = TimeManager.current_day
		EventBus.blood_moon_started.emit(TimeManager.current_day)
		_ok("Blood Moon déclenchée ! Ciel rouge + mobs élites.")
	)
	_btn(r2, "Terminer",  func() -> void:
		TimeManager.is_blood_moon   = false
		TimeManager._bm_triggered   = false
		TimeManager._bm_warning_sent = false
		TimeManager._blood_moon_day = TimeManager.current_day + 12
		EventBus.blood_moon_ended.emit()
		_ok("Blood Moon terminée.")
	)
	_btn(r2, "Avertissement (veille)", func() -> void:
		EventBus.blood_moon_warning.emit()
		_ok("Message d'avertissement envoyé.")
	)

	# Seasons (Idée #12)
	var r3 := _make_section(vb, "🌸 Saisons  [Idée #12]")
	_btn(r3, "✿ Printemps", func(): _set_season(SeasonManager.Season.SPRING))
	_btn(r3, "☀ Été",      func(): _set_season(SeasonManager.Season.SUMMER))
	_btn(r3, "✦ Automne",  func(): _set_season(SeasonManager.Season.AUTUMN))
	_btn(r3, "❄ Hiver",    func(): _set_season(SeasonManager.Season.WINTER))

	# Weather (Idée #12)
	var r4 := _make_section(vb, "☁ Météo  [Idée #12]")
	_btn(r4, "☀ Dégagé",    func(): _set_weather(SeasonManager.Weather.CLEAR))
	_btn(r4, "☁ Nuageux",   func(): _set_weather(SeasonManager.Weather.CLOUDY))
	_btn(r4, "☂ Pluie",     func(): _set_weather(SeasonManager.Weather.RAIN))
	_btn(r4, "⚡ Orage",    func(): _set_weather(SeasonManager.Weather.THUNDERSTORM))
	_btn(r4, "❄ Blizzard",  func(): _set_weather(SeasonManager.Weather.BLIZZARD))


func _set_season(s: int) -> void:
	SeasonManager.current_season   = s
	SeasonManager.day_in_season    = 0
	EventBus.season_changed.emit(s)
	_ok("Saison → %s  (multiplicateur cultures : ×%.1f)" % [
		SeasonManager.get_season_name(), SeasonManager.get_growth_multiplier()])


func _set_weather(w: int) -> void:
	SeasonManager.current_weather = w
	EventBus.weather_changed.emit(w)
	_ok("Météo → %s" % SeasonManager.get_weather_name())


# ═══════════════════════════════════════════════════════════════════════════════
# TAB 2 — PROGRESSION
# ═══════════════════════════════════════════════════════════════════════════════

func _build_tab_progression() -> void:
	var vb := _make_scroll_tab("📈 Progression")

	# Skill Tree (Idée #3)
	var r1 := _make_section(vb, "🧙 Arbre RPG  [Idée #3]  →  touche K")
	_btn(r1, "+1 Point",   func(): _add_skill_points(1))
	_btn(r1, "+5 Points",  func(): _add_skill_points(5))
	_btn(r1, "+10 Points", func(): _add_skill_points(10))
	_btn(r1, "Débloquer tous Tier 1", func() -> void:
		if _player == null or _player.skill_tree == null:
			_err("Joueur non chargé"); return
		var st := _player.skill_tree
		for def in st.get_all_skills():
			if def.get("tier", 1) == 1 and def.get("implemented", false):
				if not st.has_skill(def["id"]):
					st.available_points = maxi(st.available_points, 1)
					st.unlock(def["id"])
		_ok("Tous les skills Tier 1 débloqués. Ouvrez K pour voir.")
	)
	_btn(r1, "Reset complet", func() -> void:
		if _player == null or _player.skill_tree == null:
			_err("Joueur non chargé"); return
		_player.skill_tree.unlocked.clear()
		_player.skill_tree.available_points = 0
		_ok("Arbre de compétences réinitialisé.")
	)
	_btn(r1, "Ouvrir l'arbre", func() -> void:
		var ui := _player.get_node_or_null("SkillTreeUI") as SkillTreeUI if _player else null
		if ui: ui.toggle(); _ok("K pour fermer.")
		else: _err("SkillTreeUI introuvable.")
	)

	# Equipment sets (Idée #4)
	var r2 := _make_section(vb, "🛡 Équipements par style  [Idée #4]")
	_btn(r2, "Set Mineur complet",    func(): _give_set("mineur"))
	_btn(r2, "Set Guerrier complet",  func(): _give_set("guerrier"))
	_btn(r2, "Set Ingénieur complet", func(): _give_set("ingenieur"))
	_btn(r2, "Set Mage/Fermier",      func(): _give_set("mage"))

	# Vein Mining (Idée #2)
	var r3 := _make_section(vb, "⛏ Vein Mining  [Idée #2]  →  enchantement sur pioche")
	_btn(r3, "Donner pioche Vein Miner I", func() -> void:
		_give_stack({"id": "axiom:iron_pickaxe", "count": 1,
			"enchantments": {"vein_miner": 1}})
		_ok("Pioche Vein Miner I dans l'inventaire. Maintenez Shift + minez un minerai.")
	)
	_btn(r3, "Donner pioche Vein Miner III", func() -> void:
		_give_stack({"id": "axiom:diamond_pickaxe", "count": 1,
			"enchantments": {"vein_miner": 3}})
		_ok("Pioche Vein Miner III (64 blocs max).")
	)

	# Artifacts (Idée #13)
	var r4 := _make_section(vb, "✨ Artefacts légendaires  [Idée #13]")
	_btn(r4, "Épée Rare (2 bonus)",    func(): _spawn_artifact("axiom:iron_sword", 2))
	_btn(r4, "Épée Épique (3 bonus)",  func(): _spawn_artifact("axiom:diamond_sword", 3))
	_btn(r4, "Pioche Artefact",        func(): _spawn_artifact("axiom:diamond_pickaxe", 2))
	_btn(r4, "Arc Artefact",           func(): _spawn_artifact("axiom:bow", 2))
	_btn(r4, "Équiper dans slot 1",    func() -> void:
		_info("Glissez l'artefact dans votre barre d'accès pour voir l'overlay.")
	)

	# XP
	var r5 := _make_section(vb, "⭐ XP")
	_btn(r5, "+100 XP",   func(): _add_xp(100))
	_btn(r5, "+500 XP",   func(): _add_xp(500))
	_btn(r5, "+1000 XP",  func(): _add_xp(1000))
	_btn(r5, "Level 50",  func(): _add_xp(99999))


func _add_skill_points(n: int) -> void:
	if _player == null: _player = GameManager.local_player as Player
	if _player == null or _player.skill_tree == null:
		_err("Joueur non chargé"); return
	_player.skill_tree.available_points += n
	EventBus.skill_point_gained.emit(n)
	_ok("+%d points de compétence. Ouvrez K pour les dépenser." % n)
	EventBus.show_message.emit("+%d points de compétence disponibles (touche K)" % n, 3.0)


func _add_xp(n: int) -> void:
	if _player == null: _player = GameManager.local_player as Player
	if _player == null: _err("Joueur non chargé"); return
	_player.add_xp(n)
	_ok("+%d XP  (niveau actuel : %d)" % [n, _player.xp_level])
	EventBus.show_message.emit("+%d XP → niveau %d" % [n, _player.xp_level], 2.5)


func _give_set(cls: String) -> void:
	if _player == null: _player = GameManager.local_player as Player
	if _player == null or _player.inventory == null:
		_err("Joueur non chargé"); return
	var pieces: Array[String]
	match cls:
		"mineur":    pieces = ["axiom:miner_helmet","axiom:miner_chestplate","axiom:miner_leggings","axiom:miner_boots"]
		"guerrier":  pieces = ["axiom:warrior_helmet","axiom:warrior_chestplate","axiom:warrior_leggings","axiom:warrior_boots"]
		"ingenieur": pieces = ["axiom:engineer_helmet","axiom:engineer_chestplate","axiom:engineer_leggings","axiom:engineer_boots"]
		"mage":      pieces = ["axiom:mage_helmet","axiom:mage_chestplate","axiom:mage_leggings","axiom:mage_boots"]
	# Equip directly into armor slots (0=tête, 1=torse, 2=jambières, 3=bottes)
	for i in 4:
		_player.inventory.set_armor_slot(i, {"id": pieces[i], "count": 1, "meta": {}})
	_ok("Set %s équipé directement (slots armure). Bonus actifs immédiatement." % cls)
	EventBus.show_message.emit("Armure set '%s' équipée !" % cls, 3.0)


func _spawn_artifact(item_id: String, bonuses: int) -> void:
	var seed_val := randi()
	var stack    := ArtifactGenerator.make_artifact_stack(item_id, seed_val, bonuses)
	_give_stack(stack)
	_ok("Artefact '%s' (%d bonus) dans l'inventaire. Sélectionnez-le pour voir l'overlay." % [
		stack.get("artifact_name", "?"), bonuses])


# ═══════════════════════════════════════════════════════════════════════════════
# TAB 3 — QUÊTES & MOBS
# ═══════════════════════════════════════════════════════════════════════════════

func _build_tab_quetes() -> void:
	var vb := _make_scroll_tab("📋 Quêtes & Mobs")

	# Quests (Idée #14)
	var r1 := _make_section(vb, "📋 Système de quêtes  [Idée #14]")
	_btn(r1, "Accepter quête KILL test", func() -> void:
		var q := {"id": "dbg_kill", "type": "kill", "mob": "zombie",
			"count": 3, "desc": "TEST : Tuer {count} zombies.",
			"rewards": {"emeralds": 5, "xp": 30, "rep": 10}}
		QuestManager.accept_quest(q, 0, 0)
		_ok("Quête kill acceptée → tuez 3 zombies (Spawn Zombie ci-dessous).")
		EventBus.show_message.emit("⚑ Quête : Tuer 3 zombies — tracker visible en bas à droite", 5.0)
	)
	_btn(r1, "Accepter quête BRING test", func() -> void:
		var q := {"id": "dbg_bring", "type": "bring", "item": "axiom:coal",
			"count": 5, "desc": "TEST : Apporter {count} charbons.",
			"rewards": {"emeralds": 4, "xp": 20, "rep": 8}}
		QuestManager.accept_quest(q, 0, 0)
		_give_stack({"id": "axiom:coal", "count": 5})
		_ok("Quête bring acceptée + 5 charbons donnés.")
		EventBus.show_message.emit("⚑ Quête : Apporter 5 charbons — 5 charbons dans l'inventaire", 5.0)
	)
	_btn(r1, "+1 progrès kill", func() -> void:
		if not QuestManager.has_active_quest():
			_err("Aucune quête active."); return
		var q := QuestManager.get_active_quest()
		q["progress"] = q.get("progress", 0) + 1
		EventBus.quest_progress_updated.emit(q.duplicate())
		_ok("Progrès : %d / %d" % [q["progress"], q.get("count", 1)])
	)
	_btn(r1, "Compléter quête active", func() -> void:
		if not QuestManager.is_quest_ready_to_turn_in():
			_err("Quête pas prête."); return
		QuestManager.complete_quest()
		_ok("Quête terminée ! Réputation : %d" % QuestManager.reputation)
	)
	_btn(r1, "Annuler quête", func() -> void:
		QuestManager._active_quest = {}
		_ok("Quête active annulée.")
	)

	# Reputation (Idée #14)
	var r2 := _make_section(vb, "⭐ Réputation  [Idée #14]")
	_btn(r2, "+10 rép",   func(): QuestManager.add_reputation(10);  _ok("Réputation : %d  (%s)" % [QuestManager.reputation, QuestManager.get_reputation_label()]))
	_btn(r2, "+30 rép",   func(): QuestManager.add_reputation(30);  _ok("Réputation : %d  (%s)" % [QuestManager.reputation, QuestManager.get_reputation_label()]))
	_btn(r2, "-20 rép",   func(): QuestManager.add_reputation(-20); _ok("Réputation : %d  (%s)" % [QuestManager.reputation, QuestManager.get_reputation_label()]))
	_btn(r2, "→ Héros",   func(): QuestManager.add_reputation(100 - QuestManager.reputation); _ok("Héros !"))
	_btn(r2, "→ Paria",   func(): QuestManager.add_reputation(-100 - QuestManager.reputation); _ok("Paria !"))
	_btn(r2, "Reset 0",   func(): QuestManager.add_reputation(-QuestManager.reputation); _ok("Réputation remise à 0."))

	# Mob spawning
	var r3 := _make_section(vb, "👾 Spawner des mobs")
	_btn(r3, "Zombie",         func(): _spawn_mob("Zombie",   false))
	_btn(r3, "Zombie ÉLITE",   func(): _spawn_mob("Zombie",   true))
	_btn(r3, "Skeleton",       func(): _spawn_mob("Skeleton", false))
	_btn(r3, "Skeleton ÉLITE", func(): _spawn_mob("Skeleton", true))
	_btn(r3, "Wolf",           func(): _spawn_mob("Wolf",     false))
	_btn(r3, "Groupe ×5",      func(): _spawn_mob_group("Zombie", 5))

	# Boss
	var r4 := _make_section(vb, "💀 Boss  [Idée #7]")
	_btn(r4, "Engager boss (event HUD)", func() -> void:
		EventBus.boss_engaged.emit("Gardien de Pierre", null)
		EventBus.boss_health_changed.emit("Gardien de Pierre", 1.0)
		_ok("Barre de boss affichée. Utilisez les boutons ci-dessous pour simuler.")
	)
	_btn(r4, "Boss à 50% PV",  func(): EventBus.boss_health_changed.emit("Gardien de Pierre", 0.5);  _ok("Boss 50%"))
	_btn(r4, "Boss à 10% PV",  func(): EventBus.boss_health_changed.emit("Gardien de Pierre", 0.1);  _ok("Boss 10%"))
	_btn(r4, "Boss vaincu",    func(): EventBus.boss_defeated.emit("Gardien de Pierre");              _ok("Boss vaincu ! Barre disparaît."))


func _spawn_mob(mob_class: String, elite: bool) -> void:
	if _player == null: _player = GameManager.local_player as Player
	if _player == null: _err("Joueur non chargé"); return
	var pos := _player.global_position + _player.global_transform.basis.z * -4.0 + Vector3(0, 1, 0)
	var mob: BaseMob
	match mob_class:
		"Zombie":   mob = Zombie.new()
		"Skeleton": mob = Skeleton.new()
		"Wolf":     mob = Wolf.new()
		_: _err("Mob inconnu"); return
	if _world:
		_world.add_child(mob)
	else:
		get_tree().current_scene.add_child(mob)
	mob.global_position = pos
	if elite:
		mob.make_elite()
	var label := "ÉLITE " if elite else ""
	_ok("%s%s spawné devant vous." % [label, mob_class])
	EventBus.show_message.emit("%s%s apparu devant vous !" % [label, mob_class], 3.0)


func _spawn_mob_group(mob_class: String, count: int) -> void:
	for i in count:
		_spawn_mob(mob_class, false)


# ═══════════════════════════════════════════════════════════════════════════════
# TAB 4 — MONDE & STRUCTURES
# ═══════════════════════════════════════════════════════════════════════════════

func _build_tab_monde() -> void:
	var vb := _make_scroll_tab("🌍 Monde & Structures")

	# Teleports
	var r1 := _make_section(vb, "🗺 Téléportation")
	_btn(r1, "→ Spawn (0,80,0)",  func(): _tp(Vector3(8.5, 80, 8.5)))
	_btn(r1, "→ Archives",        func() -> void:
		var loc := GameManager.get_archives_location()
		_tp(Vector3(loc.x + 12.5, 20, loc.y + 12.5))
		_ok("TP vers les Archives (%d, ?, %d) — attendez que le chunk charge." % [loc.x, loc.y])
	)
	_btn(r1, "→ Nexus",           func() -> void:
		_tp(Vector3(100000.5, 252.5, 100000.5))
		_ok("Bienvenue dans le Nexus.")
	)
	_btn(r1, "Retour depuis Nexus", func() -> void:
		_tp(Vector3(8.5, 80, 8.5))
		EventBus.nexus_exited.emit()
		_ok("Retour depuis le Nexus.")
	)

	# Architects Arc / Nexus (Idée #11)
	var r2 := _make_section(vb, "📜 Arc des Architectes  [Idée #11]")
	_btn(r2, "Donner Soul Fragment I",  func(): _give_stack({"id": "axiom:soul_fragment_1", "count": 1}); _ok("Fragment I"))
	_btn(r2, "Donner les 4 Fragments", func() -> void:
		for i in range(1, 5): _give_stack({"id": "axiom:soul_fragment_%d" % i, "count": 1})
		_ok("4 Soul Fragments donnés → craftez la Carte des Architectes.")
	)
	_btn(r2, "Donner Carte Architectes", func() -> void:
		_give_stack({"id": "axiom:architect_map", "count": 1})
		_ok("Carte donnée → Boussole visible en haut à droite quand sélectionnée.")
	)
	_btn(r2, "Donner Fragment du Nexus", func() -> void:
		_give_stack({"id": "axiom:nexus_fragment", "count": 1})
		_ok("Fragment Nexus donné → activez l'autel des Archives pour ouvrir le portail.")
	)
	_btn(r2, "Forcer accès Nexus", func() -> void:
		var w := GameManager.world_node
		if w and w.get("_nexus_fragment_given") != null:
			w.set("_nexus_fragment_given", true)
		_ok("Accès Nexus forcé. Interagissez avec le bloc 257 (nexus_portal).")
	)

	# Skill Altars / Structures (Idée #5)
	var r3 := _make_section(vb, "🗿 Autels de compétences  [Idée #5]")
	_btn(r3, "+1 pt Mineur direct",    func(): _give_skill_point("mineur"))
	_btn(r3, "+1 pt Guerrier direct",  func(): _give_skill_point("guerrier"))
	_btn(r3, "+1 pt Ingénieur direct", func(): _give_skill_point("ingenieur"))
	_btn(r3, "+1 pt Mage direct",      func(): _give_skill_point("mage"))
	_btn(r3, "+1 pt Fermier direct",   func(): _give_skill_point("fermier"))

	# Roads / Merchants (Idée #6)
	var r4 := _make_section(vb, "🛣 Routes & Marchands ambulants  [Idée #6]")
	_btn(r4, "Donner 20 émeraudes",  func(): _give_stack({"id": "axiom:emerald", "count": 20}); _ok("Émeraudes pour acheter aux marchands."))
	_btn(r4, "Message marchand",     func(): EventBus.show_message.emit("Marchand : 'Des objets rares, aventurier ?'", 4.0); _ok("Simulation message marchand."))


func _tp(pos: Vector3) -> void:
	if _player == null: _err("Joueur non chargé"); return
	_player.global_position = pos
	_ok("Téléporté à %.0f, %.0f, %.0f" % [pos.x, pos.y, pos.z])


func _give_skill_point(cls_name: String) -> void:
	if _player == null or _player.skill_tree == null:
		_err("Joueur non chargé"); return
	_player.skill_tree.available_points += 1
	EventBus.skill_point_gained.emit(1)
	_ok("Point de compétence %s ajouté." % cls_name)


# ═══════════════════════════════════════════════════════════════════════════════
# TAB 5 — INVENTAIRE & CRAFT
# ═══════════════════════════════════════════════════════════════════════════════

func _build_tab_inventaire() -> void:
	var vb := _make_scroll_tab("🎒 Inventaire & Craft")

	# Catalog / Crafting (Idée #10)
	var r1 := _make_section(vb, "🔨 Catalogue de craft  [Idée #10]  →  touche C")
	_btn(r1, "Donner Établi Compact", func() -> void:
		_give_stack({"id": "axiom:portable_workbench", "count": 1})
		_ok("Établi Compact dans l'inventaire → touche C pour ouvrir le catalogue n'importe où.")
	)
	_btn(r1, "Ouvrir catalogue", func() -> void:
		EventBus.block_interacted.emit(Vector3i(0,0,0), 59, _player)  # crafting_table block ID
		_ok("Catalogue ouvert.")
	)

	# Basic survival items
	var r2 := _make_section(vb, "📦 Items de survie")
	_btn(r2, "Diamants ×32",   func(): _give_stack({"id": "axiom:diamond",     "count": 32}))
	_btn(r2, "Émeraudes ×16",  func(): _give_stack({"id": "axiom:emerald",     "count": 16}))
	_btn(r2, "Nourriture",     func(): _give_stack({"id": "axiom:bread",       "count": 16}); _give_stack({"id": "axiom:cooked_beef", "count": 8}))
	_btn(r2, "Charbon ×64",    func(): _give_stack({"id": "axiom:coal",        "count": 64}))
	_btn(r2, "Blé ×32",        func(): _give_stack({"id": "axiom:wheat",       "count": 32}))
	_btn(r2, "Lingots fer ×16",func(): _give_stack({"id": "axiom:iron_ingot",  "count": 16}))

	# Weapons
	var r3 := _make_section(vb, "⚔ Armes  [Idée #8 — styles de combat]")
	_btn(r3, "Épée de fer",     func(): _give_stack({"id": "axiom:iron_sword",    "count": 1}))
	_btn(r3, "Épée diamant",    func(): _give_stack({"id": "axiom:diamond_sword", "count": 1}))
	_btn(r3, "Arc + flèches",   func(): _give_stack({"id": "axiom:bow", "count": 1}); _give_stack({"id": "axiom:arrow", "count": 32}))
	_btn(r3, "Hache de fer",    func(): _give_stack({"id": "axiom:iron_axe",      "count": 1}))

	# Misc
	var r4 := _make_section(vb, "🧪 Divers")
	_btn(r4, "Vider inventaire", func() -> void:
		if _player == null or _player.inventory == null: _err("Joueur non chargé"); return
		for i in 36: _player.inventory.set_slot(i, {})
		_ok("Inventaire vidé.")
	)
	_btn(r4, "Tout donner (pack complet)", func() -> void:
		_give_starter_pack()
	)


func _give_starter_pack() -> void:
	_give_stack({"id": "axiom:diamond_sword",    "count": 1})
	_give_stack({"id": "axiom:diamond_pickaxe",  "count": 1})
	_give_stack({"id": "axiom:diamond",          "count": 64})
	_give_stack({"id": "axiom:emerald",          "count": 32})
	_give_stack({"id": "axiom:coal",             "count": 64})
	_give_stack({"id": "axiom:bread",            "count": 32})
	_give_stack({"id": "axiom:iron_ingot",       "count": 32})
	_give_stack({"id": "axiom:portable_workbench","count": 1})
	_give_stack({"id": "axiom:architect_map",    "count": 1})
	for i in range(1, 5):
		_give_stack({"id": "axiom:soul_fragment_%d" % i, "count": 1})
	_add_skill_points(10)
	_ok("Pack de démarrage complet donné ! Tous les items de test présents.")


# ═══════════════════════════════════════════════════════════════════════════════
# TAB 6 — STATUS EN DIRECT
# ═══════════════════════════════════════════════════════════════════════════════

func _build_tab_status() -> void:
	var vb := _make_scroll_tab("📊 Status")

	var r1 := _make_section(vb, "Rafraîchir")
	_btn(r1, "🔄 Actualiser", func(): _refresh_status())

	var status_box := VBoxContainer.new()
	status_box.add_theme_constant_override("separation", 4)
	vb.add_child(status_box)

	var _status_detail := Label.new()
	_status_detail.name = "StatusDetail"
	_status_detail.add_theme_font_size_override("font_size", 12)
	_status_detail.add_theme_color_override("font_color", Color(0.85, 0.90, 0.85))
	_status_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_box.add_child(_status_detail)


func _refresh_status() -> void:
	var detail := _tab.get_node_or_null("📊 Status/ScrollContainer/VBoxContainer/StatusDetail") as Label
	if detail == null:
		return

	var lines: Array[String] = []

	# Time
	lines.append("═══ TEMPS ═══")
	lines.append("  Jour : %d  |  Heure : %s  |  t=%.3f" % [
		TimeManager.current_day, TimeManager.get_time_string(), TimeManager.current_time])
	lines.append("  Phase lunaire : %s  |  Blood Moon : %s" % [
		TimeManager.get_phase_name(),
		"OUI 🌑" if TimeManager.is_blood_moon else "non"])
	lines.append("  Prochain BM prévu : jour %d" % TimeManager._blood_moon_day)

	# Season
	lines.append("")
	lines.append("═══ SAISONS / MÉTÉO ═══")
	lines.append("  Saison : %s %s  (jour %d/%d)" % [
		SeasonManager.get_season_icon(), SeasonManager.get_season_name(),
		SeasonManager.day_in_season + 1, SeasonManager.DAYS_PER_SEASON])
	lines.append("  Météo : %s %s" % [
		SeasonManager.get_weather_icon(), SeasonManager.get_weather_name()])
	lines.append("  Multiplicateur cultures : ×%.1f" % SeasonManager.get_growth_multiplier())

	# Quest
	lines.append("")
	lines.append("═══ QUÊTES ═══")
	lines.append("  Réputation : %d  (%s)" % [QuestManager.reputation, QuestManager.get_reputation_label()])
	if QuestManager.has_active_quest():
		var q := QuestManager.get_active_quest()
		lines.append("  Quête active : %s [%s]" % [q.get("id","?"), q.get("type","?")])
		lines.append("  Progression : %d / %d  |  Prête : %s" % [
			q.get("progress",0), q.get("count",1),
			"OUI ✓" if QuestManager.is_quest_ready_to_turn_in() else "non"])
	else:
		lines.append("  Aucune quête active.")

	# Skills
	lines.append("")
	lines.append("═══ ARBRE RPG ═══")
	if _player != null and _player.skill_tree != null:
		var st := _player.skill_tree
		lines.append("  Points disponibles : %d" % st.available_points)
		lines.append("  Skills débloqués : %d  → %s" % [
			st.unlocked.size(),
			", ".join(st.unlocked.keys()) if not st.unlocked.is_empty() else "aucun"])
	else:
		lines.append("  Joueur non chargé.")

	# Player
	lines.append("")
	lines.append("═══ JOUEUR ═══")
	if _player != null:
		lines.append("  PV : %.1f / %.1f  |  Faim : %.1f" % [
			_player.health, _player.max_health, _player.hunger])
		lines.append("  XP : %d  |  Niveau : %d" % [_player.xp, _player.xp_level])
		lines.append("  Pos : %.1f  %.1f  %.1f" % [
			_player.global_position.x,
			_player.global_position.y,
			_player.global_position.z])
	else:
		lines.append("  Joueur non chargé.")

	detail.text = "\n".join(lines)
	_ok("Status actualisé.")


# ── Inventory helper ───────────────────────────────────────────────────────────

func _give_stack(stack: Dictionary) -> void:
	if _player == null:
		_player = GameManager.local_player as Player
	if _player == null or _player.inventory == null:
		_err("Joueur non chargé ou inventaire absent."); return
	var id:  String = stack.get("id", stack.get("item", ""))
	var cnt: int    = stack.get("count", 1)
	# Only pass special meta — not the full stack dict (breaks meta matching in add_items)
	var meta: Dictionary = {}
	if stack.has("enchantments"):   meta["enchantments"]    = stack["enchantments"]
	if stack.has("artifact_name"):  meta["artifact_name"]   = stack["artifact_name"]
	if stack.has("artifact_bonuses"): meta["artifact_bonuses"] = stack["artifact_bonuses"]
	var leftover := _player.inventory.add_items(id, cnt, meta)
	if leftover > 0:
		_err("Inventaire plein — %d %s non ajouté(s)." % [leftover, id])
	else:
		_ok("Donné : %s ×%d  (vérifiez votre inventaire E)" % [id, cnt])
	EventBus.show_message.emit("Debug: %s ×%d ajouté" % [id, cnt], 2.5)
