## EchoEntity.gd — L'Écho, boss du Nether lié aux Architectes.
## Phase 1 : forme sombre visible, mêlée + projectiles.
## Phase 2 (≤50% PV) : semi-transparent, vitesse +40%, invoque des fragments d'écho.
class_name EchoEntity
extends BaseBoss

const PROJECTILE_CD   := 3.0
const SUMMON_CD       := 12.0
const SUMMON_COUNT    := 3
const PROJ_SPEED      := 18.0
const PROJ_DAMAGE     := 4.0
const PROJ_SLOW_DUR   := 3.0

var _proj_cd: float   = 2.0
var _summon_cd: float = SUMMON_CD
var _body_mat: StandardMaterial3D = null
var _fragments: Array[Node] = []


func _mob_ready() -> void:
	boss_name      = "L'Écho"
	max_health     = 280.0
	health         = max_health
	walk_speed     = 3.0
	chase_speed    = 6.5
	attack_damage  = 7.0
	attack_range   = 2.2
	attack_cooldown = 1.2
	aggro_range    = 20.0
	forget_range   = 40.0
	xp_reward      = 200
	loot_table = [
		{"item": "axiom:echo_fragment",    "count_min": 1, "count_max": 2, "chance": 1.00},
		{"item": "axiom:soul_fragment_i",  "count_min": 1, "count_max": 1, "chance": 1.00},
		{"item": "axiom:nether_star",      "count_min": 0, "count_max": 1, "chance": 0.15},
	]
	_build_echo_visual()
	_build_collision(0.55, 2.0)


func _get_phase_thresholds() -> Dictionary:
	return { 2: 0.50 }


func _on_phase_changed(phase: int) -> void:
	if phase == 2:
		chase_speed    = 9.0
		attack_damage  = 10.0
		# Turn semi-transparent
		if _body_mat:
			_body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_body_mat.albedo_color.a = 0.45
		EventBus.show_message.emit("L'Écho entre dans sa seconde forme !", 4.0)


func _boss_tick(delta: float) -> void:
	_proj_cd   = maxf(0.0, _proj_cd   - delta)
	_summon_cd = maxf(0.0, _summon_cd - delta)

	if _player == null or not is_instance_valid(_player):
		return

	var dist := global_position.distance_to(_player.global_position)

	# Projectile attack when 4–18 blocks away
	if _proj_cd <= 0.0 and dist > 3.5 and dist < 18.0:
		_shoot_shadow_bolt()
		_proj_cd = PROJECTILE_CD

	# Phase 2: summon echo fragments
	if _current_phase >= 2 and _summon_cd <= 0.0:
		_summon_fragments()
		_summon_cd = SUMMON_CD


func _shoot_shadow_bolt() -> void:
	if _player == null:
		return
	var bolt := _EchoBolt.new()
	bolt.damage   = PROJ_DAMAGE
	bolt.slow_dur = PROJ_SLOW_DUR
	get_parent().add_child(bolt)
	bolt.global_position = global_position + Vector3(0, 1.2, 0)
	var dir := (_player.global_position + Vector3(0, 1, 0) - bolt.global_position).normalized()
	bolt.velocity_vec = dir * PROJ_SPEED


func _summon_fragments() -> void:
	# Remove dead fragments first
	_fragments = _fragments.filter(func(f): return is_instance_valid(f))
	var to_spawn := SUMMON_COUNT - _fragments.size()
	for i in to_spawn:
		var frag := _EchoFragment.new()
		get_parent().add_child(frag)
		var angle := randf() * TAU
		frag.global_position = global_position + Vector3(cos(angle) * 4.0, 0, sin(angle) * 4.0)
		_fragments.append(frag)


func _build_echo_visual() -> void:
	_visual_root = Node3D.new()
	add_child(_visual_root)
	body_height = 1.8

	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color(0.05, 0.0, 0.12)
	_body_mat.emission_enabled = true
	_body_mat.emission = Color(0.3, 0.0, 0.6)
	_body_mat.emission_energy_multiplier = 1.2
	_body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var body := MeshInstance3D.new()
	var bm   := BoxMesh.new()
	bm.size  = Vector3(0.8, 1.2, 0.4)
	body.mesh = bm
	body.material_override = _body_mat
	body.position.y = 0.6
	_visual_root.add_child(body)

	var head := MeshInstance3D.new()
	var hm   := BoxMesh.new()
	hm.size  = Vector3(0.65, 0.65, 0.65)
	head.mesh = hm
	var hmat := _body_mat.duplicate() as StandardMaterial3D
	hmat.emission_energy_multiplier = 2.0
	head.material_override = hmat
	head.position.y = 1.55
	_visual_root.add_child(head)


# ── Inner classes ──────────────────────────────────────────────────────────────

class _EchoBolt extends Node3D:
	var damage: float    = 4.0
	var slow_dur: float  = 3.0
	var velocity_vec: Vector3 = Vector3.ZERO
	var _lifetime: float = 4.0
	var _mesh: MeshInstance3D

	func _ready() -> void:
		_mesh = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.18
		sm.height = 0.36
		_mesh.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.0, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.5, 0.0, 1.0)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mesh.material_override = mat
		add_child(_mesh)

	func _physics_process(delta: float) -> void:
		_lifetime -= delta
		if _lifetime <= 0.0:
			queue_free()
			return
		global_position += velocity_vec * delta
		# Simple player hit check
		var player := GameManager.local_player as Node3D
		if player != null:
			if global_position.distance_to(player.global_position) < 0.8:
				player.call("take_damage", damage, "echo_bolt")
				queue_free()


class _EchoFragment extends BaseHostile:
	func _mob_ready() -> void:
		max_health     = 30.0
		health         = max_health
		walk_speed     = 2.5
		chase_speed    = 7.0
		attack_damage  = 3.0
		attack_range   = 1.8
		attack_cooldown = 1.0
		aggro_range    = 24.0
		xp_reward      = 10
		loot_table     = []
		_build_visual(
			Vector3(0.45, 0.9, 0.25),
			Vector3(0.4, 0.4, 0.4),
			Color(0.15, 0.0, 0.3),
			Color(0.25, 0.0, 0.5)
		)
		_build_collision(0.3, 1.1)
