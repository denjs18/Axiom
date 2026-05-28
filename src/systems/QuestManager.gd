## QuestManager.gd
## Autoload singleton — manages village quests and player reputation.
## Reputation range : -100 (paria) → +100 (héros).
## Each village cell (cx,cz) gets 3 deterministic quest slots seeded from world_seed.
## Only 1 quest can be active at a time.
extends Node

# ── Reputation ─────────────────────────────────────────────────────────────────

var reputation: int = 0

const REP_LABELS := {
	-100: "Paria",    -50: "Ennemi",   -20: "Méfiant",
	   0: "Neutre",    20: "Ami",        50: "Allié",
	  80: "Héros",
}

const REP_KILL_MOB_NEAR   :=  1    # hostile mob killed near a village
const REP_COMPLETE_QUEST   := 0    # value comes from the quest itself
const REP_KILL_VILLAGER    := -30
const REP_STEAL_CHEST      := -15

func add_reputation(delta: int) -> void:
	reputation = clampi(reputation + delta, -100, 100)
	EventBus.reputation_changed.emit(reputation)

func get_reputation_label() -> String:
	var best_threshold := -100
	for t in REP_LABELS:
		if reputation >= t and t >= best_threshold:
			best_threshold = t
	return REP_LABELS.get(best_threshold, "Neutre")

# ── Thresholds ─────────────────────────────────────────────────────────────────

func has_merchant_discount() -> bool: return reputation >= 20
func has_guard_ally()        -> bool: return reputation >= 50
func has_special_merchant()  -> bool: return reputation >= 80
func is_hostile_to_guards()  -> bool: return reputation <= -50
func is_merchant_banned()    -> bool: return reputation <= -20

# ── Templates ──────────────────────────────────────────────────────────────────

var _templates: Array = []

func _ready() -> void:
	EventBus.mob_died.connect(_on_mob_died)
	EventBus.item_picked_up.connect(_on_item_picked_up)
	_load_templates()

func _load_templates() -> void:
	var path := "res://data/quests/quests_templates.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Array:
		_templates = parsed

# ── Village quest generation ────────────────────────────────────────────────────
# Returns 3 quests deterministically for a given village cell (cx, cz).

func get_village_quests(cx: int, cz: int) -> Array:
	if _templates.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(GameManager.world_seed ^ (cx * 73856093) ^ (cz * 19349663))
	var pool := _templates.duplicate()
	# Fisher-Yates with our RNG
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp: Variant = pool[i]; pool[i] = pool[j]; pool[j] = tmp
	var result: Array = []
	for i in mini(3, pool.size()):
		var q: Dictionary = (pool[i] as Dictionary).duplicate(true)
		# For explore quests: place a random target offset
		if q["type"] == "explore":
			var radius: int = q.get("radius", 500)
			var angle  := rng.randf_range(0.0, TAU)
			var dist   := rng.randi_range(200, radius)
			q["target_wx"] = cx * 200 + int(cos(angle) * dist)
			q["target_wz"] = cz * 200 + int(sin(angle) * dist)
		q["status"] = "available"   # available | active | completed
		q["progress"] = 0
		result.append(q)
	return result

# ── Active quest ───────────────────────────────────────────────────────────────

var _active_quest: Dictionary = {}
var _active_village_cx: int   = 0
var _active_village_cz: int   = 0

func accept_quest(quest: Dictionary, village_cx: int, village_cz: int) -> void:
	_active_quest       = quest.duplicate(true)
	_active_quest["status"]   = "active"
	_active_quest["progress"] = 0
	_active_village_cx  = village_cx
	_active_village_cz  = village_cz
	EventBus.quest_accepted.emit(_active_quest.duplicate())

func has_active_quest() -> bool:
	return not _active_quest.is_empty() and _active_quest.get("status") == "active"

func get_active_quest() -> Dictionary:
	return _active_quest

func complete_quest() -> void:
	if not has_active_quest():
		return
	var q := _active_quest
	var rewards: Dictionary = q.get("rewards", {})
	add_reputation(rewards.get("rep", 10))
	# Emeralds + XP granted in World.gd (needs inventory access)
	_active_quest = {}
	EventBus.quest_completed.emit(q.duplicate(), rewards.duplicate())

func is_quest_ready_to_turn_in() -> bool:
	if not has_active_quest():
		return false
	var q := _active_quest
	var needed: int = q.get("count", 1)
	return q.get("progress", 0) >= needed

# ── Progress tracking ──────────────────────────────────────────────────────────

func _on_mob_died(mob: Node, _killer: Node) -> void:
	if not has_active_quest():
		return
	var q := _active_quest
	if q.get("type") != "kill":
		return
	# Use the mob's species field (set on BaseMob) for reliable matching.
	# Fall back to node name only if species is empty (non-BaseMob entity).
	var mob_species: String = ""
	if mob != null:
		var sp = mob.get("species")
		mob_species = str(sp).to_lower() if sp != null and str(sp) != "" else mob.name.to_lower()
	var target: String = q.get("mob", "").to_lower()
	if target.is_empty() or mob_species == target:
		_active_quest["progress"] = _active_quest.get("progress", 0) + 1
		EventBus.quest_progress_updated.emit(_active_quest.duplicate())

func _on_item_picked_up(stack: Dictionary, _player: Node) -> void:
	if not has_active_quest():
		return
	var q := _active_quest
	if q.get("type") != "bring":
		return
	# Bring quests: player just needs to have the items when turning in;
	# update progress to reflect current count (polled on board open, not here).
	pass

func notify_explore(player_pos: Vector3) -> void:
	if not has_active_quest():
		return
	var q := _active_quest
	if q.get("type") != "explore":
		return
	if q.get("progress", 0) >= 1:
		return
	var tx: float = float(q.get("target_wx", 0)) + 8.0
	var tz: float = float(q.get("target_wz", 0)) + 8.0
	if Vector2(player_pos.x - tx, player_pos.z - tz).length() < 25.0:
		_active_quest["progress"] = 1
		EventBus.quest_progress_updated.emit(_active_quest.duplicate())

func poll_bring_progress(inventory) -> void:
	if not has_active_quest():
		return
	var q := _active_quest
	if q.get("type") != "bring":
		return
	var item_id: String = q.get("item", "")
	var needed:  int    = q.get("count", 1)
	var held    := 0
	if inventory != null:
		for i in 36:
			var slot: Dictionary = inventory.get_slot(i)
			if slot.get("id", "") == item_id:
				held += slot.get("count", 0)
	_active_quest["progress"] = mini(held, needed)
	EventBus.quest_progress_updated.emit(_active_quest.duplicate())
