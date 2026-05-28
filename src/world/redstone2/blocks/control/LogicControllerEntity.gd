## LogicControllerEntity.gd — Logic controller (Contrôleur logique). ID 4050.
## Evaluates conditional rules against its input channels and emits output channels.
## Rules are stored as an Array of Dictionaries: [{cond, op, threshold, out_ch, out_val}]
## Example: if channel 0 > 128 AND channel 1 == true → emit channel 0 = 255
class_name LogicControllerEntity
extends R2BlockEntity

# Each rule: { "inputs": [{ch, op, val}], "logic": "AND"|"OR", "out_ch": int, "out_val": int }
# op: "gt","lt","eq","neq","gte","lte","bool_true","bool_false"
var rules: Array = []

var _outputs_this_tick: Dictionary = {}


func _init(pos: Vector3i) -> void:
	super(pos, "r2_controller")


func _get_input_faces() -> Array:
	return ALL_FACES


func _get_output_faces() -> Array:
	return ALL_FACES


func phase_calculate() -> void:
	_outputs_this_tick.clear()

	for rule in rules:
		if not rule is Dictionary: continue
		var conditions: Array = rule.get("inputs", [])
		var logic: String     = rule.get("logic", "AND")
		var out_ch: int       = rule.get("out_ch", 0)
		var out_val: int      = rule.get("out_val", 255)

		var results: Array[bool] = []
		for cond in conditions:
			if not cond is Dictionary: continue
			var ch: int    = cond.get("ch", 0)
			var op: String = cond.get("op", "bool_true")
			var thr: int   = cond.get("val", 1)
			var sig        := get_input(ch)
			var val: int   = sig.to_analog() if sig != null else 0
			var res := false
			match op:
				"bool_true":  res = (val > 0)
				"bool_false": res = (val == 0)
				"gt":         res = (val > thr)
				"lt":         res = (val < thr)
				"eq":         res = (val == thr)
				"neq":        res = (val != thr)
				"gte":        res = (val >= thr)
				"lte":        res = (val <= thr)
			results.append(res)

		var triggered := false
		if results.is_empty():
			triggered = false
		elif logic == "OR":
			for r in results:
				if r: triggered = true
		else:   # AND
			triggered = true
			for r in results:
				if not r: triggered = false

		if triggered:
			_outputs_this_tick[out_ch] = out_val


func phase_emit() -> void:
	for ch in range(16):
		if _outputs_this_tick.has(ch):
			_next_outputs[ch] = R2Signal.make_analog(_outputs_this_tick[ch], ch, world_pos)
		else:
			_next_outputs[ch] = R2Signal.make_analog(0, ch, world_pos)
	super.phase_emit()


func serialize() -> Dictionary:
	var d := super.serialize()
	d["rules"] = rules.duplicate(true)
	return d


func deserialize(data: Dictionary) -> void:
	rules = data.get("rules", [])
	super.deserialize(data)
