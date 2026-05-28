## DoorLogicEntity.gd — Door / trapdoor / valve logic (Porte/Trappe/Vanne). ID 4065.
## Unified API: open, close, toggle, lock. Returns current state + jammed flag.
class_name DoorLogicEntity
extends R2BlockEntity

var _open:   bool = false
var _locked: bool = false
var _jammed: bool = false

var _prev_open:   bool = false
var _prev_close:  bool = false
var _prev_toggle: bool = false
var _prev_lock:   bool = false
var _prev_unlock: bool = false


func _init(pos: Vector3i) -> void:
	super(pos, "r2_door_logic")


func _get_input_faces() -> Array:
	# Open=back(NX), Close=top(PY), Toggle=bottom(NY), Lock=side(PZ), Unlock=side(NZ)
	return [FACE_NX, FACE_PY, FACE_NY, FACE_PZ, FACE_NZ]


func _get_output_faces() -> Array:
	# Current state = front, Jammed = side, Locked = other side
	return [facing, FACE_PZ, FACE_NZ]


func phase_calculate() -> void:
	var inp_open   := get_face_input(FACE_NX).to_bool()
	var inp_close  := get_face_input(FACE_PY).to_bool()
	var inp_toggle := get_face_input(FACE_NY).to_bool()
	var inp_lock   := get_face_input(FACE_PZ).to_bool()
	var inp_unlock := get_face_input(FACE_NZ).to_bool()

	if inp_lock and not _prev_lock:
		_locked = true
	if inp_unlock and not _prev_unlock:
		_locked = false

	_prev_lock   = inp_lock
	_prev_unlock = inp_unlock

	if _locked:
		_prev_open   = inp_open
		_prev_close  = inp_close
		_prev_toggle = inp_toggle
		return

	_jammed = false

	if inp_open and not _prev_open:
		_open = true
	if inp_close and not _prev_close:
		_open = false
	if inp_toggle and not _prev_toggle:
		_open = not _open

	_prev_open   = inp_open
	_prev_close  = inp_close
	_prev_toggle = inp_toggle


func phase_act() -> void:
	var cm := R2Engine.get_chunk_manager()
	if cm == null: return
	var parent = cm.get_parent()
	if parent == null: return
	var bem = parent.get_node_or_null("BlockEntityManager")
	if bem == null: return
	var ent = bem.get_entity(world_pos + facing)
	if ent == null: return
	if ent.has_method("set_open"):
		ent.set_open(_open)
	elif ent.has_method("set_powered"):
		ent.set_powered(_open)


func phase_emit() -> void:
	emit_bool(_open)
	_next_outputs[1] = R2Signal.make_bool(_jammed, 1, world_pos)
	_next_outputs[2] = R2Signal.make_bool(_locked, 2, world_pos)
	super.phase_emit()


func serialize() -> Dictionary:
	var d := super.serialize()
	d["open"]   = _open
	d["locked"] = _locked
	d["jammed"] = _jammed
	return d


func deserialize(data: Dictionary) -> void:
	_open   = data.get("open", false)
	_locked = data.get("locked", false)
	_jammed = data.get("jammed", false)
	super.deserialize(data)
