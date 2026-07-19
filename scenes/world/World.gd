## World.gd — Main world scene. Initializes and coordinates all world systems.
extends Node3D

@onready var chunk_manager: ChunkManager = $ChunkManager
@onready var player: Player = $Player
@onready var hud: CanvasLayer = $HUD

var world_generator: WorldGenerator

var light_engine: LightEngine
var dim_manager: DimensionManager
var block_entity_manager: BlockEntityManager
var lod_manager: LodManager

var _tick_timer: float = 0.0
const TICK_RATE := 0.05  # 20 ticks/sec

var _break_overlay: MeshInstance3D = null
var _break_mat: StandardMaterial3D = null

# Weather particles (CPUParticles3D attached to player, follows them around)
var _weather_particles: CPUParticles3D = null
var _weather_mat: StandardMaterial3D   = null
# Ambient winter snow — light snowfall independently of storm weather
var _snow_ambient: CPUParticles3D      = null
var _snow_mat: StandardMaterial3D      = null

# Quest board UI ref
var _quest_board_ui = null

# Explore quest proximity check timer
var _explore_tick: float = 0.0


func _ready() -> void:
	var wname := GameManager.current_world_name
	var wseed := GameManager.world_seed
	var dim   := GameManager.current_dimension

	# Init world generation
	world_generator = WorldGenerator.new()
	world_generator.initialize(wseed, dim)
	world_generator.generation_type = GameManager.generation_type
	chunk_manager.initialize(wname, wseed, dim)
	chunk_manager._world_generator = world_generator

	# Light engine
	light_engine = LightEngine.new()
	light_engine.setup(chunk_manager)
	add_child(light_engine)

	# Dimension manager
	dim_manager = DimensionManager.new()
	dim_manager.setup(chunk_manager)
	add_child(dim_manager)

	# Block entity manager
	block_entity_manager = BlockEntityManager.new()
	add_child(block_entity_manager)

	# Mining cracks + break particles
	add_child(BreakEffects.new())

	# Connect player
	player._chunk_manager = chunk_manager
	player._block_entity_manager = block_entity_manager
	player.creative = GameManager.creative_mode
	if GameManager.creative_mode:
		player.is_flying = true

	# LOD manager — runs alongside ChunkManager for distant terrain
	lod_manager = LodManager.new()
	lod_manager.name = "LodManager"
	add_child(lod_manager)
	lod_manager.initialize(wname, dim, world_generator)

	# Day/night cycle — reads TimeManager, drives sky/sun/moon/fog
	var day_night := preload("res://scenes/world/DayNightCycle.gd").new()
	day_night.name = "DayNightCycle"
	add_child(day_night)

	GameManager.set_world(self)
	GameManager.set_player(player)

	# Signals
	EventBus.player_died.connect(_on_player_died)
	EventBus.item_dropped.connect(_on_item_dropped)
	EventBus.block_interacted.connect(_on_block_interacted)
	EventBus.mob_died.connect(_on_mob_died)
	chunk_manager.chunk_loaded.connect(_on_chunk_loaded)
	EventBus.block_placed.connect(func(pos: Vector3i, _bid: int, _meta: Dictionary) -> void:
		_relight_around(pos))
	EventBus.block_broken.connect(func(pos: Vector3i, _bid: int, _p: Node) -> void:
		_relight_around(pos))

	# Spawn player on surface — force collision build first so they don't fall through
	var spawn_pos := _find_spawn_surface()
	_force_spawn_collision(spawn_pos)
	player.global_position = spawn_pos
	player.respawn_position = spawn_pos

	# Inventory UI — must exist before player spawns so EventBus.inventory_opened is connected
	var inv_ui := preload("res://scenes/ui/InventoryUI.tscn").instantiate()
	add_child(inv_ui)

	# Creative item palette (press G) — only in creative worlds
	if GameManager.creative_mode:
		var creative_ui: Node = load("res://scenes/ui/CreativeInventoryUI.gd").new()
		creative_ui.name = "CreativeInventoryUI"
		add_child(creative_ui)

	# Recipe catalog — primary crafting interface (opens on crafting_table interact or C key)
	var catalog_ui: Node = load("res://scenes/ui/RecipeCatalogUI.gd").new()
	catalog_ui.name = "RecipeCatalogUI"
	add_child(catalog_ui)

	# Crafting table UI — 3×3 grid, opens via catalog's "Ouvrir dans la table" button
	var craft_ui := preload("res://scenes/ui/CraftingTableUI.tscn").instantiate()
	add_child(craft_ui)

	# Furnace UI — opens on block_interacted when block is furnace/blast_furnace/smoker
	var furnace_ui := preload("res://scenes/ui/FurnaceUI.tscn").instantiate()
	add_child(furnace_ui)

	# Recipe book — layer 8, opens via "Recettes" button or EventBus
	var recipe_book := preload("res://scenes/ui/RecipeBookUI.tscn").instantiate()
	add_child(recipe_book)

	# Pause menu
	var pause_menu := preload("res://scenes/ui/PauseMenu.tscn").instantiate()
	add_child(pause_menu)

	# Death screen — respawn / back to menu
	var death_screen := DeathScreen.new()
	death_screen.name = "DeathScreen"
	add_child(death_screen)

	# Chest / container UI
	var chest_ui: Node = load("res://scenes/ui/ChestUI.gd").new()
	chest_ui.name = "ChestUI"
	add_child(chest_ui)

	# Mob spawner
	var mob_spawner := MobSpawner.new()
	mob_spawner.name = "MobSpawner"
	add_child(mob_spawner)
	mob_spawner.initialize(chunk_manager)

	# Quest board UI — opens when player interacts with block 258
	var quest_board_ui: Node = load("res://scenes/ui/QuestBoardUI.gd").new()
	quest_board_ui.name = "QuestBoardUI"
	add_child(quest_board_ui)
	_quest_board_ui = quest_board_ui

	# Equipment screen — O key, shows armor slots + stats
	var equip_ui: EquipmentUI = load("res://scenes/ui/EquipmentUI.gd").new()
	equip_ui.name = "EquipmentUI"
	add_child(equip_ui)

	# In-game guide — G / F1, modern onboarding panel for new players
	var guide_ui: GameGuideUI = load("res://scenes/ui/GameGuideUI.gd").new()
	guide_ui.name = "GameGuideUI"
	add_child(guide_ui)

	# Debug / test panel — F12 to toggle, all 14 features testable
	var debug_panel: DebugPanel = load("res://scenes/ui/DebugPanel.gd").new()
	debug_panel.name = "DebugPanel"
	add_child(debug_panel)

	_setup_environment()
	_setup_clouds()
	_setup_break_overlay()
	_setup_weather_particles()
	EventBus.weather_changed.connect(_on_weather_changed)
	# Apply current season immediately (world may load mid-winter)
	_on_season_changed_weather(SeasonManager.current_season)
	print("[World] Started: '%s'  seed=%d  dim=%s" % [wname, wseed, dim])


func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
	chunk_manager.update_player_position(player.global_position)
	lod_manager.update_player_position(player.global_position)
	_tick_clouds(delta)
	_tick_timer += delta
	if _tick_timer >= TICK_RATE:
		_tick_timer -= TICK_RATE
		_world_tick()
	# Poll explore quest every 2s
	_explore_tick += delta
	if _explore_tick >= 2.0:
		_explore_tick = 0.0
		QuestManager.notify_explore(player.global_position)


func _world_tick() -> void:
	_random_block_tick()


## Recompute light for the chunk containing pos (and adjacent chunks when the
## change is near a border), then queue the affected meshes for rebuild.
func _relight_around(pos: Vector3i) -> void:
	if light_engine == null:
		return
	light_engine.on_block_changed(pos)
	var cp    := Chunk.world_to_chunk(pos)
	var local := Chunk.world_to_local(pos, cp.y)
	# Same-frame rebuild — coalesces with the one queued by set_block_at, so
	# the edit shows up instantly with correct lighting.
	chunk_manager._rebuild_now(cp, true)
	# Light bleeds across borders — refresh direct neighbours when close to one
	if local.x <= 1:  _relight_neighbor(cp + Vector3i(-1, 0, 0))
	if local.x >= 14: _relight_neighbor(cp + Vector3i(1, 0, 0))
	if local.y <= 1:  _relight_neighbor(cp + Vector3i(0, -1, 0))
	if local.y >= 14: _relight_neighbor(cp + Vector3i(0, 1, 0))
	if local.z <= 1:  _relight_neighbor(cp + Vector3i(0, 0, -1))
	if local.z >= 14: _relight_neighbor(cp + Vector3i(0, 0, 1))


func _relight_neighbor(cp: Vector3i) -> void:
	var chunk := chunk_manager.get_chunk(cp)
	if chunk == null:
		return
	LightEngine.compute_sky_light_for_chunk(chunk)
	LightEngine.compute_block_light_for_chunk(chunk)
	chunk_manager._rebuild_now(cp)


func _random_block_tick() -> void:
	const RANDOM_TICKS  := 3
	const TICK_RADIUS   := 3   # only simulate chunks within this XZ distance of player
	var pc := chunk_manager._player_chunk
	for key in chunk_manager.loaded_chunks:
		var chunk: Chunk = chunk_manager.loaded_chunks[key]
		var cc := chunk.chunk_pos
		# Skip distant chunks — they don't need per-tick simulation
		if abs(cc.x - pc.x) > TICK_RADIUS or abs(cc.z - pc.z) > TICK_RADIUS:
			continue
		for _i in RANDOM_TICKS:
			var lx := randi() % 16
			var ly := randi() % 16
			var lz := randi() % 16
			var bid := chunk.get_block(lx, ly, lz)
			if bid == 0:
				continue
			var block := BlockRegistry.get_block(bid)
			if block == null:
				continue
			if bid == 3:  # dirt → try grass spread
				_try_grass_spread(chunk, lx, ly, lz)
			elif block.tags.has("crop"):
				_try_crop_growth(chunk, lx, ly, lz, bid)
			elif block.tags.has("sapling"):
				_try_sapling_growth(chunk, lx, ly, lz, block)
			elif block.tags.has("cane"):
				_try_cane_growth(chunk, lx, ly, lz)


func _try_grass_spread(chunk: Chunk, lx: int, ly: int, lz: int) -> void:
	if ly + 1 >= 16:
		return
	if chunk.get_block(lx, ly + 1, lz) == 0 and chunk.get_sky_light(lx, ly + 1, lz) >= 9:
		chunk.set_block(lx, ly, lz, 2)  # grass_block


## Saplings grow into full trees after a few successful random ticks.
func _try_sapling_growth(chunk: Chunk, lx: int, ly: int, lz: int,
		block: BlockRegistry.BlockDef) -> void:
	if chunk.get_sky_light(lx, ly, lz) < 8:
		return
	var mult := SeasonManager.get_growth_multiplier()
	if mult <= 0.0:
		return   # winter: nothing grows
	var meta := chunk.get_block_meta(lx, ly, lz)
	var stage: int = meta.get("stage", 0) + 1
	if stage < 3:
		meta["stage"] = stage
		chunk.set_block_meta(lx, ly, lz, meta)
		return
	var wpos := chunk.get_world_origin() + Vector3i(lx, ly, lz)
	var species: String = block.raw.get("sapling_species", "oak")
	chunk.set_block_meta(lx, ly, lz, {})
	WorldGenerator.grow_tree_at(chunk_manager, wpos, species)


## Sugar cane grows up to 3 blocks tall.
func _try_cane_growth(chunk: Chunk, lx: int, ly: int, lz: int) -> void:
	var wpos := chunk.get_world_origin() + Vector3i(lx, ly, lz)
	# Count cane below
	var below := 0
	while chunk_manager.get_block_at(wpos + Vector3i(0, -below - 1, 0)) == 89:
		below += 1
	if below >= 2:
		return
	if chunk_manager.get_block_at(wpos + Vector3i(0, 1, 0)) == 0:
		chunk_manager.set_block_at(wpos + Vector3i(0, 1, 0), 89)


func _try_crop_growth(chunk: Chunk, lx: int, ly: int, lz: int, bid: int) -> void:
	if chunk.get_sky_light(lx, ly, lz) < 9:
		return
	var mult := SeasonManager.get_growth_multiplier()
	if mult <= 0.0:
		return   # Winter: crops are frozen
	if mult < 1.0 and randf() > mult:
		return   # Autumn: skip this tick probabilistically
	var meta := chunk.get_block_meta(lx, ly, lz)
	var age: int = meta.get("age", 0)
	var block := BlockRegistry.get_block(bid)
	var max_age: int = block.raw.get("growth_stages", 8) - 1
	if age < max_age:
		age += 1
		# Summer bonus: chance for an extra stage in the same tick
		if mult > 1.0 and age < max_age and randf() < (mult - 1.0):
			age += 1
		meta["age"] = age
		chunk.set_block_meta(lx, ly, lz, meta)


func _on_item_dropped(stack: Dictionary, pos: Vector3) -> void:
	var iid: String = stack.get("id", stack.get("item", ""))
	var cnt: int    = stack.get("count", 1)
	if iid.is_empty() or cnt <= 0:
		return
	var item := DroppedItem.new()
	add_child(item)
	item.setup(iid, cnt, pos)


func _on_player_died(_player_node: Node, _cause: String) -> void:
	print("[World] Player died.")


# ── Artifact drops from boss mobs ─────────────────────────────────────────────

const _ARTIFACT_WEAPONS: Array[String] = [
	"axiom:iron_sword", "axiom:diamond_sword",
	"axiom:iron_pickaxe", "axiom:diamond_pickaxe",
	"axiom:iron_axe", "axiom:diamond_axe",
	"axiom:bow",
]

func _on_mob_died(mob: Node, killer: Node) -> void:
	if mob == null:
		return

	# soul_harvest: grant bonus XP to the player-killer
	if killer == player:
		var harvest := int(player._get_held_artifact_bonus("soul_harvest"))
		if harvest > 0:
			player.add_xp(harvest)

	# Artifact drop: only from boss-tier mobs (xp_reward >= 100)
	var xp_reward: int = int(mob.get("xp_reward")) if mob.get("xp_reward") != null else 0
	if xp_reward < 100:
		return
	if randf() > 0.70:
		return   # 70% chance to drop an artifact from bosses

	var num_bonuses := 1
	if xp_reward >= 300: num_bonuses = 2
	if xp_reward >= 500: num_bonuses = 3

	var item_id := _ARTIFACT_WEAPONS[randi() % _ARTIFACT_WEAPONS.size()]
	var pos: Vector3 = (mob as Node3D).global_position if mob is Node3D else Vector3.ZERO
	var seed_val := GameManager.world_seed ^ (int(pos.x) * 7919) ^ (int(pos.z) * 6271) ^ randi()
	var stack := ArtifactGenerator.make_artifact_stack(item_id, abs(seed_val), num_bonuses)
	EventBus.item_dropped.emit(stack, pos + Vector3(0, 1.5, 0))
	EventBus.show_message.emit(
		"Artefact : %s [%s]" % [stack["artifact_name"], stack["artifact_rarity_name"]], 5.0
	)


func _setup_environment() -> void:
	# Sky, fog, and ambient light are fully managed by DayNightCycle.
	# Only thing we enforce here: no shadows on the sun (too expensive for voxels).
	var sun := find_child("DirectionalLight3D") as DirectionalLight3D
	if sun:
		sun.shadow_enabled = false


# ── Clouds ─────────────────────────────────────────────────────────────────────

var _clouds: MeshInstance3D = null
var _cloud_mat: StandardMaterial3D = null
var _cloud_offset: float = 0.0

func _setup_clouds() -> void:
	if GameManager.current_dimension != "overworld":
		return
	# Soft seamless cloud texture: wrap-around blob stamping
	const CT := 256
	var accum := PackedFloat32Array()
	accum.resize(CT * CT)
	var rng := RandomNumberGenerator.new()
	rng.seed = GameManager.world_seed + 777
	for _i in 46:
		var cx := rng.randf_range(0, CT)
		var cy := rng.randf_range(0, CT)
		var r  := rng.randf_range(9.0, 26.0)
		var strength := rng.randf_range(0.5, 1.0)
		var ir := int(ceil(r))
		for dy in range(-ir, ir + 1):
			for dx in range(-ir, ir + 1):
				var d := sqrt(float(dx * dx + dy * dy)) / r
				if d >= 1.0:
					continue
				var px := posmod(int(cx) + dx, CT)
				var py := posmod(int(cy) + dy, CT)
				accum[py * CT + px] += (1.0 - d * d) * strength
	var img := Image.create(CT, CT, false, Image.FORMAT_RGBA8)
	for y in CT:
		for x in CT:
			var v := accum[y * CT + x]
			var alpha := clampf(smoothstep(0.35, 1.0, v), 0.0, 1.0) * 0.60
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	var tex := ImageTexture.create_from_image(img)

	_clouds = MeshInstance3D.new()
	_clouds.name = "Clouds"
	var plane := PlaneMesh.new()
	plane.size = Vector2(3600, 3600)
	_clouds.mesh = plane
	_cloud_mat = StandardMaterial3D.new()
	_cloud_mat.albedo_texture = tex
	_cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cloud_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cloud_mat.uv1_scale = Vector3(5.0, 5.0, 1.0)
	_cloud_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_clouds.material_override = _cloud_mat
	_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_clouds.position = Vector3(0, 192.0, 0)
	add_child(_clouds)


func _tick_clouds(delta: float) -> void:
	if _clouds == null or _cloud_mat == null:
		return
	# Follow the player horizontally, drift the texture with the wind
	_clouds.position.x = player.global_position.x
	_clouds.position.z = player.global_position.z
	_cloud_offset += delta * 0.0016
	_cloud_mat.uv1_offset = Vector3(_cloud_offset + player.global_position.x / 18000.0,
		player.global_position.z / 18000.0, 0.0)
	# Day/night + weather tint
	var day := clampf((TimeManager.get_sun_height() + 0.15) / 0.4, 0.0, 1.0)
	var bright := lerpf(0.10, 1.0, day)
	var alpha_mult := 1.0
	if SeasonManager.is_precipitating():
		bright *= 0.55
		alpha_mult = 1.35
	_cloud_mat.albedo_color = Color(bright, bright, minf(bright * 1.06, 1.0), alpha_mult)


## Public wrapper used by the player's void-rescue safety net.
func find_spawn_surface() -> Vector3:
	return _find_spawn_surface()


func _find_spawn_surface() -> Vector3:
	var cy_min: int = ChunkManager.DIM_Y_MIN.get(GameManager.current_dimension, -8)
	var cy_max: int = ChunkManager.DIM_Y_MAX.get(GameManager.current_dimension, 19)
	for cy in range(cy_min, cy_max + 1):
		chunk_manager.ensure_chunk_sync(Vector3i(0, cy, 0))

	# Use the heightmap to find the true surface of the column.
	# Scanning top-chunk-first guarantees we hit the highest exposed block, not a cave ceiling.
	# The old "3-air-check" approach failed when a tree/overhang was present, causing the
	# algorithm to descend past the surface and land on a cave ceiling instead.
	const LX := 8
	const LZ := 8
	for cy in range(cy_max, cy_min - 1, -1):
		var chunk := chunk_manager.get_chunk(Vector3i(0, cy, 0))
		if chunk == null or chunk.is_all_air:
			continue
		var top_ly := chunk.get_height(LX, LZ)   # topmost non-air local Y in this column
		if top_ly < 0:
			continue
		var wy := cy * 16 + top_ly
		if wy < 60:
			continue   # too deep — bedrock or deep cave, keep scanning up
		return Vector3(LX + 0.5, float(wy + 1), LZ + 0.5)

	return Vector3(8.5, 80.0, 8.5)   # fallback


## Build mesh + collision synchronously for the chunks immediately around the spawn point.
## Prevents the player from falling through the floor before async collision is ready.
func _force_spawn_collision(spawn_pos: Vector3) -> void:
	var spawn_cy := floori(spawn_pos.y / 16.0)
	for dy in range(-1, 3):   # one below, spawn chunk, two above
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var cp := Vector3i(dx, spawn_cy + dy, dz)
				# Neighbour columns may not exist yet — generate them so the
				# renderer is there to force-build (async was too late on web).
				chunk_manager.ensure_chunk_sync(cp)
				var key := chunk_manager._chunk_key(cp)
				if chunk_manager._renderers.has(key):
					(chunk_manager._renderers[key] as ChunkRenderer).force_initial_build()


func _setup_break_overlay() -> void:
	_break_overlay = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.005, 1.005, 1.005)
	_break_overlay.mesh = mesh
	_break_mat = StandardMaterial3D.new()
	_break_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_break_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	_break_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_break_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_break_mat.render_priority = 1
	_break_overlay.material_override = _break_mat
	_break_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_break_overlay.visible = false
	add_child(_break_overlay)

	player.block_targeted.connect(func(bpos: Vector3i, _bid: int) -> void:
		_break_overlay.position = Vector3(bpos.x + 0.5, bpos.y + 0.5, bpos.z + 0.5)
	)
	player.no_block_targeted.connect(func() -> void:
		_break_overlay.visible = false
		_break_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	)
	player.block_break_progress.connect(func(progress: float) -> void:
		if progress <= 0.0:
			_break_overlay.visible = false
			_break_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
		else:
			_break_overlay.visible = true
			# 9 crack stages like Minecraft: darken progressively
			var stage := floori(progress * 9.0)
			var alpha := 0.1 + stage * 0.07   # 0.1 → 0.73 across 9 stages
			_break_mat.albedo_color = Color(0.0, 0.0, 0.0, alpha)
	)


const _ALTAR_CLASS_NAME := {
	250: "Mineur",
	251: "Guerrier",
	252: "Ingénieur",
	253: "Mage",
	254: "Fermier",
}

# ── Archives / Nexus state ────────────────────────────────────────────────────

var _nexus_fragment_given: bool  = false
var _nexus_return_pos: Vector3   = Vector3.ZERO

const _ARCHIVES_LORE := [
	"NORD — Architecte Varek :\n« Nous avons bâti ces Archives pour que notre savoir survive à la Rupture. Vous trouvez ces mots. Cela signifie que nous avons échoué à l'empêcher. »",
	"SUD — Architecte Solen :\n« Le Gardien de Pierre fut notre frère. Quand la Rupture l'a corrompu, aucun d'entre nous n'a pu le toucher. Nous l'avons scellé dans la pierre pour l'éternité. »",
	"OUEST — Architecte Miren :\n« L'Écho n'est pas une créature. C'est un écho de notre propre peur, amplifié par la fissure dans le tissu du monde. On ne peut pas le tuer. On ne peut qu'espérer l'endormir. »",
	"EST — Architecte Kael :\n« Nous étions quatre. Nous serons toujours quatre. Si vous lisez ceci avec nos quatre fragments réunis, vous méritez ce qui vient après. »"
]

const _NEXUS_FINAL_LORE := "INSCRIPTION FINALE :\n« Vous avez trouvé la vérité derrière les gardiens, derrière l'Écho, derrière la Rupture. Nous, les Architectes, ne sommes pas morts. Nous sommes devenus le monde lui-même.\n\nEt quelque chose d'autre a survécu à la Rupture.\nQuelque chose qui n'a pas de nom.\n\nPas encore. »"


func _on_block_interacted(bpos: Vector3i, bid: int, interactor: Node) -> void:
	if not (interactor is Player):
		return
	var p := interactor as Player
	match bid:
		92:
			_handle_bed(bpos, p)
		250, 251, 252, 253, 254:
			_handle_skill_altar(bpos, bid, p)
		255:
			_handle_archives_core(bpos, p)
		256:
			_handle_lore_tablet(bpos, p)
		257:
			_handle_nexus_portal(p)
		258:
			_handle_quest_board(bpos, p)


## Sleeping: skip to dawn (at night) and set the respawn point.
func _handle_bed(bpos: Vector3i, p: Player) -> void:
	p.respawn_position = Vector3(bpos.x + 0.5, bpos.y + 1.0, bpos.z + 0.5)
	if TimeManager.is_day():
		EventBus.show_message.emit("Point de réapparition défini. Vous ne pouvez dormir que la nuit.", 3.5)
		return
	TimeManager.skip_to_dawn()
	EventBus.show_message.emit("Vous vous réveillez au petit matin, reposé.", 4.0)


func _handle_skill_altar(bpos: Vector3i, bid: int, p: Player) -> void:
	if p.skill_tree == null: return
	p.skill_tree.available_points += 1
	EventBus.skill_point_gained.emit(1)
	chunk_manager.set_block_at(bpos, 0)
	var cls_name: String = _ALTAR_CLASS_NAME[bid]
	EventBus.show_message.emit("Point de compétence acquis ! [%s]" % cls_name, 4.0)


func _handle_archives_core(bpos: Vector3i, p: Player) -> void:
	if _is_in_nexus():
		# Final inscription altar inside the Nexus — read only
		EventBus.show_message.emit("Fragment du Nexus, confirmé. Le cycle est accompli.", 5.0)
		return
	# Restore flag if player already owns the fragment (e.g. after world reload).
	var inv := p.inventory
	if not _nexus_fragment_given and inv != null and _has_item(inv, "axiom:nexus_fragment"):
		_nexus_fragment_given = true
	if _nexus_fragment_given:
		EventBus.show_message.emit("Le Nexus attend au-delà du portail.", 3.0)
		return
	if inv == null: return
	if not _has_item(inv, "axiom:architect_map"):
		EventBus.show_message.emit("L'autel attend la Carte des Architectes...", 4.0)
		return
	_remove_item(inv, "axiom:architect_map")
	inv.add_items("axiom:nexus_fragment", 1, {})
	_nexus_fragment_given = true
	EventBus.show_message.emit("La Carte s'enflamme. Le passage vers le Nexus est ouvert.", 6.0)


func _handle_lore_tablet(bpos: Vector3i, p: Player) -> void:
	if _is_in_nexus():
		EventBus.show_message.emit(_NEXUS_FINAL_LORE, 12.0)
		return
	var apos := GameManager.get_archives_location()
	var dx   := bpos.x - apos.x
	var dz   := bpos.z - apos.y
	var idx: int
	if abs(dx) > abs(dz):
		idx = 3 if dx > 0 else 2   # East / West
	else:
		idx = 1 if dz > 0 else 0   # South / North
	EventBus.show_message.emit(_ARCHIVES_LORE[idx], 9.0)


func _handle_nexus_portal(p: Player) -> void:
	if _is_in_nexus():
		p.global_position = _nexus_return_pos
		EventBus.show_message.emit("Vous quittez le Nexus.", 3.0)
		EventBus.nexus_exited.emit()
	else:
		if not _nexus_fragment_given:
			EventBus.show_message.emit("Le portail reste scellé.", 3.0)
			return
		_nexus_return_pos = p.global_position + Vector3(0, 1, 0)
		p.global_position = Vector3(100000.0, 252.0, 100000.0)
		EventBus.show_message.emit("Vous entrez dans le Nexus...", 4.0)
		EventBus.nexus_entered.emit()


func _handle_quest_board(bpos: Vector3i, p: Player) -> void:
	if _quest_board_ui == null:
		EventBus.show_message.emit("Panneau non initialisé.", 3.0)
		return
	var village_cx := int(floor(float(bpos.x) / 200.0))
	var village_cz := int(floor(float(bpos.z) / 200.0))
	_quest_board_ui.open(village_cx, village_cz, p)


func _is_in_nexus() -> bool:
	var lp := GameManager.local_player as Node3D
	if lp == null: return false
	return abs(lp.global_position.x - 100000.0) < 200.0 and \
		   abs(lp.global_position.z - 100000.0) < 200.0


func _has_item(inv: Inventory, item_id: String) -> bool:
	for i in 36:
		if inv.get_slot(i).get("id", "") == item_id: return true
	return false


func _remove_item(inv: Inventory, item_id: String) -> void:
	for i in 36:
		var stack := inv.get_slot(i)
		if stack.get("id", "") == item_id:
			inv.set_slot(i, {})
			return


func _on_chunk_loaded(cp: Vector3i) -> void:
	_try_spawn_road_merchant(cp)
	_try_spawn_boss(cp)
	_try_spawn_castle_npcs(cp)


# ── Merchant spawning ─────────────────────────────────────────────────────────

# Route constants mirrored from StructurePlacer — must stay in sync.
const _ROUTE_CELL  := 160
const _ROUTE_PROB  := 75
const _ROUTE_REACH := 450
const _MERCHANT_PROB := 8   # % of road nodes that spawn a merchant (per session)

var _spawned_merchant_cells: Dictionary = {}   # "cx,cz" → true, prevents duplicates


func _try_spawn_road_merchant(cp: Vector3i) -> void:
	# Only surface chunks (world y ≥ 0) near spawn
	if cp.y < 0:
		return
	var wx0 := cp.x * 16
	var wz0 := cp.z * 16
	var cx0 := floori(float(wx0) / float(_ROUTE_CELL))
	var cx1 := floori(float(wx0 + 15) / float(_ROUTE_CELL))
	var cz0 := floori(float(wz0) / float(_ROUTE_CELL))
	var cz1 := floori(float(wz0 + 15) / float(_ROUTE_CELL))
	for cx in range(cx0, cx1 + 1):
		for cz in range(cz0, cz1 + 1):
			var key := "%d,%d" % [cx, cz]
			if _spawned_merchant_cells.has(key):
				continue
			if not _road_node_in_range(cx, cz):
				continue
			var node_hash := _route_hash(cx, cz)
			if node_hash % 100 >= _ROUTE_PROB:
				continue
			if node_hash % 1000 >= _MERCHANT_PROB * 10:
				continue
			_spawned_merchant_cells[key] = true
			_spawn_merchant_at_node(cx, cz)


func _road_node_in_range(cx: int, cz: int) -> bool:
	var nx := cx * _ROUTE_CELL + _ROUTE_CELL / 2
	var nz := cz * _ROUTE_CELL + _ROUTE_CELL / 2
	return nx * nx + nz * nz <= _ROUTE_REACH * _ROUTE_REACH


func _route_hash(cx: int, cz: int) -> int:
	var wseed: int = GameManager.world_seed
	return ((cx * 374761393) ^ (cz * 668265261) ^ (wseed * 2654435761)) & 0x7FFFFFFF


func _road_node_pos_world(cx: int, cz: int) -> Vector2i:
	var h := _route_hash(cx, cz)
	var jitter := int(_ROUTE_CELL * 0.25)
	var ox := (h >> 4)  % (_ROUTE_CELL - 2 * jitter) + jitter
	var oz := (h >> 14) % (_ROUTE_CELL - 2 * jitter) + jitter
	return Vector2i(cx * _ROUTE_CELL + ox, cz * _ROUTE_CELL + oz)


func _spawn_merchant_at_node(cx: int, cz: int) -> void:
	var npos  := _road_node_pos_world(cx, cz)
	var surf  := world_generator.get_surface_y(npos.x, npos.y) if world_generator and world_generator.has_method("get_surface_y") \
			else 70
	var spawn := Vector3(npos.x + 0.5, float(surf + 1), npos.y + 0.5)

	# Build patrol path: this node + up to 3 E/S neighbours that also have nodes
	var patrol: Array[Vector3] = [spawn]
	for dcx in [1, 0, -1]:
		for dcz in [1, 0, -1]:
			if dcx == 0 and dcz == 0:
				continue
			var ncx: int = cx + dcx
			var ncz: int = cz + dcz
			if _route_hash(ncx, ncz) % 100 >= _ROUTE_PROB:
				continue
			if not _road_node_in_range(ncx, ncz):
				continue
			var np   := _road_node_pos_world(ncx, ncz)
			var ns   := world_generator.get_surface_y(np.x, np.y) if world_generator and world_generator.has_method("get_surface_y") \
					else 70
			patrol.append(Vector3(np.x + 0.5, float(ns + 1), np.y + 0.5))
			if patrol.size() >= 4:
				break
		if patrol.size() >= 4:
			break

	var merchant := WanderingMerchant.new()
	add_child(merchant)
	merchant.global_position = spawn
	merchant.setup_patrol(patrol)


# ── Boss spawning ─────────────────────────────────────────────────────────────

const _FORT_CELL   := 400
const _FORT_ODDS   := 60
const _FORT_RADIUS := 900       # max distance from origin a fortress may spawn
const _FORT_MIN_RADIUS := 260   # keep the Stone Guardian well away from spawn
const _ARENA_CELL  := 350
const _ARENA_ODDS  := 55
const _ARENA_RADIUS := 600
const _ARENA_MIN_RADIUS := 200  # keep the Echo away from the nether entry point

var _spawned_bosses: Dictionary = {}   # "type:cx,cz" → true


func _try_spawn_boss(cp: Vector3i) -> void:
	var dim := GameManager.current_dimension
	match dim:
		"overworld": _try_spawn_guardian(cp)
		"nether":    _try_spawn_echo(cp)


func _try_spawn_guardian(cp: Vector3i) -> void:
	if cp.y < 0:
		return
	var wx0 := cp.x * 16
	var wz0 := cp.z * 16
	var cx := floori(float(wx0 + 8) / float(_FORT_CELL))
	var cz := floori(float(wz0 + 8) / float(_FORT_CELL))
	var key := "guardian:%d,%d" % [cx, cz]
	if _spawned_bosses.has(key):
		return
	var h: int = (((cx * 57654319) ^ (cz * 34521961) ^ (GameManager.world_seed * 3141592)) & 0x7FFFFFFF)
	if h % 100 >= _FORT_ODDS:
		return
	var ox := (h >> 6)  % (_FORT_CELL - 20) + 10
	var oz := (h >> 18) % (_FORT_CELL - 20) + 10
	var bx := cx * _FORT_CELL + ox
	var bz := cz * _FORT_CELL + oz
	var d2 := bx * bx + bz * bz
	if d2 > _FORT_RADIUS * _FORT_RADIUS or d2 < _FORT_MIN_RADIUS * _FORT_MIN_RADIUS:
		return
	# Only spawn if this chunk actually contains the fortress center
	if abs(bx - (wx0 + 8)) > 16 or abs(bz - (wz0 + 8)) > 16:
		return
	_spawned_bosses[key] = true
	var surf := world_generator.get_surface_y(bx, bz) if world_generator else 70
	var boss := StoneGuardian.new()
	add_child(boss)
	boss.global_position = Vector3(bx + 0.5, float(surf + 2), bz + 0.5)


func _try_spawn_echo(cp: Vector3i) -> void:
	var wx0 := cp.x * 16
	var wz0 := cp.z * 16
	var cx := floori(float(wx0 + 8) / float(_ARENA_CELL))
	var cz := floori(float(wz0 + 8) / float(_ARENA_CELL))
	var key := "echo:%d,%d" % [cx, cz]
	if _spawned_bosses.has(key):
		return
	var h: int = (((cx * 91234567) ^ (cz * 45678901) ^ (GameManager.world_seed * 7654321)) & 0x7FFFFFFF)
	if h % 100 >= _ARENA_ODDS:
		return
	var ox := (h >> 5)  % (_ARENA_CELL - 20) + 10
	var oz := (h >> 17) % (_ARENA_CELL - 20) + 10
	var bx := cx * _ARENA_CELL + ox
	var bz := cz * _ARENA_CELL + oz
	var d2 := bx * bx + bz * bz
	if d2 > _ARENA_RADIUS * _ARENA_RADIUS or d2 < _ARENA_MIN_RADIUS * _ARENA_MIN_RADIUS:
		return
	if abs(bx - (wx0 + 8)) > 16 or abs(bz - (wz0 + 8)) > 16:
		return
	_spawned_bosses[key] = true
	var boss := EchoEntity.new()
	add_child(boss)
	boss.global_position = Vector3(bx + 0.5, 37.0, bz + 0.5)


# ── Castle NPC spawning ───────────────────────────────────────────────────────

const _CASTLE_CELL   := 600
const _CASTLE_ODDS   := 60
const _CASTLE_RADIUS := 900

var _spawned_castles: Dictionary = {}


func _try_spawn_castle_npcs(cp: Vector3i) -> void:
	if cp.y < 0:
		return
	var wx0 := cp.x * 16
	var wz0 := cp.z * 16
	var cx := floori(float(wx0 + 8) / float(_CASTLE_CELL))
	var cz := floori(float(wz0 + 8) / float(_CASTLE_CELL))
	var key := "castle:%d,%d" % [cx, cz]
	if _spawned_castles.has(key):
		return
	var h: int = (((cx * 29484329) ^ (cz * 81652903) ^ (GameManager.world_seed * 1234567)) & 0x7FFFFFFF)
	if h % 100 >= _CASTLE_ODDS:
		return
	var ox := (h >> 7)  % (_CASTLE_CELL - 20) + 10
	var oz := (h >> 19) % (_CASTLE_CELL - 20) + 10
	var bx := cx * _CASTLE_CELL + ox
	var bz := cz * _CASTLE_CELL + oz
	if bx * bx + bz * bz > _CASTLE_RADIUS * _CASTLE_RADIUS:
		return
	if abs(bx - (wx0 + 8)) > 16 or abs(bz - (wz0 + 8)) > 16:
		return
	_spawned_castles[key] = true
	var castle_type: int = h % 4
	var surf := world_generator.get_surface_y(bx, bz) if world_generator else 70
	var center := Vector3(bx + 0.5, float(surf + 1), bz + 0.5)
	_spawn_castle_guards(castle_type, center, surf)
	_spawn_castle_merchant(castle_type, center, surf)


func _spawn_castle_guards(castle_type: int, center: Vector3, surf: int) -> void:
	var count := 3 + (castle_type % 2)   # 3 or 4 guards per castle
	for i in count:
		var angle := (TAU / count) * i + randf() * 0.5
		var dist  := randf_range(4.0, 8.0)
		var gpos  := center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		gpos.y    = float(surf + 1)
		var guard := CastleGuard.new()
		add_child(guard)
		guard.global_position = gpos
		guard.setup(castle_type, center, 8.0)


func _spawn_castle_merchant(castle_type: int, center: Vector3, surf: int) -> void:
	# Merchant spawns inside the keep/cabin, slightly behind center
	var mpos := center + Vector3(0.0, 0.0, 3.0)
	mpos.y   = float(surf + 1)
	var merchant := CastleMerchant.new()
	add_child(merchant)
	merchant.global_position = mpos
	merchant.setup_castle(castle_type, mpos)


# ── Weather particles ──────────────────────────────────────────────────────────

func _setup_weather_particles() -> void:
	# ── Storm/Rain particles ──────────────────────────────────────────────────
	_weather_particles = CPUParticles3D.new()
	_weather_particles.name           = "WeatherParticles"
	_weather_particles.emitting       = false
	_weather_particles.amount         = 1500
	_weather_particles.lifetime       = 1.2
	_weather_particles.local_coords   = true
	_weather_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_weather_particles.emission_box_extents = Vector3(20, 0.5, 20)
	player.add_child(_weather_particles)
	_weather_particles.position = Vector3(0, 16, 0)

	# Rain mesh: thin elongated capsule oriented downward (looks like a streak)
	var rain_mesh := CapsuleMesh.new()
	rain_mesh.radius          = 0.018
	rain_mesh.height          = 0.45
	rain_mesh.radial_segments = 4
	rain_mesh.rings           = 1
	_weather_mat = StandardMaterial3D.new()
	_weather_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	_weather_mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	_weather_mat.vertex_color_use_as_albedo = true
	_weather_mat.cull_mode                  = BaseMaterial3D.CULL_DISABLED
	_weather_mat.albedo_color               = Color(0.65, 0.78, 1.00, 0.75)
	rain_mesh.material = _weather_mat
	_weather_particles.mesh = rain_mesh

	# ── Ambient winter snow (always on in WINTER season, low density) ─────────
	_snow_ambient = CPUParticles3D.new()
	_snow_ambient.name           = "SnowAmbient"
	_snow_ambient.emitting       = false
	_snow_ambient.amount         = 220
	_snow_ambient.lifetime       = 5.0
	_snow_ambient.local_coords   = true
	_snow_ambient.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_snow_ambient.emission_box_extents  = Vector3(16, 0.5, 16)
	_snow_ambient.direction             = Vector3(0.05, -1, 0.03)
	_snow_ambient.spread                = 12.0
	_snow_ambient.gravity               = Vector3(0, -1.2, 0)
	_snow_ambient.initial_velocity_min  = 1.0
	_snow_ambient.initial_velocity_max  = 2.5
	_snow_ambient.scale_amount_min      = 0.14
	_snow_ambient.scale_amount_max      = 0.22
	player.add_child(_snow_ambient)
	_snow_ambient.position = Vector3(0, 14, 0)

	var snow_mesh := SphereMesh.new()
	snow_mesh.radius          = 0.07
	snow_mesh.height          = 0.07
	snow_mesh.radial_segments = 4
	snow_mesh.rings           = 2
	_snow_mat = StandardMaterial3D.new()
	_snow_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	_snow_mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	_snow_mat.vertex_color_use_as_albedo = true
	_snow_mat.cull_mode                  = BaseMaterial3D.CULL_DISABLED
	_snow_mat.albedo_color               = Color(0.95, 0.97, 1.00, 0.88)
	snow_mesh.material = _snow_mat
	_snow_ambient.mesh = snow_mesh

	# Apply current season immediately in case World loads mid-winter
	EventBus.season_changed.connect(_on_season_changed_weather)


func _on_season_changed_weather(season: int) -> void:
	if _snow_ambient == null:
		return
	_snow_ambient.emitting = (season == SeasonManager.Season.WINTER)


func _on_weather_changed(weather: int) -> void:
	if _weather_particles == null:
		return
	var is_winter: bool = SeasonManager.is_winter()
	match weather:
		SeasonManager.Weather.CLEAR, SeasonManager.Weather.CLOUDY:
			_weather_particles.emitting = false
			# Winter: ambient snow stays active even without storm
			if _snow_ambient:
				_snow_ambient.emitting = is_winter
			return
		SeasonManager.Weather.RAIN:
			_weather_particles.amount               = 1500
			_weather_particles.lifetime             = 1.1
			_weather_particles.direction            = Vector3(0, -1, 0)
			_weather_particles.spread               = 4.0
			_weather_particles.gravity              = Vector3(0, -18, 0)
			_weather_particles.initial_velocity_min = 16.0
			_weather_particles.initial_velocity_max = 22.0
			_weather_particles.scale_amount_min     = 0.8
			_weather_particles.scale_amount_max     = 1.2
			_weather_mat.albedo_color = Color(0.60, 0.72, 0.95, 0.65)
		SeasonManager.Weather.THUNDERSTORM:
			_weather_particles.amount               = 2200
			_weather_particles.lifetime             = 0.9
			_weather_particles.direction            = Vector3(-0.12, -1, 0)
			_weather_particles.spread               = 6.0
			_weather_particles.gravity              = Vector3(-4, -24, 0)
			_weather_particles.initial_velocity_min = 22.0
			_weather_particles.initial_velocity_max = 30.0
			_weather_particles.scale_amount_min     = 0.9
			_weather_particles.scale_amount_max     = 1.3
			_weather_mat.albedo_color = Color(0.45, 0.55, 0.88, 0.80)
		SeasonManager.Weather.BLIZZARD:
			# Blizzard uses snow mesh (large, horizontal wind)
			var bliz_mesh := SphereMesh.new()
			bliz_mesh.radius = 0.07; bliz_mesh.height = 0.07
			bliz_mesh.radial_segments = 4; bliz_mesh.rings = 2
			_weather_mat.albedo_color = Color(0.93, 0.97, 1.00, 0.90)
			bliz_mesh.material = _weather_mat
			_weather_particles.mesh = bliz_mesh
			_weather_particles.amount               = 1400
			_weather_particles.lifetime             = 2.5
			_weather_particles.direction            = Vector3(0.7, -0.3, 0.2)
			_weather_particles.spread               = 30.0
			_weather_particles.gravity              = Vector3(5, -2, 1)
			_weather_particles.initial_velocity_min = 8.0
			_weather_particles.initial_velocity_max = 18.0
			_weather_particles.scale_amount_min     = 0.9
			_weather_particles.scale_amount_max     = 1.6
	_weather_particles.emitting = true
	# Blizzard suppresses ambient snow (blizzard IS the snow)
	if _snow_ambient:
		_snow_ambient.emitting = (is_winter and weather != SeasonManager.Weather.BLIZZARD)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_and_quit()


func save_world() -> void:
	chunk_manager.save_all_chunks()
	# Save block entities
	var save_path := GameManager.get_world_save_path() + "block_entities.json"
	DirAccess.make_dir_recursive_absolute(GameManager.get_world_save_path())
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(block_entity_manager.serialize()))
		file.close()
	print("[World] Saved.")


func _save_and_quit() -> void:
	save_world()
	get_tree().quit()


## Make sure the area around a respawn/teleport target has generated chunks
## with collision, so the player doesn't fall through the world.
func prepare_respawn_area(pos: Vector3) -> void:
	var cp := Vector3i(floori(pos.x / 16.0), floori(pos.y / 16.0), floori(pos.z / 16.0))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				chunk_manager.ensure_chunk_sync(cp + Vector3i(dx, dy, dz))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var key: int = chunk_manager._chunk_key(cp + Vector3i(dx, dy, dz))
				if chunk_manager._renderers.has(key):
					(chunk_manager._renderers[key] as ChunkRenderer).force_initial_build()
