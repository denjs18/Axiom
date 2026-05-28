## Piston2Entity.gd — Piston 2.0 (Piston 2.0). ID 4061.
## No quasi-connectivity. Explicit ports: extend, retract, toggle, stop.
## Feedback ports: extended, retracted, blocked, busy.
class_name Piston2Entity
extends R2BlockEntity

enum PistonMode { NORMAL = 0, STICKY = 1, PULSE_SAFE = 2, HOLD_POSITION = 3 }

var piston_mode: int = PistonMode.NORMAL
var push_limit:  int = 12   # max blocks to push (vanilla = 12)

# Internal state
var _extended:    bool = false
var _busy:        bool = false   # mid-animation
var _blocked:     bool = false

var _prev_extend: bool = false
var _prev_retract: bool = false
var _prev_toggle: bool = false


func _init(pos: Vector3i) -> void:
	super(pos, "r2_piston2")


func _get_input_faces() -> Array:
	# Extend = back (NX), Retract = top (PY), Toggle = bottom (NY), Stop = side (PZ)
	return [FACE_NX, FACE_PY, FACE_NY, FACE_PZ]


func _get_output_faces() -> Array:
	# Facing = push direction, side = feedback channels
	return [facing, FACE_NZ]


func phase_act() -> void:
	var ext    := get_face_input(FACE_NX).to_bool()
	var ret    := get_face_input(FACE_PY).to_bool()
	var tog    := get_face_input(FACE_NY).to_bool()
	var stop   := get_face_input(FACE_PZ).to_bool()

	if _busy: return   # ignore inputs while animating (pulse-safe)

	if stop:
		_busy = false
		return

	var want_extend  := (ext and not _prev_extend) or (tog and not _prev_toggle and not _extended)
	var want_retract := (ret and not _prev_retract) or (tog and not _prev_toggle and _extended)

	_prev_extend  = ext
	_prev_retract = ret
	_prev_toggle  = tog

	if want_extend and not _extended:
		_blocked = not _try_extend()
		if not _blocked: _extended = true

	elif want_retract and _extended:
		_try_retract()
		_extended = false
		_blocked  = false


func _try_extend() -> bool:
	var push_pos := world_pos + facing
	var count    := 0
	while count < push_limit:
		var bid := R2Engine.get_block_id(push_pos)
		if bid == 0: break     # air: can extend
		if _is_immovable(bid): return false
		push_pos += facing
		count    += 1
	if count >= push_limit: return false

	# Push the column
	var shift_pos := push_pos
	while shift_pos != world_pos + facing:
		var prev_pos := shift_pos - facing
		var bid := R2Engine.get_block_id(prev_pos)
		R2Engine.set_world_block(shift_pos, bid)
		shift_pos -= facing

	R2Engine.set_world_block(world_pos + facing, 0)   # piston head placeholder
	return true


func _try_retract() -> void:
	# Sticky: pull one block back
	if piston_mode == PistonMode.STICKY:
		var pull_pos := world_pos + facing * 2
		var bid := R2Engine.get_block_id(pull_pos)
		if bid != 0 and not _is_immovable(bid):
			R2Engine.set_world_block(world_pos + facing, bid)
			R2Engine.set_world_block(pull_pos, 0)
		else:
			R2Engine.set_world_block(world_pos + facing, 0)
	else:
		R2Engine.set_world_block(world_pos + facing, 0)


func _is_immovable(bid: int) -> bool:
	# Obsidian, bedrock, etc. — IDs to be defined per project
	return bid in [7, 49]   # bedrock=7, obsidian=49


func phase_emit() -> void:
	# Channel 0: extended status
	emit_bool(_extended)
	# Feedback on channel 1: retracted, channel 2: blocked, channel 3: busy
	_next_outputs[1] = R2Signal.make_bool(not _extended, 1, world_pos)
	_next_outputs[2] = R2Signal.make_bool(_blocked, 2, world_pos)
	_next_outputs[3] = R2Signal.make_bool(_busy, 3, world_pos)
	super.phase_emit()


func serialize() -> Dictionary:
	var d := super.serialize()
	d["piston_mode"] = piston_mode
	d["push_limit"]  = push_limit
	d["extended"]    = _extended
	d["blocked"]     = _blocked
	return d


func deserialize(data: Dictionary) -> void:
	piston_mode = data.get("piston_mode", PistonMode.NORMAL)
	push_limit  = data.get("push_limit", 12)
	_extended   = data.get("extended", false)
	_blocked    = data.get("blocked", false)
	super.deserialize(data)
