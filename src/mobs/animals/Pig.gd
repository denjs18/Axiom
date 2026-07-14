class_name Pig
extends BaseAnimal

func _mob_ready() -> void:
	species         = "pig"
	walk_speed      = 2.2
	flee_speed      = 4.5
	detection_range = 6.0
	max_health      = 10.0
	can_breed       = true
	feed_item       = "axiom:carrot"
	loot_table = [
		{"item": "axiom:raw_porkchop", "count_min": 1, "count_max": 3, "chance": 1.0},
	]
	_build_collision(0.35, 0.90)
	_build_visual(
		Vector3(0.80, 0.65, 1.10), Vector3(0.55, 0.50, 0.55),
		Color(0.95, 0.72, 0.72),   Color(0.95, 0.65, 0.65)
	)
	_init_genes()
	super._mob_ready()


func _spawn_offspring() -> BaseAnimal:
	var piglet := Pig.new()
	get_parent().add_child(piglet)
	piglet.global_position = (global_position + _breed_partner.global_position) * 0.5 + Vector3(0, 0.3, 0)
	var g := _get_offspring_genes(_breed_partner)
	piglet.genes = g
	piglet._init_genes(g["speed"], g["health"], g["size"] * 0.70)
	return piglet
