## MovementSensorEntity.gd — Movement sensor (Capteur de mouvement). ID 4036.
## Detects entity movement (speed, direction, stop, acceleration) in a radius.
class_name MovementSensorEntity
extends R2BlockEntity

enum ReadMode {
	SPEED        = 0,   # analog: average speed of entities (0-255, mapped from 0-20 m/s)
	DIRECTION    = 1,   # analog: dominant direction (0=north 64=east 128=south 192=west)
	ANY_MOVING   = 2,   # bool: at least one entity moving above threshold
	ANY_STOPPED  = 3,   # bool: at least one entity stopped
	COUNT_MOVING = 4,   # analog: count of moving entities (clamped 0-255)
}

var read_mode:      int   = ReadMode.ANY_MOVING
var radius:         float = 4.0
var speed_threshold: float = 0.5   # m/s: below this = "stopped"

var _prev_positions: Dictionary = {}   # node_id → Vector3


func _init(pos: Vector3i) -> void:
	super(pos, "r2_movement")


func _get_input_faces() -> Array:
	return []


func _get_output_faces() -> Array:
	return ALL_FACES


func phase_calculate() -> void:
	var cm := R2Engine.get_chunk_manager()
	if cm == null:
		emit_analog(0)
		return
	var parent = cm.get_parent()
	if parent == null:
		emit_analog(0)
		return

	var world_3d := parent.get_world_3d()
	if world_3d == null:
		emit_analog(0)
		return

	var space  := world_3d.direct_space_state
	var center := Vector3(world_pos) + Vector3(0.5, 0.5, 0.5)
	var shape  := SphereShape3D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape     = shape
	params.transform = Transform3D(Basis.IDENTITY, center)
	params.collision_mask = 4 | 8

	var hits := space.intersect_shape(params, 64)

	# Calculate per-entity speeds using position delta (approx, one R2 tick apart)
	var new_positions: Dictionary = {}
	var speeds: Array[float] = []
	var directions: Array[Vector2] = []

	for h in hits:
		var node := h.get("collider") as Node3D
		if node == null: continue
		var nid := node.get_instance_id()
		var cur_pos: Vector3 = node.global_position
		new_positions[nid] = cur_pos
		if _prev_positions.has(nid):
			var delta: Vector3 = cur_pos - (_prev_positions[nid] as Vector3)
			var speed: float = delta.length() / R2Engine.TICK_INTERVAL
			speeds.append(speed)
			if delta.length() > 0.01:
				directions.append(Vector2(delta.x, delta.z).normalized())

	_prev_positions = new_positions

	match read_mode:
		ReadMode.ANY_MOVING:
			var any := false
			for s in speeds:
				if s > speed_threshold:
					any = true
					break
			emit_bool(any)

		ReadMode.ANY_STOPPED:
			var any := false
			for s in speeds:
				if s <= speed_threshold:
					any = true
					break
			if speeds.is_empty(): any = false
			emit_bool(any)

		ReadMode.SPEED:
			var avg := 0.0
			for s in speeds:
				avg += s
			if not speeds.is_empty():
				avg /= float(speeds.size())
			# 0-20 m/s → 0-255
			emit_analog(clampi(int(avg / 20.0 * 255.0), 0, 255))

		ReadMode.COUNT_MOVING:
			var cnt := 0
			for s in speeds:
				if s > speed_threshold:
					cnt += 1
			emit_analog(mini(cnt, 255))

		ReadMode.DIRECTION:
			if directions.is_empty():
				emit_analog(0)
			else:
				var avg_dir := Vector2.ZERO
				for d in directions:
					avg_dir += d
				avg_dir = avg_dir.normalized()
				# Angle from North (-Z), clockwise: north=0, east=64, south=128, west=192
				var angle := rad_to_deg(atan2(avg_dir.x, -avg_dir.y))
				if angle < 0: angle += 360.0
				emit_analog(int(angle / 360.0 * 255.0) & 0xFF)


func serialize() -> Dictionary:
	var d := super.serialize()
	d["read_mode"]       = read_mode
	d["radius"]          = radius
	d["speed_threshold"] = speed_threshold
	return d


func deserialize(data: Dictionary) -> void:
	read_mode       = data.get("read_mode", ReadMode.ANY_MOVING)
	radius          = data.get("radius", 4.0)
	speed_threshold = data.get("speed_threshold", 0.5)
	_prev_positions.clear()
	super.deserialize(data)
