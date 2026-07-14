## BaseHostile.gd — Base CharacterBody3D for all hostile mobs.
## Detects the player → chases → attacks melee. Loses aggro when out of range.
class_name BaseHostile
extends BaseMob

enum State { IDLE, CHASE, ATTACK }

var _state: State        = State.IDLE
var _ai_timer: float     = 0.0
var _attack_cd: float    = 0.0
var _wander_timer: float = 0.0
var _wander_target: Vector3 = Vector3.ZERO
var _player: Player      = null

# Tunable per subclass
var walk_speed: float     = 2.0
var chase_speed: float    = 4.5
var aggro_range: float    = 16.0
var attack_range: float   = 2.0
var attack_damage: float  = 3.0
var attack_cooldown: float = 1.5
var forget_range: float   = 28.0

var _visual_root: Node3D = null
var body_height: float   = 0.9


func _mob_ready() -> void:
	pass  # subclasses configure stats here


## Set true on species that burn under the open sun (zombies, skeletons).
var burns_in_daylight: bool = false
var _burn_timer: float = 0.0

func _physics_process(delta: float) -> void:
	if _dead:
		return
	_apply_base_physics(delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_ai_timer  = maxf(0.0, _ai_timer  - delta)
	_run_ai(delta)
	move_and_slide()
	animate_walk(delta)
	if burns_in_daylight:
		_tick_daylight_burn(delta)


func _tick_daylight_burn(delta: float) -> void:
	if not TimeManager.is_day():
		return
	_burn_timer += delta
	if _burn_timer < 1.2:
		return
	_burn_timer = 0.0
	# Only burn under the open sky
	var world := GameManager.world_node
	if world == null:
		return
	var cm = world.get("chunk_manager")
	if cm == null:
		return
	var head := Vector3i(floori(global_position.x),
		floori(global_position.y + body_height), floori(global_position.z))
	var cp := Chunk.world_to_chunk(head)
	var chunk = cm.get_chunk(cp)
	if chunk == null:
		return
	var local := Chunk.world_to_local(head, cp.y)
	if chunk.get_sky_light(local.x, local.y, local.z) >= 13:
		take_damage(2.0, null)


func _run_ai(delta: float) -> void:
	match _state:
		State.IDLE:
			_do_wander(delta)
			if _ai_timer <= 0.0:
				_ai_timer = 0.3
				_check_aggro()

		State.CHASE:
			if _player == null or not is_instance_valid(_player):
				_state = State.IDLE
				return
			var dist := global_position.distance_to(_player.global_position)
			if dist > forget_range:
				_player = null
				_state  = State.IDLE
				return
			if dist <= attack_range and _attack_cd <= 0.0:
				_do_melee_attack()
			else:
				_move_toward(_player.global_position, chase_speed)

		State.ATTACK:
			_state = State.CHASE  # flows directly back into CHASE


func _check_aggro() -> void:
	var p := GameManager.local_player as Player
	if p == null:
		return
	if global_position.distance_to(p.global_position) <= aggro_range:
		_player = p
		_state  = State.CHASE


func _do_wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(3.0, 7.0)
		var angle := randf() * TAU
		_wander_target = global_position + Vector3(cos(angle) * 5.0, 0.0, sin(angle) * 5.0)
	var dir := (_wander_target - global_position)
	dir.y = 0.0
	if dir.length_squared() > 1.0:
		dir = dir.normalized()
		velocity.x = lerpf(velocity.x, dir.x * walk_speed * 0.45, 0.08)
		velocity.z = lerpf(velocity.z, dir.z * walk_speed * 0.45, 0.08)
	else:
		velocity.x = lerpf(velocity.x, 0.0, 0.15)
		velocity.z = lerpf(velocity.z, 0.0, 0.15)


func _do_melee_attack() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_player.take_damage(attack_damage, "mob")
	_attack_cd = attack_cooldown
	# Brief pause after swinging
	velocity.x = lerpf(velocity.x, 0.0, 0.5)
	velocity.z = lerpf(velocity.z, 0.0, 0.5)


func _move_toward(target: Vector3, speed: float) -> void:
	var dir := target - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		return
	dir = dir.normalized()
	velocity.x = lerpf(velocity.x, dir.x * speed, 0.2)
	velocity.z = lerpf(velocity.z, dir.z * speed, 0.2)
	rotation.y = atan2(dir.x, dir.z)
	if is_on_wall() and is_on_floor():
		velocity.y = 7.0  # step up / jump over obstacle


# ── Helpers for subclasses ─────────────────────────────────────────────────────

func _build_collision(radius: float, height: float) -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = height
	col.shape  = cap
	col.position.y = height * 0.5
	add_child(col)
	collision_layer = 4  # layer 3 — mobs (player attack ray uses mask 4)
	collision_mask  = 1  # layer 1 — terrain


func _build_visual(body_size: Vector3, head_size: Vector3,
		body_col: Color, head_col: Color) -> void:
	_visual_root = Node3D.new()
	add_child(_visual_root)
	body_height = 0.72 + body_size.y   # legs + torso

	build_biped(_visual_root, {
		"body_size": body_size,
		"head_size": head_size,
		"body_col": body_col,
		"head_col": head_col,
		"arms_forward": species == "zombie",
	})
