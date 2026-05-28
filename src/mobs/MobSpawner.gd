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

# Biome-based spawn tables: biome_category → [{class, weight}]
# category "" = any biome
const BIOME_TABLES: Dictionary = {
	"plains":   [
		{"class": "Cow",      "weight": 28},
		{"class": "Sheep",    "weight": 22},
		{"class": "Pig",      "weight": 18},
		{"class": "Chicken",  "weight": 14},
		{"class": "Deer",     "weight": 10},
		{"class": "Zombie",   "weight": 5},
		{"class": "Skeleton", "weight": 3},
	],
	"forest":   [
		{"class": "Deer",     "weight": 28},
		{"class": "Wolf",     "weight": 18},
		{"class": "Rabbit",   "weight": 26},
		{"class": "Chicken",  "weight": 10},
		{"class": "Pig",      "weight": 8},
		{"class": "Zombie",   "weight": 7},
		{"class": "Skeleton", "weight": 3},
	],
	"taiga":    [
		{"class": "Wolf",     "weight": 28},
		{"class": "Deer",     "weight": 28},
		{"class": "Rabbit",   "weight": 24},
		{"class": "Sheep",    "weight": 8},
		{"class": "Zombie",   "weight": 8},
		{"class": "Skeleton", "weight": 4},
	],
	"desert":   [
		{"class": "Rabbit",   "weight": 36},
		{"class": "Coyote",   "weight": 30},
		{"class": "Chicken",  "weight": 18},
		{"class": "Zombie",   "weight": 10},
		{"class": "Skeleton", "weight": 6},
	],
	"savanna":  [
		{"class": "Cow",      "weight": 28},
		{"class": "Sheep",    "weight": 22},
		{"class": "Deer",     "weight": 22},
		{"class": "Coyote",   "weight": 16},
		{"class": "Zombie",   "weight": 8},
		{"class": "Skeleton", "weight": 4},
	],
	"swamp":    [
		{"class": "Pig",      "weight": 32},
		{"class": "Chicken",  "weight": 28},
		{"class": "Rabbit",   "weight": 18},
		{"class": "Zombie",   "weight": 14},
		{"class": "Skeleton", "weight": 8},
	],
	"": [
		{"class": "Rabbit",   "weight": 18},
		{"class": "Coyote",   "weight": 7},
		{"class": "Wolf",     "weight": 8},
		{"class": "Chicken",  "weight": 13},
		{"class": "Zombie",   "weight": 10},
		{"class": "Skeleton", "weight": 6},
	],
}


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

	for _attempt in 8:
		var angle  := randf() * TAU
		var dist   := randf_range(MIN_DIST, MAX_DIST)
		var try_xz := player.global_position + Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		var surface := _find_surface(try_xz)
		if surface == Vector3.ZERO:
			continue
		var biome_cat := _get_biome_category(surface)
		var animal_class := _pick_species(biome_cat, _species_count)
		if animal_class.is_empty():
			continue
		var blood_moon := TimeManager.is_blood_moon
		var solo := (animal_class == "Wolf" or animal_class == "Coyote")
		var group: int
		if blood_moon:
			group = 1 if solo else randi_range(3, 6)
		else:
			group = 1 if solo else randi_range(2, 4)
		for _i in group:
			var off := Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
			var mob := _spawn_animal(animal_class, surface + off)
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
		_: return null
	get_parent().add_child(mob)
	mob.global_position = pos
	return mob
