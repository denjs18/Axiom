## Arrow.gd — Simple kinematic projectile fired by Skeleton.
## Moves in a parabola, deals damage on player contact, vanishes on terrain hit.
class_name Arrow
extends Node3D

var _vel: Vector3          = Vector3.ZERO
var _damage: float         = 3.0
var _lifetime: float       = 5.0
var _player: Player        = null
var _chunk_manager         = null


func setup(origin: Vector3, dir: Vector3, dmg: float) -> void:
	global_position = origin
	_vel    = dir.normalized() * 22.0
	_damage = dmg
	_player = GameManager.local_player as Player
	var wn  = GameManager.world_node
	if wn:
		_chunk_manager = wn.get("chunk_manager")

	# Visual: thin elongated box
	var mi  := MeshInstance3D.new()
	var bm  := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, 0.38)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.48, 0.22)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_face_velocity()


func _process(delta: float) -> void:
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()
		return

	_vel.y -= 9.8 * delta
	global_position += _vel * delta
	_face_velocity()

	# Hit player
	if _player != null and is_instance_valid(_player):
		if global_position.distance_to(_player.global_position + Vector3(0, 1, 0)) < 0.75:
			_player.take_damage(_damage, "arrow")
			queue_free()
			return

	# Hit terrain
	if _chunk_manager != null:
		var bpos := Vector3i(
			floori(global_position.x),
			floori(global_position.y),
			floori(global_position.z)
		)
		var bid: int = _chunk_manager.get_block_at(bpos)
		if bid > 0 and not BlockRegistry.is_fluid(bid):
			queue_free()


func _face_velocity() -> void:
	if _vel.length_squared() > 0.01:
		look_at(global_position + _vel.normalized(), Vector3.UP)
