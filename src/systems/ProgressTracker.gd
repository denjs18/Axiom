## ProgressTracker.gd — Lightweight vanilla advancement system.
## Watches EventBus for gameplay milestones and emits advancement_unlocked,
## which the HUD turns into a toast (with the chime). Unlocks persist in
## user://progress.json so toasts never repeat across sessions.
extends Node

const SAVE_PATH := "user://progress.json"

# id → [title, description] (shown in the HUD toast)
const _DEFS: Dictionary = {
	"first_wood":    ["Bûcheron", "Ramassez votre premier tronc"],
	"craft_table":   ["L'établi", "Fabriquez une table d'artisanat"],
	"wood_pickaxe":  ["À la mine !", "Fabriquez une pioche en bois"],
	"stone_age":     ["L'âge de pierre", "Ramassez de la pierre"],
	"furnace":       ["Ça chauffe", "Fabriquez un four"],
	"iron_age":      ["L'âge du fer", "Obtenez un lingot de fer"],
	"diamonds":      ["DIAMANTS !", "Trouvez des diamants"],
	"obsidian":      ["Larmes de lave", "Minez de l'obsidienne"],
	"nether":        ["Les Enfers", "Traversez un portail du Nether"],
	"the_end":       ["La fin du début", "Entrez dans l'End"],
	"first_morning": ["Premier matin", "Survivez à votre première nuit"],
	"first_kill":    ["Chasseur", "Éliminez votre premier monstre"],
	"boss_slayer":   ["Tombeur de titans", "Vainquez un boss"],
}

var _unlocked: Dictionary = {}


func _ready() -> void:
	_load()
	EventBus.item_picked_up.connect(_on_item_picked_up)
	EventBus.item_crafted.connect(_on_item_crafted)
	EventBus.block_broken.connect(_on_block_broken)
	EventBus.player_dimension_changed.connect(_on_dimension_changed)
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.mob_died.connect(_on_mob_died)
	EventBus.boss_defeated.connect(_on_boss_defeated)


func unlock(id: String) -> void:
	if _unlocked.has(id) or not _DEFS.has(id):
		return
	_unlocked[id] = true
	_save()
	var d: Array = _DEFS[id]
	EventBus.advancement_unlocked.emit(id, str(d[0]), str(d[1]))


func is_unlocked(id: String) -> bool:
	return _unlocked.has(id)


# ── Triggers ───────────────────────────────────────────────────────────────────

func _on_item_picked_up(stack: Dictionary, _player: Node) -> void:
	var iid := str(stack.get("id", ""))
	if ":" in iid:
		iid = iid.split(":")[-1]
	if iid.ends_with("_log"):
		unlock("first_wood")
	elif iid == "cobblestone" or iid == "stone":
		unlock("stone_age")
	elif iid == "iron_ingot":
		unlock("iron_age")
	elif iid == "diamond":
		unlock("diamonds")


func _on_item_crafted(result: Dictionary, _player: Node) -> void:
	var rid := str(result.get("id", ""))
	if ":" in rid:
		rid = rid.split(":")[-1]
	match rid:
		"crafting_table": unlock("craft_table")
		"wooden_pickaxe": unlock("wood_pickaxe")
		"furnace":        unlock("furnace")


func _on_block_broken(_pos: Vector3i, block_id: int, player: Node) -> void:
	if block_id == 101 and player is Player:   # obsidian
		unlock("obsidian")


func _on_dimension_changed(_player: Node, _from: String, to: String) -> void:
	if to == "nether":
		unlock("nether")
	elif to == "the_end":
		unlock("the_end")


func _on_day_changed(day: int) -> void:
	if day >= 1 and GameManager.current_state == GameManager.GameState.PLAYING:
		unlock("first_morning")


func _on_mob_died(mob: Node, killer: Node) -> void:
	if mob is BaseHostile and killer is Player:
		unlock("first_kill")


func _on_boss_defeated(_boss_name: String) -> void:
	unlock("boss_slayer")


# ── Persistence ────────────────────────────────────────────────────────────────

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		_unlocked = data


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_unlocked))
