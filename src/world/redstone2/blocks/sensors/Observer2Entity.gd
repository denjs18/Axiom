## Observer2Entity.gd — Observer 2.0 (Observer 2.0). ID 4030.
## Detects world changes in front of the block and emits configurable signals.
## Deterministic: identical on all platforms, no Java/Bedrock divergence.
class_name Observer2Entity
extends R2BlockEntity

enum DetectMode {
	BLOCK_CHANGE   = 0,   # block ID changed in front
	STATE_CHANGE   = 1,   # block metadata changed in front
	INVENTORY      = 2,   # inventory contents changed in front
	LIGHT_CHANGE   = 3,   # light level changed in front
	FLUID_CHANGE   = 4,   # fluid state changed in front
	RISING_EDGE    = 5,   # any state: false → true
	FALLING_EDGE   = 6,   # any state: true → false
	ANY_CHANGE     = 7,   # any of the above
	REPEAT_WHILE   = 8,   # re-emit every tick while condition is true
}

enum OutputMode { EVENT = 0, BOOL_PULSE = 1, COUNTER = 2, TYPE_CODE = 3 }

var detect_mode: int = DetectMode.BLOCK_CHANGE
var output_mode: int = OutputMode.EVENT
var _prev_block_id: int = -1
var _prev_meta_hash: int = -1
var _prev_inventory_hash: int = -1
var _change_count: int = 0
var _pulse_timer: int = 0


func _init(pos: Vector3i) -> void:
	super(pos, "r2_observer2")


func _get_input_faces() -> Array:
	return []   # sensors don't receive R2 inputs


func _get_output_faces() -> Array:
	return [-facing]   # output from back face


func phase_acquire(tick: int) -> void:
	current_tick = tick
	_inputs.clear()
	_face_inputs.clear()


func phase_calculate() -> void:
	var watch_pos := world_pos + facing
	var changed   := false
	var type_code := 0

	match detect_mode:
		DetectMode.BLOCK_CHANGE, DetectMode.ANY_CHANGE:
			var cur := R2Engine.get_block_id(watch_pos)
			if _prev_block_id >= 0 and cur != _prev_block_id:
				changed   = true
				type_code = 1
			_prev_block_id = cur

		DetectMode.STATE_CHANGE, DetectMode.ANY_CHANGE:
			var cm := R2Engine.get_chunk_manager()
			if cm != null:
				var chunk_ref = cm.get_chunk(
					Vector3i(watch_pos.x >> 4, watch_pos.y >> 4, watch_pos.z >> 4))
				if chunk_ref != null:
					var meta: Dictionary = chunk_ref.get_block_meta(
						watch_pos.x & 15, watch_pos.y & 15, watch_pos.z & 15)
					var h := meta.hash()
					if _prev_meta_hash >= 0 and h != _prev_meta_hash:
						changed   = true
						type_code = 2
					_prev_meta_hash = h

		DetectMode.INVENTORY:
			var bem = Engine.get_singleton("BlockEntityManager") if Engine.has_singleton("BlockEntityManager") else null
			if bem != null:
				var ent := bem.get_entity(watch_pos)
				var h := 0 if ent == null else ent.serialize().hash()
				if _prev_inventory_hash >= 0 and h != _prev_inventory_hash:
					changed   = true
					type_code = 3
				_prev_inventory_hash = h

		DetectMode.REPEAT_WHILE:
			var cur := R2Engine.get_block_id(watch_pos)
			changed = cur != 0   # emit while something is there
			type_code = 4

	if changed:
		_change_count += 1

	if _pulse_timer > 0:
		_pulse_timer -= 1

	match output_mode:
		OutputMode.EVENT:
			if changed: emit_event()
			else: emit_bool(false)
		OutputMode.BOOL_PULSE:
			if changed: _pulse_timer = 2
			emit_bool(_pulse_timer > 0)
		OutputMode.COUNTER:
			emit_analog(mini(_change_count, 255))
		OutputMode.TYPE_CODE:
			if changed: emit_analog(type_code * 64)
			else: emit_analog(0)


func _get_output_toward(target_pos: Vector3i) -> R2Signal:
	var dir := target_pos - world_pos
	if dir == -facing:
		return get_output(0)
	return null


func serialize() -> Dictionary:
	var d := super.serialize()
	d["detect_mode"]     = detect_mode
	d["output_mode"]     = output_mode
	d["prev_block_id"]   = _prev_block_id
	d["change_count"]    = _change_count
	return d


func deserialize(data: Dictionary) -> void:
	detect_mode   = data.get("detect_mode", DetectMode.BLOCK_CHANGE)
	output_mode   = data.get("output_mode", OutputMode.EVENT)
	_prev_block_id = data.get("prev_block_id", -1)
	_change_count  = data.get("change_count", 0)
	super.deserialize(data)
