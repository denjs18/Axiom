class_name Sheep
extends BaseAnimal

func _mob_ready() -> void:
	species         = "sheep"
	walk_speed      = 2.0
	flee_speed      = 4.8
	detection_range = 8.0
	max_health      = 8.0
	can_breed       = true
	feed_item       = "axiom:wheat"
	loot_table = [
		{"item": "axiom:raw_mutton", "count_min": 1, "count_max": 2, "chance": 1.0},
		{"item": "axiom:wool",   "count_min": 1, "count_max": 1, "chance": 1.0},
	]
	var wool_col := _random_wool_color()
	_build_collision(0.35, 1.1)
	_build_visual(
		Vector3(0.80, 0.85, 1.10), Vector3(0.40, 0.42, 0.45),
		wool_col, wool_col
	)
	_init_genes()
	super._mob_ready()


var _sheared: bool = false
var _regrow_timer: float = 0.0


## Right-click with shears → wool without the mutton.
func try_interact(player: Node) -> void:
	if not _sheared:
		var held: Dictionary = player.call("_get_held_item")
		if held.get("id", "") == "axiom:shears":
			_sheared = true
			_regrow_timer = 120.0
			var count := randi_range(1, 3)
			EventBus.item_dropped.emit({"id": "axiom:wool", "count": count},
				global_position + Vector3(0, 0.8, 0))
			_tint_body(Color(0.92, 0.80, 0.72))   # shorn skin tone
			return
	super.try_interact(player)


func _process(delta: float) -> void:
	if _sheared:
		_regrow_timer -= delta
		if _regrow_timer <= 0.0:
			_sheared = false
			_tint_body(Color(0.95, 0.95, 0.95))


func _tint_body(col: Color) -> void:
	for child in _visual_root.get_children() if _visual_root else []:
		if child is MeshInstance3D:
			var mat := (child as MeshInstance3D).material_override as StandardMaterial3D
			if mat != null:
				mat.albedo_color = col


func _random_wool_color() -> Color:
	var colors := [
		Color(0.95, 0.95, 0.95), Color(0.85, 0.85, 0.85),
		Color(0.85, 0.55, 0.22), Color(0.20, 0.55, 0.20),
		Color(0.88, 0.30, 0.22), Color(0.25, 0.35, 0.78),
		Color(0.90, 0.85, 0.22), Color(0.55, 0.20, 0.65),
	]
	return colors[randi() % colors.size()]


func _spawn_offspring() -> BaseAnimal:
	var lamb := Sheep.new()
	get_parent().add_child(lamb)
	lamb.global_position = (global_position + _breed_partner.global_position) * 0.5 + Vector3(0, 0.3, 0)
	var g := _get_offspring_genes(_breed_partner)
	lamb.genes = g
	lamb._init_genes(g["speed"], g["health"], g["size"] * 0.75)
	return lamb
