## EventQueueEntity.gd — Event queue / FIFO buffer (File d'événements). ID 4047.
## Stores incoming event pulses in a FIFO queue and releases them one per tick
## or on a clock pulse. Prevents event loss in high-rate systems.
class_name EventQueueEntity
extends R2BlockEntity

var max_size:    int  = 16    # max queued events (1-64)
var clock_mode:  bool = false # false=auto (one per tick), true=release on clk pulse
var _queue:      Array[int] = []   # stores tick timestamps
var _prev_input: bool = false
var _prev_clk:   bool = false
var _overflow:   bool = false


func _init(pos: Vector3i) -> void:
	super(pos, "r2_event_queue")


func _get_input_faces() -> Array:
	# Event input = back (NX), Clock = top (PY), Flush = bottom (NY)
	return [FACE_NX, FACE_PY, FACE_NY]


func _get_output_faces() -> Array:
	# Event out = front, Full flag = side, Overflow flag = other side
	return [facing, FACE_PZ, FACE_NZ]


func phase_acquire(tick: int) -> void:
	super.phase_acquire(tick)


func phase_calculate() -> void:
	var inp   := get_face_input(FACE_NX)
	var clk   := get_face_input(FACE_PY).to_bool()
	var flush := get_face_input(FACE_NY).to_bool()

	if flush:
		_queue.clear()
		_overflow = false
		_prev_input = inp.to_bool()
		_prev_clk   = clk
		return

	# Enqueue on rising edge or on EVENT type
	var should_enqueue := false
	if inp.type == R2Signal.Type.EVENT:
		should_enqueue = true
	elif inp.to_bool() and not _prev_input:
		should_enqueue = true
	_prev_input = inp.to_bool()

	if should_enqueue:
		if _queue.size() < maxi(max_size, 1):
			_queue.append(current_tick)
		else:
			_overflow = true

	# Dequeue
	var dequeue := false
	if not clock_mode:
		dequeue = not _queue.is_empty()
	else:
		if clk and not _prev_clk:
			dequeue = not _queue.is_empty()
	_prev_clk = clk

	if dequeue and not _queue.is_empty():
		_queue.pop_front()
		_next_outputs[0] = R2Signal.make_event(0, world_pos)
	else:
		_next_outputs[0] = R2Signal.make_bool(false, 0, world_pos)

	# Full flag (channel 1)
	_next_outputs[1] = R2Signal.make_bool(_queue.size() >= maxi(max_size, 1), 1, world_pos)
	# Overflow flag (channel 2)
	_next_outputs[2] = R2Signal.make_bool(_overflow, 2, world_pos)
	if _overflow and dequeue: _overflow = false


func phase_emit() -> void:
	super.phase_emit()


func serialize() -> Dictionary:
	var d := super.serialize()
	d["max_size"]   = max_size
	d["clock_mode"] = clock_mode
	d["queue_size"] = _queue.size()
	d["overflow"]   = _overflow
	return d


func deserialize(data: Dictionary) -> void:
	max_size   = data.get("max_size", 16)
	clock_mode = data.get("clock_mode", false)
	_overflow  = data.get("overflow", false)
	_queue.clear()
	super.deserialize(data)
