class_name Cow
extends BaseAnimal

func _mob_ready() -> void:
	species         = "cow"
	walk_speed      = 2.0
	flee_speed      = 4.5
	detection_range = 8.0
	max_health      = 10.0
	can_breed       = true
	feed_item       = "axiom:wheat"
	loot_table = [
		{"item": "axiom:raw_beef",    "count_min": 1, "count_max": 3, "chance": 1.0},
		{"item": "axiom:leather", "count_min": 0, "count_max": 2, "chance": 1.0},
	]
	_build_collision(0.42, 1.2)
	_build_visual(
		Vector3(0.85, 0.75, 1.30), Vector3(0.50, 0.50, 0.55),
		Color(0.88, 0.85, 0.80),   Color(0.78, 0.75, 0.70)
	)
	_init_genes()
	super._mob_ready()


func _spawn_offspring() -> BaseAnimal:
	var calf := Cow.new()
	get_parent().add_child(calf)
	calf.global_position = (global_position + _breed_partner.global_position) * 0.5 + Vector3(0, 0.3, 0)
	var g := _get_offspring_genes(_breed_partner)
	calf.genes = g
	calf._init_genes(g["speed"], g["health"], g["size"] * 0.80)
	return calf
