## SmartDispenserEntity.gd — Smart dispenser (Distributeur intelligent). ID 4062.
## Dispenses a selected slot or filtered item on trigger. Returns error if empty.
class_name SmartDispenserEntity
extends R2BlockEntity

enum SlotMode { ROUND_ROBIN = 0, FIRST_MATCH = 1, ANALOG_SELECT = 2 }

var slot_mode:   int    = SlotMode.FIRST_MATCH
var filter_item: String = ""   # empty = any
var _last_slot:  int    = 0
var _error:      bool   = false   # true if no item to dispense


func _init(pos: Vector3i) -> void:
	super(pos, "r2_dispenser2")


func _get_input_faces() -> Array:
	# Trigger = back (NX), Slot select = top (PY, analog)
	return [FACE_NX, FACE_PY]


func _get_output_faces() -> Array:
	# Success ack = front, Error = side
	return [facing, FACE_PZ]


func phase_act() -> void:
	var trigger := get_face_input(FACE_NX)
	if not (trigger.type == R2Signal.Type.EVENT or trigger.to_bool()):
		_error = false
		return

	var cm := R2Engine.get_chunk_manager()
	if cm == null: return
	var parent = cm.get_parent()
	if parent == null: return
	var bem = parent.get_node_or_null("BlockEntityManager")
	if bem == null: return

	# Self entity (dispenser has its own inventory)
	var self_ent = bem.get_entity(world_pos)
	if self_ent == null or not self_ent.has_method("get_all_slots"):
		_error = true
		return

	var slots: Array = self_ent.get_all_slots()
	var chosen_slot := -1

	match slot_mode:
		SlotMode.FIRST_MATCH:
			for i in slots.size():
				var s = slots[i]
				if s is Dictionary and s.get("id", "") != "":
					if filter_item == "" or s.get("id", "") == filter_item:
						chosen_slot = i
						break

		SlotMode.ROUND_ROBIN:
			for _i in slots.size():
				var idx := (_last_slot + _i + 1) % slots.size()
				var s = slots[idx]
				if s is Dictionary and s.get("id", "") != "":
					if filter_item == "" or s.get("id", "") == filter_item:
						chosen_slot = idx
						_last_slot  = idx
						break

		SlotMode.ANALOG_SELECT:
			var analog := get_face_input(FACE_PY).to_analog()
			var idx    := int(float(analog) / 256.0 * float(slots.size()))
			idx = clampi(idx, 0, slots.size() - 1)
			if (slots[idx] as Dictionary).get("id", "") != "":
				chosen_slot = idx

	if chosen_slot < 0:
		_error = true
		return

	# Dispense: drop item in front of facing
	_error = false
	if self_ent.has_method("remove_from_slot"):
		self_ent.remove_from_slot(chosen_slot, 1)


func phase_emit() -> void:
	# Channel 0 = success (true when last action succeeded)
	emit_bool(not _error)
	# Channel 1 = error flag
	_next_outputs[1] = R2Signal.make_bool(_error, 1, world_pos)
	super.phase_emit()


func serialize() -> Dictionary:
	var d := super.serialize()
	d["slot_mode"]   = slot_mode
	d["filter_item"] = filter_item
	d["last_slot"]   = _last_slot
	return d


func deserialize(data: Dictionary) -> void:
	slot_mode   = data.get("slot_mode", SlotMode.FIRST_MATCH)
	filter_item = data.get("filter_item", "")
	_last_slot  = data.get("last_slot", 0)
	super.deserialize(data)
