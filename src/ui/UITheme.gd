## UITheme.gd — Modern design system for all Axiom interfaces.
## Central place for colors, style boxes and a project-wide Theme resource.
## Design language: dark "glass" panels, soft rounded corners, one warm accent.
class_name UITheme
extends RefCounted

# ── Palette ────────────────────────────────────────────────────────────────────
const BG_DEEP      := Color(0.055, 0.065, 0.090)          # page background
const PANEL        := Color(0.090, 0.100, 0.130, 0.965)   # card / modal
const PANEL_SOFT   := Color(0.120, 0.132, 0.168, 0.940)   # nested panel
const SLOT         := Color(0.055, 0.060, 0.080, 0.900)   # item slot well
const SLOT_HOVER   := Color(0.180, 0.200, 0.260, 0.950)
const BORDER       := Color(0.285, 0.310, 0.380, 0.550)
const BORDER_SOFT  := Color(0.240, 0.260, 0.320, 0.350)

const ACCENT       := Color(0.400, 0.720, 0.420)          # herb green — "alive" accent
const ACCENT_DEEP  := Color(0.270, 0.560, 0.310)
const GOLD         := Color(0.930, 0.760, 0.320)
const DANGER       := Color(0.870, 0.280, 0.250)
const INFO         := Color(0.420, 0.640, 0.940)

const TEXT         := Color(0.940, 0.945, 0.960)
const TEXT_DIM     := Color(0.640, 0.665, 0.720)
const TEXT_FAINT   := Color(0.430, 0.455, 0.510)

static var _theme: Theme = null


# ── StyleBox factories ─────────────────────────────────────────────────────────

static func flat(bg: Color, radius: int = 10, border: Color = Color.TRANSPARENT,
		border_w: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if border_w > 0:
		s.set_border_width_all(border_w)
		s.border_color = border
	return s


## Main modal card: dark glass + hairline border + soft shadow.
static func card(radius: int = 14) -> StyleBoxFlat:
	var s := flat(PANEL, radius, BORDER, 1)
	s.shadow_color  = Color(0, 0, 0, 0.45)
	s.shadow_size   = 24
	s.shadow_offset = Vector2(0, 6)
	s.set_content_margin_all(0)
	return s


static func slot_style(hovered: bool = false, radius: int = 8) -> StyleBoxFlat:
	var s := flat(SLOT_HOVER if hovered else SLOT, radius,
		ACCENT if hovered else BORDER_SOFT, 1)
	return s


# ── Project-wide Theme ─────────────────────────────────────────────────────────

## Build (once) the shared Theme applied to the root window.
static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()

	# Buttons — pill-ish, clear hover/press states
	var btn_n := flat(Color(0.150, 0.165, 0.210, 0.960), 10, BORDER_SOFT, 1)
	btn_n.set_content_margin_all(10)
	btn_n.content_margin_left = 18; btn_n.content_margin_right = 18
	var btn_h := flat(Color(0.205, 0.225, 0.285, 0.980), 10, ACCENT, 1)
	btn_h.set_content_margin_all(10)
	btn_h.content_margin_left = 18; btn_h.content_margin_right = 18
	var btn_p := flat(Color(0.120, 0.130, 0.165, 1.0), 10, ACCENT_DEEP, 1)
	btn_p.set_content_margin_all(10)
	btn_p.content_margin_left = 18; btn_p.content_margin_right = 18
	var btn_d := flat(Color(0.110, 0.115, 0.140, 0.700), 10)
	btn_d.set_content_margin_all(10)
	t.set_stylebox("normal",   "Button", btn_n)
	t.set_stylebox("hover",    "Button", btn_h)
	t.set_stylebox("pressed",  "Button", btn_p)
	t.set_stylebox("disabled", "Button", btn_d)
	t.set_stylebox("focus",    "Button", StyleBoxEmpty.new())
	t.set_color("font_color",          "Button", TEXT)
	t.set_color("font_hover_color",    "Button", Color.WHITE)
	t.set_color("font_pressed_color",  "Button", TEXT_DIM)
	t.set_color("font_disabled_color", "Button", TEXT_FAINT)

	# Panels
	t.set_stylebox("panel", "Panel", flat(PANEL, 12, BORDER_SOFT, 1))

	# LineEdit
	var le := flat(Color(0.060, 0.066, 0.088, 0.95), 8, BORDER_SOFT, 1)
	le.set_content_margin_all(8)
	le.content_margin_left = 12; le.content_margin_right = 12
	var le_f := flat(Color(0.070, 0.078, 0.104, 0.98), 8, ACCENT, 1)
	le_f.set_content_margin_all(8)
	le_f.content_margin_left = 12; le_f.content_margin_right = 12
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus",  "LineEdit", le_f)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_FAINT)
	t.set_color("caret_color", "LineEdit", ACCENT)

	# ItemList (world list)
	var il := flat(Color(0.060, 0.066, 0.088, 0.90), 10, BORDER_SOFT, 1)
	t.set_stylebox("panel", "ItemList", il)
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	var il_sel := flat(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.22), 6, ACCENT, 1)
	t.set_stylebox("selected", "ItemList", il_sel)
	t.set_stylebox("selected_focus", "ItemList", il_sel)
	t.set_stylebox("hovered", "ItemList", flat(Color(1, 1, 1, 0.04), 6))
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_constant("v_separation", "ItemList", 6)

	# CheckBox / CheckButton text
	t.set_color("font_color", "CheckBox", TEXT_DIM)
	t.set_color("font_hover_color", "CheckBox", TEXT)
	t.set_color("font_pressed_color", "CheckBox", TEXT)

	# ProgressBar
	var pb_bg := flat(Color(0.05, 0.05, 0.07, 0.85), 6)
	var pb_fg := flat(ACCENT, 6)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fg)

	# HSeparator — hairline
	var sep := StyleBoxLine.new()
	sep.color = Color(1, 1, 1, 0.07)
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)

	# Labels default
	t.set_color("font_color", "Label", TEXT)

	# Tooltips
	var tip := flat(Color(0.05, 0.055, 0.075, 0.98), 8, BORDER, 1)
	tip.set_content_margin_all(8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)

	_theme = t
	return t


## Apply the shared theme to the whole application (call once at startup).
static func apply_to_root(node: Node) -> void:
	var window := node.get_tree().root
	if window.theme != get_theme():
		window.theme = get_theme()


# ── Small composed widgets ─────────────────────────────────────────────────────

## Heading label.
static func heading(text: String, size: int = 22, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Dim caption label.
static func caption(text: String, size: int = 11) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", TEXT_DIM)
	return l


## Big primary call-to-action button.
static func primary_button(text: String, min_size: Vector2 = Vector2(0, 52)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	var n := flat(ACCENT_DEEP, 12, ACCENT, 1)
	n.set_content_margin_all(10)
	var h := flat(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.92), 12, Color.WHITE, 1)
	h.set_content_margin_all(10)
	var p := flat(Color(0.20, 0.42, 0.24), 12, ACCENT_DEEP, 1)
	p.set_content_margin_all(10)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_font_size_override("font_size", 17)
	return b


## Danger button (quit, delete...).
static func danger_button(text: String, min_size: Vector2 = Vector2(0, 44)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	var n := flat(Color(0.28, 0.10, 0.10, 0.92), 10, Color(0.55, 0.20, 0.18), 1)
	n.set_content_margin_all(8)
	var h := flat(Color(0.42, 0.14, 0.13, 0.96), 10, DANGER, 1)
	h.set_content_margin_all(8)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(1.0, 0.82, 0.80))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	return b
