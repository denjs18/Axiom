class_name Deer
extends BaseAnimal

func _mob_ready() -> void:
	species         = "deer"
	walk_speed      = 3.2
	flee_speed      = 7.0
	detection_range = 12.0   # very alert
	max_health      = 10.0
	can_breed       = true
	feed_item       = "axiom:apple"
	loot_table = [
		{"item": "axiom:beef",    "count_min": 1, "count_max": 2, "chance": 1.0},
		{"item": "axiom:leather", "count_min": 0, "count_max": 1, "chance": 0.70},
	]
	_build_collision(0.40, 1.40)
	_build_visual(
		Vector3(0.65, 0.90, 1.30), Vector3(0.40, 0.50, 0.45),
		Color(0.72, 0.52, 0.30),   Color(0.68, 0.48, 0.26)
	)
	_init_genes(1.1, 1.0, 1.0)
	super._mob_ready()


func _spawn_offspring() -> BaseAnimal:
	var fawn := Deer.new()
	get_parent().add_child(fawn)
	fawn.global_position = (global_position + _breed_partner.global_position) * 0.5 + Vector3(0, 0.3, 0)
	var g := _get_offspring_genes(_breed_partner)
	fawn.genes = g
	fawn._init_genes(g["speed"], g["health"], g["size"] * 0.65)
	return fawn
