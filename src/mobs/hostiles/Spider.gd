## Spider.gd — Fast, low, leaps at its prey. Neutral in daylight, hostile at night.
class_name Spider
extends BaseHostile

const LEAP_RANGE := 4.5
const LEAP_CD    := 2.4

var _leap_cd: float = 0.0
var _provoked: bool = false


func _mob_ready() -> void:
	species        = "spider"
	max_health     = 16.0
	walk_speed     = 3.0
	chase_speed    = 5.2
	aggro_range    = 14.0
	attack_range   = 1.7
	attack_damage  = 2.5
	attack_cooldown = 1.2
	forget_range   = 24.0
	xp_reward      = 6
	loot_table     = [
		{"item": "axiom:string",     "count_min": 0, "count_max": 2, "chance": 1.0},
		{"item": "axiom:spider_eye", "count_min": 0, "count_max": 1, "chance": 0.35},
	]
	_build_collision(0.55, 0.80)
	_build_spider_visual()


func _build_spider_visual() -> void:
	_visual_root = Node3D.new()
	add_child(_visual_root)
	body_height = 0.65

	var body_col := Color(0.16, 0.13, 0.13)
	var body := _make_box(Vector3(0.85, 0.42, 1.00), body_col)
	body.position.y = 0.42
	_visual_root.add_child(body)

	var head := Node3D.new()
	head.position = Vector3(0, 0.44, -0.62)
	head.add_child(_make_box(Vector3(0.52, 0.36, 0.40), Color(0.20, 0.16, 0.15)))
	# Red eyes
	for sx in [-1, 1]:
		var eye := _make_box(Vector3(0.07, 0.07, 0.03), Color(0.95, 0.15, 0.12))
		eye.position = Vector3(sx * 0.12, 0.05, -0.21)
		var mat := eye.material_override as StandardMaterial3D
		mat.emission_enabled = true
		mat.emission = Color(0.9, 0.1, 0.1) * 0.7
		head.add_child(eye)
	_visual_root.add_child(head)
	_anim_head = head

	# 8 legs: 4 per side, angled out
	for side in [-1, 1]:
		for i in 4:
			var leg := _make_limb(Vector3(0.07, 0.55, 0.07), Color(0.13, 0.10, 0.10),
				Vector3(side * 0.45, 0.52, -0.35 + i * 0.24))
			leg.rotation_degrees.z = side * 42.0
			_visual_root.add_child(leg)
			_anim_legs.append(leg)


func take_damage(amount: float, source: Node3D = null) -> void:
	super.take_damage(amount, source)
	_provoked = true   # attacking a spider always makes it hostile


func _check_aggro() -> void:
	# Neutral during the day unless provoked
	if TimeManager.is_day() and not _provoked:
		return
	super._check_aggro()


func _run_ai(delta: float) -> void:
	_leap_cd = maxf(0.0, _leap_cd - delta)
	super._run_ai(delta)
	# Pounce when mid-range and grounded
	if _state == State.CHASE and _player != null and is_instance_valid(_player) \
			and _leap_cd <= 0.0 and is_on_floor():
		var dist := global_position.distance_to(_player.global_position)
		if dist > 2.0 and dist < LEAP_RANGE:
			var dir := (_player.global_position - global_position).normalized()
			velocity = dir * 7.5
			velocity.y = 6.5
			_leap_cd = LEAP_CD
