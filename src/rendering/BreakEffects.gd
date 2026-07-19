## BreakEffects.gd — Mining feedback in the world: a progressive crack overlay
## on the block being broken, plus a burst of colored fragments when it pops.
## Added as a child of World; connects to the local player's block_breaking_at
## signal and to EventBus.block_broken.
class_name BreakEffects
extends Node3D

const STAGES := 8
const SEGMENTS := 60          # total crack walk segments at full damage
const SEG_LEN := 5            # pixels per crack walk

var _crack_tex: Array[ImageTexture] = []
var _overlay: MeshInstance3D = null
var _overlay_mat: StandardMaterial3D = null


func _ready() -> void:
	_gen_crack_textures()
	_build_overlay()
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.block_broken.connect(_on_block_broken)
	# The player may have spawned before this node was added
	if GameManager.local_player != null:
		_on_player_spawned(GameManager.local_player)


func _on_player_spawned(player: Node) -> void:
	if player == null or not player.has_signal("block_breaking_at"):
		return
	if not player.block_breaking_at.is_connected(_on_breaking):
		player.block_breaking_at.connect(_on_breaking)


func _on_breaking(bpos: Vector3i, progress: float) -> void:
	if progress <= 0.0 or progress >= 1.0:
		_overlay.visible = false
		return
	var stage := clampi(int(progress * STAGES), 0, STAGES - 1)
	_overlay_mat.albedo_texture = _crack_tex[stage]
	_overlay.position = Vector3(bpos) + Vector3(0.5, 0.5, 0.5)
	_overlay.visible  = true


func _on_block_broken(pos: Vector3i, block_id: int, _player: Node) -> void:
	_overlay.visible = false
	if block_id <= 0:
		return   # air ping (e.g. explosion relight) — nothing to shatter
	_spawn_fragments(Vector3(pos) + Vector3(0.5, 0.5, 0.5), block_id)


# ── Crack overlay ──────────────────────────────────────────────────────────────

func _build_overlay() -> void:
	_overlay_mat = StandardMaterial3D.new()
	_overlay_mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay_mat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var box := BoxMesh.new()
	box.size     = Vector3(1.005, 1.005, 1.005)
	box.material = _overlay_mat
	_overlay = MeshInstance3D.new()
	_overlay.mesh    = box
	_overlay.visible = false
	_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_overlay)


## Pre-generate the crack stages. All stages share one deterministic set of
## random crack walks; stage N reveals the first (N+1)/STAGES of them, so the
## pattern grows instead of jumping around.
func _gen_crack_textures() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xC4AC
	# Build the full segment list once: each walk = start point + steps
	var walks: Array = []
	for _i in SEGMENTS:
		var pts: Array[Vector2i] = []
		var p := Vector2i(rng.randi_range(1, 14), rng.randi_range(1, 14))
		pts.append(p)
		for _j in SEG_LEN:
			p += Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
			p.x = clampi(p.x, 0, 15)
			p.y = clampi(p.y, 0, 15)
			pts.append(p)
		walks.append(pts)

	for stage in STAGES:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		var visible_walks := int(float(SEGMENTS) * float(stage + 1) / float(STAGES))
		for w in visible_walks:
			var pts: Array[Vector2i] = walks[w]
			for p in pts:
				img.set_pixel(p.x, p.y, Color(0.04, 0.04, 0.04, 0.62))
		_crack_tex.append(ImageTexture.create_from_image(img))


# ── Break fragments ────────────────────────────────────────────────────────────

func _spawn_fragments(center: Vector3, block_id: int) -> void:
	var col := _block_color(block_id)
	var p := CPUParticles3D.new()
	p.one_shot             = true
	p.amount               = 14
	p.lifetime             = 0.55
	p.explosiveness        = 1.0
	p.direction            = Vector3.UP
	p.spread               = 80.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5
	p.gravity              = Vector3(0, -18.0, 0)
	p.scale_amount_min     = 0.5
	p.scale_amount_max     = 1.0
	p.emission_shape       = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.32, 0.32, 0.32)
	p.color                = col
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.09, 0.09, 0.09)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	p.mesh = mesh
	add_child(p)
	p.position = center
	p.emitting = true
	get_tree().create_timer(1.4).timeout.connect(p.queue_free)


func _block_color(block_id: int) -> Color:
	var b := BlockRegistry.get_block(block_id)
	if b == null:
		return Color(0.6, 0.6, 0.6)
	var tex_name := ""
	if b.texture is String:
		tex_name = b.texture
	elif b.texture is Dictionary:
		var d: Dictionary = b.texture
		tex_name = str(d.get("side", d.get("all", d.get("top", ""))))
	if tex_name.is_empty():
		tex_name = b.name
	# Slightly darkened so unshaded fragments don't glow at night
	return BlockTextureAtlas.get_avg_tile_color(tex_name).darkened(0.15)
