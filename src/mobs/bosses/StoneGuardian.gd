## StoneGuardian.gd — Le Gardien de Pierre, boss de l'Overworld.
## Phase 1 : tank lent, frappe de sol (knockback).
## Phase 2 (≤40% PV) : enragé, +50% dégâts, projette des blocs de pierre.
class_name StoneGuardian
extends BaseBoss

const SLAM_CD       := 5.0
const SLAM_RANGE    := 4.5
const ROCK_CD       := 4.0
const ROCK_SPEED    := 14.0

var _slam_cd: float  = 3.0
var _rock_cd: float  = ROCK_CD
var _enraged: bool   = false
var _body_mat: StandardMaterial3D = null


func _mob_ready() -> void:
	boss_name      = "Le Gardien de Pierre"
	max_health     = 420.0
	health         = max_health
	walk_speed     = 1.8
	chase_speed    = 3.5
	attack_damage  = 12.0
	attack_range   = 2.8
	attack_cooldown = 2.0
	aggro_range    = 18.0
	forget_range   = 35.0
	xp_reward      = 250
	loot_table = [
		{"item": "axiom:guardian_core",     "count_min": 1, "count_max": 1, "chance": 1.00},
		{"item": "axiom:soul_fragment_ii",  "count_min": 1, "count_max": 1, "chance": 1.00},
		{"item": "axiom:iron_ingot",        "count_min": 4, "count_max": 8, "chance": 1.00},
		{"item": "axiom:emerald",           "count_min": 1, "count_max": 3, "chance": 0.60},
	]
	_build_guardian_visual()
	_build_collision(0.7, 2.4)


func _get_phase_thresholds() -> Dictionary:
	return { 2: 0.40 }


func _on_phase_changed(phase: int) -> void:
	if phase == 2:
		_enraged     = true
		attack_damage *= 1.5
		chase_speed   = 5.5
		# Crack effect: tint body orange-red
		if _body_mat:
			_body_mat.albedo_color = Color(0.55, 0.22, 0.08)
			_body_mat.emission_enabled = true
			_body_mat.emission = Color(0.6, 0.15, 0.0)
			_body_mat.emission_energy_multiplier = 0.8
		EventBus.show_message.emit("Le Gardien de Pierre entre en rage !", 4.0)


func _boss_tick(delta: float) -> void:
	_slam_cd = maxf(0.0, _slam_cd - delta)
	_rock_cd = maxf(0.0, _rock_cd - delta)

	if _player == null or not is_instance_valid(_player):
		return

	var dist := global_position.distance_to(_player.global_position)

	# Ground slam when close
	if _slam_cd <= 0.0 and dist <= SLAM_RANGE:
		_do_ground_slam()
		_slam_cd = SLAM_CD

	# Phase 2: throw rocks at range
	if _enraged and _rock_cd <= 0.0 and dist > 3.0 and dist < 20.0:
		_throw_rock()
		_rock_cd = ROCK_CD


func _do_ground_slam() -> void:
	if _player == null:
		return
	var dist := global_position.distance_to(_player.global_position)
	if dist <= SLAM_RANGE:
		_player.call("take_damage", attack_damage * 1.5, "slam")
		# Knockback player away
		var dir := (_player.global_position - global_position).normalized()
		dir.y = 0.5
		(_player as CharacterBody3D).velocity = dir * 16.0
	EventBus.show_message.emit("Frappe de sol !", 1.5)


func _throw_rock() -> void:
	if _player == null:
		return
	var rock := _StoneRock.new()
	rock.damage = 8.0
	get_parent().add_child(rock)
	rock.global_position = global_position + Vector3(0, 1.8, 0)
	var target := _player.global_position + Vector3(0, 1, 0)
	rock.velocity_vec = (target - rock.global_position).normalized() * ROCK_SPEED


func _build_guardian_visual() -> void:
	_visual_root = Node3D.new()
	add_child(_visual_root)
	body_height = 2.2

	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color(0.42, 0.38, 0.34)
	_body_mat.roughness    = 1.0

	# Wide stone body
	var body := MeshInstance3D.new()
	var bm   := BoxMesh.new()
	bm.size  = Vector3(1.2, 1.4, 0.8)
	body.mesh = bm
	body.material_override = _body_mat
	body.position.y = 0.7
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_visual_root.add_child(body)

	# Head
	var head := MeshInstance3D.new()
	var hm   := BoxMesh.new()
	hm.size  = Vector3(0.85, 0.85, 0.85)
	head.mesh = hm
	head.material_override = _body_mat.duplicate()
	head.position.y = 1.85
	_visual_root.add_child(head)

	# Glowing eyes (phase 2 tinted via _body_mat)
	for ex in [-0.18, 0.18]:
		var eye := MeshInstance3D.new()
		var em  := BoxMesh.new()
		em.size = Vector3(0.12, 0.12, 0.12)
		eye.mesh = em
		var emat := StandardMaterial3D.new()
		emat.albedo_color = Color(1.0, 0.6, 0.0)
		emat.emission_enabled = true
		emat.emission = Color(1.0, 0.5, 0.0)
		emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		eye.material_override = emat
		eye.position = Vector3(ex, 1.92, -0.45)
		_visual_root.add_child(eye)


# ── Stone projectile ───────────────────────────────────────────────────────────

class _StoneRock extends Node3D:
	var damage: float       = 8.0
	var velocity_vec: Vector3 = Vector3.ZERO
	var _lifetime: float    = 5.0
	const GRAVITY := 14.0

	func _ready() -> void:
		var mesh := MeshInstance3D.new()
		var bm   := BoxMesh.new()
		bm.size  = Vector3(0.35, 0.35, 0.35)
		mesh.mesh = bm
		var mat  := StandardMaterial3D.new()
		mat.albedo_color = Color(0.42, 0.38, 0.34)
		mat.roughness    = 1.0
		mesh.material_override = mat
		add_child(mesh)

	func _physics_process(delta: float) -> void:
		_lifetime -= delta
		if _lifetime <= 0.0:
			queue_free()
			return
		velocity_vec.y -= GRAVITY * delta
		global_position += velocity_vec * delta
		rotation += Vector3(delta * 3.0, delta * 2.0, delta * 1.5)
		var player := GameManager.local_player as Node3D
		if player != null and global_position.distance_to(player.global_position) < 0.9:
			player.call("take_damage", damage, "rock")
			queue_free()
		# Despawn on ground contact (rough check: y below terrain would need ChunkManager)
		if global_position.y < -20.0:
			queue_free()
