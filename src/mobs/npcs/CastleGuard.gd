## CastleGuard.gd — NPC guard that patrols a castle area.
## Neutral by default; becomes hostile if the player gets too close (< 2.5 blocks) or attacks.
class_name CastleGuard
extends BaseHostile

enum GuardState { PATROL, IDLE, HOSTILE }

const PATROL_SPEED  := 2.0
const HOSTILE_SPEED := 5.5
const AGGRO_DIST    := 2.5    # triggers if player enters this distance
const FORGET_DIST   := 30.0

var castle_type: int = 0   # 0=plains 1=desert 2=forest 3=taiga
var _patrol_center: Vector3 = Vector3.ZERO
var _patrol_radius: float   = 8.0
var _patrol_target: Vector3 = Vector3.ZERO
var _patrol_timer: float    = 0.0
var _guard_state: GuardState = GuardState.PATROL

# Override — guards don't auto-aggro at range; handled manually below
var _was_attacked: bool = false


func _mob_ready() -> void:
	max_health     = 24.0
	health         = max_health
	walk_speed     = PATROL_SPEED
	chase_speed    = HOSTILE_SPEED
	attack_damage  = 5.0
	attack_range   = 2.0
	attack_cooldown = 1.2
	aggro_range    = 2.5
	forget_range   = FORGET_DIST
	xp_reward      = 15
	loot_table = [
		{"item": "axiom:bread",      "count_min": 1, "count_max": 2, "chance": 0.60},
		{"item": "axiom:iron_ingot", "count_min": 1, "count_max": 2, "chance": 0.25},
		{"item": "axiom:arrow",      "count_min": 2, "count_max": 6, "chance": 0.40},
	]
	_patrol_center = global_position
	_pick_patrol_target()
	_build_guard_visual()
	_build_collision(0.3, 1.8)


func setup(type: int, center: Vector3, radius: float) -> void:
	castle_type    = type
	_patrol_center = center
	_patrol_radius = radius


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_apply_base_physics(delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_patrol_timer = maxf(0.0, _patrol_timer - delta)
	_run_guard_ai(delta)
	move_and_slide()


func _run_guard_ai(delta: float) -> void:
	var p := GameManager.local_player as Node3D
	match _guard_state:
		GuardState.PATROL:
			_do_patrol(delta)
			if p != null and global_position.distance_to(p.global_position) < aggro_range:
				_go_hostile(p as Player)

		GuardState.IDLE:
			velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
			_patrol_timer -= delta
			if _patrol_timer <= 0.0:
				_pick_patrol_target()
				_guard_state = GuardState.PATROL
			if p != null and global_position.distance_to(p.global_position) < aggro_range:
				_go_hostile(p as Player)

		GuardState.HOSTILE:
			if _player == null or not is_instance_valid(_player):
				_guard_state = GuardState.PATROL
				return
			var dist := global_position.distance_to(_player.global_position)
			if dist > FORGET_DIST and not _was_attacked:
				_player = null
				_guard_state = GuardState.PATROL
				return
			if dist <= attack_range and _attack_cd <= 0.0:
				_do_melee_attack()
			else:
				_move_toward(_player.global_position, HOSTILE_SPEED)


func _do_patrol(delta: float) -> void:
	var diff := _patrol_target - global_position
	diff.y = 0.0
	if diff.length() < 1.0:
		_guard_state  = GuardState.IDLE
		_patrol_timer = randf_range(3.0, 8.0)
		return
	_move_toward(_patrol_target, PATROL_SPEED)


func _pick_patrol_target() -> void:
	var angle := randf() * TAU
	var dist  := randf_range(2.0, _patrol_radius)
	_patrol_target = _patrol_center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)


func _go_hostile(p: Player) -> void:
	_player      = p
	_guard_state = GuardState.HOSTILE


func take_damage(amount: float, source: Node3D = null) -> void:
	_was_attacked = true
	if source is Player:
		_go_hostile(source as Player)
	super(amount, source)


# ── Visuals ────────────────────────────────────────────────────────────────────

const _TUNIC_COLORS: Array[Color] = [
	Color(0.55, 0.55, 0.60),   # 0 plains  — grey tabard
	Color(0.80, 0.65, 0.20),   # 1 desert  — gold tunic
	Color(0.20, 0.50, 0.20),   # 2 forest  — green cloak
	Color(0.40, 0.30, 0.22),   # 3 taiga   — brown fur
]

func _build_guard_visual() -> void:
	_visual_root = Node3D.new()
	add_child(_visual_root)
	body_height = 1.8

	var tunic_col := _TUNIC_COLORS[clampi(castle_type, 0, 3)]
	var skin_col  := Color(0.85, 0.70, 0.55)

	# Body
	var body := MeshInstance3D.new()
	var bm   := BoxMesh.new()
	bm.size  = Vector3(0.6, 0.9, 0.35)
	body.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = tunic_col
	bmat.roughness    = 0.95
	body.material_override = bmat
	body.position.y = 0.45
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_visual_root.add_child(body)

	# Head
	var head := MeshInstance3D.new()
	var hm   := BoxMesh.new()
	hm.size  = Vector3(0.50, 0.50, 0.50)
	head.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = skin_col
	hmat.roughness    = 0.95
	head.material_override = hmat
	head.position.y = 1.15
	_visual_root.add_child(head)

	# Helmet (small box on top of head)
	var helm := MeshInstance3D.new()
	var helmbm := BoxMesh.new()
	helmbm.size = Vector3(0.54, 0.22, 0.54)
	helm.mesh   = helmbm
	var helmmat := StandardMaterial3D.new()
	helmmat.albedo_color = Color(0.45, 0.45, 0.48)
	helmmat.roughness    = 0.6
	helm.material_override = helmmat
	helm.position.y = 1.50
	_visual_root.add_child(helm)

	# Name label
	var lbl          := Label3D.new()
	lbl.text         = _guard_name()
	lbl.font_size    = 24
	lbl.modulate     = Color(0.9, 0.9, 1.0)
	lbl.billboard    = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position     = Vector3(0.0, 2.1, 0.0)
	add_child(lbl)


func _guard_name() -> String:
	match castle_type:
		0: return "Garde des Plaines"
		1: return "Garde du Désert"
		2: return "Éclaireur Forestier"
		3: return "Mercenaire Nordique"
		_: return "Garde"
