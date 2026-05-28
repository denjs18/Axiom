## ClockEntity.gd — Stable logic clock (Horloge). ID 4046.
## Generates a periodic signal with configurable frequency and duty cycle.
## Pause input stops the clock. Sync input resets the phase.
class_name ClockEntity
extends R2BlockEntity

var period:     int   = 10   # ticks per full cycle (must be >= 2)
var duty:       float = 0.5  # 0.0-1.0, fraction of period where output is HIGH
var _phase:     int   = 0
var _running:   bool  = true
var _prev_sync: bool  = false


func _init(pos: Vector3i) -> void:
	super(pos, "r2_clock")


func _get_input_faces() -> Array:
	# Pause (high=stop) = back (NX), Sync = top (PY)
	return [FACE_NX, FACE_PY]


func _get_output_faces() -> Array:
	return [facing]


func phase_calculate() -> void:
	var pause := get_face_input(FACE_NX).to_bool()
	var sync  := get_face_input(FACE_PY).to_bool()

	if sync and not _prev_sync:
		_phase = 0
	_prev_sync = sync

	_running = not pause

	if _running:
		_phase = (_phase + 1) % maxi(period, 2)


func phase_emit() -> void:
	var high_ticks := int(float(maxi(period, 2)) * clampf(duty, 0.0, 1.0))
	emit_bool(_phase < high_ticks)


func serialize() -> Dictionary:
	var d := super.serialize()
	d["period"]    = period
	d["duty"]      = duty
	d["phase"]     = _phase
	d["running"]   = _running
	d["prev_sync"] = _prev_sync
	return d


func deserialize(data: Dictionary) -> void:
	period     = data.get("period", 10)
	duty       = data.get("duty", 0.5)
	_phase     = data.get("phase", 0)
	_running   = data.get("running", true)
	_prev_sync = data.get("prev_sync", false)
	super.deserialize(data)
