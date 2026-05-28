class_name Wolf
extends BaseAnimal

var _hunt_target: BaseAnimal = null
var _hunt_timer:  float = 0.0
var _attack_cd:   float = 0.0
var _aggro_player: Player = null
var _aggro_timer:  float  = 0.0
const HUNT_RANGE := 16.0

func _mob_ready() -> void:
	species           = "wolf"
	walk_speed        = 3.2
	flee_speed        = 6.0
	detection_range   = 6.0   # wolves don't flee from player by default
	max_health        = 20.0
	can_be_tamed      = true
	taming_item       = "axiom:bone"
	taming_increment  = 0.15
	taming_fail_chance = 0.25
	loot_table = [
		{"item": "axiom:predator_claw", "count_min": 1, "count_max": 2, "chance": 0.25},
	]
	_build_collision(0.35, 1.05)
	_build_visual(
		Vector3(0.65, 0.65, 1.10), Vector3(0.45, 0.45, 0.50),
		Color(0.65, 0.63, 0.62),   Color(0.70, 0.68, 0.65)
	)
	_init_genes(1.0, 2.0, 1.0)   # wolves have 2× health multiplier
	super._mob_ready()


func _do_periodic_checks() -> void:
	if _is_tamed:
		return
	# Wolves don't flee from player (neutral unless attacked)
	# Hunt nearest prey species
	if _hunt_target == null and \
			(_state == AnimalState.IDLE or _state == AnimalState.WANDER):
		_find_prey()


func _find_prey() -> void:
	var prey_species := ["rabbit", "chicken", "sheep"]
	var best_dist := HUNT_RANGE
	var best: BaseAnimal = null
	for ps in prey_species:
		if not BaseAnimal._herd_registry.has(ps):
			continue
		for animal: BaseAnimal in (BaseAnimal._herd_registry[ps] as Array):
			if not is_instance_valid(animal) or animal._dead:
				continue
			var d := global_position.distance_to(animal.global_position)
			if d < best_dist:
				best_dist = d
				best = animal
	if best != null:
		_hunt_target = best
		_hunt_timer  = 15.0


func _update_ai(delta: float) -> void:
	_attack_cd   = maxf(0.0, _attack_cd   - delta)
	_aggro_timer = maxf(0.0, _aggro_timer - delta)
	if _aggro_player != null:
		_update_player_aggro(delta)
	elif _hunt_target != null:
		_update_hunt(delta)
	else:
		super._update_ai(delta)


func _update_player_aggro(delta: float) -> void:
	if not is_instance_valid(_aggro_player) or _aggro_timer <= 0.0:
		_aggro_player = null
		_set_state(AnimalState.IDLE, 3.0)
		return
	var dist := global_position.distance_to(_aggro_player.global_position)
	if dist > 22.0:
		_aggro_player = null
		_set_state(AnimalState.IDLE, 3.0)
		return
	if dist <= 1.6 and _attack_cd <= 0.0:
		_aggro_player.take_damage(4.0, "wolf")
		_attack_cd = 1.2
	else:
		_wander_target = _aggro_player.global_position
		_move_toward_target(delta, flee_speed * 0.95)


func _update_hunt(delta: float) -> void:
	_hunt_timer -= delta
	_state_timer -= delta
	_ai_tick_timer -= delta
	if _ai_tick_timer <= 0.0:
		_ai_tick_timer = 0.35
		_do_periodic_checks()

	if not is_instance_valid(_hunt_target) or _hunt_target._dead or _hunt_timer <= 0.0:
		_hunt_target = null
		_set_state(AnimalState.IDLE, 4.0)
		return

	var dist := global_position.distance_to(_hunt_target.global_position)
	if dist <= 1.3 and _attack_cd <= 0.0:
		_hunt_target.take_damage(4.0, self)
		_attack_cd   = 1.2
		_hunt_target = null
		_set_state(AnimalState.IDLE, 3.0)
	else:
		_wander_target = _hunt_target.global_position
		_move_toward_target(delta, flee_speed * 0.9)


func _on_tamed(_player: Node) -> void:
	loot_table.clear()
	_hunt_target = null


func take_damage(amount: float, source: Node3D = null) -> void:
	super.take_damage(amount, source)
	if _is_tamed or source == null:
		return
	# Retaliate against any attacker — animal or player
	if source is BaseAnimal and _hunt_target == null:
		_hunt_target = source as BaseAnimal
		_hunt_timer  = 20.0
	elif source is Player and _aggro_player == null:
		_aggro_player = source as Player
		_aggro_timer  = 20.0
