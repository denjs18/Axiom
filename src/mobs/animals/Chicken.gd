class_name Chicken
extends BaseAnimal

var _egg_timer: float = 0.0

func _mob_ready() -> void:
	species         = "chicken"
	walk_speed      = 1.8
	flee_speed      = 3.5
	detection_range = 6.0
	max_health      = 4.0
	can_breed       = true
	feed_item       = "axiom:wheat_seeds"
	loot_table = [
		{"item": "axiom:chicken",        "count_min": 1, "count_max": 1, "chance": 1.0},
		{"item": "axiom:feather",        "count_min": 0, "count_max": 2, "chance": 1.0},
		{"item": "axiom:arcane_feather", "count_min": 1, "count_max": 1, "chance": 0.08},
	]
	_build_collision(0.20, 0.70)
	_build_visual(
		Vector3(0.40, 0.45, 0.55), Vector3(0.28, 0.30, 0.30),
		Color(0.95, 0.94, 0.90),   Color(0.96, 0.86, 0.72)
	)
	_egg_timer = randf_range(300.0, 600.0)
	_init_genes()
	super._mob_ready()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_egg_timer -= delta
	if _egg_timer <= 0.0:
		_lay_egg()
		_egg_timer = randf_range(300.0, 600.0)


func _lay_egg() -> void:
	var drop := DroppedItem.new()
	get_parent().add_child(drop)
	drop.setup("axiom:egg", 1, global_position + Vector3(0, 0.5, 0))


func _spawn_offspring() -> BaseAnimal:
	var chick := Chicken.new()
	get_parent().add_child(chick)
	chick.global_position = (global_position + _breed_partner.global_position) * 0.5 + Vector3(0, 0.3, 0)
	var g := _get_offspring_genes(_breed_partner)
	chick.genes = g
	chick._init_genes(g["speed"], g["health"], g["size"] * 0.60)
	return chick
