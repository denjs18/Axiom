## LodSettings.gd — LOD configuration autoload.
## Access via LodSettings.lod1_distance, LodSettings.apply_preset(), etc.
extends Node

enum Preset { LOW = 0, BALANCED = 1, HIGH = 2, ULTRA = 3 }

var preset:          int  = Preset.BALANCED
var render_distance: int  = 4    # Full voxel chunks (LOD0), in chunk units XZ
var lod1_distance:   int  = 12   # Simplified mesh tiles (LOD1), in chunk units XZ
var lod2_distance:   int  = 32   # Macro tiles 4×4 chunks (LOD2), in chunk units XZ
var lod_enabled:     bool = true
var cache_enabled:   bool = true

# LOD2 tile geometry constants — one LOD2 tile covers LOD2_CHUNKS_PER_TILE² chunks.
# Each tile is rendered as LOD2_COLS×LOD2_COLS columns, each LOD2_COL_WIDTH blocks wide.
const LOD2_CHUNKS_PER_TILE := 4
const LOD2_COLS            := 16   # Always 16 columns per tile side
const LOD2_COL_WIDTH       := 4    # Each column = 4×4 world blocks

const PRESETS: Array = [
	{"render": 4, "lod1": 8,  "lod2": 24},   # LOW
	{"render": 4, "lod1": 12, "lod2": 32},   # BALANCED
	{"render": 6, "lod1": 24, "lod2": 96},   # HIGH
	{"render": 8, "lod1": 48, "lod2": 192},  # ULTRA
]


func _ready() -> void:
	# The web export generates chunks much slower (WorkerThreadPool contention)
	# — a smaller full-voxel radius fills in far faster, and the LOD + fog
	# cover the distance.
	if OS.has_feature("web"):
		apply_preset(Preset.BALANCED)
	else:
		apply_preset(Preset.HIGH)


func apply_preset(p: int) -> void:
	preset          = p
	render_distance = PRESETS[p]["render"]
	lod1_distance   = PRESETS[p]["lod1"]
	lod2_distance   = PRESETS[p]["lod2"]
