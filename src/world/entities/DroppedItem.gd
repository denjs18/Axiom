## DroppedItem.gd — Physical item entity dropped in the world.
## Pops up on spawn, bobs and spins, magnets toward the player, then auto-collects.
class_name DroppedItem
extends RigidBody3D

var item_id: String = ""
var count: int = 1

var _mesh: MeshInstance3D = null
var _mesh_sprite: Sprite3D = null
var _bob_t: float = 0.0
var _lifetime: float = 300.0   # despawn after 5 minutes
var _pickup_delay: float = 0.8 # brief grace period so the item doesn't immediately re-collect

const PICKUP_RANGE := 2.2
const MAGNET_RANGE := 6.0


func setup(iid: String, cnt: int, spawn_pos: Vector3) -> void:
	item_id      = iid
	count        = cnt
	position     = spawn_pos   # World is at origin so local == global
	lock_rotation = true
	linear_damp  = 1.5
	_build_mesh()
	_build_collider()
	call_deferred("_spawn_impulse")


func _spawn_impulse() -> void:
	apply_central_impulse(Vector3(
		randf_range(-1.0, 1.0),
		4.5,
		randf_range(-1.0, 1.0)
	))


func _build_mesh() -> void:
	# Prefer the real item/block texture as a small billboard sprite
	var tex: Texture2D = ItemIcon._resolve(item_id)
	if tex == null:
		# Blocks: use their top-face texture from the block textures folder
		var block_id := ItemRegistry.get_block_id_for_item(item_id)
		if block_id != 0:
			var block := BlockRegistry.get_block(block_id)
			if block != null:
				var tex_name: String = block.get_texture_for_face("top")
				for path in ["res://assets/textures/blocks/%s.png" % tex_name,
						"res://assets/textures/blocks/%s.png" % block.name]:
					if ResourceLoader.exists(path):
						tex = load(path) as Texture2D
						if tex != null:
							break

	if tex != null:
		var spr := Sprite3D.new()
		spr.texture        = tex
		spr.pixel_size     = 0.018
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		spr.billboard      = BaseMaterial3D.BILLBOARD_ENABLED
		spr.shaded         = true
		spr.cast_shadow    = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spr.position.y     = 0.15
		add_child(spr)
		_mesh_sprite = spr
		return

	# Fallback: colored cube
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.25, 0.25, 0.25)
	_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ItemIcon._fallback_color(item_id)
	mat.roughness    = 0.8
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.material_override = mat
	add_child(_mesh)


func _build_collider() -> void:
	var col    := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.15
	col.shape = sphere
	add_child(col)


func _process(delta: float) -> void:
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()
		return

	# Bob + spin on the mesh child, not the physics body
	_bob_t += delta * 2.5
	if _mesh:
		_mesh.position.y  = sin(_bob_t) * 0.06
		_mesh.rotation.y  = fmod(_mesh.rotation.y + delta * 2.0, TAU)
	elif _mesh_sprite:
		_mesh_sprite.position.y = 0.15 + sin(_bob_t) * 0.05

	_pickup_delay = maxf(0.0, _pickup_delay - delta)
	if _pickup_delay > 0.0:
		return

	var player := GameManager.local_player as Node3D
	if player == null:
		return

	var player_pos := player.global_position
	var dist := global_position.distance_to(player_pos)
	if dist <= PICKUP_RANGE:
		player.call("_collect_item", item_id, count)
		EventBus.item_picked_up.emit({"id": item_id, "count": count}, player)
		queue_free()
	elif dist <= MAGNET_RANGE:
		var dir: Vector3 = (player_pos - global_position).normalized()
		linear_velocity = dir * 6.0
