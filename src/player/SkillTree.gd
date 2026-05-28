## SkillTree.gd — RPG skill tree data and bonus system.
## One instance per player, added as a child Node in Player._ready().
## Points are awarded every 5 XP levels; skills unlock permanently (never lost on death).
class_name SkillTree
extends Node

var _skill_defs: Array[Dictionary] = []   # ordered list from JSON
var _skill_map:  Dictionary        = {}   # id → def dict (fast lookup)
var unlocked:    Dictionary        = {}   # skill_id → true
var available_points: int          = 0


func _ready() -> void:
	_load_skills()


func _load_skills() -> void:
	var f := FileAccess.open("res://data/skills/skills.json", FileAccess.READ)
	if f == null:
		push_error("SkillTree: cannot open data/skills/skills.json")
		return
	var text := f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if not data is Dictionary:
		push_error("SkillTree: invalid JSON")
		return
	for skill in data.get("skills", []):
		_skill_defs.append(skill)
		_skill_map[skill["id"]] = skill


# ── Queries ────────────────────────────────────────────────────────────────────

func get_all_skills() -> Array[Dictionary]:
	return _skill_defs


func get_skills_for_class(cls: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for skill in _skill_defs:
		if skill.get("class", "") == cls:
			result.append(skill)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["tier"] != b["tier"]:
			return a["tier"] < b["tier"]
		return a.get("slot", 0) < b.get("slot", 0)
	)
	return result


func get_skill_def(skill_id: String) -> Dictionary:
	return _skill_map.get(skill_id, {})


func has_skill(skill_id: String) -> bool:
	return unlocked.has(skill_id)


func can_unlock(skill_id: String) -> bool:
	if available_points <= 0:
		return false
	if unlocked.has(skill_id):
		return false
	var def: Dictionary = _skill_map.get(skill_id, {})
	if def.is_empty():
		return false
	if not def.get("implemented", false):
		return false
	var tier: int = def.get("tier", 1)
	if tier == 1:
		return true
	var cls: String = def.get("class", "")
	return _has_unlocked_in_tier_class(tier - 1, cls)


func _has_unlocked_in_tier_class(tier: int, cls: String) -> bool:
	for skill_id in unlocked:
		var d: Dictionary = _skill_map.get(skill_id, {})
		if d.get("class", "") == cls and d.get("tier", 0) == tier:
			return true
	return false


func unlock(skill_id: String) -> bool:
	if not can_unlock(skill_id):
		return false
	unlocked[skill_id] = true
	available_points -= 1
	EventBus.skill_unlocked.emit(skill_id)
	return true


# ── Bonus getters ──────────────────────────────────────────────────────────────

func mining_speed_mult() -> float:
	return 1.30 if has_skill("mineur_vitesse") else 1.0


func vein_limit() -> int:
	return 64 if has_skill("mineur_vein2") else 32


func fortune_bonus() -> int:
	return 1 if has_skill("mineur_fortune") else 0


func attack_damage_mult() -> float:
	var m := 1.0
	if has_skill("guerrier_degats"):   m += 0.20
	if has_skill("guerrier_seigneur"): m += 0.30
	return m


func max_health_bonus() -> float:
	return 4.0 if has_skill("guerrier_vie") else 0.0


func damage_reduction_mult() -> float:
	var m := 1.0
	if has_skill("guerrier_resistance"): m -= 0.10
	if has_skill("guerrier_seigneur"):   m -= 0.10
	return maxf(m, 0.1)


func execute_damage_mult(target_hp_ratio: float, threshold: float = 0.25) -> float:
	if has_skill("guerrier_executeur") and target_hp_ratio < threshold:
		return 2.0
	return 1.0


func sprint_speed_mult() -> float:
	var bonus := 0.0
	if has_skill("ingenieur_sprint"):       bonus += 0.30
	if has_skill("ingenieur_exosquelette"): bonus += 0.30
	return 1.0 + bonus


func jump_mult() -> float:
	return 1.5 if has_skill("ingenieur_exosquelette") else 1.0


func has_no_fall_damage() -> bool:
	return has_skill("ingenieur_exosquelette")


func xp_gain_mult() -> float:
	return 1.30 if has_skill("mage_xp") else 1.0


func food_regen_mult() -> float:
	return 1.50 if has_skill("fermier_regen") else 1.0


func is_3x3_enabled() -> bool:
	return has_skill("mineur_3x3")


# ── Serialization ──────────────────────────────────────────────────────────────

func serialize() -> Dictionary:
	return {
		"unlocked":          unlocked.keys(),
		"available_points":  available_points,
	}


func deserialize(data: Dictionary) -> void:
	unlocked.clear()
	for sid in data.get("unlocked", []):
		unlocked[sid] = true
	available_points = data.get("available_points", 0)
