## MobSpawner.gd — Spawns animal groups in the world around the player.
## Biome-aware: reads the current biome at the spawn position and selects species accordingly.
class_name MobSpawner
extends Node

const MAX_TOTAL    := 60
const MAX_SPECIES  := 12
const SPAWN_EVERY  := 22.0
const MIN_DIST     := 18.0
const MAX_DIST     := 52.0

var _chunk_manager: ChunkManager = null
var _spawn_timer: float = 8.0   # delay before first spawn after world load

# Mob census — maintained via EventBus signals, avoids O(n) scene-tree scan each cycle.
var _total_mobs: int = 0
var _species_count: Dictionary = {}   # species (lowercase) → count

# Biome-based ANIMAL tables: biome_category → [{class, weight}]
# category "" = any biome. Hostiles use the separate night table below.
const BIOME_TABLES: Dictionary = {
	"plains":   [
		{"class": "Cow",      "weight": 28},
		{"class": "Sheep",    "weight": 22},
		{"class": "Pig",      "weight": 18},
		{"class": "Chicken",  "weight": 14},
		{"class": "Deer",     "weight": 10},
	],
	"forest":   [
		{"class": "Deer",     "weight": 28},
		{"class": "Wolf",     "weight": 16},
		{"class": "Rabbit",   "weight": 26},
		{"class": "Chicken",  "weight": 12},
		{"class": "Pig",      "weight": 10},
	],
	"taiga":    [
		{"class": "Wolf",     "weight": 28},
		{"class": "Deer",     "weight": 30},
		{"class": "Rabbit",   "weight": 26},
		{"class": "Sheep",    "weight": 10},
	],
	"desert":   [
		{"class": "Rabbit",   "weight": 40},
		{"class": "Coyote",   "weight": 34},
		{"class": "Chicken",  "weight": 20},
	],
	"savanna":  [
		{"class": "Cow",      "weight": 30},
		{"class": "Sheep",    "weight": 24},
		{"class": "Deer",     "weight": 24},
		{"class": "Coyote",   "weight": 18},
	],
	"swamp":    [
		{"class": "Pig",      "weight": 36},
		{"class": "Chicken",  "weight": 32},
		{"class": "Rabbit",   "weight": 22},
	],
	"": [
		{"class": "Rabbit",   "weight": 20},
		{"class": "Coyote",   "weight": 8},
		{"class": "Wolf",     "weight": 9},
		{"class": "Chicken",  "weight": 15},
		{"class": "Sheep",    "weight": 10},
	],
}

# Hostiles spawn at night (or during blood moons, or in the Nether).
const HOSTILE_TABLE: Array = [
	{"class": "Zombie",   "weight": 36},
	{"class": "Skeleton", "weight": 24},
	{"class": "Creeper",  "weight": 22},
	{"class": "Spider",   "weight": 18},
]


func initialize(chunk_manager: ChunkManager) -> void:
	_chunk_manager = chunk_manager
	EventBus.mob_spawned.connect(_on_mob_spawned)
	EventBus.mob_died.connect(_on_mob_died_census)


func _on_mob_spawned(mob: Node, _pos: Vector3) -> void:
	_total_mobs += 1
	var sp: String = mob.get("species") if mob.get("species") != null else ""
	if not sp.is_empty():
		_species_count[sp] = _species_count.get(sp, 0) + 1


func _on_mob_died_census(mob: Node, _killer: Node) -> void:
	_total_mobs = maxi(0, _total_mobs - 1)
	var sp: String = mob.get("species") if mob.get("species") != null else ""
	if not sp.is_empty():
		_species_count[sp] = maxi(0, _species_count.get(sp, 0) - 1)


func _process(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = SPAWN_EVERY
		_try_spawn_group()
		# Blood moon: extra spawn attempt every tick
		if TimeManager.is_blood_moon:
			_try_spawn_group()


func _try_spawn_group() -> void:
	var player := GameManager.local_player as Node3D
	if player == null or _chunk_manager == null:
		return
	if _total_mobs >= MAX_TOTAL:
		return

	# Pick the spawn category: hostiles come out at night / blood moon / Nether
	var blood_moon := TimeManager.is_blood_moon
	var is_night := not TimeManager.is_day()
	var in_nether := GameManager.current_dimension == "nether"
	var hostile_roll: bool
	if in_nether or blood_moon:
		hostile_roll = true
	elif is_night:
		hostile_roll = randf() < 0.72
	else:
		hostile_roll = false

	for _attempt in 8:
		var angle  := randf() * TAU
		var dist   := randf_range(MIN_DIST, MAX_DIST)
		var try_xz := player.global_position + Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		var surface := _find_surface(try_xz)
		if surface == Vector3.ZERO:
			continue

		var mob_class: String
		if hostile_roll:
			mob_class = _pick_from_table(HOSTILE_TABLE, _species_count)
		else:
			var biome_cat := _get_biome_category(surface)
			mob_class = _pick_species(biome_cat, _species_count)
		if mob_class.is_empty():
			continue

		var solo := mob_class in ["Wolf", "Coyote", "Creeper", "Spider"]
		var group: int
		if blood_moon:
			group = randi_range(2, 4) if solo else randi_range(3, 6)
		elif hostile_roll:
			group = 1 if solo else randi_range(1, 3)
		else:
			group = 1 if solo else randi_range(2, 4)
		for _i in group:
			var off := Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
			var mob := _spawn_animal(mob_class, surface + off)
			if mob != null and blood_moon and randf() < 0.30:
				mob.make_elite()
		return


func _find_surface(world_xz: Vector3) -> Vector3:
	var x := floori(world_xz.x)
	var z := floori(world_xz.z)
	for y in range(320, -128, -1):
		var bid := _chunk_manager.get_block_at(Vector3i(x, y, z))
		if bid == 0 or BlockRegistry.is_fluid(bid):
			continue
		var above  := _chunk_manager.get_block_at(Vector3i(x, y + 1, z))
		var above2 := _chunk_manager.get_block_at(Vector3i(x, y + 2, z))
		if above == 0 and above2 == 0 and y > 40:
			return Vector3(x + 0.5, float(y + 1), z + 0.5)
	return Vector3.ZERO


func _get_biome_category(surface_pos: Vector3) -> String:
	var wn := GameManager.world_node
	if wn == null:
		return ""
	var wg = wn.get("world_generator")
	if wg == null:
		return ""
	var biome_id: String = wg.get_biome_at(surface_pos.x, surface_pos.z)
	var biome := BiomeRegistry.get_biome(biome_id)
	if biome == null:
		return ""
	return biome.category


func _pick_species(biome_cat: String, species_counts: Dictionary) -> String:
	# Try biome-specific table first, fall back to generic
	var table: Array = BIOME_TABLES.get(biome_cat, BIOME_TABLES.get("", []))
	return _pick_from_table(table, species_counts)


func _pick_from_table(table: Array, species_counts: Dictionary) -> String:
	if table.is_empty():
		return ""
	var candidates: Array = []
	var total_w := 0
	for entry in table:
		var cls: String = entry["class"]
		if species_counts.get(cls.to_lower(), 0) >= MAX_SPECIES:
			continue
		candidates.append(entry)
		total_w += entry["weight"]
	if candidates.is_empty():
		return ""
	var r := randi() % total_w
	var cum := 0
	for c in candidates:
		cum += c["weight"]
		if r < cum:
			return c["class"]
	return ""


func _spawn_animal(mob_class: String, pos: Vector3) -> BaseMob:
	var mob: BaseMob
	match mob_class:
		"Cow":      mob = Cow.new()
		"Sheep":    mob = Sheep.new()
		"Pig":      mob = Pig.new()
		"Chicken":  mob = Chicken.new()
		"Rabbit":   mob = Rabbit.new()
		"Wolf":     mob = Wolf.new()
		"Deer":     mob = Deer.new()
		"Coyote":   mob = Coyote.new()
		"Zombie":   mob = Zombie.new()
		"Skeleton": mob = Skeleton.new()
		"Creeper":  mob = Creeper.new()
		"Spider":   mob = Spider.new()
		_: return null
	get_parent().add_child(mob)
	mob.global_position = pos
	return mob
