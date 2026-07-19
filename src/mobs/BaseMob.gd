## BaseMob.gd — Base CharacterBody3D for all living entities in Axiom.
class_name BaseMob
extends CharacterBody3D

const GRAVITY := 28.0

@export var max_health: float = 10.0
var health: float = 0.0
var species: String = ""
var loot_table: Array = []  # [{item, count_min, count_max, chance}]

var xp_reward: int = 5   # override in hostile subclasses
var damage_reduction: float = 0.0   # 0.0–1.0 fraction of incoming damage absorbed
var _dead: bool = false
var _knockback_vel: Vector3 = Vector3.ZERO
var _invincible_timer: float = 0.0
var _stun_timer: float = 0.0
var is_elite: bool = false

signal mob_died(mob: BaseMob)


func _ready() -> void:
	health = max_health
	_mob_ready()
	# Emit after _mob_ready so species (and other subclass fields) are set.
	EventBus.mob_spawned.emit(self, global_position)


func _mob_ready() -> void:
	pass  # override in subclasses


func stun(duration: float) -> void:
	_stun_timer = maxf(_stun_timer, duration)


func take_damage(amount: float, source: Node3D = null) -> void:
	if _dead or _invincible_timer > 0.0:
		return
	# Apply damage reduction (set by mace armor_pierce on the caller side)
	var effective := amount * (1.0 - damage_reduction)
	health = maxf(0.0, health - effective)
	amount = effective
	_invincible_timer = 0.5
	_flash_damage()
	EventBus.mob_damaged.emit(self, amount, source)
	if source:
		var dir := (global_position - source.global_position)
		dir.y = 0.0
		if dir.length_squared() > 0.0001:
			dir = dir.normalized()
		_knockback_vel = dir * 4.5 + Vector3.UP * 5.5
	if health <= 0.0:
		_die(source)


func _die(killer: Node3D = null) -> void:
	if _dead:
		return
	_dead = true
	_drop_loot()
	EventBus.mob_died.emit(self, killer)
	mob_died.emit(self)
	queue_free()


func _drop_loot() -> void:
	if not is_inside_tree():
		return
	var parent := get_parent()
	if parent == null:
		return
	for entry in loot_table:
		if randf() > entry.get("chance", 1.0):
			continue
		var cnt: int = randi_range(
			entry.get("count_min", 1),
			entry.get("count_max", entry.get("count_min", 1))
		)
		if cnt <= 0:
			continue
		var drop := DroppedItem.new()
		parent.add_child(drop)
		var offset := Vector3(randf_range(-0.3, 0.3), 0.5, randf_range(-0.3, 0.3))
		drop.setup(entry["item"], cnt, global_position + offset)


## Call after the mob is added to the scene tree (visuals already built).
## Applies elite stat multipliers and red mesh tint.
func make_elite() -> void:
	is_elite     = true
	max_health   = ceili(max_health * 1.5)
	health       = max_health
	_tint_elite_meshes(self)
	for entry in loot_table:
		entry["count_max"] = entry.get("count_max", entry.get("count_min", 1)) + 1
		entry["chance"]    = minf(entry.get("chance", 1.0) * 1.5, 1.0)


func _tint_elite_meshes(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mat := (child as MeshInstance3D).material_override
			if mat is StandardMaterial3D:
				var m: StandardMaterial3D = mat.duplicate()
				m.albedo_color = m.albedo_color.lerp(Color(0.85, 0.05, 0.05), 0.45)
				(child as MeshInstance3D).material_override = m
		_tint_elite_meshes(child)


func get_hp_ratio() -> float:
	if max_health <= 0.0:
		return 1.0
	return health / max_health


# ── Hit flash (brief red tint on every mesh when damaged) ─────────────────────

var _flash_restore: Array = []      # [[mesh, original material], ...]
var _flash_active: bool = false


func _flash_damage() -> void:
	if _flash_active or not is_inside_tree():
		return
	_flash_active = true
	_flash_restore.clear()
	_collect_flash(self)
	get_tree().create_timer(0.13).timeout.connect(_end_flash)


func _collect_flash(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.material_override is StandardMaterial3D:
				var original: StandardMaterial3D = mi.material_override
				_flash_restore.append([mi, original])
				var m: StandardMaterial3D = original.duplicate()
				m.albedo_color = m.albedo_color.lerp(Color(1.0, 0.12, 0.12), 0.72)
				mi.material_override = m
		_collect_flash(child)


func _end_flash() -> void:
	_flash_active = false
	for entry in _flash_restore:
		var mi: MeshInstance3D = entry[0]
		if is_instance_valid(mi):
			mi.material_override = entry[1]
	_flash_restore.clear()


# ── Shared blocky body builder + walk animation ────────────────────────────────

var _anim_legs: Array = []    # Node3D pivots (rotate at hip)
var _anim_arms: Array = []
var _anim_head: Node3D = null
var _walk_t: float = 0.0
var _arms_forward: bool = false

func _make_box(size: Vector3, col: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box  := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness    = 0.95
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


## A limb that swings from its top (hip/shoulder pivot).
func _make_limb(size: Vector3, col: Color, hip_pos: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = hip_pos
	var mesh := _make_box(size, col)
	mesh.position = Vector3(0, -size.y * 0.5, 0)
	pivot.add_child(mesh)
	return pivot


## Quadruped: body + head + 4 legs (+ species extras via cfg).
## cfg: body_size, body_col, head_size, head_col, leg_h, leg_col,
##      snout_col?, ears?, antlers?, tail?, wool? (sheep look)
func build_quadruped(root: Node3D, cfg: Dictionary) -> void:
	var body_size: Vector3 = cfg.get("body_size", Vector3(0.8, 0.7, 1.2))
	var head_size: Vector3 = cfg.get("head_size", Vector3(0.5, 0.5, 0.5))
	var body_col: Color = cfg.get("body_col", Color(0.7, 0.7, 0.7))
	var head_col: Color = cfg.get("head_col", body_col)
	var leg_h: float = cfg.get("leg_h", 0.38)
	var leg_col: Color = cfg.get("leg_col", body_col.darkened(0.25))

	var body_y := leg_h + body_size.y * 0.5
	var body := _make_box(body_size, body_col)
	body.position.y = body_y
	root.add_child(body)

	var head := Node3D.new()
	head.position = Vector3(0, body_y + body_size.y * 0.30,
		-body_size.z * 0.5 - head_size.z * 0.35)
	var head_mesh := _make_box(head_size, head_col)
	head.add_child(head_mesh)
	root.add_child(head)
	_anim_head = head

	# Snout (pig, cow, wolf...)
	if cfg.has("snout_col"):
		var snout := _make_box(Vector3(head_size.x * 0.45, head_size.y * 0.35, 0.12), cfg["snout_col"])
		snout.position = Vector3(0, -head_size.y * 0.12, -head_size.z * 0.55)
		head.add_child(snout)

	# Ears (rabbit: tall; wolf: small triangles)
	if cfg.get("ears", "") == "tall":
		for sx in [-1, 1]:
			var ear := _make_box(Vector3(0.08, 0.30, 0.05), head_col.darkened(0.1))
			ear.position = Vector3(sx * head_size.x * 0.25, head_size.y * 0.62, 0.02)
			head.add_child(ear)
	elif cfg.get("ears", "") == "small":
		for sx in [-1, 1]:
			var ear := _make_box(Vector3(0.10, 0.12, 0.06), head_col.darkened(0.2))
			ear.position = Vector3(sx * head_size.x * 0.32, head_size.y * 0.55, 0.05)
			head.add_child(ear)

	# Antlers (deer)
	if cfg.get("antlers", false):
		for sx in [-1, 1]:
			var a1 := _make_box(Vector3(0.06, 0.34, 0.06), Color(0.62, 0.51, 0.38))
			a1.position = Vector3(sx * head_size.x * 0.3, head_size.y * 0.72, 0.0)
			head.add_child(a1)
			var a2 := _make_box(Vector3(0.20, 0.06, 0.06), Color(0.62, 0.51, 0.38))
			a2.position = Vector3(sx * head_size.x * 0.3 + sx * 0.07, head_size.y * 0.86, 0.0)
			head.add_child(a2)

	# Tail (wolf, coyote, deer)
	if cfg.get("tail", false):
		var tail := _make_box(Vector3(0.14, 0.14, 0.42), body_col.darkened(0.12))
		tail.position = Vector3(0, body_y + body_size.y * 0.22, body_size.z * 0.5 + 0.18)
		tail.rotation_degrees.x = -22
		root.add_child(tail)

	# Wool cap (sheep)
	if cfg.get("wool", false):
		var wool := _make_box(Vector3(head_size.x * 1.06, head_size.y * 0.5, head_size.z * 0.7), body_col)
		wool.position = Vector3(0, head_size.y * 0.5, 0.08)
		head.add_child(wool)

	# 4 legs at the body corners
	var lw := body_size.x * 0.28
	var ld := minf(body_size.z * 0.20, 0.24)
	for iz in [-1, 1]:
		for ix in [-1, 1]:
			var leg := _make_limb(Vector3(lw, leg_h + 0.05, ld), leg_col,
				Vector3(ix * (body_size.x * 0.5 - lw * 0.5),
					leg_h + 0.02,
					iz * (body_size.z * 0.5 - ld * 0.8)))
			root.add_child(leg)
			_anim_legs.append(leg)


## Biped: torso + head + 2 arms + 2 legs (zombies, skeletons...).
## cfg: body_size, body_col, head_size, head_col, leg_col?, arm_col?, arms_forward?
func build_biped(root: Node3D, cfg: Dictionary) -> void:
	var body_size: Vector3 = cfg.get("body_size", Vector3(0.55, 0.75, 0.30))
	var head_size: Vector3 = cfg.get("head_size", Vector3(0.5, 0.5, 0.5))
	var body_col: Color = cfg.get("body_col", Color(0.5, 0.5, 0.5))
	var head_col: Color = cfg.get("head_col", body_col)
	var leg_col: Color = cfg.get("leg_col", body_col.darkened(0.3))
	var arm_col: Color = cfg.get("arm_col", body_col)
	var leg_h := 0.72
	var arms_forward: bool = cfg.get("arms_forward", false)

	var body_y := leg_h + body_size.y * 0.5
	var body := _make_box(body_size, body_col)
	body.position.y = body_y
	root.add_child(body)

	var head := Node3D.new()
	head.position = Vector3(0, leg_h + body_size.y + head_size.y * 0.5, 0)
	head.add_child(_make_box(head_size, head_col))
	root.add_child(head)
	_anim_head = head

	_arms_forward = arms_forward
	var arm_size := Vector3(0.16, body_size.y * 0.92, 0.16)
	for sx in [-1, 1]:
		var arm := _make_limb(arm_size, arm_col,
			Vector3(sx * (body_size.x * 0.5 + arm_size.x * 0.5),
				leg_h + body_size.y - 0.06, 0))
		if arms_forward:
			arm.rotation_degrees.x = -85
		root.add_child(arm)
		_anim_arms.append(arm)

	var leg_size := Vector3(0.20, leg_h, 0.20)
	for sx in [-1, 1]:
		var leg := _make_limb(leg_size, leg_col,
			Vector3(sx * body_size.x * 0.24, leg_h, 0))
		root.add_child(leg)
		_anim_legs.append(leg)


## Call every physics frame — swings limbs while moving, bobs the head.
func animate_walk(delta: float) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if hspeed > 0.15:
		_walk_t += delta * clampf(hspeed * 2.6, 2.0, 9.0)
	else:
		_walk_t = lerpf(_walk_t, roundf(_walk_t / PI) * PI, 12.0 * delta)
	var swing := sin(_walk_t) * clampf(hspeed * 0.35, 0.0, 0.75)
	for i in _anim_legs.size():
		var leg := _anim_legs[i] as Node3D
		if leg != null:
			leg.rotation.x = swing if (i % 2 == 0) else -swing
	if not _arms_forward:
		for i in _anim_arms.size():
			var arm := _anim_arms[i] as Node3D
			if arm != null:
				arm.rotation.x = -swing if (i % 2 == 0) else swing
	if _anim_head != null and hspeed > 0.15:
		_anim_head.position.y += sin(_walk_t * 2.0) * 0.004


func _apply_base_physics(delta: float) -> void:
	_invincible_timer = maxf(0.0, _invincible_timer - delta)
	_stun_timer       = maxf(0.0, _stun_timer       - delta)
	if _stun_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		if not is_on_floor():
			velocity.y -= 28.0 * delta
		return
	if _knockback_vel.length_squared() > 0.01:
		velocity = _knockback_vel
		_knockback_vel = Vector3.ZERO
	elif not is_on_floor():
		velocity.y -= GRAVITY * delta
		velocity.y = maxf(velocity.y, -25.0)
	elif velocity.y < 0.0:
		velocity.y = 0.0
