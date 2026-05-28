## EnvironmentalSensorEntity.gd — Environmental sensor (Capteur environnemental). ID 4035.
## Reads world conditions around the block and emits analog/boolean signals.
class_name EnvironmentalSensorEntity
extends R2BlockEntity

enum ReadMode {
	LIGHT_LEVEL  = 0,   # analog: 0-255 (block light * 17)
	TIME_OF_DAY  = 1,   # analog: 0-255 mapped from 0-24000 ticks
	WEATHER      = 2,   # analog: 0=clear 128=rain 255=thunder
	BIOME        = 3,   # analog: biome numeric ID (mod 256)
	ALTITUDE     = 4,   # analog: y clamped 0-255
	IS_RAINING   = 5,   # bool
	IS_THUNDER   = 6,   # bool
	IS_DAY       = 7,   # bool: day = time 0-12000
	IS_NIGHT     = 8,   # bool: night = time 12000-24000
	NEAR_WATER   = 9,   # bool: water in adjacent 3x3 column
	NEAR_FIRE    = 10,  # bool: fire/lava adjacent
	SKY_LIGHT    = 11,  # analog: sky light level * 17
}

var read_mode: int = ReadMode.LIGHT_LEVEL


func _init(pos: Vector3i) -> void:
	super(pos, "r2_env_sensor")


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

	match read_mode:
		ReadMode.LIGHT_LEVEL:
			var light := _get_block_light(cm)
			emit_analog(clampi(light * 17, 0, 255))

		ReadMode.SKY_LIGHT:
			var sky := _get_sky_light(cm)
			emit_analog(clampi(sky * 17, 0, 255))

		ReadMode.TIME_OF_DAY:
			var t := _get_day_time(parent)
			emit_analog(int(float(t) / 24000.0 * 255.0))

		ReadMode.WEATHER:
			var w := _get_weather(parent)
			emit_analog(w)

		ReadMode.BIOME:
			var b := _get_biome_id(cm)
			emit_analog(b & 0xFF)

		ReadMode.ALTITUDE:
			emit_analog(clampi(world_pos.y + 128, 0, 255))

		ReadMode.IS_RAINING:
			emit_bool(_get_weather(parent) >= 128)

		ReadMode.IS_THUNDER:
			emit_bool(_get_weather(parent) >= 200)

		ReadMode.IS_DAY:
			var t := _get_day_time(parent)
			emit_bool(t < 12000)

		ReadMode.IS_NIGHT:
			var t := _get_day_time(parent)
			emit_bool(t >= 12000)

		ReadMode.NEAR_WATER:
			emit_bool(_check_adjacent_block(cm, [8, 9]))   # water IDs

		ReadMode.NEAR_FIRE:
			emit_bool(_check_adjacent_block(cm, [51, 10, 11]))  # fire, lava flowing/still


func _get_block_light(cm) -> int:
	var chunk = cm.get_chunk(Vector3i(world_pos.x >> 4, world_pos.y >> 4, world_pos.z >> 4))
	if chunk == null: return 0
	if chunk.has_method("get_block_light"):
		return chunk.get_block_light(world_pos.x & 15, world_pos.y & 15, world_pos.z & 15)
	return 0


func _get_sky_light(cm) -> int:
	var chunk = cm.get_chunk(Vector3i(world_pos.x >> 4, world_pos.y >> 4, world_pos.z >> 4))
	if chunk == null: return 0
	if chunk.has_method("get_sky_light"):
		return chunk.get_sky_light(world_pos.x & 15, world_pos.y & 15, world_pos.z & 15)
	return 15


func _get_day_time(parent) -> int:
	if parent == null: return 0
	var world_env = parent.get_node_or_null("WorldEnvironment")
	if world_env == null: return 0
	if world_env.has_method("get_day_time"):
		return world_env.get_day_time()
	if "day_time" in world_env:
		return world_env.day_time
	return 0


func _get_weather(parent) -> int:
	if parent == null: return 0
	var wm = parent.get_node_or_null("WeatherManager")
	if wm == null: return 0
	if "thunder" in wm and wm.thunder: return 220
	if "raining" in wm and wm.raining: return 140
	return 0


func _get_biome_id(cm) -> int:
	if cm.has_method("get_biome_at"):
		return cm.get_biome_at(world_pos)
	return 0


func _check_adjacent_block(cm, ids: Array) -> bool:
	var neighbors := [FACE_PX, FACE_NX, FACE_PY, FACE_NY, FACE_PZ, FACE_NZ]
	for face in neighbors:
		var nb_pos := world_pos + face
		var bid := R2Engine.get_block_id(nb_pos)
		if bid in ids:
			return true
	return false


func serialize() -> Dictionary:
	var d := super.serialize()
	d["read_mode"] = read_mode
	return d


func deserialize(data: Dictionary) -> void:
	read_mode = data.get("read_mode", ReadMode.LIGHT_LEVEL)
	super.deserialize(data)
