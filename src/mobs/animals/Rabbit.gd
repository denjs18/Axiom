class_name Rabbit
extends BaseAnimal

func _mob_ready() -> void:
	species         = "rabbit"
	walk_speed      = 3.0
	flee_speed      = 6.5
	detection_range = 10.0   # very skittish
	max_health      = 3.0
	can_breed       = true
	feed_item       = "axiom:carrot"
	loot_table = [
		{"item": "axiom:rabbit",      "count_min": 0, "count_max": 1, "chance": 0.90},
		{"item": "axiom:rabbit_hide", "count_min": 0, "count_max": 1, "chance": 0.90},
	]
	_build_collision(0.18, 0.50)
	_build_visual(
		Vector3(0.35, 0.38, 0.50), Vector3(0.24, 0.30, 0.28),
		Color(0.78, 0.65, 0.50),   Color(0.82, 0.70, 0.55)
	)
	_init_genes()
	super._mob_ready()


func _spawn_offspring() -> BaseAnimal:
	var kit := Rabbit.new()
	get_parent().add_child(kit)
	kit.global_position = (global_position + _breed_partner.global_position) * 0.5 + Vector3(0, 0.2, 0)
	var g := _get_offspring_genes(_breed_partner)
	kit.genes = g
	kit._init_genes(g["speed"], g["health"], g["size"] * 0.65)
	return kit
