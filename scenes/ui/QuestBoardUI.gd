## QuestBoardUI.gd
## Full-screen overlay shown when interacting with a quest_board block (ID 258).
## Displays 3 village quests, lets the player accept one, and complete the active quest.
class_name QuestBoardUI
extends CanvasLayer

const RARITY_COL_KILL    := Color(0.90, 0.30, 0.30)
const RARITY_COL_BRING   := Color(0.40, 0.80, 0.40)
const RARITY_COL_EXPLORE := Color(0.40, 0.70, 1.00)

var _root:      Control = null
var _rep_lbl:   Label   = null
var _quest_rows: Array  = []   # Array of Control (one per quest slot)

var _village_cx: int = 0
var _village_cz: int = 0
var _quests:     Array = []
var _player_ref: Player = null

signal closed()


func _ready() -> void:
	layer     = 10
	visible   = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func open(village_cx: int, village_cz: int, player: Player) -> void:
	_village_cx = village_cx
	_village_cz = village_cz
	_player_ref = player
	_quests     = QuestManager.get_village_quests(village_cx, village_cz)
	_refresh()
	visible = true
	GameManager.ui_open()


func close() -> void:
	visible = false
	GameManager.ui_close()
	emit_signal("closed")


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()


# ── UI construction ────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Dark overlay
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.60)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	_root = Control.new()
	_root.anchor_left   = 0.5
	_root.anchor_right  = 0.5
	_root.anchor_top    = 0.5
	_root.anchor_bottom = 0.5
	_root.offset_left   = -300
	_root.offset_right  = 300
	_root.offset_top    = -280
	_root.offset_bottom = 280
	add_child(_root)

	# Panel background
	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg_s := StyleBoxFlat.new()
	bg_s.bg_color                   = Color(0.08, 0.07, 0.05, 0.96)
	bg_s.border_width_left          = 2
	bg_s.border_width_right         = 2
	bg_s.border_width_top           = 2
	bg_s.border_width_bottom        = 2
	bg_s.border_color               = Color(0.65, 0.50, 0.15, 0.95)
	bg_s.corner_radius_top_left     = 6
	bg_s.corner_radius_top_right    = 6
	bg_s.corner_radius_bottom_left  = 6
	bg_s.corner_radius_bottom_right = 6
	bg.add_theme_stylebox_override("panel", bg_s)
	_root.add_child(bg)

	# Title
	var title := Label.new()
	title.anchor_left  = 0.0; title.anchor_right  = 1.0
	title.offset_top   = 12;  title.offset_bottom = 44
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "Panneau d'Affichage du Village"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.20))
	_root.add_child(title)

	# Reputation label
	_rep_lbl = Label.new()
	_rep_lbl.anchor_left  = 0.0; _rep_lbl.anchor_right  = 1.0
	_rep_lbl.offset_top   = 44;  _rep_lbl.offset_bottom = 64
	_rep_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rep_lbl.add_theme_font_size_override("font_size", 13)
	_rep_lbl.add_theme_color_override("font_color", Color(0.80, 0.80, 0.80))
	_root.add_child(_rep_lbl)

	# Quest rows
	for i in 3:
		var row := _build_quest_row(i)
		_quest_rows.append(row)
		_root.add_child(row)

	# Close button
	var close_btn := Button.new()
	close_btn.anchor_left   = 0.5; close_btn.anchor_right   = 0.5
	close_btn.anchor_top    = 1.0; close_btn.anchor_bottom  = 1.0
	close_btn.offset_left   = -60; close_btn.offset_right   = 60
	close_btn.offset_top    = -44; close_btn.offset_bottom  = -10
	close_btn.text = "Fermer"
	close_btn.add_theme_font_size_override("font_size", 13)
	close_btn.pressed.connect(close)
	_root.add_child(close_btn)


func _build_quest_row(index: int) -> Control:
	var row := Control.new()
	row.anchor_left   = 0.0; row.anchor_right  = 1.0
	row.offset_left   = 16;  row.offset_right  = -16
	var y_top := 72 + index * 138
	row.offset_top    = y_top
	row.offset_bottom = y_top + 128

	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var s := StyleBoxFlat.new()
	s.bg_color                   = Color(0.12, 0.11, 0.08, 0.90)
	s.corner_radius_top_left     = 4
	s.corner_radius_top_right    = 4
	s.corner_radius_bottom_left  = 4
	s.corner_radius_bottom_right = 4
	bg.add_theme_stylebox_override("panel", s)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bg)

	var desc := Label.new()
	desc.name = "Desc"
	desc.anchor_left  = 0.0; desc.anchor_right  = 0.68
	desc.offset_left  = 10;  desc.offset_top    = 8
	desc.offset_bottom = 50
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	row.add_child(desc)

	var progress := Label.new()
	progress.name = "Progress"
	progress.anchor_left  = 0.0; progress.anchor_right  = 0.68
	progress.offset_left  = 10;  progress.offset_top    = 52
	progress.offset_bottom = 78
	progress.add_theme_font_size_override("font_size", 12)
	progress.add_theme_color_override("font_color", Color(0.70, 0.90, 0.70))
	row.add_child(progress)

	var reward_lbl := Label.new()
	reward_lbl.name = "Reward"
	reward_lbl.anchor_left  = 0.0; reward_lbl.anchor_right  = 0.68
	reward_lbl.offset_left  = 10;  reward_lbl.offset_top    = 80
	reward_lbl.offset_bottom = 110
	reward_lbl.add_theme_font_size_override("font_size", 11)
	reward_lbl.add_theme_color_override("font_color", Color(0.80, 0.75, 0.40))
	row.add_child(reward_lbl)

	var btn := Button.new()
	btn.name = "ActionBtn"
	btn.anchor_left   = 0.70; btn.anchor_right  = 0.98
	btn.anchor_top    = 0.15; btn.anchor_bottom = 0.85
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(_on_quest_btn_pressed.bind(index))
	row.add_child(btn)

	return row


# ── Refresh ────────────────────────────────────────────────────────────────────

func _refresh() -> void:
	_rep_lbl.text = "Réputation : %d  (%s)" % [
		QuestManager.reputation,
		QuestManager.get_reputation_label(),
	]
	# Poll bring progress if active quest is bring-type
	if QuestManager.has_active_quest() and _player_ref != null:
		if QuestManager.get_active_quest().get("type") == "bring":
			QuestManager.poll_bring_progress(_player_ref.inventory)

	for i in 3:
		if i >= _quests.size():
			_quest_rows[i].visible = false
			continue
		_quest_rows[i].visible = true
		_populate_row(i, _quests[i])


func _populate_row(idx: int, quest: Dictionary) -> void:
	var row: Control = _quest_rows[idx]
	var desc   := row.get_node("Desc")    as Label
	var prog   := row.get_node("Progress") as Label
	var reward := row.get_node("Reward")   as Label
	var btn    := row.get_node("ActionBtn") as Button

	# Description with count substitution
	var raw_desc: String = quest.get("desc", "")
	desc.text = raw_desc.replace("{count}", str(quest.get("count", 1)))

	# Type colour tint
	match quest.get("type", ""):
		"kill":    desc.add_theme_color_override("font_color", RARITY_COL_KILL)
		"bring":   desc.add_theme_color_override("font_color", RARITY_COL_BRING)
		"explore": desc.add_theme_color_override("font_color", RARITY_COL_EXPLORE)
		_:         desc.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))

	# Rewards
	var r: Dictionary = quest.get("rewards", {})
	reward.text = "%d émeraudes  +%d XP  +%d rép." % [
		r.get("emeralds", 0), r.get("xp", 0), r.get("rep", 0)
	]

	# Active quest status
	var active := QuestManager.get_active_quest()
	var this_is_active: bool = QuestManager.has_active_quest() \
		and active.get("id") == quest.get("id")

	if this_is_active:
		var needed: int = active.get("count", 1)
		var current: int = active.get("progress", 0)
		prog.text = "Progression : %d / %d" % [current, needed]
		if QuestManager.is_quest_ready_to_turn_in():
			btn.text     = "Terminer"
			btn.disabled = false
		else:
			btn.text     = "En cours..."
			btn.disabled = true
	else:
		prog.text    = ""
		var can_accept := not QuestManager.has_active_quest()
		btn.text     = "Accepter" if can_accept else "—"
		btn.disabled = not can_accept


func _on_quest_btn_pressed(index: int) -> void:
	if index >= _quests.size():
		return
	var quest: Dictionary = _quests[index]
	var active := QuestManager.get_active_quest()
	var this_is_active: bool = QuestManager.has_active_quest() \
		and active.get("id") == quest.get("id")

	if this_is_active and QuestManager.is_quest_ready_to_turn_in():
		# Complete quest — remove items for bring quests, give rewards
		if quest.get("type") == "bring" and _player_ref != null:
			# Re-poll right before submitting to guard against inventory changes
			# since the board was opened.
			QuestManager.poll_bring_progress(_player_ref.inventory)
			if not QuestManager.is_quest_ready_to_turn_in():
				EventBus.show_message.emit("Objets insuffisants dans l'inventaire.", 3.0)
				_refresh()
				return
			var item_id: String = quest.get("item", "")
			var needed:  int    = quest.get("count", 1)
			_remove_items_from_inventory(item_id, needed)

		QuestManager.complete_quest()
		# Give emerald + XP rewards via player
		if _player_ref != null:
			var rewards: Dictionary = quest.get("rewards", {})
			_player_ref.inventory.add_items(
				"axiom:emerald", rewards.get("emeralds", 0), {})
			_player_ref.add_xp(rewards.get("xp", 0))
		EventBus.show_message.emit("Quête accomplie ! Récompenses reçues.", 4.0)
		_quests = QuestManager.get_village_quests(_village_cx, _village_cz)
	else:
		# Accept quest
		QuestManager.accept_quest(quest, _village_cx, _village_cz)
		EventBus.show_message.emit("Quête acceptée : %s" % quest.get("desc",""), 3.5)

	_refresh()


func _remove_items_from_inventory(item_id: String, count: int) -> void:
	if _player_ref == null or _player_ref.inventory == null:
		return
	var remaining := count
	for i in 36:
		if remaining <= 0:
			break
		var slot := _player_ref.inventory.get_slot(i)
		if slot.get("id", "") != item_id:
			continue
		var in_slot: int = slot.get("count", 0)
		if in_slot <= remaining:
			remaining -= in_slot
			_player_ref.inventory.set_slot(i, {})
		else:
			slot["count"] = in_slot - remaining
			_player_ref.inventory.set_slot(i, slot)
			remaining = 0
