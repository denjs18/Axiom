## ItemIcon.gd — Displays an item icon using real PNG textures from assets/textures/.
## Looks in items/ first, then blocks/. Falls back to a colored placeholder if missing.
class_name ItemIcon
extends Control

var item_id: String = "" :
	set(v):
		item_id = v
		_update()

var _tex_rect: TextureRect = null
var _fallback: ColorRect   = null

# Session cache: full item id → Texture2D or null
static var _cache: Dictionary = {}


func _ready() -> void:
	_tex_rect = TextureRect.new()
	_tex_rect.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
	_tex_rect.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tex_rect.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	add_child(_tex_rect)

	_fallback = ColorRect.new()
	_fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fallback.visible      = false
	add_child(_fallback)

	_update()


func _update() -> void:
	if _tex_rect == null:
		return
	if item_id.is_empty():
		_tex_rect.texture  = null
		_fallback.visible  = false
		return

	var tex := _resolve(item_id)
	if tex != null:
		_tex_rect.texture = tex
		_fallback.visible = false
	else:
		_tex_rect.texture  = null
		_fallback.color    = _fallback_color(item_id)
		_fallback.visible  = true


static func _resolve(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]

	# Determine texture name from ItemRegistry, else derive from id
	var item := ItemRegistry.get_item(id)
	var tex_name: String = item.texture if item and item.texture != "" else ""
	if tex_name.is_empty():
		tex_name = id.split(":")[-1] if ":" in id else id

	# Search order: items/ → blocks/
	var candidates := [
		"res://assets/textures/items/%s.png"  % tex_name,
		"res://assets/textures/blocks/%s.png" % tex_name,
		# Some block faces have _top or _side suffix — try the plain name too
		"res://assets/textures/blocks/%s_top.png" % tex_name,
	]

	var tex: Texture2D = null
	for path in candidates:
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
			if tex != null:
				break

	_cache[id] = tex
	return tex


## Simple color fallback when no texture exists (based on item name hash)
static func _fallback_color(id: String) -> Color:
	var short := id.split(":")[-1] if ":" in id else id
	match short:
		"grass_block": return Color(0.30, 0.70, 0.20)
		"dirt":        return Color(0.55, 0.35, 0.20)
		"stone":       return Color(0.62, 0.62, 0.62)
		"cobblestone": return Color(0.50, 0.50, 0.50)
		"sand":        return Color(0.92, 0.87, 0.60)
		"gravel":      return Color(0.55, 0.52, 0.50)
		"coal":        return Color(0.18, 0.18, 0.20)
		"iron_ingot":  return Color(0.85, 0.85, 0.92)
		"gold_ingot":  return Color(1.00, 0.82, 0.12)
		"diamond":     return Color(0.22, 0.88, 0.96)
		"emerald":     return Color(0.18, 0.82, 0.38)
	var h := short.hash()
	return Color(
		0.35 + (h & 0xFF) / 510.0,
		0.35 + ((h >> 8) & 0xFF) / 510.0,
		0.35 + ((h >> 16) & 0xFF) / 510.0
	)
