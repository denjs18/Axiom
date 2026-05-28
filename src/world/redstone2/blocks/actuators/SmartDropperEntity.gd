## SmartDropperEntity.gd — Smart dropper (Dropper intelligent). ID 4063.
## Transfers items to adjacent container on trigger. Supports queue ack and filter.
class_name SmartDropperEntity
extends R2BlockEntity

var filter_item:  String  = ""      # empty = any
var target_face:  Vector3i = FACE_NX
var batch_size:   int     = 1       # items per trigger
var _ack:         bool    = false   # last transfer success
var _error:       bool    = false


func _init(pos: Vector3i) -> void:
	super(pos, "r2_dropper2")


func _get_input_faces() -> Array:
	return [FACE_NX, FACE_PY]   # Trigger, Batch size (analog)


func _get_output_faces() -> Array:
	return [facing, FACE_PZ]   # Ack, Error


func phase_act() -> void:
	var trigger := get_face_input(FACE_NX)
	if not (trigger.type == R2Signal.Type.EVENT or trigger.to_bool()):
		return

	var qty_input := get_face_input(FACE_PY).to_analog()
	var qty := batch_size
	if qty_input > 0:
		qty = maxi(1, qty_input)

	var cm := R2Engine.get_chunk_manager()
	if cm == null: return
	var parent = cm.get_parent()
	if parent == null: return
	var bem = parent.get_node_or_null("BlockEntityManager")
	if bem == null: return

	var src_ent  = bem.get_entity(world_pos)
	var dst_ent  = bem.get_entity(world_pos + target_face)

	if src_ent == null or dst_ent == null:
		_error = true
		_ack   = false
		return

	if not src_ent.has_method("get_all_slots") or not dst_ent.has_method("try_insert"):
		_error = true
		_ack   = false
		return

	var slots: Array = src_ent.get_all_slots()
	var transferred := 0

	for i in slots.size():
		if transferred >= qty: break
		var s = slots[i]
		if not (s is Dictionary) or s.get("id", "") == "": continue
		if filter_item != "" and s.get("id", "") != filter_item: continue

		var to_move := mini(qty - transferred, int(s.get("count", 1)))
		if dst_ent.try_insert(s.get("id", ""), to_move):
			if src_ent.has_method("remove_from_slot"):
				src_ent.remove_from_slot(i, to_move)
			transferred += to_move

	_ack   = transferred > 0
	_error = transferred == 0


func phase_emit() -> void:
	emit_bool(_ack)
	_next_outputs[1] = R2Signal.make_bool(_error, 1, world_pos)
	super.phase_emit()


func serialize() -> Dictionary:
	var d := super.serialize()
	d["filter_item"] = filter_item
	d["target_face"] = [target_face.x, target_face.y, target_face.z]
	d["batch_size"]  = batch_size
	return d


func deserialize(data: Dictionary) -> void:
	filter_item = data.get("filter_item", "")
	var tf := data.get("target_face", [-1, 0, 0]) as Array
	if tf.size() == 3: target_face = Vector3i(int(tf[0]), int(tf[1]), int(tf[2]))
	batch_size  = data.get("batch_size", 1)
	super.deserialize(data)
