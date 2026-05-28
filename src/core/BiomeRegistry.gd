## BiomeRegistry.gd
## Autoload singleton. Loads biome definitions and provides biome lookup.
extends Node

const DATA_PATHS := {
	"overworld": "res://data/biomes/biomes_overworld.json",
	"nether": "res://data/biomes/biomes_nether.json",
	"the_end": "res://data/biomes/biomes_end.json",
}

var _biomes: Dictionary = {}          # "axiom:plains" -> BiomeDef
var _biomes_by_dim: Dictionary = {}   # "overworld" -> Array[BiomeDef]
var _biome_pool: Dictionary = {}      # "overworld" -> Array[BiomeDef] (weighted)
# Pre-filtered surface-only biomes for Voronoi selection (no underground/rare/endgame)
var _surface_biomes_by_dim: Dictionary = {}


class BiomeDef:
	var id: String
	var full_id: String
	var display_name: String
	var temperature: float
	var humidity: float
	var weight: int
	var category: String
	var sky_color: Color
	var fog_color: Color
	var water_color: Color
	var grass_color: Color
	var foliage_color: Color
	var precipitation: String     # "rain", "snow", "none"
	var surface: Dictionary
	var features: Dictionary
	var structures: Array
	var mobs: Dictionary
	var generation: Dictionary
	var ores: Array
	var underground: bool
	var layer: int               # End layer (0=central, 1=outer, 2=upper, 3=abyss)
	var rare: bool
	var endgame: bool
	var custom: bool
	var dimension: String
	var raw: Dictionary

	func _init(data: Dictionary, ns: String, dim: String) -> void:
		raw = data
		dimension = dim
		id = data.get("id", "unknown")
		full_id = ns + ":" + id
		display_name = data.get("display_name", id)
		temperature = data.get("temperature", 0.5)
		humidity = data.get("humidity", 0.5)
		weight = data.get("weight", 5)
		category = data.get("category", "plains")
		sky_color = Color(data.get("sky_color", "#78A7FF"))
		fog_color = Color(data.get("fog_color", "#C0D8FF"))
		water_color = Color(data.get("water_color", "#3F76E4"))
		grass_color = Color(data.get("grass_color", "#79C05A"))
		foliage_color = Color(data.get("foliage_color", "#59AE30"))
		precipitation = data.get("precipitation", "rain")
		surface = data.get("surface", {})
		features = data.get("features", {})
		structures = data.get("structures", [])
		mobs = data.get("mobs", {})
		generation = data.get("generation", {})
		ores = data.get("ores", [])
		underground = data.get("underground", false)
		layer = data.get("layer", 0)
		rare = data.get("rare", false)
		endgame = data.get("endgame", false)
		custom = data.get("custom", false)

	func get_surface_block() -> String:
		return surface.get("top", "axiom:grass_block")

	func get_filler_block() -> String:
		return surface.get("filler", "axiom:dirt")

	func has_snow() -> bool:
		return precipitation == "snow" or temperature < 0.15

	func spawns_underwater() -> bool:
		return underground and surface.get("underwater", false)

	func get_passive_mobs() -> Array:
		return mobs.get("passive", [])

	func get_hostile_mobs() -> Array:
		return mobs.get("hostile", [])


func _ready() -> void:
	for dim in DATA_PATHS:
		var path: String = DATA_PATHS[dim]
		if FileAccess.file_exists(path):
			_load_biome_file(path, dim)
	_build_biome_pools()
	print("[BiomeRegistry] Loaded %d biomes." % _biomes.size())


func _load_biome_file(path: String, dimension: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary:
		return
	var ns: String = data.get("namespace", "axiom")
	for biome_data in data.get("biomes", []):
		if biome_data is Dictionary:
			var biome := BiomeDef.new(biome_data, ns, dimension)
			_biomes[biome.full_id] = biome
			if not _biomes_by_dim.has(dimension):
				_biomes_by_dim[dimension] = []
			_biomes_by_dim[dimension].append(biome)


func _build_biome_pools() -> void:
	for dim in _biomes_by_dim:
		var surface := []
		var pool := []
		for biome in _biomes_by_dim[dim]:
			if biome.underground or biome.rare or biome.endgame:
				continue
			surface.append(biome)
			for _i in biome.weight:
				pool.append(biome)
		_biome_pool[dim] = pool
		_surface_biomes_by_dim[dim] = surface


# --- Public API ---

func get_biome(full_id: String) -> BiomeDef:
	return _biomes.get(full_id)


func get_biomes_for_dimension(dimension: String) -> Array:
	return _biomes_by_dim.get(dimension, [])


func get_random_biome(dimension: String) -> BiomeDef:
	var pool: Array = _biome_pool.get(dimension, [])
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]


## Select biome at a point using temperature/humidity Voronoi.
## Returns BiomeDef or null. Used by WorldGenerator.
func select_biome_at(temperature: float, humidity: float, dimension: String) -> BiomeDef:
	var candidates: Array = _surface_biomes_by_dim.get(dimension, [])
	var best: BiomeDef = null
	var best_dist: float = INF
	for biome: BiomeDef in candidates:
		var dt: float = biome.temperature - temperature
		var dh: float = biome.humidity - humidity
		var dist: float = dt * dt + dh * dh
		if dist < best_dist:
			best_dist = dist
			best = biome
	return best
