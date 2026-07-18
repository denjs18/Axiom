## BlockTextureAtlas.gd
## Autoload singleton. Builds a square block-texture atlas at startup.
## Each tile is loaded from the imported Minecraft PNGs in
## res://assets/textures/blocks/ (matched by texture name). Any texture name
## without a PNG falls back to the procedural pixel-art generator below, so the
## game never shows a blank tile.
extends Node

const T := 16  # tile size in pixels (vanilla Minecraft texture size)
const BLOCKS_TEX_DIR := "res://assets/textures/blocks/"

var texture:      ImageTexture
var tile_uv_size: float = 0.0625  # = 1 / grid_cols, set in _build()
var _grid_cols:   int   = 16      # atlas is _grid_cols × _grid_cols tiles

# tex_name → Vector2 atlas UV top-left
var _uv: Dictionary = {}

# Atlas layout: [col, row, "texture_name"]
const _LAYOUT: Array = [
	# Row 0 — core terrain + common
	[0,0,"grass_block_top"],[1,0,"grass_block_side"],[2,0,"dirt"],[3,0,"stone"],
	[4,0,"cobblestone"],[5,0,"sand"],[6,0,"gravel"],[7,0,"oak_log"],
	[8,0,"oak_log_top"],[9,0,"oak_planks"],[10,0,"oak_leaves"],[11,0,"bedrock"],
	[12,0,"water"],[13,0,"lava"],[14,0,"glass"],[15,0,"glowstone"],
	# Row 1 — nether/end + spruce
	[0,1,"netherrack"],[1,1,"end_stone"],[2,1,"deepslate"],[3,1,"deepslate_top"],
	[4,1,"spruce_log"],[5,1,"spruce_log_top"],[6,1,"spruce_planks"],[7,1,"spruce_leaves"],
	[8,1,"birch_log"],[9,1,"birch_log_top"],[10,1,"birch_planks"],[11,1,"birch_leaves"],
	[12,1,"jungle_log"],[13,1,"jungle_log_top"],[14,1,"jungle_planks"],[15,1,"jungle_leaves"],
	# Row 2 — acacia, dark oak, ores
	[0,2,"acacia_log"],[1,2,"acacia_log_top"],[2,2,"acacia_planks"],[3,2,"acacia_leaves"],
	[4,2,"dark_oak_log"],[5,2,"dark_oak_log_top"],[6,2,"dark_oak_planks"],[7,2,"dark_oak_leaves"],
	[8,2,"coal_ore"],[9,2,"iron_ore"],[10,2,"gold_ore"],[11,2,"diamond_ore"],
	[12,2,"redstone_ore"],[13,2,"lapis_ore"],[14,2,"emerald_ore"],[15,2,"copper_ore"],
	# Row 3 — deepslate ores + stone variants
	[0,3,"deepslate_coal_ore"],[1,3,"deepslate_iron_ore"],[2,3,"deepslate_gold_ore"],
	[3,3,"deepslate_diamond_ore"],[4,3,"deepslate_redstone_ore"],[5,3,"deepslate_lapis_ore"],
	[6,3,"deepslate_emerald_ore"],[7,3,"deepslate_copper_ore"],
	[8,3,"andesite"],[9,3,"diorite"],[10,3,"granite"],[11,3,"tuff"],
	[12,3,"calcite"],[13,3,"red_sand"],[14,3,"coarse_dirt"],[15,3,"missing"],
	# Row 4 — more woods + biome surfaces
	[0,4,"mangrove_log"],[1,4,"mangrove_log_top"],[2,4,"mangrove_planks"],[3,4,"mangrove_leaves"],
	[4,4,"cherry_log"],[5,4,"cherry_log_top"],[6,4,"cherry_planks"],[7,4,"cherry_leaves"],
	[8,4,"pale_oak_log"],[9,4,"pale_oak_log_top"],[10,4,"pale_oak_planks"],[11,4,"pale_oak_leaves"],
	[12,4,"rooted_dirt"],[13,4,"podzol_top"],[14,4,"podzol_side"],[15,4,"mycelium_top"],
	# Row 5 — nether blocks + stone bricks
	[0,5,"mycelium_side"],[1,5,"stone_bricks"],[2,5,"mossy_stone_bricks"],[3,5,"cracked_stone_bricks"],
	[4,5,"basalt_side"],[5,5,"basalt_top"],[6,5,"blackstone"],[7,5,"nether_bricks"],
	[8,5,"soul_sand"],[9,5,"soul_soil"],[10,5,"magma_block"],[11,5,"obsidian"],
	[12,5,"ancient_debris_side"],[13,5,"ancient_debris_top"],[14,5,"nether_quartz_ore"],[15,5,"quartz_block_side"],
	# Row 6 — metal/gem blocks
	[0,6,"iron_block"],[1,6,"gold_block"],[2,6,"diamond_block"],[3,6,"emerald_block"],
	[4,6,"lapis_block"],[5,6,"redstone_block"],[6,6,"coal_block"],[7,6,"copper_block"],
	[8,6,"netherite_block"],[9,6,"amethyst_block"],[10,6,"end_stone_bricks"],[11,6,"purpur_block"],
	[12,6,"shroomlight"],[13,6,"sea_lantern"],[14,6,"crafting_table_top"],[15,6,"crafting_table_side"],
	# Row 7 — misc / unused (fill with missing)
	[0,7,"furnace_front"],[1,7,"furnace_side"],[2,7,"furnace_top"],
	[3,7,"dirt_path_top"],[4,7,"dirt_path_side"],[5,7,"mud"],[6,7,"packed_mud"],
	[7,7,"moss_block"],[8,7,"tuff_bricks"],[9,7,"polished_tuff"],[10,7,"polished_basalt_side"],
	[11,7,"crying_obsidian"],[12,7,"chiseled_stone_bricks"],[13,7,"smooth_stone"],
	[14,7,"raw_iron_block"],[15,7,"raw_copper_block"],
	# Row 8 — new biome surface blocks
	[0,8,"snow_block"],[1,8,"orange_terracotta"],
]

# Minecraft ships grass & foliage textures in grayscale and tints them at
# runtime with the biome colormap. We bake a pleasant tint at atlas build time.
const _COL_GRASS   := Color(0.558, 0.725, 0.351)   # #8EB95A
const _COL_FOLIAGE := Color(0.467, 0.671, 0.184)   # #77AB2F
const _COL_SPRUCE  := Color(0.380, 0.600, 0.380)   # #619961
const _COL_BIRCH   := Color(0.502, 0.655, 0.333)   # #80A755
const _COL_MANGROVE := Color(0.553, 0.694, 0.153)  # #8DB127
const _COL_LILY    := Color(0.298, 0.620, 0.220)

const _TINTS: Dictionary = {
	"grass_block_top":         _COL_GRASS,
	"grass_block_side_overlay": _COL_GRASS,
	"short_grass":             _COL_GRASS,
	"tall_grass_top":          _COL_GRASS,
	"tall_grass_bottom":       _COL_GRASS,
	"fern":                    _COL_GRASS,
	"large_fern_top":          _COL_GRASS,
	"large_fern_bottom":       _COL_GRASS,
	"sugar_cane":              _COL_GRASS,
	"lily_pad":                _COL_LILY,
	"oak_leaves":              _COL_FOLIAGE,
	"jungle_leaves":           _COL_FOLIAGE,
	"acacia_leaves":           _COL_FOLIAGE,
	"dark_oak_leaves":         _COL_FOLIAGE,
	"mangrove_leaves":         _COL_MANGROVE,
	"spruce_leaves":           _COL_SPRUCE,
	"birch_leaves":            _COL_BIRCH,
	"vine":                    _COL_FOLIAGE,
}

# Aliases: some texture names used in JSON map to a canonical atlas name
const _ALIASES: Dictionary = {
	"grass_block":            "grass_block_top",
	"oak_log_side":           "oak_log",
	"spruce_log_side":        "spruce_log",
	"birch_log_side":         "birch_log",
	"jungle_log_side":        "jungle_log",
	"acacia_log_side":        "acacia_log",
	"dark_oak_log_side":      "dark_oak_log",
	"mangrove_log_side":      "mangrove_log",
	"cherry_log_side":        "cherry_log",
	"pale_oak_log_side":      "pale_oak_log",
	"deepslate_side":         "deepslate",
	"cobbled_deepslate":      "deepslate",
	"polished_deepslate":     "deepslate",
	"deepslate_bricks":       "deepslate",
	"deepslate_tiles":        "deepslate",
	"chiseled_deepslate":     "deepslate",
	"mossy_cobblestone":      "cobblestone",
	"smooth_stone_slab":      "smooth_stone",
}


func _ready() -> void:
	_build()


func get_face_uv(tex_name: String) -> Vector2:
	# Prefer the exact texture name (real imported PNG); fall back to an alias,
	# then to the "missing" tile.
	if _uv.has(tex_name):
		return _uv[tex_name]
	var key: String = _ALIASES[tex_name] if _ALIASES.has(tex_name) else tex_name
	if _uv.has(key):
		return _uv[key]
	if _uv.has("missing"):
		return _uv["missing"]
	return Vector2.ZERO


func _build() -> void:
	var names := _collect_texture_names()
	var count: int = names.size()
	var cols: int = max(1, int(ceil(sqrt(float(count)))))
	_grid_cols = cols
	tile_uv_size = 1.0 / float(cols)

	var atlas := Image.create(cols * T, cols * T, false, Image.FORMAT_RGBA8)
	var rng   := RandomNumberGenerator.new()
	var real_count := 0

	for i in count:
		var name: String = names[i]
		var col: int = i % cols
		var row: int = i / cols
		var loaded := _load_tile(name)
		var tile: Image
		if loaded != null:
			tile = loaded
			real_count += 1
		else:
			# Procedural fallback for any texture without an imported PNG.
			rng.seed = hash(name) & 0x7FFFFFFF
			tile = Image.create(T, T, false, Image.FORMAT_RGBA8)
			_draw_texture(tile, rng, name)
		atlas.blit_rect(tile, Rect2i(0, 0, T, T), Vector2i(col * T, row * T))
		_uv[name] = Vector2(float(col) / float(cols), float(row) / float(cols))

	texture = ImageTexture.create_from_image(atlas)
	print("[BlockTextureAtlas] Atlas built (%d×%d, %d tiles, %d from imported PNGs)." % [
		cols * T, cols * T, count, real_count])


## Gather every texture name referenced by registered blocks (plus the
## procedural layout names and alias targets) so each gets its own atlas tile.
func _collect_texture_names() -> Array:
	var name_set: Dictionary = {}
	for bid in BlockRegistry.get_all_block_ids():
		var b = BlockRegistry.get_block(bid)
		if b == null:
			continue
		var t = b.texture
		if t is String:
			name_set[t] = true
		elif t is Dictionary:
			for v in t.values():
				name_set[str(v)] = true
	# Keep procedural fallbacks and alias targets available as tiles too.
	for entry in _LAYOUT:
		name_set[entry[2]] = true
	for k in _ALIASES:
		name_set[_ALIASES[k]] = true
	name_set["missing"] = true
	return name_set.keys()


## Load an imported block PNG as a 16×16 RGBA tile, or null if none exists.
func _load_tile(tex_name: String) -> Image:
	var path := BLOCKS_TEX_DIR + tex_name + ".png"
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	var tile := _normalize_tile(img)
	if tile == null:
		return null
	# Biome tint for grayscale grass/foliage textures
	if _TINTS.has(tex_name):
		_tint_tile(tile, _TINTS[tex_name])
	# The grass block side is dirt + a grayscale grass overlay that needs tinting
	if tex_name == "grass_block_side":
		var overlay := _load_raw_tile("grass_block_side_overlay")
		if overlay != null:
			_tint_tile(overlay, _COL_GRASS)
			_composite_over(tile, overlay)
	return tile


func _load_raw_tile(tex_name: String) -> Image:
	var path := BLOCKS_TEX_DIR + tex_name + ".png"
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	return _normalize_tile(img)


func _tint_tile(img: Image, tint: Color) -> void:
	for y in T:
		for x in T:
			var c := img.get_pixel(x, y)
			if c.a <= 0.01:
				continue
			img.set_pixel(x, y, Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a))


func _composite_over(base: Image, overlay: Image) -> void:
	for y in T:
		for x in T:
			var o := overlay.get_pixel(x, y)
			if o.a > 0.5:
				base.set_pixel(x, y, Color(o.r, o.g, o.b, 1.0))


## Convert any source image to a 16×16 RGBA8 tile. Animated strips (taller than
## wide, e.g. water/lava) are cropped to their first frame.
func _normalize_tile(src: Image) -> Image:
	var img: Image = src.duplicate()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w <= 0 or h <= 0:
		return null
	if h > w:
		var frame := Image.create(w, w, false, Image.FORMAT_RGBA8)
		frame.blit_rect(img, Rect2i(0, 0, w, w), Vector2i.ZERO)
		img = frame
	if img.get_width() != T or img.get_height() != T:
		img.resize(T, T, Image.INTERPOLATE_NEAREST)
	return img


# ── Main dispatch ──────────────────────────────────────────────────────────────

func _draw_texture(img: Image, rng: RandomNumberGenerator, name: String) -> void:
	match name:
		"grass_block_top":         _grass_top(img, rng)
		"grass_block_side":        _grass_side(img, rng)
		"dirt","rooted_dirt":      _noise_fill(img, rng, 139, 94, 60, 14, 255)
		"coarse_dirt":             _noise_fill(img, rng, 127, 84, 52, 16, 255)
		"podzol_top":              _podzol_top(img, rng)
		"podzol_side":             _podzol_side(img, rng)
		"mycelium_top":            _mycelium_top(img, rng)
		"mycelium_side":           _mycelium_side(img, rng)
		"stone":                   _stone(img, rng)
		"cobblestone":             _cobblestone(img, rng)
		"smooth_stone":            _noise_fill(img, rng, 138, 138, 138, 6, 255)
		"stone_bricks":            _stone_bricks(img, rng)
		"mossy_stone_bricks":      _mossy_stone_bricks(img, rng)
		"cracked_stone_bricks":    _cracked_stone_bricks(img, rng)
		"chiseled_stone_bricks":   _chiseled_stone_bricks(img, rng)
		"sand":                    _noise_fill(img, rng, 219, 201, 122, 12, 255)
		"red_sand":                _noise_fill(img, rng, 180, 97, 30, 14, 255)
		"gravel":                  _gravel(img, rng)
		"andesite":                _noise_fill(img, rng, 132, 132, 132, 10, 255)
		"diorite":                 _noise_fill(img, rng, 200, 196, 190, 18, 255)
		"granite":                 _noise_fill(img, rng, 163, 114, 92, 16, 255)
		"tuff":                    _noise_fill(img, rng, 114, 116, 100, 12, 255)
		"tuff_bricks":             _stone_bricks_col(img, rng, 114, 116, 100, 95, 97, 82)
		"polished_tuff":           _noise_fill(img, rng, 114, 116, 100, 6, 255)
		"calcite":                 _noise_fill(img, rng, 222, 218, 212, 10, 255)
		"bedrock":                 _bedrock(img, rng)
		"deepslate":               _deepslate(img, rng)
		"deepslate_top":           _deepslate_top(img, rng)
		"cobbled_deepslate":       _deepslate(img, rng)
		"polished_deepslate":      _noise_fill(img, rng, 72, 72, 80, 8, 255)
		"mud":                     _noise_fill(img, rng, 80, 62, 46, 10, 255)
		"packed_mud":              _noise_fill(img, rng, 110, 82, 56, 10, 255)
		"moss_block":              _noise_fill(img, rng, 78, 112, 42, 18, 255)
		"dirt_path_top":           _noise_fill(img, rng, 152, 128, 80, 14, 255)
		"dirt_path_side":          _grass_side(img, rng)
		# Logs and wood
		"oak_log":                 _log_side(img, rng, 122, 92, 58, 84, 63, 39)
		"oak_log_top":             _log_top(img, rng, 155, 118, 75, 105, 78, 44)
		"oak_planks":              _planks(img, rng, 197, 160, 102, 155, 124, 74)
		"oak_leaves":              _leaves(img, rng, 38, 88, 18)
		"spruce_log":              _log_side(img, rng, 90, 62, 32, 60, 42, 20)
		"spruce_log_top":          _log_top(img, rng, 110, 80, 50, 72, 52, 28)
		"spruce_planks":           _planks(img, rng, 115, 85, 52, 88, 65, 36)
		"spruce_leaves":           _leaves(img, rng, 24, 52, 14)
		"birch_log":               _birch_log_side(img, rng)
		"birch_log_top":           _log_top(img, rng, 230, 224, 188, 180, 174, 138)
		"birch_planks":            _planks(img, rng, 228, 214, 158, 190, 178, 128)
		"birch_leaves":            _leaves(img, rng, 52, 100, 22)
		"jungle_log":              _log_side(img, rng, 120, 88, 40, 80, 58, 22)
		"jungle_log_top":          _log_top(img, rng, 138, 108, 60, 92, 68, 32)
		"jungle_planks":           _planks(img, rng, 168, 118, 66, 130, 90, 46)
		"jungle_leaves":           _leaves(img, rng, 28, 95, 14)
		"acacia_log":              _log_side(img, rng, 168, 100, 50, 110, 64, 22)
		"acacia_log_top":          _log_top(img, rng, 188, 120, 60, 130, 80, 30)
		"acacia_planks":           _planks(img, rng, 186, 112, 56, 152, 88, 36)
		"acacia_leaves":           _leaves(img, rng, 50, 88, 18)
		"dark_oak_log":            _log_side(img, rng, 66, 43, 20, 44, 28, 10)
		"dark_oak_log_top":        _log_top(img, rng, 85, 60, 32, 55, 36, 14)
		"dark_oak_planks":         _planks(img, rng, 104, 68, 36, 78, 50, 22)
		"dark_oak_leaves":         _leaves(img, rng, 20, 48, 8)
		"mangrove_log":            _log_side(img, rng, 102, 56, 38, 70, 36, 20)
		"mangrove_log_top":        _log_top(img, rng, 118, 72, 48, 80, 46, 26)
		"mangrove_planks":         _planks(img, rng, 140, 78, 52, 108, 58, 32)
		"mangrove_leaves":         _leaves(img, rng, 30, 72, 16)
		"cherry_log":              _log_side(img, rng, 198, 148, 128, 148, 108, 90)
		"cherry_log_top":          _log_top(img, rng, 218, 168, 140, 168, 118, 92)
		"cherry_planks":           _planks(img, rng, 232, 184, 166, 196, 146, 128)
		"cherry_leaves":           _cherry_leaves(img, rng)
		"pale_oak_log":            _log_side(img, rng, 228, 220, 212, 188, 180, 172)
		"pale_oak_log_top":        _log_top(img, rng, 242, 238, 228, 200, 196, 186)
		"pale_oak_planks":         _planks(img, rng, 238, 232, 218, 200, 194, 180)
		"pale_oak_leaves":         _leaves(img, rng, 190, 200, 180)
		# Fluids & special
		"water":                   _water(img, rng)
		"lava":                    _lava(img, rng)
		"glass":                   _glass(img, rng)
		"glowstone":               _glowstone(img, rng)
		"shroomlight":             _noise_fill(img, rng, 238, 170, 66, 18, 255)
		"sea_lantern":             _sea_lantern(img, rng)
		# Nether
		"netherrack":              _noise_fill(img, rng, 122, 18, 18, 16, 255)
		"soul_sand":               _noise_fill(img, rng, 80, 60, 42, 12, 255)
		"soul_soil":               _noise_fill(img, rng, 88, 70, 52, 10, 255)
		"magma_block":             _magma(img, rng)
		"obsidian":                _noise_fill(img, rng, 22, 14, 30, 6, 255)
		"crying_obsidian":         _crying_obsidian(img, rng)
		"ancient_debris_side":     _noise_fill(img, rng, 98, 72, 58, 10, 255)
		"ancient_debris_top":      _noise_fill(img, rng, 130, 98, 76, 12, 255)
		"nether_quartz_ore":       _nether_ore(img, rng, 240, 234, 220)
		"quartz_block_side":       _noise_fill(img, rng, 236, 228, 210, 8, 255)
		"nether_bricks":           _stone_bricks_col(img, rng, 52, 8, 8, 38, 4, 4)
		"blackstone":              _noise_fill(img, rng, 28, 20, 32, 8, 255)
		"blackstone_top":          _deepslate_top(img, rng)
		"basalt_side":             _basalt_side(img, rng)
		"basalt_top":              _basalt_top(img, rng)
		"polished_basalt_side":    _noise_fill(img, rng, 82, 82, 88, 8, 255)
		# End
		"end_stone":               _noise_fill(img, rng, 220, 216, 140, 10, 255)
		"end_stone_bricks":        _stone_bricks_col(img, rng, 220, 216, 140, 188, 184, 110)
		"purpur_block":            _noise_fill(img, rng, 168, 112, 168, 14, 255)
		# Ores
		"coal_ore":                _ore(img, rng, false, 28, 24, 24)
		"iron_ore":                _ore(img, rng, false, 200, 152, 120)
		"gold_ore":                _ore(img, rng, false, 252, 212, 40)
		"diamond_ore":             _ore(img, rng, false, 80, 230, 252)
		"redstone_ore":            _ore(img, rng, false, 210, 24, 24)
		"lapis_ore":               _ore(img, rng, false, 38, 70, 200)
		"emerald_ore":             _ore(img, rng, false, 36, 200, 72)
		"copper_ore":              _ore(img, rng, false, 168, 118, 68)
		"deepslate_coal_ore":      _ore(img, rng, true, 28, 24, 24)
		"deepslate_iron_ore":      _ore(img, rng, true, 200, 152, 120)
		"deepslate_gold_ore":      _ore(img, rng, true, 252, 212, 40)
		"deepslate_diamond_ore":   _ore(img, rng, true, 80, 230, 252)
		"deepslate_redstone_ore":  _ore(img, rng, true, 210, 24, 24)
		"deepslate_lapis_ore":     _ore(img, rng, true, 38, 70, 200)
		"deepslate_emerald_ore":   _ore(img, rng, true, 36, 200, 72)
		"deepslate_copper_ore":    _ore(img, rng, true, 168, 118, 68)
		# Metal/gem blocks
		"iron_block":              _metal_block(img, rng, 212, 212, 212)
		"gold_block":              _metal_block(img, rng, 252, 210, 40)
		"diamond_block":           _metal_block(img, rng, 90, 220, 240)
		"emerald_block":           _metal_block(img, rng, 46, 200, 80)
		"lapis_block":             _metal_block(img, rng, 44, 80, 196)
		"redstone_block":          _metal_block(img, rng, 200, 24, 24)
		"coal_block":              _metal_block(img, rng, 22, 22, 22)
		"copper_block":            _metal_block(img, rng, 196, 118, 62)
		"netherite_block":         _metal_block(img, rng, 60, 52, 60)
		"amethyst_block":          _metal_block(img, rng, 154, 92, 220)
		# Crafting surfaces
		"crafting_table_top":      _crafting_table_top(img, rng)
		"crafting_table_side":     _crafting_table_side(img, rng)
		"furnace_front":           _furnace_front(img, rng)
		"furnace_side":            _furnace_side(img, rng)
		"furnace_top":             _furnace_top(img, rng)
		# Raw metal blocks
		"raw_iron_block":          _noise_fill(img, rng, 188, 142, 110, 16, 255)
		"raw_copper_block":        _noise_fill(img, rng, 178, 108, 58, 16, 255)
		# New biome surface blocks
		"snow_block":              _noise_fill(img, rng, 248, 250, 252, 6, 255)
		"orange_terracotta":       _noise_fill(img, rng, 196, 112, 58, 14, 255)
		# Bed (compact half-block)
		"bed_top":                 _bed_top(img, rng)
		"bed_side":                _bed_side(img, rng)
		# End portal surface (dark void with sparkles)
		"end_portal_block":        _end_portal(img, rng)
		_:                         _missing(img)


# ── Drawing primitives ─────────────────────────────────────────────────────────

func _noise_fill(img: Image, rng: RandomNumberGenerator,
		r: int, g: int, b: int, v: int, a: int = 255) -> void:
	for y in T:
		for x in T:
			var dr := rng.randi_range(-v, v)
			img.set_pixel(x, y, Color8(
				clampi(r + dr,             0, 255),
				clampi(g + rng.randi_range(-v, v), 0, 255),
				clampi(b + dr,             0, 255), a))


func _missing(img: Image) -> void:
	for y in T:
		for x in T:
			img.set_pixel(x, y, Color8(255, 0, 255) if (x + y) % 2 == 0 else Color8(0, 0, 0))


# ── Terrain ────────────────────────────────────────────────────────────────────

func _grass_top(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			var v := rng.randi_range(-12, 12)
			img.set_pixel(x, y, Color8(clampi(52 + v, 0, 255), clampi(108 + v, 0, 255), clampi(28 + v, 0, 255)))


func _grass_side(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			if y < 3:
				var v := rng.randi_range(-12, 12)
				img.set_pixel(x, y, Color8(clampi(52 + v, 0, 255), clampi(108 + v, 0, 255), clampi(28 + v, 0, 255)))
			elif y == 3:
				img.set_pixel(x, y, Color8(68, 52, 28))
			else:
				var v := rng.randi_range(-14, 14)
				img.set_pixel(x, y, Color8(clampi(139 + v, 0, 255), clampi(94 + v / 2, 0, 255), clampi(60 + v / 2, 0, 255)))


func _stone(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			var v := rng.randi_range(-14, 14)
			img.set_pixel(x, y, Color8(clampi(130 + v, 0, 255), clampi(130 + v, 0, 255), clampi(130 + v, 0, 255)))
	# subtle crack lines
	var cx := rng.randi_range(2, 13)
	var cy := rng.randi_range(2, 10)
	for i in rng.randi_range(3, 6):
		var px := clampi(cx + rng.randi_range(-1, 1), 0, 15)
		var py := clampi(cy + i, 0, 15)
		img.set_pixel(px, py, Color8(90, 90, 90))


func _cobblestone(img: Image, rng: RandomNumberGenerator) -> void:
	# Fill with medium gray base
	for y in T:
		for x in T:
			img.set_pixel(x, y, Color8(120, 120, 120))
	# Draw "rock" outlines
	var rocks := [[2,2,4,3],[7,1,5,4],[1,7,4,3],[7,6,5,3],[12,2,3,4],[11,8,4,3]]
	for rock in rocks:
		var rx: int = rock[0]; var ry: int = rock[1]
		var rw: int = rock[2]; var rh: int = rock[3]
		var v := rng.randi_range(-10, 10)
		for dy in rh:
			for dx in rw:
				var bx := rx + dx; var by := ry + dy
				if bx < T and by < T:
					var edge := (dx == 0 or dx == rw-1 or dy == 0 or dy == rh-1)
					if edge:
						img.set_pixel(bx, by, Color8(82, 82, 82))
					else:
						img.set_pixel(bx, by, Color8(clampi(138 + v, 0, 255), clampi(138 + v, 0, 255), clampi(138 + v, 0, 255)))


func _gravel(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			var v := rng.randi_range(-20, 20)
			img.set_pixel(x, y, Color8(clampi(128 + v, 0, 255), clampi(122 + v, 0, 255), clampi(112 + v, 0, 255)))
	# pebble dots
	for _i in 8:
		var px := rng.randi_range(1, 14); var py := rng.randi_range(1, 14)
		var br := rng.randi_range(20, 40)
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if abs(dx) + abs(dy) < 2:
					var c := img.get_pixel(clampi(px+dx,0,15), clampi(py+dy,0,15))
					img.set_pixel(clampi(px+dx,0,15), clampi(py+dy,0,15), Color8(
						clampi(int(c.r8) + br, 0, 255), clampi(int(c.g8) + br, 0, 255), clampi(int(c.b8) + br, 0, 255)))


func _bedrock(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			var v := rng.randi_range(0, 30)
			img.set_pixel(x, y, Color8(v, v, v))


func _deepslate(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			var v := rng.randi_range(-10, 10)
			# Slightly horizontal layering
			var layer_v := int(sin(y * 0.9) * 6.0)
			img.set_pixel(x, y, Color8(
				clampi(72 + v + layer_v, 0, 255),
				clampi(72 + v + layer_v, 0, 255),
				clampi(82 + v + layer_v, 0, 255)))
	# cracks
	for _i in 2:
		var cx := rng.randi_range(1, 14); var cy := rng.randi_range(1, 12)
		for j in rng.randi_range(2, 5):
			img.set_pixel(clampi(cx + rng.randi_range(-1, 1), 0, 15), clampi(cy + j, 0, 15), Color8(42, 42, 50))


func _deepslate_top(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			var cx_f := float(x) - 7.5; var cy_f := float(y) - 7.5
			var dist := sqrt(cx_f*cx_f + cy_f*cy_f)
			var ring_v := int(sin(dist * 0.9) * 8.0)
			var v := rng.randi_range(-8, 8)
			img.set_pixel(x, y, Color8(
				clampi(72 + v + ring_v, 0, 255),
				clampi(72 + v + ring_v, 0, 255),
				clampi(82 + v + ring_v, 0, 255)))


func _podzol_top(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			var v := rng.randi_range(-14, 14)
			img.set_pixel(x, y, Color8(clampi(148 + v, 0, 255), clampi(96 + v, 0, 255), clampi(44 + v, 0, 255)))


func _podzol_side(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			if y < 2:
				var v := rng.randi_range(-14, 14)
				img.set_pixel(x, y, Color8(clampi(148 + v, 0, 255), clampi(96 + v, 0, 255), clampi(44 + v, 0, 255)))
			else:
				var v := rng.randi_range(-14, 14)
				img.set_pixel(x, y, Color8(clampi(139 + v, 0, 255), clampi(94 + v / 2, 0, 255), clampi(60 + v / 2, 0, 255)))


func _mycelium_top(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			var v := rng.randi_range(-14, 14)
			# Mix of gray and purplish
			img.set_pixel(x, y, Color8(clampi(156 + v, 0, 255), clampi(134 + v, 0, 255), clampi(158 + v, 0, 255)))


func _mycelium_side(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			if y < 2:
				var v := rng.randi_range(-14, 14)
				img.set_pixel(x, y, Color8(clampi(156 + v, 0, 255), clampi(134 + v, 0, 255), clampi(158 + v, 0, 255)))
			else:
				var v := rng.randi_range(-14, 14)
				img.set_pixel(x, y, Color8(clampi(139 + v, 0, 255), clampi(94 + v / 2, 0, 255), clampi(60 + v / 2, 0, 255)))


# ── Stone bricks variants ──────────────────────────────────────────────────────

func _stone_bricks(img: Image, rng: RandomNumberGenerator) -> void:
	_stone_bricks_col(img, rng, 128, 128, 128, 96, 96, 96)


func _stone_bricks_col(img: Image, rng: RandomNumberGenerator,
		br: int, bg: int, bb: int, lr: int, lg: int, lb: int) -> void:
	for y in T:
		for x in T:
			# Brick pattern: 8-wide, 4-tall bricks with 1px mortar
			var in_mortar_x := (x % 8 == 0)
			var row_y := y % 4
			var offset_x := (y / 4 % 2) * 4
			var in_mortar_v := (row_y == 0)
			var in_mortar := in_mortar_v or ((x + offset_x) % 8 == 0)
			if in_mortar:
				img.set_pixel(x, y, Color8(lr, lg, lb))
			else:
				var v := rng.randi_range(-10, 10)
				img.set_pixel(x, y, Color8(clampi(br + v, 0, 255), clampi(bg + v, 0, 255), clampi(bb + v, 0, 255)))


func _mossy_stone_bricks(img: Image, rng: RandomNumberGenerator) -> void:
	_stone_bricks(img, rng)
	# Add green moss patches
	for _i in 6:
		var px := rng.randi_range(0, 14); var py := rng.randi_range(0, 14)
		var size := rng.randi_range(1, 3)
		for dy in size:
			for dx in size:
				if rng.randf() > 0.3:
					img.set_pixel(clampi(px+dx, 0, 15), clampi(py+dy, 0, 15), Color8(
						rng.randi_range(50, 90), rng.randi_range(100, 140), rng.randi_range(30, 60)))


func _cracked_stone_bricks(img: Image, rng: RandomNumberGenerator) -> void:
	_stone_bricks(img, rng)
	# Large cracks
	for _i in 4:
		var cx := rng.randi_range(2, 12); var cy := rng.randi_range(1, 12)
		for j in rng.randi_range(3, 7):
			var px := clampi(cx + rng.randi_range(-1, 1), 0, 15)
			var py := clampi(cy + j, 0, 15)
			img.set_pixel(px, py, Color8(50, 50, 50))


func _chiseled_stone_bricks(img: Image, rng: RandomNumberGenerator) -> void:
	_stone(img, rng)
	# Centered flower/cross pattern
	for y in T:
		for x in T:
			var cx_f := float(x) - 7.5; var cy_f := float(y) - 7.5
			var dist := sqrt(cx_f*cx_f + cy_f*cy_f)
			if dist < 3.0:
				img.set_pixel(x, y, Color8(90, 90, 90))
			elif dist < 3.5:
				img.set_pixel(x, y, Color8(160, 160, 160))


# ── Wood textures ──────────────────────────────────────────────────────────────

func _log_side(img: Image, rng: RandomNumberGenerator,
		br: int, bg: int, bb: int, dr: int, dg: int, db: int) -> void:
	# Base fill
	for y in T:
		for x in T:
			var v := rng.randi_range(-8, 8)
			img.set_pixel(x, y, Color8(clampi(br + v, 0, 255), clampi(bg + v, 0, 255), clampi(bb + v, 0, 255)))
	# Vertical grain lines
	for i in 4:
		var gx := rng.randi_range(1, 14)
		for y in T:
			if rng.randf() > 0.2:
				img.set_pixel(gx, y, Color8(dr, dg, db))
	# Bark edges darker
	for y in T:
		img.set_pixel(0, y, Color8(dr, dg, db))
		img.set_pixel(15, y, Color8(dr, dg, db))


func _log_top(img: Image, rng: RandomNumberGenerator,
		br: int, bg: int, bb: int, dr: int, dg: int, db: int) -> void:
	# Fill base
	for y in T:
		for x in T:
			var v := rng.randi_range(-8, 8)
			img.set_pixel(x, y, Color8(clampi(br + v, 0, 255), clampi(bg + v, 0, 255), clampi(bb + v, 0, 255)))
	# Concentric rings
	for y in T:
		for x in T:
			var cx_f := float(x) - 7.5; var cy_f := float(y) - 7.5
			var dist := sqrt(cx_f*cx_f + cy_f*cy_f)
			var ring := int(dist * 1.4) % 2
			if ring == 1:
				var c := img.get_pixel(x, y)
				img.set_pixel(x, y, Color8(
					clampi(int(c.r8) - 30, 0, 255),
					clampi(int(c.g8) - 20, 0, 255),
					clampi(int(c.b8) - 15, 0, 255)))
	# Dark outer ring
	for y in T:
		for x in T:
			var cx_f := float(x) - 7.5; var cy_f := float(y) - 7.5
			var dist := sqrt(cx_f*cx_f + cy_f*cy_f)
			if dist > 6.8:
				img.set_pixel(x, y, Color8(dr, dg, db))


func _birch_log_side(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			var v := rng.randi_range(-10, 10)
			img.set_pixel(x, y, Color8(clampi(228 + v, 0, 255), clampi(224 + v, 0, 255), clampi(192 + v, 0, 255)))
	# Black knot marks
	for _i in 3:
		var ky := rng.randi_range(2, 13)
		var kw := rng.randi_range(2, 5)
		var kx := rng.randi_range(2, T - kw - 2)
		for dy in 2:
			for dx in kw:
				img.set_pixel(clampi(kx + dx, 0, 15), clampi(ky + dy, 0, 15), Color8(30, 28, 22))
	# Dark horizontal grain lines
	for _i in 3:
		var ly := rng.randi_range(1, 14)
		for x in T:
			if rng.randf() > 0.3:
				img.set_pixel(x, ly, Color8(180, 176, 148))


func _planks(img: Image, rng: RandomNumberGenerator,
		br: int, bg: int, bb: int, lr: int, lg: int, lb: int) -> void:
	for y in T:
		for x in T:
			var plank_line := (y % 4 == 0) or (y % 4 == 3 and rng.randf() > 0.7)
			if plank_line:
				img.set_pixel(x, y, Color8(lr, lg, lb))
			else:
				var v := rng.randi_range(-12, 12)
				img.set_pixel(x, y, Color8(clampi(br + v, 0, 255), clampi(bg + v, 0, 255), clampi(bb + v, 0, 255)))
	# Knot in a random plank
	var kx := rng.randi_range(2, 12); var ky := (rng.randi_range(0, 3) * 4) + 1
	img.set_pixel(kx, clampi(ky, 0, 15), Color8(lr, lg, lb))
	img.set_pixel(clampi(kx+1, 0, 15), clampi(ky, 0, 15), Color8(lr, lg, lb))


func _leaves(img: Image, rng: RandomNumberGenerator, r: int, g: int, b: int) -> void:
	for y in T:
		for x in T:
			var t := rng.randf()
			if t < 0.10:
				img.set_pixel(x, y, Color8(0, 0, 0, 0))  # transparent gap
			else:
				var v := rng.randi_range(-12, 12)
				# Three tones: deep shadow, mid, highlight — gives volumetric feel
				var mul: float
				if t < 0.30:
					mul = 0.55   # deep shadow cluster
				elif t < 0.65:
					mul = 0.80   # mid tone
				else:
					mul = 1.0    # sunlit tip
				img.set_pixel(x, y, Color8(
					clampi(int(r * mul) + v, 0, 255),
					clampi(int(g * mul) + v, 0, 255),
					clampi(int(b * mul) + v, 0, 255)))


func _cherry_leaves(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			var t := rng.randf()
			if t < 0.06:
				img.set_pixel(x, y, Color8(0, 0, 0, 0))
			else:
				var v := rng.randi_range(-20, 20)
				img.set_pixel(x, y, Color8(
					clampi(234 + v, 0, 255), clampi(160 + v, 0, 255), clampi(178 + v, 0, 255)))


# ── Fluids & special ───────────────────────────────────────────────────────────

func _water(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			var wave := int(sin((x + y * 0.5) * 0.8) * 12.0)
			var v    := rng.randi_range(-8, 8)
			img.set_pixel(x, y, Color8(
				clampi(30 + v, 0, 255), clampi(80 + wave + v, 0, 255), clampi(200 + v, 0, 255), 200))


func _lava(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			var heat := rng.randi_range(0, 80)
			if heat > 60:
				img.set_pixel(x, y, Color8(clampi(255, 0, 255), clampi(200 + heat - 60, 0, 255), 0))
			elif heat > 20:
				img.set_pixel(x, y, Color8(220, clampi(60 + heat, 0, 255), 0))
			else:
				img.set_pixel(x, y, Color8(30, 8, 0))


func _glass(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			var edge := (x == 0 or x == 15 or y == 0 or y == 15)
			var corner := (x <= 1 and y <= 1) or (x >= 14 and y <= 1) or (x <= 1 and y >= 14) or (x >= 14 and y >= 14)
			if corner:
				img.set_pixel(x, y, Color8(0, 0, 0, 0))
			elif edge:
				img.set_pixel(x, y, Color8(188, 220, 248, 200))
			else:
				var v := rng.randi_range(0, 10)
				img.set_pixel(x, y, Color8(clampi(168 + v, 0, 255), clampi(210 + v, 0, 255), clampi(248, 0, 255), 30))


func _glowstone(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			var v := rng.randi_range(-18, 18)
			img.set_pixel(x, y, Color8(clampi(200 + v, 0, 255), clampi(148 + v, 0, 255), clampi(40 + v, 0, 255)))
	# Bright crystal spots
	for _i in 6:
		var cx := rng.randi_range(1, 14); var cy := rng.randi_range(1, 14)
		var bright := rng.randi_range(40, 60)
		img.set_pixel(cx, cy, Color8(clampi(248 + bright, 0, 255), clampi(220 + bright, 0, 255), clampi(80 + bright, 0, 255)))
		img.set_pixel(clampi(cx-1, 0, 15), cy, Color8(230, 180, 60))
		img.set_pixel(cx, clampi(cy-1, 0, 15), Color8(230, 180, 60))


func _sea_lantern(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			var cx_f := float(x) - 7.5; var cy_f := float(y) - 7.5
			var dist := sqrt(cx_f*cx_f + cy_f*cy_f)
			var v := rng.randi_range(-10, 10)
			if dist < 4.0:
				img.set_pixel(x, y, Color8(clampi(200 + v, 0, 255), clampi(240 + v, 0, 255), clampi(220 + v, 0, 255)))
			else:
				img.set_pixel(x, y, Color8(clampi(140 + v, 0, 255), clampi(180 + v, 0, 255), clampi(160 + v, 0, 255)))


func _magma(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			var v := rng.randi_range(-12, 12)
			img.set_pixel(x, y, Color8(clampi(100 + v, 0, 255), clampi(28 + v, 0, 255), clampi(8 + v, 0, 255)))
	# Glowing cracks
	for _i in 5:
		var cx := rng.randi_range(1, 13); var cy := rng.randi_range(1, 13)
		for j in rng.randi_range(2, 5):
			var px := clampi(cx + rng.randi_range(-1, 1), 0, 15)
			var py := clampi(cy + j, 0, 15)
			img.set_pixel(px, py, Color8(255, 140, 0))


func _crying_obsidian(img: Image, rng: RandomNumberGenerator) -> void:
	_noise_fill(img, rng, 22, 14, 30, 6)
	# Purple drips
	for x in [3, 7, 12]:
		for dy in rng.randi_range(3, 8):
			var py := clampi(dy + 2, 0, 15)
			img.set_pixel(x, py, Color8(140, 30, 200))
			img.set_pixel(clampi(x-1, 0, 15), py, Color8(100, 20, 160))


# ── Nether/special blocks ──────────────────────────────────────────────────────

func _basalt_side(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			var v := rng.randi_range(-8, 8)
			# Slightly blue-gray with horizontal banding
			var band := int(sin(y * 0.6) * 6.0)
			img.set_pixel(x, y, Color8(
				clampi(70 + v + band, 0, 255), clampi(72 + v + band, 0, 255), clampi(78 + v + band, 0, 255)))


func _basalt_top(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			var v := rng.randi_range(-10, 10)
			img.set_pixel(x, y, Color8(clampi(80 + v, 0, 255), clampi(82 + v, 0, 255), clampi(88 + v, 0, 255)))


func _nether_ore(img: Image, rng: RandomNumberGenerator, or_: int, og: int, ob: int) -> void:
	_noise_fill(img, rng, 122, 18, 18, 16)
	_ore_blobs(img, rng, or_, og, ob)


# ── Ores ───────────────────────────────────────────────────────────────────────

func _ore(img: Image, rng: RandomNumberGenerator, deep: bool, or_: int, og: int, ob: int) -> void:
	if deep:
		_deepslate(img, rng)
	else:
		_stone(img, rng)
	_ore_blobs(img, rng, or_, og, ob)


func _ore_blobs(img: Image, rng: RandomNumberGenerator, or_: int, og: int, ob: int) -> void:
	var num := rng.randi_range(3, 5)
	for _b in num:
		var cx := rng.randi_range(2, 13)
		var cy := rng.randi_range(2, 13)
		var pts := rng.randi_range(4, 7)
		for _p in pts:
			var px := clampi(cx + rng.randi_range(-2, 2), 0, 15)
			var py := clampi(cy + rng.randi_range(-1, 1), 0, 15)
			var br := rng.randi_range(-20, 20)
			img.set_pixel(px, py, Color8(
				clampi(or_ + br, 0, 255), clampi(og + br, 0, 255), clampi(ob + br, 0, 255)))
		# Outline pixels slightly darker
		img.set_pixel(clampi(cx - 2, 0, 15), cy, Color8(
			clampi(or_ - 30, 0, 255), clampi(og - 30, 0, 255), clampi(ob - 30, 0, 255)))
		img.set_pixel(clampi(cx + 2, 0, 15), cy, Color8(
			clampi(or_ - 30, 0, 255), clampi(og - 30, 0, 255), clampi(ob - 30, 0, 255)))


# ── Metal/gem blocks ───────────────────────────────────────────────────────────

func _metal_block(img: Image, rng: RandomNumberGenerator, r: int, g: int, b: int) -> void:
	for y in T:
		for x in T:
			var v := rng.randi_range(-8, 8)
			img.set_pixel(x, y, Color8(clampi(r + v, 0, 255), clampi(g + v, 0, 255), clampi(b + v, 0, 255)))
	# Subtle cross-hatch highlight
	for i in T:
		var cx := img.get_pixel(i, i)
		img.set_pixel(i, i, Color8(
			clampi(int(cx.r8) + 20, 0, 255), clampi(int(cx.g8) + 20, 0, 255), clampi(int(cx.b8) + 20, 0, 255)))


# ── Crafting/functional blocks ─────────────────────────────────────────────────

func _crafting_table_top(img: Image, rng: RandomNumberGenerator) -> void:
	_planks(img, rng, 197, 160, 102, 155, 124, 74)
	# Grid lines for crafting grid (3×3)
	for i in [4, 8, 12]:
		for j in T:
			img.set_pixel(i, j, Color8(80, 55, 25))
			img.set_pixel(j, i, Color8(80, 55, 25))


func _crafting_table_side(img: Image, rng: RandomNumberGenerator) -> void:
	_planks(img, rng, 197, 160, 102, 155, 124, 74)
	# 2 horizontal shelf lines
	for x in T:
		img.set_pixel(x, 4, Color8(80, 55, 25))
		img.set_pixel(x, 12, Color8(80, 55, 25))


func _furnace_front(img: Image, rng: RandomNumberGenerator) -> void:
	_stone(img, rng)
	# Mouth of furnace (dark rectangle center)
	for y in range(4, 13):
		for x in range(3, 13):
			if y >= 5 and y <= 11 and x >= 4 and x <= 11:
				if y == 5 or y == 11 or x == 4 or x == 11:
					img.set_pixel(x, y, Color8(30, 28, 26))
				else:
					# Glow inside
					var gv := rng.randi_range(0, 30)
					img.set_pixel(x, y, Color8(clampi(180 + gv, 0, 255), clampi(80 + gv, 0, 255), 0))


func _furnace_side(img: Image, rng: RandomNumberGenerator) -> void:
	# Stone base slightly darker than regular stone
	for y in T:
		for x in T:
			var v := rng.randi_range(-10, 10)
			var base := 112
			img.set_pixel(x, y, Color8(clampi(base + v, 0, 255), clampi(base + v, 0, 255), clampi(base + v, 0, 255)))
	# Outer border frame (dark edge)
	for i in T:
		img.set_pixel(i, 0, Color8(70, 70, 70))
		img.set_pixel(i, 15, Color8(70, 70, 70))
		img.set_pixel(0, i, Color8(70, 70, 70))
		img.set_pixel(15, i, Color8(70, 70, 70))


func _bed_top(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			var v := rng.randi_range(-8, 8)
			if y < 5:
				# White pillow end
				img.set_pixel(x, y, Color8(clampi(235 + v, 0, 255), clampi(235 + v, 0, 255), clampi(238 + v, 0, 255)))
			else:
				# Red blanket
				img.set_pixel(x, y, Color8(clampi(165 + v, 0, 255), clampi(38 + v / 2, 0, 255), clampi(38 + v / 2, 0, 255)))
	# Blanket fold line
	for x in T:
		img.set_pixel(x, 5, Color8(120, 24, 24))
	# Pillow shading
	for x in T:
		img.set_pixel(x, 0, Color8(205, 205, 210))


func _bed_side(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			var v := rng.randi_range(-8, 8)
			if y < 6:
				img.set_pixel(x, y, Color8(clampi(150 + v, 0, 255), clampi(34 + v / 2, 0, 255), clampi(34 + v / 2, 0, 255)))
			else:
				# Wooden frame
				img.set_pixel(x, y, Color8(clampi(140 + v, 0, 255), clampi(102 + v, 0, 255), clampi(60 + v, 0, 255)))
	for x in T:
		img.set_pixel(x, 6, Color8(90, 60, 30))


func _end_portal(img: Image, rng: RandomNumberGenerator) -> void:
	for y in T:
		for x in T:
			var v := rng.randi_range(0, 14)
			img.set_pixel(x, y, Color8(4 + v / 3, 6 + v / 2, 12 + v))
	# Star sparkles
	for _i in 8:
		var px := rng.randi_range(0, 15)
		var py := rng.randi_range(0, 15)
		var c: Color = [Color8(120, 240, 190), Color8(90, 160, 230), Color8(230, 230, 160)][rng.randi_range(0, 2)]
		img.set_pixel(px, py, c)


func _furnace_top(img: Image, rng: RandomNumberGenerator) -> void:
	_stone(img, rng)
	# Small square vent opening in center
	for y in range(5, 11):
		for x in range(5, 11):
			if y == 5 or y == 10 or x == 5 or x == 10:
				img.set_pixel(x, y, Color8(70, 68, 66))
			else:
				img.set_pixel(x, y, Color8(28, 26, 24))
