## BlockStateSensorEntity.gd — Block state reader (Lecteur d'état de bloc). ID 4034.
## Reads any readable block's unified state contract and emits configurable signals.
class_name BlockStateSensorEntity
extends R2BlockEntity

enum ReadMode {
	ACTIVE       = 0,   # bool: block is powered/active
	LEVEL        = 1,   # analog: numeric level (0-255)
	ORIENTATION  = 2,   # analog: facing as index (0-5 = PX/NX/PY/NY/PZ/NZ)
	PRIMARY      = 3,   # analog: primary state value
	SECONDARY    = 4,   # analog: secondary state value
	VARIANT      = 5,   # analog: variant index
	HAS_CONTENT  = 6,   # bool: block has content (e.g. furnace has items)
}

var read_mode:  int     = ReadMode.ACTIVE
var watch_face: Vector3i = FACE_NX


func _init(pos: Vector3i) -> void:
	super(pos, "r2_block_state")


func _get_input_faces() -> Array:
	return []


func _get_output_faces() -> Array:
	return ALL_FACES


func phase_calculate() -> void:
	var watch_pos := world_pos + watch_face
	var block_id  := R2Engine.get_block_id(watch_pos)

	if block_id == 0:
		emit_analog(0)
		return

	var cm := R2Engine.get_chunk_manager()
	if cm == null:
		emit_analog(0)
		return

	var meta: Dictionary = {}
	var chunk_ref = cm.get_chunk(
		Vector3i(watch_pos.x >> 4, watch_pos.y >> 4, watch_pos.z >> 4))
	if chunk_ref != null:
		meta = chunk_ref.get_block_meta(
			watch_pos.x & 15, watch_pos.y & 15, watch_pos.z & 15)

	match read_mode:
		ReadMode.ACTIVE:
			var active: bool = meta.get("powered", false) or meta.get("active", false) \
				or meta.get("lit", false) or meta.get("open", false)
			emit_bool(active)

		ReadMode.LEVEL:
			var level: int = int(meta.get("level", meta.get("power", meta.get("age", 0))))
			emit_analog(clampi(level * 17, 0, 255))   # scale 0-15 → 0-255

		ReadMode.ORIENTATION:
			var facing_str: String = meta.get("facing", "")
			var idx := 0
			match facing_str:
				"east":  idx = 0
				"west":  idx = 1
				"up":    idx = 2
				"down":  idx = 3
				"south": idx = 4
				"north": idx = 5
			emit_analog(idx * 51)   # 0/51/102/153/204/255

		ReadMode.PRIMARY:
			var v: int = int(meta.get("state", meta.get("type", meta.get("part", 0))))
			emit_analog(clampi(v, 0, 255))

		ReadMode.SECONDARY:
			var v: int = int(meta.get("half", meta.get("shape", meta.get("mode", 0))))
			emit_analog(clampi(v, 0, 255))

		ReadMode.VARIANT:
			var v: int = int(meta.get("variant", meta.get("color", meta.get("instrument", 0))))
			emit_analog(clampi(v, 0, 255))

		ReadMode.HAS_CONTENT:
			var parent = cm.get_parent()
			var has_content := false
			if parent != null:
				var bem = parent.get_node_or_null("BlockEntityManager")
				if bem != null:
					var ent = bem.get_entity(watch_pos)
					if ent != null and ent.has_method("get_all_slots"):
						var slots: Array = ent.get_all_slots()
						for s in slots:
							if s is Dictionary and s.get("id", "") != "":
								has_content = true
								break
			emit_bool(has_content)


func serialize() -> Dictionary:
	var d := super.serialize()
	d["read_mode"]  = read_mode
	d["watch_face"] = [watch_face.x, watch_face.y, watch_face.z]
	return d


func deserialize(data: Dictionary) -> void:
	read_mode = data.get("read_mode", ReadMode.ACTIVE)
	var wf := data.get("watch_face", [-1, 0, 0]) as Array
	if wf.size() == 3: watch_face = Vector3i(int(wf[0]), int(wf[1]), int(wf[2]))
	super.deserialize(data)
