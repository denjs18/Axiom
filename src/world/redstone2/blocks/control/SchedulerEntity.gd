## SchedulerEntity.gd — Time-based scheduler (Planificateur). ID 4053.
## Triggers at a specific in-game time, on a regular interval, or by world date/season.
class_name SchedulerEntity
extends R2BlockEntity

enum Mode {
	TIME_OF_DAY  = 0,   # fire when world time matches target_time (ticks, 0-24000)
	INTERVAL     = 1,   # fire every interval_ticks, starts from world age
	WORLD_AGE    = 2,   # fire once when world_age >= target_age
}

var mode:           int = Mode.TIME_OF_DAY
var target_time:    int = 6000    # dawn = 6000 ticks
var interval_ticks: int = 200     # 20s at 10 TPS
var target_age:     int = 0

var _last_fire_tick: int  = -1
var _age_fired:      bool = false
var _prev_day_time:  int  = -1


func _init(pos: Vector3i) -> void:
	super(pos, "r2_scheduler")


func _get_input_faces() -> Array:
	return [FACE_NX]   # Enable (disable scheduling when low in BOOL mode)


func _get_output_faces() -> Array:
	return [facing]


func phase_calculate() -> void:
	var enabled := get_face_input(FACE_NX).to_bool() or \
		get_face_input(FACE_NX).type == R2Signal.Type.BOOLEAN and true
	# If no explicit enable input, treat as always enabled
	var inp := get_face_input(FACE_NX)
	if inp.analog_value == 0 and not inp.bool_value and inp.type == R2Signal.Type.BOOLEAN:
		# connected but off
		enabled = false
	else:
		enabled = true

	if not enabled:
		_next_outputs[0] = R2Signal.make_bool(false, 0, world_pos)
		return

	var cm := R2Engine.get_chunk_manager()
	var fire := false

	match mode:
		Mode.TIME_OF_DAY:
			var day_time := _get_day_time(cm)
			if _prev_day_time >= 0:
				# Detect crossing of target time
				if _prev_day_time < target_time and day_time >= target_time:
					fire = true
				elif _prev_day_time > day_time and (target_time <= day_time or target_time > _prev_day_time):
					fire = true   # day wrapped
			_prev_day_time = day_time

		Mode.INTERVAL:
			if _last_fire_tick < 0:
				_last_fire_tick = current_tick
			elif (current_tick - _last_fire_tick) >= interval_ticks:
				fire = true
				_last_fire_tick = current_tick

		Mode.WORLD_AGE:
			if not _age_fired:
				var age := current_tick   # approximate: R2 tick ≈ world age
				if age >= target_age:
					fire = true
					_age_fired = true

	if fire:
		_next_outputs[0] = R2Signal.make_event(0, world_pos)
	else:
		_next_outputs[0] = R2Signal.make_bool(false, 0, world_pos)


func _get_day_time(cm) -> int:
	if cm == null: return 0
	var parent = cm.get_parent()
	if parent == null: return 0
	var env = parent.get_node_or_null("WorldEnvironment")
	if env == null: return 0
	if env.has_method("get_day_time"): return env.get_day_time()
	if "day_time" in env: return env.day_time
	return 0


func phase_emit() -> void:
	super.phase_emit()


func serialize() -> Dictionary:
	var d := super.serialize()
	d["mode"]            = mode
	d["target_time"]     = target_time
	d["interval_ticks"]  = interval_ticks
	d["target_age"]      = target_age
	d["last_fire_tick"]  = _last_fire_tick
	d["age_fired"]       = _age_fired
	d["prev_day_time"]   = _prev_day_time
	return d


func deserialize(data: Dictionary) -> void:
	mode            = data.get("mode", Mode.TIME_OF_DAY)
	target_time     = data.get("target_time", 6000)
	interval_ticks  = data.get("interval_ticks", 200)
	target_age      = data.get("target_age", 0)
	_last_fire_tick = data.get("last_fire_tick", -1)
	_age_fired      = data.get("age_fired", false)
	_prev_day_time  = data.get("prev_day_time", -1)
	super.deserialize(data)
