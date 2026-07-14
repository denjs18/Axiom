## BaseAnimal.gd — AI base for all passive/neutral animals.
## Handles: wandering, herd panic, taming (with 3D progress bar), breeding, genetics.
class_name BaseAnimal
extends BaseMob

# ── Static registries ─────────────────────────────────────────────────────────
static var _herd_registry: Dictionary = {}   # species → Array[BaseAnimal]
static var _tamable_registry: Array   = []   # all tamable animals (for biome display queries)

# ── State machine ─────────────────────────────────────────────────────────────
enum AnimalState { IDLE, WANDER, GRAZE, FLEE, FOLLOW, SIT, BREED }
var _state: AnimalState  = AnimalState.IDLE
var _state_timer: float  = 0.0
var _ai_tick_timer: float = 0.0

# ── Movement ──────────────────────────────────────────────────────────────────
var walk_speed: float    = 2.0
var flee_speed: float    = 5.0
var _wander_target: Vector3 = Vector3.ZERO
var _flee_dir: Vector3   = Vector3.ZERO
var _flee_timer: float   = 0.0

# ── Detection ─────────────────────────────────────────────────────────────────
var detection_range: float = 8.0

# ── Taming ────────────────────────────────────────────────────────────────────
var can_be_tamed: bool      = false
var taming_item: String     = ""
var taming_progress: float  = 0.0   # 0.0 → 1.0
var taming_increment: float = 0.12
var taming_fail_chance: float = 0.30
var taming_cooldown: float  = 0.0
const _TAME_CD := 1.5

var _is_tamed: bool     = false
var _owner_node: Node3D = null

# Taming bar 3D visuals
var _tbar_root: Node3D       = null
var _tbar_fill: MeshInstance3D = null

# ── Breeding ──────────────────────────────────────────────────────────────────
var feed_item: String      = ""
var can_breed: bool        = true
var _in_love_mode: bool    = false
var _love_timer: float     = 0.0
var _breed_cooldown: float = 0.0
var _breed_partner: BaseAnimal = null
var _breed_timer: float    = 0.0
const _LOVE_DUR  := 30.0
const _BREED_CD  := 300.0

# ── Genetics ──────────────────────────────────────────────────────────────────
var genes: Dictionary = {"speed": 1.0, "health": 1.0, "size": 1.0}

# ── Visuals ───────────────────────────────────────────────────────────────────
var _visual_root: Node3D = null
var body_height: float   = 0.9


# ─────────────────────────────────────────────────────────────────────────────
# Setup helpers (called by subclasses in _mob_ready)
# ─────────────────────────────────────────────────────────────────────────────

func _init_genes(speed: float = 1.0, health_mult: float = 1.0, size: float = 1.0) -> void:
	genes = {
		"speed":  speed        * randf_range(0.90, 1.10),
		"health": health_mult  * randf_range(0.90, 1.10),
		"size":   size         * randf_range(0.90, 1.10),
	}
	walk_speed  = walk_speed  * genes["speed"]
	flee_speed  = flee_speed  * genes["speed"]
	max_health  = max_health  * genes["health"]
	health      = max_health
	if _visual_root:
		var s: float = genes["size"]
		_visual_root.scale = Vector3(s, s, s)


func _build_visual(body_size: Vector3, head_size: Vector3,
		body_col: Color, head_col: Color = Color(-1, 0, 0)) -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "Visual"
	add_child(_visual_root)
	body_height = body_size.y + 0.38   # legs raise the body

	var cfg := {
		"body_size": body_size,
		"head_size": head_size,
		"body_col": body_col,
		"head_col": head_col if head_col.r >= 0.0 else body_col,
		"leg_h": 0.38,
	}
	# Species flair — snouts, ears, tails, antlers, wool
	match species:
		"pig":
			cfg["snout_col"] = Color(0.98, 0.55, 0.55)
			cfg["leg_h"] = 0.28
		"cow":
			cfg["snout_col"] = Color(0.92, 0.85, 0.78)
			cfg["ears"] = "small"
		"sheep":
			cfg["wool"] = true
			cfg["head_col"] = Color(0.85, 0.78, 0.70)
			cfg["leg_col"] = Color(0.90, 0.88, 0.85)
		"chicken":
			cfg["leg_h"] = 0.30
			cfg["leg_col"] = Color(0.92, 0.75, 0.30)
			cfg["snout_col"] = Color(0.95, 0.70, 0.20)   # beak
		"rabbit":
			cfg["ears"] = "tall"
			cfg["leg_h"] = 0.16
		"wolf", "coyote":
			cfg["ears"] = "small"
			cfg["tail"] = true
			cfg["snout_col"] = (head_col if head_col.r >= 0.0 else body_col).darkened(0.15)
		"deer":
			cfg["antlers"] = true
			cfg["tail"] = true
			cfg["leg_h"] = 0.52
	build_quadruped(_visual_root, cfg)

	# Chickens get 2 legs only — drop the front pair
	if species == "chicken" and _anim_legs.size() == 4:
		(_anim_legs[2] as Node3D).queue_free()
		(_anim_legs[3] as Node3D).queue_free()
		_anim_legs.resize(2)


func _build_collision(radius: float, height: float) -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = height
	col.shape  = cap
	col.position.y = height * 0.5
	add_child(col)
	collision_layer = 4   # layer 3 (bit 2)
	collision_mask  = 1   # collide with terrain only


func _build_taming_bar() -> void:
	_tbar_root = Node3D.new()
	_tbar_root.name    = "TamingBar"
	_tbar_root.visible = false
	add_child(_tbar_root)

	const W := 0.70
	const H := 0.07

	var bg      := MeshInstance3D.new()
	var bg_box  := BoxMesh.new()
	bg_box.size = Vector3(W, H, 0.01)
	bg.mesh     = bg_box
	var bg_mat  := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.12, 0.12, 0.12, 0.88)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.no_depth_test  = true
	bg_mat.render_priority = 2
	bg.material_override   = bg_mat
	bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tbar_root.add_child(bg)

	var fill      := MeshInstance3D.new()
	var fill_box  := BoxMesh.new()
	fill_box.size = Vector3(W - 0.04, H - 0.02, 0.015)
	fill.mesh     = fill_box
	var fill_mat  := StandardMaterial3D.new()
	fill_mat.albedo_color  = Color(0.12, 0.82, 0.22)
	fill_mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.no_depth_test = true
	fill_mat.render_priority = 3
	fill.material_override   = fill_mat
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tbar_root.add_child(fill)
	_tbar_fill = fill


# ─────────────────────────────────────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────────────────────────────────────

func _mob_ready() -> void:
	_register_herd()
	if can_be_tamed:
		_tamable_registry.append(self)
		_build_taming_bar()
	_set_state(AnimalState.IDLE, randf_range(1.0, 3.0))
	_wander_target = global_position


func _exit_tree() -> void:
	_unregister_herd()
	_tamable_registry.erase(self)


# ─────────────────────────────────────────────────────────────────────────────
# Physics
# ─────────────────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if _dead:
		return
	_update_ai(delta)
	_apply_base_physics(delta)
	move_and_slide()
	_check_step_up()
	animate_walk(delta)
	_update_taming_bar()


# ─────────────────────────────────────────────────────────────────────────────
# AI state machine
# ─────────────────────────────────────────────────────────────────────────────

func _update_ai(delta: float) -> void:
	_state_timer    -= delta
	_ai_tick_timer  -= delta
	taming_cooldown  = maxf(0.0, taming_cooldown - delta)
	_breed_cooldown  = maxf(0.0, _breed_cooldown  - delta)

	if _ai_tick_timer <= 0.0:
		_ai_tick_timer = 0.30 + randf() * 0.15
		_do_periodic_checks()

	if _in_love_mode:
		_love_timer -= delta
		if _love_timer <= 0.0:
			_in_love_mode = false

	match _state:
		AnimalState.IDLE:
			velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
			if _state_timer <= 0.0:
				_transition_from_idle()

		AnimalState.WANDER:
			_move_toward_target(delta, walk_speed)
			if _state_timer <= 0.0 or _reached_wander_target():
				_set_state(AnimalState.IDLE, randf_range(1.5, 4.0))

		AnimalState.GRAZE:
			velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
			if _state_timer <= 0.0:
				_set_state(AnimalState.IDLE, randf_range(1.0, 2.5))

		AnimalState.FLEE:
			_flee_timer = maxf(0.0, _flee_timer - delta)
			_move_in_direction(_flee_dir, flee_speed, delta)
			if _flee_timer <= 0.0:
				_set_state(AnimalState.IDLE, 2.0)

		AnimalState.FOLLOW:
			if not is_instance_valid(_owner_node):
				_is_tamed = false
				_owner_node = null
				_set_state(AnimalState.IDLE, 2.0)
				return
			var dist := global_position.distance_to(_owner_node.global_position)
			if dist > 14.0:
				global_position = _owner_node.global_position \
					+ Vector3(randf_range(-2, 2), 1, randf_range(-2, 2))
			elif dist > 3.5:
				_wander_target = _owner_node.global_position
				_move_toward_target(delta, walk_speed * 1.4)
			else:
				velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
				velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)

		AnimalState.SIT:
			velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)

		AnimalState.BREED:
			_breed_timer -= delta
			if not is_instance_valid(_breed_partner):
				_set_state(AnimalState.IDLE, 2.0)
				return
			var dist := global_position.distance_to(_breed_partner.global_position)
			if dist > 1.8:
				_wander_target = _breed_partner.global_position
				_move_toward_target(delta, walk_speed)
			else:
				velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
				velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
			if _breed_timer <= 0.0:
				_do_breed()
				_set_state(AnimalState.IDLE, 3.0)


func _do_periodic_checks() -> void:
	if _is_tamed:
		return
	# Flee from player if too close
	var player := GameManager.local_player as Node3D
	if player != null and _state != AnimalState.FLEE:
		var dist := global_position.distance_to(player.global_position)
		if dist < detection_range:
			_start_flee(player.global_position)
			return
	# Look for breed partner when in love mode
	if _in_love_mode and _breed_cooldown <= 0.0 \
			and (_state == AnimalState.IDLE or _state == AnimalState.WANDER):
		_find_breeding_partner()


func _transition_from_idle() -> void:
	var r := randf()
	if r < 0.35:
		_pick_wander_target()
		_set_state(AnimalState.WANDER, randf_range(5.0, 12.0))
	elif r < 0.60:
		_set_state(AnimalState.GRAZE, randf_range(3.0, 8.0))
	else:
		_set_state(AnimalState.IDLE, randf_range(2.0, 5.0))


func _set_state(s: AnimalState, duration: float) -> void:
	_state       = s
	_state_timer = duration


func _start_flee(from_pos: Vector3) -> void:
	var dir := (global_position - from_pos)
	dir.y = 0.0
	_flee_dir = dir.normalized() if dir.length_squared() > 0.0001 \
		else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	_flee_timer = randf_range(5.0, 8.0)
	_set_state(AnimalState.FLEE, _flee_timer + 0.5)
	_alert_herd(_flee_dir)


# ─────────────────────────────────────────────────────────────────────────────
# Herd system
# ─────────────────────────────────────────────────────────────────────────────

func _register_herd() -> void:
	if species.is_empty():
		return
	if not _herd_registry.has(species):
		_herd_registry[species] = []
	(_herd_registry[species] as Array).append(self)


func _unregister_herd() -> void:
	if not species.is_empty() and _herd_registry.has(species):
		(_herd_registry[species] as Array).erase(self)


func _alert_herd(flee_dir: Vector3) -> void:
	if species.is_empty() or not _herd_registry.has(species):
		return
	for animal: BaseAnimal in (_herd_registry[species] as Array):
		if animal == self or not is_instance_valid(animal):
			continue
		if global_position.distance_to(animal.global_position) <= 12.0 \
				and animal._state != AnimalState.FLEE:
			animal._flee_dir   = flee_dir
			animal._flee_timer = randf_range(4.0, 7.0)
			animal._set_state(AnimalState.FLEE, animal._flee_timer + 0.5)


# ─────────────────────────────────────────────────────────────────────────────
# Taming
# ─────────────────────────────────────────────────────────────────────────────

## Called by Player on right-click.
func try_interact(player: Node) -> void:
	if _is_tamed:
		_on_interact_tamed(player)
		return
	# Try feeding for breeding
	if can_breed and not feed_item.is_empty() and not _in_love_mode \
			and _breed_cooldown <= 0.0:
		var held: Dictionary = player.call("_get_held_item")
		if held.get("id", "") == feed_item:
			player.call("_consume_held_item", 1)
			_in_love_mode = true
			_love_timer   = _LOVE_DUR
			return
	# Try taming
	if not can_be_tamed or taming_cooldown > 0.0:
		return
	var held2: Dictionary = player.call("_get_held_item")
	if held2.get("id", "") != taming_item:
		return
	player.call("_consume_held_item", 1)
	taming_cooldown = _TAME_CD

	if randf() < taming_fail_chance:
		taming_progress = maxf(0.0, taming_progress - 0.05)
		_start_flee(player.global_position)
	else:
		taming_progress += taming_increment
		if taming_progress >= 1.0:
			_do_tame(player)
		elif _state == AnimalState.FLEE:
			_set_state(AnimalState.IDLE, 1.5)


func _do_tame(player: Node) -> void:
	_is_tamed       = true
	taming_progress = 1.0
	_owner_node     = player as Node3D
	_set_state(AnimalState.FOLLOW, 9999.0)
	EventBus.mob_tamed.emit(self, player)
	_on_tamed(player)


func _on_tamed(_player: Node) -> void:
	pass


func _on_interact_tamed(_player: Node) -> void:
	if _state == AnimalState.SIT:
		_set_state(AnimalState.FOLLOW, 9999.0)
	else:
		_set_state(AnimalState.SIT, 9999.0)


# ─────────────────────────────────────────────────────────────────────────────
# Breeding
# ─────────────────────────────────────────────────────────────────────────────

func _find_breeding_partner() -> void:
	if not _herd_registry.has(species):
		return
	for animal: BaseAnimal in (_herd_registry[species] as Array):
		if animal == self or not is_instance_valid(animal):
			continue
		if not animal._in_love_mode or animal._breed_cooldown > 0.0:
			continue
		if global_position.distance_to(animal.global_position) > 8.0:
			continue
		_breed_partner        = animal
		animal._breed_partner = self
		_breed_timer          = 3.0
		animal._breed_timer   = 3.0
		_set_state(AnimalState.BREED, 4.0)
		animal._set_state(AnimalState.BREED, 4.0)
		return


func _do_breed() -> void:
	if not is_instance_valid(_breed_partner):
		return
	_in_love_mode            = false
	_breed_cooldown          = _BREED_CD
	_breed_partner._in_love_mode   = false
	_breed_partner._breed_cooldown = _BREED_CD

	var offspring := _spawn_offspring()
	if offspring != null:
		EventBus.mob_bred.emit(self, _breed_partner, offspring)
	_breed_partner = null


## Override in each species to instantiate the right class.
func _spawn_offspring() -> BaseAnimal:
	return null


func _get_offspring_genes(partner: BaseAnimal) -> Dictionary:
	var g := {}
	for key in genes:
		var a: float = genes[key]
		var b: float = partner.genes.get(key, 1.0)
		g[key] = lerp(a, b, randf()) * randf_range(0.95, 1.05)
	return g


# ─────────────────────────────────────────────────────────────────────────────
# Movement helpers
# ─────────────────────────────────────────────────────────────────────────────

func _pick_wander_target() -> void:
	var angle := randf() * TAU
	var dist  := randf_range(3.0, 10.0)
	_wander_target = global_position + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)


func _reached_wander_target() -> bool:
	var h := Vector2(global_position.x - _wander_target.x,
		global_position.z - _wander_target.z)
	return h.length() < 1.0


func _move_toward_target(delta: float, speed: float) -> void:
	var diff := _wander_target - global_position
	diff.y = 0.0
	if diff.length_squared() < 0.25:
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		return
	_move_in_direction(diff.normalized(), speed, delta)


func _move_in_direction(dir: Vector3, speed: float, delta: float) -> void:
	if dir.length_squared() > 0.001:
		var ty := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, ty, 8.0 * delta)

	if _is_ledge_ahead(dir):
		_pick_wander_target()
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
		return

	velocity.x = lerp(velocity.x, dir.x * speed, 10.0 * delta)
	velocity.z = lerp(velocity.z, dir.z * speed, 10.0 * delta)


func _is_ledge_ahead(dir: Vector3) -> bool:
	if not is_on_floor():
		return false
	var space := get_world_3d().direct_space_state
	var check := global_position + dir * 0.65 + Vector3(0, 0.1, 0)
	var query := PhysicsRayQueryParameters3D.create(check, check + Vector3(0, -2.8, 0))
	query.exclude       = [self]
	query.collision_mask = 1
	return space.intersect_ray(query).is_empty()


func _check_step_up() -> void:
	if not is_on_floor():
		return
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if abs(col.get_normal().y) < 0.3:
			velocity.y = 5.5
			return


# ─────────────────────────────────────────────────────────────────────────────
# Taming bar visuals (3D world-space bar above head)
# ─────────────────────────────────────────────────────────────────────────────

func _update_taming_bar() -> void:
	if _tbar_root == null:
		return
	var player := GameManager.local_player as Node3D
	if player == null:
		_tbar_root.visible = false
		return
	var dist := global_position.distance_to(player.global_position)
	var show := (taming_progress > 0.0 or dist < 4.5) and not _is_tamed and can_be_tamed
	_tbar_root.visible = show
	if not show:
		return

	_tbar_root.global_position = global_position + Vector3(0, body_height + 0.5, 0)

	# Bill-board: face the player camera on Y axis
	var cam := player.get_node_or_null("Head/Camera3D") as Camera3D
	if cam != null:
		var look_dir := cam.global_position - _tbar_root.global_position
		look_dir.y = 0.0
		if look_dir.length_squared() > 0.001:
			_tbar_root.look_at(_tbar_root.global_position + look_dir)

	# Scale fill bar on X to match progress (anchor to left edge)
	if _tbar_fill != null:
		var p := maxf(0.001, taming_progress)
		_tbar_fill.scale.x    = p
		_tbar_fill.position.x = (p - 1.0) * 0.33
