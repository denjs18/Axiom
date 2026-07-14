## Creeper.gd — Silent green menace. Chases the player, hisses, explodes.
class_name Creeper
extends BaseHostile

const FUSE_TIME    := 1.5
const EXPLODE_DIST := 2.6
const ABORT_DIST   := 5.0
const BLAST_RADIUS := 3

var _fusing: bool = false
var _fuse_t: float = 0.0
var _flash_t: float = 0.0


func _mob_ready() -> void:
	species        = "creeper"
	max_health     = 20.0
	walk_speed     = 2.2
	chase_speed    = 4.0
	aggro_range    = 15.0
	attack_range   = EXPLODE_DIST
	attack_damage  = 0.0
	forget_range   = 26.0
	xp_reward      = 8
	loot_table     = [
		{"item": "axiom:gunpowder", "count_min": 0, "count_max": 2, "chance": 1.0},
	]
	_build_collision(0.28, 1.60)
	_build_visual(
		Vector3(0.50, 0.90, 0.34),
		Vector3(0.48, 0.48, 0.48),
		Color(0.32, 0.62, 0.30),
		Color(0.36, 0.68, 0.34)
	)
	# Creepers have no arms — remove them, keep the 2 legs
	for arm in _anim_arms:
		(arm as Node3D).queue_free()
	_anim_arms.clear()


func _run_ai(delta: float) -> void:
	if _fusing:
		_tick_fuse(delta)
		return
	super._run_ai(delta)
	# Close enough → start the fuse
	if _state == State.CHASE and _player != null and is_instance_valid(_player):
		if global_position.distance_to(_player.global_position) <= EXPLODE_DIST:
			_fusing = true
			_fuse_t = 0.0
			EventBus.show_message.emit("Tsss...", 0.9)


func _tick_fuse(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
	_fuse_t  += delta
	_flash_t += delta

	# Flash white faster and faster
	var flash_speed := 6.0 + _fuse_t * 10.0
	var white := 0.5 + 0.5 * sin(_flash_t * flash_speed)
	_set_flash(white * 0.8)
	# Swell before the blast
	if _visual_root != null:
		var s := 1.0 + _fuse_t / FUSE_TIME * 0.25
		_visual_root.scale = Vector3(s, s, s)

	# Player ran away — defuse
	if _player == null or not is_instance_valid(_player) \
			or global_position.distance_to(_player.global_position) > ABORT_DIST:
		_fusing = false
		_set_flash(0.0)
		if _visual_root != null:
			_visual_root.scale = Vector3.ONE
		return

	if _fuse_t >= FUSE_TIME:
		_explode()


func _set_flash(amount: float) -> void:
	for child in _visual_root.get_children() if _visual_root else []:
		_flash_rec(child, amount)


func _flash_rec(node: Node, amount: float) -> void:
	if node is MeshInstance3D:
		var mat := (node as MeshInstance3D).material_override as StandardMaterial3D
		if mat != null:
			mat.emission_enabled = amount > 0.02
			mat.emission = Color(1, 1, 1) * amount
	for c in node.get_children():
		_flash_rec(c, amount)


func _explode() -> void:
	var origin := global_position
	var world := GameManager.world_node
	var cm = world.get("chunk_manager") if world != null else null

	# Break blocks in a sphere (respecting blast resistance)
	if cm != null:
		var center := Vector3i(floori(origin.x), floori(origin.y + 0.5), floori(origin.z))
		for dx in range(-BLAST_RADIUS, BLAST_RADIUS + 1):
			for dy in range(-BLAST_RADIUS, BLAST_RADIUS + 1):
				for dz in range(-BLAST_RADIUS, BLAST_RADIUS + 1):
					if dx * dx + dy * dy + dz * dz > BLAST_RADIUS * BLAST_RADIUS:
						continue
					var pos: Vector3i = center + Vector3i(dx, dy, dz)
					var bid: int = cm.get_block_at(pos)
					if bid == 0:
						continue
					var block := BlockRegistry.get_block(bid)
					if block == null or block.hardness < 0 or block.blast_resistance > 100:
						continue
					# Some destroyed blocks drop as items
					if randf() < 0.28:
						var drops: Array = block.get_drop_list("", 99, 0, false)
						for drop in drops:
							if drop["item"] != "" and drop["count"] > 0:
								EventBus.item_dropped.emit(
									{"id": drop["item"], "count": drop["count"]},
									Vector3(pos.x + 0.5, pos.y + 0.5, pos.z + 0.5))
					cm.set_block_at(pos, 0)
		EventBus.block_broken.emit(center, 0, self)   # trigger relight around

	# Damage the player by proximity
	var player := GameManager.local_player
	if player != null and player is Node3D:
		var dist := origin.distance_to((player as Node3D).global_position)
		if dist < BLAST_RADIUS * 2.2:
			var dmg := clampf(22.0 * (1.0 - dist / (BLAST_RADIUS * 2.2)), 2.0, 22.0)
			player.take_damage(dmg, "explosion")
			# Knockback
			var kdir := ((player as Node3D).global_position - origin).normalized()
			kdir.y = 0.5
			if player is CharacterBody3D:
				(player as CharacterBody3D).velocity += kdir * 12.0

	# Damage nearby mobs too
	var space := get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = BLAST_RADIUS * 2.0
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis.IDENTITY, origin)
	params.collision_mask = 4
	params.exclude = [get_rid()]
	for hit in space.intersect_shape(params, 12):
		var node := hit.get("collider") as Node3D
		if node != null and node.has_method("take_damage"):
			node.take_damage(14.0, self)

	loot_table = []   # exploding creepers drop nothing
	_die(null)
