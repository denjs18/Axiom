## MechanicalMotorEntity.gd — Mechanical motor (Moteur mécanique). ID 4066.
## Drives rotation or translation. Configurable axis, speed, continuous/step mode.
class_name MechanicalMotorEntity
extends R2BlockEntity

enum MotionType { ROTATION = 0, TRANSLATION = 1 }
enum DriveMode  { CONTINUOUS = 0, STEP = 1 }

var motion_type: int   = MotionType.ROTATION
var drive_mode:  int   = DriveMode.CONTINUOUS
var axis:        int   = 1   # 0=X, 1=Y, 2=Z
var speed:       float = 1.0   # rotations/s or blocks/s
var max_steps:   int   = 0     # 0 = unlimited

var _running:    bool  = false
var _position:   float = 0.0   # accumulated rotation (degrees) or translation (blocks)
var _step_count: int   = 0
var _prev_fwd:   bool  = false
var _prev_bwd:   bool  = false


func _init(pos: Vector3i) -> void:
	super(pos, "r2_motor")


func _get_input_faces() -> Array:
	# Forward = back (NX), Backward = top (PY), Stop = bottom (NY), Speed = side (PZ, analog)
	return [FACE_NX, FACE_PY, FACE_NY, FACE_PZ]


func _get_output_faces() -> Array:
	# Position (analog 0-255 = 0-360° or 0-max_steps) = front, Running = side
	return [facing, FACE_NZ]


func phase_calculate() -> void:
	var fwd   := get_face_input(FACE_NX).to_bool()
	var bwd   := get_face_input(FACE_PY).to_bool()
	var stop  := get_face_input(FACE_NY).to_bool()
	var spd   := get_face_input(FACE_PZ).to_analog()

	if spd > 0:
		speed = float(spd) / 255.0 * 10.0   # 0-10 units/s

	if stop:
		_running = false
		_prev_fwd = fwd
		_prev_bwd = bwd
		return

	match drive_mode:
		DriveMode.CONTINUOUS:
			_running = fwd or bwd
			if _running:
				var dir := 1.0 if fwd else -1.0
				_position += dir * speed * R2Engine.TICK_INTERVAL
				if motion_type == MotionType.ROTATION:
					_position = fmod(_position, 360.0)
					if _position < 0: _position += 360.0

		DriveMode.STEP:
			if fwd and not _prev_fwd:
				if max_steps <= 0 or _step_count < max_steps:
					_position += 1.0
					_step_count += 1
					_running = true
				else:
					_running = false
			elif bwd and not _prev_bwd:
				_position -= 1.0
				_step_count -= 1
				_running = true
			else:
				_running = false

	_prev_fwd = fwd
	_prev_bwd = bwd


func phase_emit() -> void:
	var out := 0
	if motion_type == MotionType.ROTATION:
		out = int(_position / 360.0 * 255.0) & 0xFF
	else:
		out = clampi(int(_position), 0, 255)

	emit_analog(out)
	_next_outputs[1] = R2Signal.make_bool(_running, 1, world_pos)
	super.phase_emit()


func serialize() -> Dictionary:
	var d := super.serialize()
	d["motion_type"] = motion_type
	d["drive_mode"]  = drive_mode
	d["axis"]        = axis
	d["speed"]       = speed
	d["max_steps"]   = max_steps
	d["position"]    = _position
	d["step_count"]  = _step_count
	d["running"]     = _running
	return d


func deserialize(data: Dictionary) -> void:
	motion_type = data.get("motion_type", MotionType.ROTATION)
	drive_mode  = data.get("drive_mode", DriveMode.CONTINUOUS)
	axis        = data.get("axis", 1)
	speed       = data.get("speed", 1.0)
	max_steps   = data.get("max_steps", 0)
	_position   = data.get("position", 0.0)
	_step_count = data.get("step_count", 0)
	_running    = data.get("running", false)
	super.deserialize(data)
