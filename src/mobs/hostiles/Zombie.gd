class_name Zombie
extends BaseHostile

func _mob_ready() -> void:
	species        = "zombie"
	max_health     = 20.0
	walk_speed     = 2.0
	chase_speed    = 3.8
	aggro_range    = 16.0
	attack_range   = 1.8
	attack_damage  = 3.0
	attack_cooldown = 1.4
	forget_range   = 26.0
	loot_table     = [
		{"item": "axiom:rotten_flesh",   "count_min": 0, "count_max": 2, "chance": 1.0},
		{"item": "axiom:corrupted_fang", "count_min": 1, "count_max": 1, "chance": 0.20},
	]
	_build_collision(0.30, 1.80)
	_build_visual(
		Vector3(0.60, 0.80, 0.35),  # body
		Vector3(0.55, 0.55, 0.55),  # head
		Color(0.35, 0.52, 0.32),    # body: greenish-gray
		Color(0.42, 0.60, 0.38)     # head: slightly lighter green
	)
