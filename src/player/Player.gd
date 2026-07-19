## Player.gd
## Main player controller with full Minecraft-like movement:
## walking, sprinting, jumping, sneaking, swimming, flying (elytra/creative).
class_name Player
extends CharacterBody3D

# --- Stats ---
@export var max_health: float = 20.0
@export var max_hunger: float = 20.0
@export var max_saturation: float = 20.0
@export var base_speed: float = 4.317     # blocks/sec (vanilla walk speed)
@export var sprint_multiplier: float = 1.3
@export var sneak_multiplier: float = 0.3
@export var swim_multiplier: float = 0.4
@export var fly_speed: float = 10.92
@export var jump_velocity: float = 8.8    # vanilla ≈ 8.5 blocks/s
@export var gravity: float = 32.0         # blocks/s²
@export var elytra_min_speed: float = 3.0
@export var reach_distance: float = 4.5
@export var attack_reach: float = 3.0

# --- Current State ---
var health: float = 20.0
var hunger: float = 20.0
var saturation: float = 5.0
var xp_points: int = 0
var xp_level: int = 0
var armor_value: float = 0.0
var selected_hotbar_slot: int = 0

var is_on_ground: bool = false
var is_swimming: bool = false
var is_flying: bool = false         # Creative fly
var creative: bool = false          # Creative mode: instant break, no damage, infinite blocks
var is_gliding: bool = false        # Elytra
var is_sneaking: bool = false
var is_sprinting: bool = false
var is_underwater: bool = false

var _jump_count: int = 0
var _coyote_time: float = 0.0
var _last_jump_press: float = 0.0
var _double_jump_timer: float = 0.0
var _hunger_tick: float = 0.0
var _damage_cooldown: float = 0.0
var _swing_t: float = 0.0

# Survival damage tracking
var _starvation_timer: float = 0.0
var _lava_timer: float       = 0.0
var _pre_y_vel: float        = 0.0   # velocity.y before move_and_slide (for fall damage)
var _pre_floor: bool         = true  # is_on_floor() before move_and_slide

# Skill tree
var skill_tree: SkillTree = null
var _fury_timer: float    = 0.0   # Guerrier Furie: +20% dmg after kill
var _last_break_normal: Vector3i = Vector3i.ZERO

# References
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _head: Node3D = $Head
@onready var _hand_pivot: Node3D = $Head/Camera3D/HandPivot
@onready var _body_collision: CollisionShape3D = $BodyCollision
@onready var _sneak_collision: CollisionShape3D = $SneakCollision
@onready var _interact_ray: RayCast3D = $Head/Camera3D/InteractRay
var _chunk_manager: ChunkManager
var _block_entity_manager = null
var inventory: Inventory
var _hand_mesh: MeshInstance3D = null   # legacy, kept for reference
var _hand_visual: Node3D = null         # current hand visual (rebuilt on item change)
var _last_hand_item_id: String = "__none__"
var _mob_attack_cd: float = 0.0
# Weapon-style combat state
var _combo_count: int     = 0    # sword combo (1→2→3)
var _combo_timer: float   = 0.0  # window to chain next hit
const _COMBO_WINDOW       := 2.0

# Eating state
var _eating_time: float   = 0.0
var _poison_timer: float  = 0.0
var _poison_ticks: int    = 0
const EAT_DURATION := 1.4

# Respawn
var respawn_position: Vector3 = Vector3(8.5, 80.0, 8.5)

# Signals
signal health_changed(new_health: float, max_health: float)
signal hunger_changed(new_hunger: float, saturation: float)
signal xp_changed(points: int, level: int)
signal died()
signal block_targeted(block_pos: Vector3i, block_id: int)
signal no_block_targeted()
signal block_break_progress(progress_0_1: float)
signal eating_progress(progress_0_1: float)
signal block_breaking_at(block_pos: Vector3i, progress_0_1: float)  # crack overlay

# Game-feel state (footsteps, view bob, damage kick)
var _step_accum: float   = 0.0
var _dig_sound_t: float  = 0.0
var _munch_t: float      = 0.0
var _bob_t: float        = 0.0
var _cam_kick: float     = 0.0
var _base_cam_pos: Vector3 = Vector3.ZERO
var _base_fov: float     = 75.0
var _was_swimming: bool  = false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_chunk_manager = get_node_or_null("../ChunkManager")
	inventory = get_node_or_null("Inventory")

	creative = GameManager.creative_mode
	if creative:
		is_flying = true   # start airborne so you don't fall before chunks load

	# RPG Skill tree (must be before _give_dev_items)
	skill_tree = SkillTree.new()
	skill_tree.name = "SkillTree"
	add_child(skill_tree)
	var skill_ui := SkillTreeUI.new()
	skill_ui.name = "SkillTreeUI"
	add_child(skill_ui)
	skill_ui.init(skill_tree)
	EventBus.skill_unlocked.connect(_on_skill_unlocked)
	EventBus.mob_died.connect(_on_mob_died)
	if inventory != null:
		inventory.armor_changed.connect(_on_armor_changed)

	_setup_hand()
	_base_cam_pos = _camera.position
	_base_fov     = _camera.fov
	_give_dev_items()
	_apply_permanent_skill_bonuses()
	GameManager.set_player(self)
	EventBus.player_spawned.emit(self)
	safe_margin      = 0.04
	floor_snap_length = 0.3


func _physics_process(delta: float) -> void:
	# Hold physics while the terrain under our feet has no collision yet —
	# web builds chunks asynchronously and without this you can fall through
	# freshly loaded ground (especially right after spawn).
	if _should_hold_for_terrain():
		# Emergency: build the ground under us synchronously (one small hitch
		# beats being frozen for seconds while the async queue catches up).
		if _chunk_manager.has_method("make_solid_now"):
			_chunk_manager.make_solid_now(global_position + Vector3(0, -0.3, 0))
		if _should_hold_for_terrain():
			velocity = Vector3.ZERO
			return
	_tick_void_rescue()
	_handle_gravity(delta)
	_handle_movement(delta)
	_tick_eating(delta)
	_handle_block_interaction()
	_tick_portal_travel(delta)
	_tick_hunger(delta)
	_tick_poison(delta)
	_tick_damage_cooldown(delta)
	_pre_y_vel  = velocity.y
	_pre_floor  = is_on_floor()
	move_and_slide()
	is_on_ground = is_on_floor()
	if is_on_ground:
		_jump_count = 0
		_coyote_time = 0.15
	_handle_fall_damage(_pre_y_vel, _pre_floor)
	_tick_lava_damage(delta)
	_tick_footsteps()


func _process(delta: float) -> void:
	_coyote_time    = maxf(_coyote_time    - delta, 0.0)
	_mob_attack_cd  = maxf(_mob_attack_cd  - delta, 0.0)
	_fury_timer     = maxf(_fury_timer     - delta, 0.0)
	_combo_timer    = maxf(_combo_timer    - delta, 0.0)
	if _combo_timer <= 0.0:
		_combo_count = 0
	_handle_hotbar_scroll()
	_handle_attack()
	_handle_mob_attack()
	_handle_mob_interaction()
	_check_underwater()
	_update_hand()
	_animate_hand(delta)
	_update_camera_feel(delta)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotate_camera(event.relative)
	if event.is_action_pressed("open_inventory"):
		EventBus.inventory_opened.emit(self)
	if event.is_action_pressed("drop_item"):
		_drop_held_item()
	if event.is_action_pressed("open_skill_tree"):
		var ui := get_node_or_null("SkillTreeUI") as SkillTreeUI
		if ui != null:
			ui.toggle()
		get_viewport().set_input_as_handled()


func _handle_gravity(delta: float) -> void:
	if is_flying or is_gliding:
		return
	if is_swimming:
		# Gentle sink/float
		if not Input.is_action_pressed("jump"):
			velocity.y -= 2.0 * delta
			velocity.y = maxf(velocity.y, -1.5)
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
		# Cap at 25 m/s (~0.42 blocks/frame at 60fps, 0.83 at 30fps).
		# 54 m/s caused tunneling through 1-block-thick floors at low framerates.
		velocity.y = maxf(velocity.y, -25.0)
	_handle_coyote_jump()


func _handle_coyote_jump() -> void:
	if Input.is_action_just_pressed("jump"):
		_last_jump_press = 0.15
	elif Input.is_action_pressed("jump") and (is_on_floor() or _coyote_time > 0.0):
		_last_jump_press = 0.15   # maintien espace au sol → saute à chaque atterrissage
	_last_jump_press = maxf(_last_jump_press - get_physics_process_delta_time(), 0.0)
	if _last_jump_press > 0.0 and (_coyote_time > 0.0 or _jump_count < 1):
		var jm := (skill_tree.jump_mult() if skill_tree else 1.0) + _get_armor_bonus("jump_mult")
		velocity.y = jump_velocity * jm
		_jump_count += 1
		_last_jump_press = 0.0
		_coyote_time = 0.0


func _handle_movement(delta: float) -> void:
	var dir := Vector3.ZERO
	var cam_basis := _head.global_basis

	if Input.is_action_pressed("move_forward"):
		dir -= cam_basis.z
	if Input.is_action_pressed("move_backward"):
		dir += cam_basis.z
	if Input.is_action_pressed("move_left"):
		dir -= cam_basis.x
	if Input.is_action_pressed("move_right"):
		dir += cam_basis.x

	dir.y = 0.0
	if dir.length_squared() > 0.001:
		dir = dir.normalized()

	is_sprinting = Input.is_action_pressed("sprint") and not is_sneaking and hunger > 6.0
	is_sneaking = Input.is_action_pressed("sneak") and not is_flying

	var speed := base_speed * (1.0 + _get_armor_bonus("move_speed"))
	if is_sprinting:
		var skill_sprint := skill_tree.sprint_speed_mult() if skill_tree else 1.0
		var sm := sprint_multiplier * (skill_sprint + _get_armor_bonus("sprint_speed"))
		speed *= sm
	elif is_sneaking:
		speed *= sneak_multiplier
	elif is_swimming:
		speed *= swim_multiplier
	if _is_on_path():
		speed *= 1.2

	if is_flying:
		speed = fly_speed
		if Input.is_action_pressed("jump"):
			velocity.y = fly_speed
		elif Input.is_action_pressed("sneak"):
			velocity.y = -fly_speed
		else:
			velocity.y = lerp(velocity.y, 0.0, 10.0 * delta)
	elif is_gliding:
		_handle_elytra(delta)
		return

	# Horizontal velocity with acceleration/deceleration
	var target_vel := dir * speed
	var accel := 30.0 if is_on_floor() else 5.0
	velocity.x = lerp(velocity.x, target_vel.x, accel * delta)
	velocity.z = lerp(velocity.z, target_vel.z, accel * delta)

	# Jump
	if is_swimming:
		if Input.is_action_pressed("jump"):
			velocity.y = 2.0
		elif Input.is_action_pressed("sneak"):
			velocity.y = -2.0
	elif Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
		_jump_count = 1

	# Sneak collision shape
	_body_collision.disabled = is_sneaking
	_sneak_collision.disabled = not is_sneaking


func _handle_elytra(delta: float) -> void:
	# Elytra gliding physics
	var fwd := -_head.global_basis.z
	var speed := velocity.length()
	var lift := fwd.dot(Vector3.UP) * speed * 0.5
	velocity += Vector3.UP * lift * delta
	velocity -= Vector3.UP * gravity * 0.5 * delta
	velocity = velocity.lerp(fwd * maxf(speed, elytra_min_speed), 5.0 * delta)
	# Firework boost
	# (handled by item use event)


func _rotate_camera(mouse_delta: Vector2) -> void:
	var sensitivity := 0.002
	_head.rotate_y(-mouse_delta.x * sensitivity)
	_camera.rotate_x(-mouse_delta.y * sensitivity)
	_camera.rotation.x = clampf(_camera.rotation.x, -PI * 0.49, PI * 0.49)


func _handle_block_interaction() -> void:
	if _chunk_manager == null:
		return
	# Don't interact with the world when the mouse is free (inventory, menus, etc.)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_reset_block_break()
		return
	var ray_result := _chunk_manager.raycast(
		_camera.global_position,
		-_camera.global_basis.z,
		reach_distance
	)
	if ray_result.get("hit", false):
		var bpos: Vector3i = ray_result["position"]
		var bid: int = ray_result["block_id"]
		block_targeted.emit(bpos, bid)
		# Break: hold left mouse button
		if Input.is_action_pressed("attack"):
			_last_break_normal = ray_result.get("normal", Vector3i.ZERO) as Vector3i
			_continue_block_break(bpos, bid)
		else:
			_reset_block_break()
		# Place / interact: single press for interactive blocks, hold to build continuously
		var just_interact := Input.is_action_just_pressed("interact")
		var hold_interact := Input.is_action_pressed("interact")
		if just_interact or (hold_interact and _place_cooldown <= 0.0):
			var block := BlockRegistry.get_block(bid)
			if block != null and block.interactive:
				if just_interact:
					EventBus.block_interacted.emit(bpos, bid, self)
			elif just_interact and _try_use_flint_and_steel(bpos, ray_result):
				_place_cooldown = 0.4
			else:
				var place_pos: Vector3i = bpos + (ray_result.get("normal", Vector3i.ZERO) as Vector3i)
				_place_block(place_pos)
				_place_cooldown = 0.25
	else:
		no_block_targeted.emit()
		_reset_block_break()


var _breaking_block_pos: Vector3i = Vector3i(-9999, -9999, -9999)
var _breaking_progress: float = 0.0
var _breaking_time: float = 0.0
var _place_cooldown: float = 0.0


func _compute_break_time(block: BlockRegistry.BlockDef, held_item: ItemRegistry.ItemDef) -> float:
	if creative:
		return 0.05  # instant break in creative
	if block.hardness == 0.0:
		return 0.05  # instant break (dirt-layer blocks, leaves, etc.)
	# No preferred tool → hand speed, no penalty
	if block.tool == "" or block.tool == "none":
		return maxf(block.hardness * 1.5, 0.05)
	# Check if held tool is the right type and level
	var speed := 1.0
	var correct_tool := false
	if held_item != null and held_item.tool == block.tool:
		if held_item.tool_level >= block.tool_level:
			correct_tool = true
			speed = maxf(held_item.mining_speed, 1.0)
	if correct_tool:
		var mining_mult := (skill_tree.mining_speed_mult() if skill_tree else 1.0) \
			+ _get_armor_bonus("mining_speed") \
			+ _get_held_artifact_bonus("fast_mining")
		return maxf(block.hardness * 1.5 / (speed * mining_mult), 0.05)
	# Bare hands / wrong tool: stone-family blocks resist hard, organic
	# blocks (wood, dirt...) only mildly — keeps the fist-vs-tree start fair.
	var penalty := 5.0 if block.tool == "pickaxe" else 2.5
	return maxf(block.hardness * penalty, 0.05)


func _continue_block_break(bpos: Vector3i, bid: int) -> void:
	if bpos != _breaking_block_pos:
		_breaking_block_pos = bpos
		_breaking_progress = 0.0
		_dig_sound_t = 0.0
		var block := BlockRegistry.get_block(bid)
		if block == null:
			return
		if block.hardness < 0:
			return  # indestructible (bedrock)
		var held := _get_held_item()
		var held_item: ItemRegistry.ItemDef = ItemRegistry.get_item(held.get("id", "")) if not ItemRegistry.is_empty_stack(held) else null
		_breaking_time = _compute_break_time(block, held_item)
	_breaking_progress += get_physics_process_delta_time()
	var ratio := _breaking_progress / _breaking_time if _breaking_time > 0.0 else 0.0
	block_break_progress.emit(ratio)
	block_breaking_at.emit(bpos, ratio)
	_dig_sound_t -= get_physics_process_delta_time()
	if _dig_sound_t <= 0.0:
		_dig_sound_t = 0.22
		SoundManager.dig_block(bid, Vector3(bpos) + Vector3(0.5, 0.5, 0.5))
	if _breaking_progress >= _breaking_time:
		_break_block(bpos, bid)


func _reset_block_break() -> void:
	if _breaking_progress > 0.0:
		block_break_progress.emit(0.0)
		block_breaking_at.emit(_breaking_block_pos, 0.0)
	_breaking_block_pos = Vector3i(-9999, -9999, -9999)
	_breaking_progress = 0.0


func _break_block(bpos: Vector3i, bid: int) -> void:
	var block := BlockRegistry.get_block(bid)
	if block == null or block.hardness < 0:
		return  # Indestructible (bedrock)

	# Always drop for now — tool requirement skipped until tools are fully balanced
	var held := _get_held_item()
	var held_item: ItemRegistry.ItemDef = ItemRegistry.get_item(held.get("id", "")) if not ItemRegistry.is_empty_stack(held) else null
	var drops := block.get_drop_list(
		held_item.tool if held_item else "",
		held_item.tool_level if held_item else 0,
		0, false
	)
	var drop_pos := Vector3(bpos.x + 0.5, bpos.y + 0.8, bpos.z + 0.5)
	for drop in drops:
		if drop["item"] != "" and drop["count"] > 0:
			EventBus.item_dropped.emit({"id": drop["item"], "count": drop["count"]}, drop_pos)
	# Artifact: double_drop chance
	var dd := _get_held_artifact_bonus("double_drop")
	if dd > 0.0 and randf() < dd:
		for drop in drops:
			if drop["item"] != "" and drop["count"] > 0:
				EventBus.item_dropped.emit({"id": drop["item"], "count": drop["count"]}, drop_pos)

	_chunk_manager.set_block_at(bpos, 0)
	if _block_entity_manager != null:
		_spill_container_contents(bpos)
		_block_entity_manager.remove_entity(bpos)
	EventBus.block_broken.emit(bpos, bid, self)
	block_break_progress.emit(0.0)
	block_breaking_at.emit(bpos, 0.0)
	_breaking_block_pos = Vector3i(-9999, -9999, -9999)
	_breaking_progress = 0.0

	# Vein Mining: BFS-mine connected ore blocks if enchantment present
	# Enchantments may be stored at top level (set_slot) or inside meta["enchantments"] (add_items)
	var _meta: Dictionary = held.get("meta", {})
	var enchants: Dictionary = _meta.get("enchantments", held.get("enchantments", {}))
	if held_item != null and held_item.tool == "pickaxe" \
			and enchants.get("vein_miner", 0) > 0 \
			and block.name.ends_with("_ore"):
		_vein_mine(bpos, bid, held_item)

	# 3×3 area mining (Mineur T3: Minage en Croix, requires sneaking)
	if skill_tree != null and skill_tree.is_3x3_enabled() and is_sneaking:
		_mine_3x3(bpos, held_item, _last_break_normal)


# ── Portals ────────────────────────────────────────────────────────────────────

var _portal_stand_timer: float = 0.0

## Flint & steel on obsidian lights a nether portal.
func _try_use_flint_and_steel(bpos: Vector3i, ray_result: Dictionary) -> bool:
	var held := _get_held_item()
	if held.get("id", "") != "axiom:flint_and_steel":
		return false
	if _chunk_manager.get_block_at(bpos) != 101:   # obsidian
		return false
	var world := GameManager.world_node
	if world == null:
		return false
	var dm = world.get("dim_manager")
	if dm == null:
		return false
	var air_pos: Vector3i = bpos + (ray_result.get("normal", Vector3i.ZERO) as Vector3i)
	return dm.try_ignite(air_pos)


## Standing inside a portal block starts the travel timer.
func _tick_portal_travel(delta: float) -> void:
	if _chunk_manager == null:
		return
	var feet := Vector3i(floori(global_position.x), floori(global_position.y + 0.2), floori(global_position.z))
	var bid := _chunk_manager.get_block_at(feet)
	if bid != 93 and bid != 94:   # nether_portal / end_portal
		_portal_stand_timer = 0.0
		return
	_portal_stand_timer += delta
	if _portal_stand_timer < 0.9:
		return
	_portal_stand_timer = 0.0
	var world := GameManager.world_node
	if world == null:
		return
	var dm = world.get("dim_manager")
	if dm == null or not dm.can_travel():
		return
	if bid == 93:
		dm.travel_nether(global_position)
	else:
		dm.travel_end(global_position)


# ── Eating ─────────────────────────────────────────────────────────────────────

func _held_food_item() -> ItemRegistry.ItemDef:
	var held := _get_held_item()
	if ItemRegistry.is_empty_stack(held):
		return null
	var item := ItemRegistry.get_item(held.get("id", ""))
	if item != null and item.is_food():
		return item
	return null


func is_eating() -> bool:
	return _eating_time > 0.0


func _tick_eating(delta: float) -> void:
	var item := _held_food_item()
	var can_eat := item != null and (hunger < max_hunger - 0.01 or health < max_health)
	var wants := Input.is_action_pressed("interact") \
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if can_eat and wants and not _targeting_interactive_block():
		_eating_time += delta
		eating_progress.emit(_eating_time / EAT_DURATION)
		_munch_t -= delta
		if _munch_t <= 0.0:
			_munch_t = 0.42
			SoundManager.play("eat", -10.0, 1.0 + randf_range(-0.1, 0.1))
		if _eating_time >= EAT_DURATION:
			_finish_eating(item)
			_eating_time = 0.0
			eating_progress.emit(0.0)
	elif _eating_time > 0.0:
		_eating_time = 0.0
		_munch_t = 0.0
		eating_progress.emit(0.0)


func _targeting_interactive_block() -> bool:
	if _chunk_manager == null:
		return false
	var ray := _chunk_manager.raycast(
		_camera.global_position, -_camera.global_basis.z, reach_distance)
	if not ray.get("hit", false):
		return false
	var block := BlockRegistry.get_block(ray.get("block_id", 0))
	return block != null and block.interactive


func _finish_eating(item: ItemRegistry.ItemDef) -> void:
	feed(item.food_value, item.saturation)
	# Special foods
	match item.short_id:
		"golden_apple":
			heal(4.0)
		"enchanted_golden_apple":
			heal(8.0)
		"milk_bucket":
			_poison_ticks = 0   # milk cures poison
	# Negative effects (rotten flesh, raw chicken, poisonous potato...)
	for eff in item.effects:
		var eff_name: String = eff.get("effect", "")
		if eff_name in ["hunger", "poison"] and randf() < eff.get("chance", 1.0):
			_poison_ticks = 4   # 4 damage ticks over ~6 s
	_consume_held_item(1)
	SoundManager.play("gulp", -8.0)
	EventBus.show_message.emit("", 0.0)   # clear any lingering message


func _tick_poison(delta: float) -> void:
	if _poison_ticks <= 0:
		return
	_poison_timer += delta
	if _poison_timer >= 1.5:
		_poison_timer = 0.0
		_poison_ticks -= 1
		if health > 1.0:
			health = maxf(1.0, health - 1.0)
			EventBus.player_health_changed.emit(self, health, max_health)


## Breaking a chest/furnace spills its contents on the ground.
func _spill_container_contents(bpos: Vector3i) -> void:
	var ent = _block_entity_manager.get_entity(bpos)
	if ent == null:
		return
	var drop_pos := Vector3(bpos.x + 0.5, bpos.y + 0.6, bpos.z + 0.5)
	var stacks: Array = []
	if ent is ChestEntity:
		stacks = (ent as ChestEntity).slots
	elif ent is FurnaceEntity:
		var f := ent as FurnaceEntity
		stacks = [f.input_slot, f.fuel_slot, f.output_slot]
	for stack in stacks:
		if stack is Dictionary and not ItemRegistry.is_empty_stack(stack):
			EventBus.item_dropped.emit(stack.duplicate(), drop_pos)


func _place_block(bpos: Vector3i) -> void:
	var held := _get_held_item()
	if ItemRegistry.is_empty_stack(held):
		return
	# Food is eaten (handled by _tick_eating), never placed
	if _held_food_item() != null:
		return
	var item_id: String = held.get("id", "")
	# Soul fragment: read lore text instead of placing
	var item_def := ItemRegistry.get_item(item_id)
	if item_def != null and item_def.raw.get("tags", []).has("soul_fragment"):
		var lore: String = item_def.raw.get("lore_text", "")
		if not lore.is_empty():
			EventBus.show_message.emit(lore, 8.0)
		return
	var block_id := ItemRegistry.get_block_id_for_item(item_id)
	if block_id == 0:
		return
	# Check space isn't occupied by player
	var block_center := Vector3(bpos) + Vector3(0.5, 0.5, 0.5)
	if global_position.distance_to(block_center) < 0.8:
		return
	_chunk_manager.set_block_at(bpos, block_id)
	if _block_entity_manager != null:
		_block_entity_manager.create_entity(bpos, block_id)
	EventBus.block_placed.emit(bpos, block_id, {})
	# Consume item (infinite blocks in creative)
	if not creative:
		_consume_held_item(1)


func _handle_hotbar_scroll() -> void:
	if Input.is_action_just_pressed("scroll_up"):
		selected_hotbar_slot = (selected_hotbar_slot - 1 + 9) % 9
	if Input.is_action_just_pressed("scroll_down"):
		selected_hotbar_slot = (selected_hotbar_slot + 1) % 9
	for i in 9:
		if Input.is_action_just_pressed("hotbar_%d" % (i + 1)):
			selected_hotbar_slot = i


func _handle_attack() -> void:
	pass


## Attack mob with left-click (separate from block breaking).
func _handle_mob_attack() -> void:
	if _mob_attack_cd > 0.0:
		return
	if not Input.is_action_just_pressed("attack"):
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var cam := _camera
	if cam == null:
		return
	var held_item := ItemRegistry.get_item(_get_held_item().get("id", ""))
	var reach := _get_attack_reach_for_weapon(held_item)
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		cam.global_position,
		cam.global_position + (-cam.global_basis.z * reach)
	)
	query.collision_mask = 4
	query.exclude = [self]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var body: Node3D = hit.get("collider") as Node3D
	if body == null or not body.has_method("take_damage"):
		return

	var wtype := _get_weapon_type(held_item)

	# Sword combo: track hits; finisher on 3rd
	if wtype == "sword":
		_combo_count += 1
		_combo_timer  = _COMBO_WINDOW

	var dmg := _get_attack_damage(body, held_item)

	# Artifact: crit chance (applied before damage)
	var crit_v := _get_held_artifact_bonus("crit_chance")
	var is_crit := crit_v > 0.0 and randf() < crit_v
	if is_crit:
		dmg *= 2.0

	# Artifact: shield_break — boost damage proportionally to ignored armour
	var sbreak := _get_held_artifact_bonus("shield_break")
	if sbreak > 0.0:
		dmg *= (1.0 + sbreak)

	if wtype == "sword" and _combo_count >= 3:
		_combo_count = 0
		_combo_timer = 0.0
		var dir := (body.global_position - global_position).normalized()
		dir.y = 0.3
		if body is CharacterBody3D:
			(body as CharacterBody3D).velocity = dir * 18.0

	# Mace: override mob's damage_reduction to apply armor pierce, then stun
	if wtype == "mace" and held_item != null:
		var pierce: float = held_item.raw.get("armor_pierce", 0.5)
		var saved_dr: float = body.get("damage_reduction") if body.get("damage_reduction") != null else 0.0
		if body.has_method("stun"):
			body.set("damage_reduction", saved_dr * (1.0 - pierce))
		body.take_damage(dmg, self)
		body.set("damage_reduction", saved_dr)
		var stun_dur: float = held_item.raw.get("stun_duration", 0.5)
		if body.has_method("stun"):
			body.stun(stun_dur)
	else:
		body.take_damage(dmg, self)

	# Artifact: post-hit effects
	_apply_artifact_hit_effects(body, dmg, is_crit)

	# Artifact: knockback_amp (applied after damage)
	var kb := _get_held_artifact_bonus("knockback_amp")
	if kb > 1.0 and body is CharacterBody3D:
		var kdir := (body.global_position - global_position).normalized()
		kdir.y = 0.2
		(body as CharacterBody3D).velocity += kdir * (kb - 1.0) * 8.0

	_mob_attack_cd = _get_attack_cooldown(held_item)


func _get_weapon_type(item: ItemRegistry.ItemDef) -> String:
	if item == null:
		return "fist"
	return item.tool   # "sword", "axe", "spear", "dagger", "mace", etc.


func _get_attack_cooldown(item: ItemRegistry.ItemDef) -> float:
	if item == null:
		return 0.5
	match item.tool:
		"sword":  return 0.50
		"axe":    return 1.00
		"spear":  return 0.80
		"dagger": return 0.22
		"mace":   return 0.90
		_:        return 0.50


func _get_attack_reach_for_weapon(item: ItemRegistry.ItemDef) -> float:
	if item != null and item.tool == "spear":
		return float(item.raw.get("reach", 5.5))
	return attack_reach


func _get_attack_damage(target: Node3D = null, item: ItemRegistry.ItemDef = null) -> float:
	if item == null:
		var held := _get_held_item()
		if not ItemRegistry.is_empty_stack(held):
			item = ItemRegistry.get_item(held.get("id", ""))

	var base_dmg := 1.0
	if item != null:
		base_dmg = float(item.raw.get("damage", 1))

	var wtype := _get_weapon_type(item)

	# Sword finisher: 3rd combo hit gets +20% damage + knockback (knockback applied in caller)
	if wtype == "sword" and _combo_count >= 3:
		base_dmg *= 1.20

	# Spear jump attack: +50% if falling
	if wtype == "spear" and velocity.y < -2.0:
		base_dmg *= 1.50

	# Dagger backstab: ×2 if attacking target's back
	if wtype == "dagger" and target != null:
		var my_fwd   := -global_basis.z
		var tgt_fwd  := -target.global_basis.z if target is Node3D else Vector3.ZERO
		if my_fwd.dot(tgt_fwd) > 0.5:   # both facing same direction = player behind mob
			var mult: float = item.raw.get("backstab_mult", 2.0) if item != null else 2.0
			base_dmg *= mult

	if skill_tree == null:
		return base_dmg

	var atk_mult := skill_tree.attack_damage_mult() + _get_armor_bonus("attack_damage")
	var dmg := base_dmg * atk_mult

	if _fury_timer > 0.0:
		dmg *= 1.20

	if target != null and target.has_method("get_hp_ratio"):
		var threshold := 0.25 + _get_armor_bonus("execute_threshold")
		dmg *= skill_tree.execute_damage_mult(target.get_hp_ratio(), threshold)

	return dmg


## Right-click on mob: tame / feed / interact.
func _handle_mob_interaction() -> void:
	if not Input.is_action_just_pressed("interact"):
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var space  := get_world_3d().direct_space_state
	var cam    := _camera
	if cam == null:
		return
	var query := PhysicsRayQueryParameters3D.create(
		cam.global_position,
		cam.global_position + (-cam.global_basis.z * reach_distance)
	)
	query.collision_mask = 4   # layer 3 = mobs
	query.exclude = [self]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var body: Node3D = hit.get("collider") as Node3D
	if body != null and body.has_method("try_interact"):
		body.try_interact(self)


func _check_underwater() -> void:
	if _chunk_manager == null:
		return
	var head_pos := Vector3i(
		floori(_head.global_position.x),
		floori(_head.global_position.y),
		floori(_head.global_position.z)
	)
	var block_at_head := _chunk_manager.get_block_at(head_pos)
	is_underwater = BlockRegistry.is_fluid(block_at_head)
	var feet_pos := Vector3i(
		floori(global_position.x),
		floori(global_position.y),
		floori(global_position.z)
	)
	is_swimming = BlockRegistry.is_fluid(_chunk_manager.get_block_at(feet_pos))
	if is_swimming and not _was_swimming and velocity.y < -3.0:
		SoundManager.play_at("splash", global_position, -4.0)
	_was_swimming = is_swimming


func _tick_hunger(delta: float) -> void:
	if creative:
		return  # no hunger/starvation in creative
	if is_sprinting:
		_hunger_tick += delta * 0.1  # Sprint drains hunger faster
	else:
		_hunger_tick += delta * 0.01
	if _hunger_tick >= 1.0:
		_hunger_tick = 0.0
		if saturation > 0:
			saturation = maxf(0.0, saturation - 1.0)
		elif hunger > 0:
			hunger = maxf(0.0, hunger - 1.0)
			EventBus.player_hunger_changed.emit(self, hunger, saturation)
	# Natural health regen when hunger > 18 (Fermier Symbiose: ×1.5 rate)
	if hunger > 18.0 and health < max_health:
		var regen_rate := 0.5 * ((skill_tree.food_regen_mult() if skill_tree else 1.0) + _get_armor_bonus("food_regen"))
		health = minf(health + delta * regen_rate, max_health)
		EventBus.player_health_changed.emit(self, health, max_health)
	# Starvation: 1 damage every 4 s when hunger = 0, stops at 1 HP
	if hunger <= 0.0 and health > 1.0:
		_starvation_timer += delta
		if _starvation_timer >= 4.0:
			_starvation_timer = 0.0
			health = maxf(1.0, health - 1.0)
			EventBus.player_health_changed.emit(self, health, max_health)
	else:
		_starvation_timer = 0.0


func _tick_damage_cooldown(delta: float) -> void:
	_damage_cooldown = maxf(0.0, _damage_cooldown - delta)
	_place_cooldown  = maxf(0.0, _place_cooldown  - delta)


func _handle_fall_damage(pre_vel_y: float, was_on_floor: bool) -> void:
	# Only triggers on landing: wasn't on floor before, is now, and fell fast enough.
	if was_on_floor or not is_on_floor():
		return
	if is_swimming or is_flying or is_gliding:
		return
	if skill_tree != null and skill_tree.has_no_fall_damage():
		return
	var impact := -pre_vel_y  # positive = falling down
	# Vanilla threshold: 3-block fall ~ 7.7 m/s impact; damage starts at ~14 m/s (7+ blocks).
	if impact > 14.0:
		var fall_dmg := (impact - 14.0) * 0.5
		fall_dmg *= maxf(0.0, 1.0 - _get_armor_bonus("fall_damage_mult"))
		take_damage(fall_dmg, "fall")


func _tick_lava_damage(delta: float) -> void:
	if _chunk_manager == null:
		return
	var feet := Vector3i(floori(global_position.x), floori(global_position.y), floori(global_position.z))
	var bid := _chunk_manager.get_block_at(feet)
	var block := BlockRegistry.get_block(bid)
	var in_lava := block != null and block.fluid and block.tags.has("lava")
	if in_lava:
		_lava_timer += delta
		if _lava_timer >= 0.5:
			_lava_timer = 0.0
			take_damage(4.0, "lava")
	else:
		_lava_timer = 0.0


## True while the chunk at (or just below) the feet has no collision yet.
func _should_hold_for_terrain() -> bool:
	if creative or is_flying or _chunk_manager == null:
		return false
	if not _chunk_manager.has_method("has_collision_at"):
		return false
	var feet := global_position + Vector3(0, -0.3, 0)
	if not _chunk_manager.has_collision_at(feet):
		return true
	if velocity.y < -0.1 and not _chunk_manager.has_collision_at(feet + Vector3(0, -2.0, 0)):
		return true
	return false


## Safety net: if we somehow end up far below the world floor, teleport back
## to a safe surface instead of falling forever.
func _tick_void_rescue() -> void:
	var cy_min: int = ChunkManager.DIM_Y_MIN.get(GameManager.current_dimension, -8)
	if global_position.y >= float(cy_min * 16) - 24.0:
		return
	var world := GameManager.world_node
	var target := respawn_position
	if world != null and world.has_method("find_spawn_surface"):
		target = world.find_spawn_surface()
	if world != null and world.has_method("prepare_respawn_area"):
		world.prepare_respawn_area(target)
	global_position = target + Vector3(0, 1.5, 0)
	velocity = Vector3.ZERO
	take_damage(2.0, "void")
	EventBus.show_message.emit("Le vide vous a recraché…", 2.5)


## Distance-based footsteps + landing thump, using the block under the feet.
func _tick_footsteps() -> void:
	if is_on_ground and not _pre_floor and _pre_y_vel < -7.0:
		_play_step_under_feet(-3.0)   # landing thump
		_step_accum = 0.0
		return
	if not is_on_ground or is_swimming or is_flying:
		return
	var hvel := Vector2(velocity.x, velocity.z).length()
	if hvel < 1.0:
		return
	_step_accum += hvel * get_physics_process_delta_time()
	if _step_accum >= 2.1:
		_step_accum = 0.0
		_play_step_under_feet(-9.0)


func _play_step_under_feet(vol_db: float) -> void:
	if _chunk_manager == null:
		return
	var below := Vector3i(floori(global_position.x), floori(global_position.y - 0.4), floori(global_position.z))
	var bid: int = _chunk_manager.get_block_at(below)
	if bid == 0:
		below.y -= 1
		bid = _chunk_manager.get_block_at(below)
	if bid != 0:
		SoundManager.step_on(bid, global_position, vol_db)


## View bobbing, sprint FOV kick and damage camera roll — all subtle.
func _update_camera_feel(delta: float) -> void:
	if _camera == null:
		return
	var hvel := Vector2(velocity.x, velocity.z).length()
	if is_on_ground and hvel > 0.8 and not is_swimming:
		_bob_t += delta * hvel * 1.6
		var amp := 0.042 if is_sprinting else 0.028
		var off := Vector3(cos(_bob_t * 0.5) * amp * 0.8, sin(_bob_t) * amp, 0.0)
		_camera.position = _camera.position.lerp(_base_cam_pos + off, minf(delta * 12.0, 1.0))
	else:
		_camera.position = _camera.position.lerp(_base_cam_pos, minf(delta * 6.0, 1.0))

	var target_fov := _base_fov
	if is_gliding:
		target_fov = _base_fov * 1.20
	elif is_sprinting and hvel > 1.0:
		target_fov = _base_fov * 1.13
	_camera.fov = lerpf(_camera.fov, target_fov, minf(delta * 8.0, 1.0))

	if absf(_cam_kick) > 0.0005:
		_camera.rotation.z = _cam_kick
		_cam_kick = lerpf(_cam_kick, 0.0, minf(delta * 10.0, 1.0))
	elif _camera.rotation.z != 0.0:
		_camera.rotation.z = 0.0


# --- Public API ---

func take_damage(amount: float, source: String = "generic") -> void:
	if creative:
		return  # invulnerable in creative
	if _damage_cooldown > 0.0:
		return
	var effective := maxf(0.0, amount - armor_value * 0.04)
	var dr_mult := (skill_tree.damage_reduction_mult() if skill_tree != null else 1.0) \
		- _get_armor_bonus("damage_reduction")
	effective *= maxf(0.05, dr_mult)
	health = maxf(0.0, health - effective)
	_damage_cooldown = 0.5
	EventBus.player_health_changed.emit(self, health, max_health)
	# Feel: hurt grunt + a quick camera roll kick
	SoundManager.play("hurt", -6.0, 1.0 + randf_range(-0.06, 0.06))
	_cam_kick = clampf(0.03 + effective * 0.02, 0.03, 0.09) * (1.0 if randf() < 0.5 else -1.0)
	if health <= 0:
		_die()


func heal(amount: float) -> void:
	health = minf(health + amount, max_health)
	EventBus.player_health_changed.emit(self, health, max_health)


func feed(food: int, sat: float) -> void:
	hunger = minf(hunger + food, max_hunger)
	saturation = minf(saturation + sat, max_saturation)
	EventBus.player_hunger_changed.emit(self, hunger, saturation)


func add_xp(amount: int) -> void:
	var gain := roundi(float(amount) * ((skill_tree.xp_gain_mult() if skill_tree else 1.0) + _get_armor_bonus("xp_gain")))
	xp_points += gain
	var xp_to_next := _xp_for_level(xp_level + 1)
	while xp_points >= xp_to_next:
		xp_points -= xp_to_next
		xp_level += 1
		xp_to_next = _xp_for_level(xp_level + 1)
		# Award 1 skill point every 5 levels
		if xp_level % 5 == 0 and skill_tree != null:
			skill_tree.available_points += 1
			EventBus.skill_point_gained.emit(1)
	xp_changed.emit(xp_points, xp_level)
	EventBus.player_xp_changed.emit(self, xp_points, xp_level)


func _xp_for_level(level: int) -> int:
	if level <= 16:
		return 2 * level + 7
	elif level <= 31:
		return 5 * level - 38
	else:
		return 9 * level - 158


func _die() -> void:
	# Keep xp_level but lose current progress toward next level
	xp_points = 0
	xp_changed.emit(xp_points, xp_level)
	EventBus.player_xp_changed.emit(self, xp_points, xp_level)
	died.emit()
	EventBus.player_died.emit(self, "generic")


## Hard-set position (used by portals, respawn, debug).
func teleport(pos: Vector3) -> void:
	global_position = pos
	velocity        = Vector3.ZERO
	_knockback_reset()


func _knockback_reset() -> void:
	_pre_y_vel = 0.0
	_pre_floor = true


## Bring the player back to life at the respawn point. Inventory is kept.
func respawn() -> void:
	health          = max_health
	hunger          = max_hunger
	saturation      = 5.0
	_poison_ticks   = 0
	_damage_cooldown = 2.0
	teleport(respawn_position + Vector3(0, 0.5, 0))
	EventBus.player_health_changed.emit(self, health, max_health)
	EventBus.player_hunger_changed.emit(self, hunger, saturation)
	EventBus.player_respawned.emit(self)


func toggle_creative_fly() -> void:
	is_flying = not is_flying
	if is_flying:
		velocity.y = 0


func set_dimension(dim_id: String) -> void:
	EventBus.player_dimension_changed.emit(self, GameManager.current_dimension, dim_id)
	GameManager.current_dimension = dim_id


func _get_held_item() -> Dictionary:
	if inventory == null:
		return {}
	return inventory.get_hotbar_item(selected_hotbar_slot)


func _consume_held_item(count: int) -> void:
	if inventory == null:
		return
	inventory.consume_hotbar_item(selected_hotbar_slot, count)


func _drop_held_item() -> void:
	var held := _get_held_item()
	if ItemRegistry.is_empty_stack(held):
		return
	EventBus.item_dropped.emit(held, global_position)  # drop as entity (future)
	_consume_held_item(1)


## Add item directly to inventory. Falls back to EventBus for future item-entity pickup.
func _collect_item(item_id: String, count: int) -> void:
	if inventory != null:
		var leftover := inventory.add_items(item_id, count)
		if leftover > 0:
			# Inventory full — drop the rest as an entity (future feature)
			EventBus.item_dropped.emit({"id": item_id, "count": leftover}, global_position)
	else:
		EventBus.item_dropped.emit({"id": item_id, "count": count}, global_position)


# --- Hand rendering ---

func _setup_hand() -> void:
	if _hand_pivot == null:
		return
	_build_fist_visual()


func _update_hand() -> void:
	if _hand_pivot == null:
		return
	var held     := _get_held_item()
	var item_id: String = held.get("id", "") if not ItemRegistry.is_empty_stack(held) else ""
	if item_id == _last_hand_item_id:
		return
	_last_hand_item_id = item_id

	# Remove old visual
	if _hand_visual != null and is_instance_valid(_hand_visual):
		_hand_visual.queue_free()
		_hand_visual = null

	if item_id.is_empty():
		_build_fist_visual()
		return
	var block_id := ItemRegistry.get_block_id_for_item(item_id)
	if block_id != 0:
		_build_block_visual(block_id)
	else:
		_build_item_visual(item_id)


func _build_fist_visual() -> void:
	# Small forearm poking in from the bottom-right corner (MC-style),
	# not a giant cube in the middle of the view.
	var mesh := MeshInstance3D.new()
	var box  := BoxMesh.new()
	box.size = Vector3(0.10, 0.10, 0.30)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.70, 0.55)
	mat.roughness    = 0.9
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.position = Vector3(0.12, -0.10, 0.02)
	mesh.rotation_degrees = Vector3(-20, 14, 10)
	_hand_pivot.add_child(mesh)
	_hand_visual = mesh


func _build_item_visual(item_id: String) -> void:
	# Try to load the PNG texture for this item
	var tex: Texture2D = ItemIcon._resolve(item_id)
	if tex != null:
		var spr := Sprite3D.new()
		spr.texture        = tex
		spr.pixel_size     = 0.015          # 16px × 0.015 ≈ 0.24 units wide
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		spr.shaded         = false
		spr.no_depth_test  = false
		# Gentle tilt — a strong yaw showed the flat sprite edge-on
		spr.rotation_degrees = Vector3(-6, -24, -10)
		spr.position = Vector3(0.10, -0.06, 0.02)
		spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hand_pivot.add_child(spr)
		_hand_visual = spr
	else:
		# Fallback: colored box
		var mesh := MeshInstance3D.new()
		var box  := BoxMesh.new()
		box.size = Vector3(0.08, 0.28, 0.06)
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = ItemIcon._fallback_color(item_id)
		mat.roughness    = 0.8
		mesh.material_override = mat
		mesh.rotation_degrees  = Vector3(-10, -35, -15)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hand_pivot.add_child(mesh)
		_hand_visual = mesh


func _build_block_visual(block_id: int) -> void:
	var block := BlockRegistry.get_block(block_id)
	# Try PNG texture for the block's top face
	var tex: Texture2D = null
	if block != null:
		var tex_name := block.get_texture_for_face("top")
		var candidates := [
			"res://assets/textures/blocks/%s.png" % tex_name,
			"res://assets/textures/blocks/%s_top.png" % tex_name,
			"res://assets/textures/blocks/%s.png" % block.name,
		]
		for path in candidates:
			if ResourceLoader.exists(path):
				tex = load(path) as Texture2D
				if tex != null:
					break

	if tex != null:
		var spr := Sprite3D.new()
		spr.texture        = tex
		spr.pixel_size     = 0.015
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		# Unshaded + almost facing the camera: with a strong yaw the sprite was
		# seen edge-on and showed up as a dark diagonal streak.
		spr.shaded         = false
		spr.no_depth_test  = false
		spr.rotation_degrees = Vector3(0, 22, 8)
		spr.position = Vector3(0.10, -0.06, 0.02)
		spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hand_pivot.add_child(spr)
		_hand_visual = spr
	else:
		var mesh := MeshInstance3D.new()
		var box  := BoxMesh.new()
		box.size = Vector3(0.28, 0.28, 0.28)
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = ItemIcon._fallback_color(
			"axiom:" + (block.name if block else "stone"))
		mat.roughness    = 0.9
		mesh.material_override = mat
		mesh.rotation_degrees  = Vector3(20, 45, 15)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hand_pivot.add_child(mesh)
		_hand_visual = mesh


# --- Skill tree integration ---

func _on_skill_unlocked(_skill_id: String) -> void:
	_apply_permanent_skill_bonuses()


func _apply_permanent_skill_bonuses() -> void:
	if skill_tree == null:
		return
	var base_health := 20.0
	max_health = base_health + skill_tree.max_health_bonus()
	health = minf(health, max_health)
	EventBus.player_health_changed.emit(self, health, max_health)


func _on_mob_died(mob: Node, killer: Node) -> void:
	if killer != self:
		return
	var reward := 5
	if mob.get("xp_reward") != null:
		reward = int(mob.xp_reward)
	add_xp(reward)
	# Guerrier Furie: start 5-second damage bonus after kill
	if skill_tree != null and skill_tree.has_skill("guerrier_furie"):
		_fury_timer = 5.0


func _is_on_path() -> bool:
	if _chunk_manager == null or is_flying or is_gliding:
		return false
	var bp := Vector3i(floori(global_position.x), floori(global_position.y) - 1, floori(global_position.z))
	return _chunk_manager.get_block_at(bp) == 4  # coarse_dirt = path surface


# ── Artifact helpers ───────────────────────────────────────────────────────────

func _get_held_artifact_bonus(type: String) -> float:
	var stack := _get_held_item()
	for b in stack.get("artifact_bonuses", []):
		if b.get("type") == type:
			return float(b.get("value", 0.0))
	return 0.0


func _apply_artifact_hit_effects(target: Node3D, dmg: float, is_crit: bool) -> void:
	# Lifesteal: heal a fraction of damage dealt
	var ls := _get_held_artifact_bonus("lifesteal")
	if ls > 0.0:
		health = minf(health + dmg * ls, max_health)
		EventBus.player_health_changed.emit(self, health, max_health)

	# AOE splash: damage all mobs within 3.5 m of target
	var aoe := _get_held_artifact_bonus("aoe_damage")
	if aoe > 0.0:
		var aoe_dmg := dmg * aoe
		var sphere := SphereShape3D.new()
		sphere.radius = 3.5
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape      = sphere
		params.transform  = Transform3D(Basis.IDENTITY, target.global_position)
		params.collision_mask = 4   # mob collision layer
		# exclude takes RIDs in Godot 4
		var excl: Array[RID] = []
		if self is CollisionObject3D:   excl.append((self as CollisionObject3D).get_rid())
		if target is CollisionObject3D: excl.append((target as CollisionObject3D).get_rid())
		params.exclude = excl
		var hits := get_world_3d().direct_space_state.intersect_shape(params, 8)
		for h in hits:
			var node := h.get("collider") as Node3D
			if node != null and node.has_method("take_damage"):
				node.take_damage(aoe_dmg, self)

	# Lightning strike: chance to deal bonus lightning damage
	var lightning := _get_held_artifact_bonus("lightning")
	if lightning > 0.0 and randf() < lightning:
		target.take_damage(dmg, self)
		EventBus.show_message.emit("⚡ Foudre !", 1.2)

	if is_crit:
		EventBus.show_message.emit("✦ Critique !", 0.8)


func can_craft_anywhere() -> bool:
	if inventory == null: return false
	for i in 36:
		if inventory.get_slot(i).get("id", "") == "axiom:portable_workbench":
			return true
	return false


func _get_armor_bonus(key: String) -> float:
	if inventory == null:
		return 0.0
	var total := 0.0
	for i in 4:
		var stack: Dictionary = inventory.get_armor_slot(i)
		if stack.is_empty():
			continue
		var item := ItemRegistry.get_item(stack.get("id", ""))
		if item == null:
			continue
		var bonus: Dictionary = item.raw.get("skill_bonus", {})
		total += float(bonus.get(key, 0.0))
	return total


func _recalculate_armor_value() -> void:
	var total := 0.0
	if inventory != null:
		for i in 4:
			var stack: Dictionary = inventory.get_armor_slot(i)
			if stack.is_empty():
				continue
			var item := ItemRegistry.get_item(stack.get("id", ""))
			if item != null:
				total += float(item.raw.get("armor", 0))
	armor_value = total
	EventBus.player_health_changed.emit(self, health, max_health)


func _on_armor_changed(_slot: int, _stack: Dictionary) -> void:
	_recalculate_armor_value()


func _mine_3x3(center: Vector3i, held_item: ItemRegistry.ItemDef, normal: Vector3i) -> void:
	if _chunk_manager == null:
		return
	# Determine the two axes perpendicular to the face normal
	var ax1: Vector3i
	var ax2: Vector3i
	if normal.x != 0:
		ax1 = Vector3i(0, 1, 0)
		ax2 = Vector3i(0, 0, 1)
	elif normal.y != 0:
		ax1 = Vector3i(1, 0, 0)
		ax2 = Vector3i(0, 0, 1)
	else:
		ax1 = Vector3i(1, 0, 0)
		ax2 = Vector3i(0, 1, 0)

	var tool_id := held_item.tool if held_item else ""
	var tool_lvl := held_item.tool_level if held_item else 0
	var fortune_lvl := (skill_tree.fortune_bonus() if skill_tree else 0) \
		+ roundi(_get_armor_bonus("fortune"))

	for da: int in [-1, 0, 1]:
		for db: int in [-1, 0, 1]:
			if da == 0 and db == 0:
				continue   # center already broken
			var pos := center + ax1 * da + ax2 * db
			var bid := _chunk_manager.get_block_at(pos)
			if bid == 0:
				continue
			var blk := BlockRegistry.get_block(bid)
			if blk == null or blk.hardness < 0:
				continue
			var drops := blk.get_drop_list(tool_id, tool_lvl, fortune_lvl, false)
			var dp := Vector3(pos.x + 0.5, pos.y + 0.8, pos.z + 0.5)
			for drop in drops:
				if drop["item"] != "" and drop["count"] > 0:
					EventBus.item_dropped.emit({"id": drop["item"], "count": drop["count"]}, dp)
			_chunk_manager.set_block_at(pos, 0)
			EventBus.block_broken.emit(pos, bid, self)


# --- Dev helpers (remove before release) ---

func _vein_mine(origin: Vector3i, ore_id: int, held_item: ItemRegistry.ItemDef) -> void:
	var MAX_VEIN: int = (skill_tree.vein_limit() if skill_tree else 32) \
		+ roundi(_get_armor_bonus("vein_bonus"))
	const DIRS: Array[Vector3i] = [
		Vector3i(1,0,0), Vector3i(-1,0,0),
		Vector3i(0,1,0), Vector3i(0,-1,0),
		Vector3i(0,0,1), Vector3i(0,0,-1)
	]
	var queue:    Array[Vector3i] = [origin]
	var seen:     Dictionary      = {}   # Vector3i → true (fast membership test)
	var to_break: Array[Vector3i] = []   # blocks to mine (excludes origin)
	seen[origin] = true

	# BFS flood fill — 6-connected, same block ID
	while not queue.is_empty() and to_break.size() < MAX_VEIN:
		var pos: Vector3i = queue.pop_front()
		for dir in DIRS:
			var nb: Vector3i = pos + dir
			if seen.has(nb):
				continue
			seen[nb] = true
			if _chunk_manager.get_block_at(nb) != ore_id:
				continue
			to_break.append(nb)
			queue.append(nb)

	# Mine collected blocks (origin already broken, no double-count)
	var block := BlockRegistry.get_block(ore_id)
	if block == null:
		return
	var fortune_lvl := (skill_tree.fortune_bonus() if skill_tree else 0) \
		+ roundi(_get_armor_bonus("fortune"))
	for pos in to_break:
		var drops := block.get_drop_list(held_item.tool, held_item.tool_level, fortune_lvl, false)
		var dp := Vector3(pos.x + 0.5, pos.y + 0.8, pos.z + 0.5)
		for drop in drops:
			if drop["item"] != "" and drop["count"] > 0:
				EventBus.item_dropped.emit({"id": drop["item"], "count": drop["count"]}, dp)
		_chunk_manager.set_block_at(pos, 0)
		EventBus.block_broken.emit(pos, ore_id, self)


func _give_dev_items() -> void:
	if inventory == null:
		return
	# True survival start: empty hands, the world provides.
	# (Creative worlds get the full item palette on G.)
	if creative:
		inventory.set_slot(0, {"id": "axiom:torch", "count": 64})
		inventory.set_slot(1, {"id": "axiom:oak_planks", "count": 64})


func _animate_hand(delta: float) -> void:
	if _hand_pivot == null:
		return
	var swinging := Input.is_action_pressed("attack") \
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if swinging:
		_swing_t = fmod(_swing_t + delta * 5.0, 1.0)
		# Fast downward strike then return: half-period forward, half back
		var angle := -sin(_swing_t * TAU) * 0.65
		_hand_pivot.rotation.x = lerp(_hand_pivot.rotation.x, angle, 25.0 * delta)
	else:
		_swing_t = 0.0
		_hand_pivot.rotation.x = lerp(_hand_pivot.rotation.x, 0.0, 12.0 * delta)
