## UniversalActuatorEntity.gd — Universal actuator (Actionneur universel). ID 4060.
## Unified action interface: open, close, toggle, activate, emit light, play sound, transfer.
class_name UniversalActuatorEntity
extends R2BlockEntity

enum Command {
	OPEN        = 0,
	CLOSE       = 1,
	TOGGLE      = 2,
	ACTIVATE    = 3,
	DEACTIVATE  = 4,
	LOCK        = 5,
	UNLOCK      = 6,
	EMIT_LIGHT  = 7,
	PLAY_SOUND  = 8,
	TRANSFER    = 9,
}

var command:    int     = Command.TOGGLE
var target_face: Vector3i = FACE_NX
var sound_id:   String  = ""
var light_level: int    = 15

var _state:    bool = false   # current actuated state
var _feedback: bool = false   # ack from last action


func _init(pos: Vector3i) -> void:
	super(pos, "r2_actuator")


func _get_input_faces() -> Array:
	# Command input = back (NX), parameter = top (PY)
	return [FACE_NX, FACE_PY]


func _get_output_faces() -> Array:
	# State feedback = front
	return [facing]


func phase_act() -> void:
	var trigger := get_face_input(FACE_NX).to_bool()
	if not trigger:
		_feedback = false
		return

	var target_pos := world_pos + target_face
	var cm := R2Engine.get_chunk_manager()

	match command:
		Command.TOGGLE:
			_state = not _state
			_apply_state_to_target(target_pos, cm, _state)
			_feedback = true

		Command.OPEN, Command.ACTIVATE, Command.UNLOCK:
			_state = true
			_apply_state_to_target(target_pos, cm, true)
			_feedback = true

		Command.CLOSE, Command.DEACTIVATE, Command.LOCK:
			_state = false
			_apply_state_to_target(target_pos, cm, false)
			_feedback = true

		Command.EMIT_LIGHT:
			_set_light(target_pos, cm)
			_feedback = true

		Command.PLAY_SOUND:
			_play_sound(cm)
			_feedback = true

		Command.TRANSFER:
			_transfer_items(target_pos, cm)
			_feedback = true


func _apply_state_to_target(tpos: Vector3i, cm, state: bool) -> void:
	if cm == null: return
	var parent = cm.get_parent()
	if parent == null: return
	var bem = parent.get_node_or_null("BlockEntityManager")
	if bem == null: return
	var ent = bem.get_entity(tpos)
	if ent == null: return
	if ent.has_method("set_open"):   ent.set_open(state)
	elif ent.has_method("set_active"): ent.set_active(state)
	elif ent.has_method("set_powered"): ent.set_powered(state)


func _set_light(_tpos: Vector3i, _cm) -> void:
	pass   # light system integration point


func _play_sound(_cm) -> void:
	if sound_id != "":
		pass   # audio system integration point


func _transfer_items(_tpos: Vector3i, _cm) -> void:
	pass   # inventory system integration point


func phase_emit() -> void:
	emit_bool(_feedback)


func serialize() -> Dictionary:
	var d := super.serialize()
	d["command"]     = command
	d["target_face"] = [target_face.x, target_face.y, target_face.z]
	d["sound_id"]    = sound_id
	d["light_level"] = light_level
	d["state"]       = _state
	return d


func deserialize(data: Dictionary) -> void:
	command     = data.get("command", Command.TOGGLE)
	var tf := data.get("target_face", [-1, 0, 0]) as Array
	if tf.size() == 3: target_face = Vector3i(int(tf[0]), int(tf[1]), int(tf[2]))
	sound_id    = data.get("sound_id", "")
	light_level = data.get("light_level", 15)
	_state      = data.get("state", false)
	super.deserialize(data)
