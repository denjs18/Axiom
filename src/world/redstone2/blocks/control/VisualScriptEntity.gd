## VisualScriptEntity.gd — Visual script block (Script visuel). ID 4054.
## Stores a node graph (event → condition → action) as data and evaluates it each tick.
## Intended for in-game visual editing; graph is serialized as a node/edge list.
class_name VisualScriptEntity
extends R2BlockEntity

# Node types: "event_in", "condition", "action_out", "math", "memory_read", "constant"
# Each node: { "id": int, "type": String, "params": {}, "out_edges": [node_id, ...] }
# Evaluation: topological sort → eval each node → drive output channels

var graph_nodes: Array = []   # Array of Dictionaries (see above)
var _node_values: Dictionary = {}   # node_id → computed value (int or bool)


func _init(pos: Vector3i) -> void:
	super(pos, "r2_visual_script")


func _get_input_faces() -> Array:
	return ALL_FACES


func _get_output_faces() -> Array:
	return ALL_FACES


func phase_calculate() -> void:
	_node_values.clear()
	if graph_nodes.is_empty(): return

	# Topological evaluation: process nodes in order (user must ensure no cycles via analyser)
	for node in graph_nodes:
		if not node is Dictionary: continue
		_eval_node(node)


func _eval_node(node: Dictionary) -> void:
	var nid:  int    = node.get("id", -1)
	var ntype: String = node.get("type", "")
	var params: Dictionary = node.get("params", {})

	var result: int = 0

	match ntype:
		"constant":
			result = params.get("value", 0)

		"event_in":
			var ch: int = params.get("ch", 0)
			var sig := get_input(ch)
			result = sig.to_analog() if sig != null else 0

		"condition":
			var in_id: int  = params.get("input_node", -1)
			var op: String  = params.get("op", "gt")
			var thr: int    = params.get("threshold", 128)
			var in_val: int = _node_values.get(in_id, 0)
			var passes := false
			match op:
				"gt":  passes = in_val > thr
				"lt":  passes = in_val < thr
				"eq":  passes = in_val == thr
				"neq": passes = in_val != thr
				"gte": passes = in_val >= thr
				"lte": passes = in_val <= thr
			result = 255 if passes else 0

		"math":
			var a_id: int = params.get("a_node", -1)
			var b_id: int = params.get("b_node", -1)
			var op: String = params.get("op", "add")
			var a: int = _node_values.get(a_id, 0)
			var b: int = _node_values.get(b_id, 0)
			match op:
				"add": result = clampi(a + b, 0, 255)
				"sub": result = clampi(a - b, 0, 255)
				"mul": result = clampi(a * b / 255, 0, 255)
				"div": result = clampi(a / maxi(b, 1), 0, 255)
				"min": result = mini(a, b)
				"max": result = maxi(a, b)
				"not": result = 255 - a

		"action_out":
			var in_id: int = params.get("input_node", -1)
			var ch: int    = params.get("ch", 0)
			result = _node_values.get(in_id, 0)
			_next_outputs[ch] = R2Signal.make_analog(result, ch, world_pos)

	_node_values[nid] = result


func phase_emit() -> void:
	super.phase_emit()


func serialize() -> Dictionary:
	var d := super.serialize()
	d["graph_nodes"] = graph_nodes.duplicate(true)
	return d


func deserialize(data: Dictionary) -> void:
	graph_nodes = data.get("graph_nodes", [])
	super.deserialize(data)
