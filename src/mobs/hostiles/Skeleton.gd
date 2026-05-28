class_name Skeleton
extends BaseHostile

const SHOOT_RANGE   := 14.0
const SHOOT_EVERY   := 2.2   # seconds between shots
const FLEE_RANGE    := 3.5   # keeps distance from player

var _shoot_timer: float = 1.0  # initial delay before first shot


func _mob_ready() -> void:
	species        = "skeleton"
	max_health     = 20.0
	walk_speed     = 2.5
	chase_speed    = 3.2
	aggro_range    = 18.0
	attack_range   = SHOOT_RANGE  # "melee" range overridden — handled below
	attack_damage  = 2.5
	attack_cooldown = SHOOT_EVERY
	forget_range   = 30.0
	loot_table     = [
		{"item": "axiom:bone",           "count_min": 0, "count_max": 2, "chance": 1.0},
		{"item": "axiom:arrow",          "count_min": 0, "count_max": 2, "chance": 0.5},
		{"item": "axiom:corrupted_fang", "count_min": 1, "count_max": 1, "chance": 0.15},
	]
	_build_collision(0.28, 1.80)
	_build_visual(
		Vector3(0.48, 0.72, 0.24),  # thin bone body
		Vector3(0.50, 0.50, 0.50),
		Color(0.88, 0.88, 0.80),    # white-bone body
		Color(0.92, 0.92, 0.84)
	)


func _run_ai(delta: float) -> void:
	_shoot_timer = maxf(0.0, _shoot_timer - delta)
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

			# Keep a medium distance — back away if player is too close
			if dist < FLEE_RANGE:
				var away := (global_position - _player.global_position)
				away.y = 0.0
				away = away.normalized()
				velocity.x = lerpf(velocity.x, away.x * chase_speed, 0.2)
				velocity.z = lerpf(velocity.z, away.z * chase_speed, 0.2)
			elif dist > SHOOT_RANGE:
				_move_toward(_player.global_position, chase_speed)
			else:
				# In range — slow down and face target
				velocity.x = lerpf(velocity.x, 0.0, 0.15)
				velocity.z = lerpf(velocity.z, 0.0, 0.15)
				var look_dir := (_player.global_position - global_position)
				look_dir.y = 0.0
				if look_dir.length_squared() > 0.001:
					rotation.y = atan2(look_dir.x, look_dir.z)

			# Shoot when in range and timer ready
			if dist <= SHOOT_RANGE and _shoot_timer <= 0.0:
				_shoot_arrow()

		State.ATTACK:
			_state = State.CHASE


func _shoot_arrow() -> void:
	if _player == null:
		return
	_shoot_timer = SHOOT_EVERY
	var arrow := Arrow.new()
	get_parent().add_child(arrow)
	var origin := global_position + Vector3(0, body_height + 0.3, 0)
	# Aim slightly above player center to account for arc drop
	var target := _player.global_position + Vector3(0, 1.2, 0)
	var dir := (target - origin).normalized()
	arrow.setup(origin, dir, attack_damage)
