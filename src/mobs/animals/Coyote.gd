## Coyote.gd — Neutral scavenger that actively seeks and steals dropped items.
class_name Coyote
extends BaseAnimal

var _item_target: DroppedItem = null
var _steal_timer: float = 0.0

func _mob_ready() -> void:
	species         = "coyote"
	walk_speed      = 3.5
	flee_speed      = 6.5
	detection_range = 5.0
	max_health      = 8.0
	can_breed       = false   # coyotes don't breed with player interaction
	loot_table = [
		{"item": "axiom:beef",          "count_min": 0, "count_max": 1, "chance": 0.80},
		{"item": "axiom:leather",       "count_min": 0, "count_max": 1, "chance": 0.60},
		{"item": "axiom:predator_claw", "count_min": 1, "count_max": 1, "chance": 0.25},
	]
	_build_collision(0.30, 0.95)
	_build_visual(
		Vector3(0.55, 0.60, 1.00), Vector3(0.38, 0.40, 0.42),
		Color(0.72, 0.58, 0.35),   Color(0.68, 0.55, 0.32)
	)
	_init_genes()
	super._mob_ready()


func _do_periodic_checks() -> void:
	# Coyotes don't flee from player — they flee only when hit
	if _state == AnimalState.IDLE or _state == AnimalState.WANDER:
		_scan_for_dropped_items()


func _scan_for_dropped_items() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var best_dist := 8.0
	var best: DroppedItem = null
	for child in parent.get_children():
		if not (child is DroppedItem):
			continue
		var d := global_position.distance_to(child.global_position)
		if d < best_dist:
			best_dist = d
			best = child as DroppedItem
	if best != null:
		_item_target = best
		_steal_timer = 10.0
		_wander_target = best.global_position
		_set_state(AnimalState.WANDER, 12.0)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _item_target == null:
		return
	_steal_timer -= delta
	if not is_instance_valid(_item_target) or _steal_timer <= 0.0:
		_item_target = null
		return
	# Update wander target to track moving item
	_wander_target = _item_target.global_position
	if global_position.distance_to(_item_target.global_position) < 0.8:
		_item_target.queue_free()
		_item_target = null
		# Run away after stealing
		_flee_dir   = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		_flee_timer = 5.0
		_set_state(AnimalState.FLEE, 5.5)


func take_damage(amount: float, source: Node3D = null) -> void:
	super.take_damage(amount, source)
	# Coyote flees when hit (unlike wolf, doesn't fight back)
	if source != null and _state != AnimalState.FLEE:
		_start_flee(source.global_position)
