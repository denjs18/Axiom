## DayNightCycle.gd
## Attached as a child of the World node.
## Reads TimeManager for server time + applies longitude offset for the local player,
## then updates sky colours, sun/moon DirectionalLights, ambient light and fog every frame.
##
## Renderer note: The project uses GL Compatibility, so shader_type sky is unavailable.
## We animate a ProceduralSkyMaterial instead.  Upgrading to Forward+ would allow a
## custom atmosphere shader with procedural stars and visual lunar phases.
extends Node

# ── Key sky colour anchors ─────────────────────────────────────────────────────
const _SKY_TOP_DAY     := Color(0.12, 0.30, 0.72)
const _SKY_TOP_NIGHT   := Color(0.003, 0.004, 0.018)
const _SKY_TOP_SUNSET  := Color(0.32, 0.10, 0.48)
const _SKY_TOP_BLOOD   := Color(0.20, 0.01, 0.01)   # blood moon night sky

const _SKY_HOR_DAY     := Color(0.50, 0.68, 0.92)
const _SKY_HOR_NIGHT   := Color(0.008, 0.012, 0.028)
const _SKY_HOR_SUNSET  := Color(1.00, 0.38, 0.07)
const _SKY_HOR_BLOOD   := Color(0.52, 0.04, 0.04)   # blood moon horizon

const _GND_HOR_DAY     := Color(0.30, 0.23, 0.17)
const _GND_HOR_NIGHT   := Color(0.010, 0.008, 0.006)
const _GND_BOT_DAY     := Color(0.20, 0.15, 0.10)
const _GND_BOT_NIGHT   := Color(0.004, 0.003, 0.002)

# ── References ─────────────────────────────────────────────────────────────────
var _env:      Environment
var _sky_mat:  ProceduralSkyMaterial
var _sun:      DirectionalLight3D
var _moon:     DirectionalLight3D

var _base_fog_density:  float = 0.006
var _blood_moon_blend:  float = 0.0   # 0 = normal, 1 = full red tint
var _blood_moon_target: float = 0.0   # lerp target — avoids instant snap

# ── Seasonal sky tint targets (day sky only) ───────────────────────────────────
# Each season nudges the daytime sky colour slightly.
const _SEASON_SKY_TOP: Array[Color] = [
	Color(0.10, 0.32, 0.75),   # Spring  — fresh blue
	Color(0.14, 0.33, 0.80),   # Summer  — vivid bright blue
	Color(0.14, 0.20, 0.58),   # Autumn  — muted blue-violet
	Color(0.06, 0.09, 0.42),   # Winter  — dark cold blue
]
const _SEASON_SKY_HOR: Array[Color] = [
	Color(0.48, 0.70, 0.94),   # Spring
	Color(0.54, 0.74, 0.98),   # Summer
	Color(0.52, 0.48, 0.74),   # Autumn  — warm-purple tinge
	Color(0.32, 0.40, 0.68),   # Winter  — cold grey-blue
]

var _season_idx:   int   = 0   # cached from EventBus.season_changed
var _weather_idx:  int   = 0   # cached from EventBus.weather_changed
var _weather_fog_mult:   float = 1.0
var _weather_sky_darken: float = 0.0


func _ready() -> void:
	_build_scene()
	_update(TimeManager.current_time)
	EventBus.blood_moon_started.connect(_on_blood_moon_started)
	EventBus.blood_moon_ended.connect(_on_blood_moon_ended)
	EventBus.season_changed.connect(func(s: int) -> void: _season_idx = s)
	EventBus.weather_changed.connect(_on_weather_changed)


func _on_weather_changed(w: int) -> void:
	_weather_idx = w
	_weather_fog_mult   = SeasonManager.WEATHER_FOG_MULT[w]
	_weather_sky_darken = SeasonManager.WEATHER_SKY_DARKEN[w]


func _on_blood_moon_started(_day: int) -> void:
	_blood_moon_target = 1.0


func _on_blood_moon_ended() -> void:
	_blood_moon_target = 0.0


func _process(delta: float) -> void:
	# Smooth blood moon sky transition (~4s fade in/out)
	_blood_moon_blend = move_toward(_blood_moon_blend, _blood_moon_target, delta * 0.25)
	var player := GameManager.local_player
	var t := TimeManager.get_local_time(
		player.global_position.x if player else 0.0)
	_update(t)


# ── Scene setup ────────────────────────────────────────────────────────────────

func _build_scene() -> void:
	# WorldEnvironment ─────────────────────────────────────────────────────────
	var env_node := get_parent().find_child("WorldEnvironment") as WorldEnvironment
	if env_node == null:
		env_node = WorldEnvironment.new()
		env_node.name = "WorldEnvironment"
		get_parent().add_child(env_node)

	if env_node.environment == null:
		env_node.environment = Environment.new()
	_env = env_node.environment

	# Procedural sky ───────────────────────────────────────────────────────────
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sky_curve            = 0.40
	_sky_mat.sun_angle_max        = 22.0   # tighter, more dramatic sun disc
	_sky_mat.sun_curve            = 0.08
	_sky_mat.ground_curve         = 0.02
	_sky_mat.use_debanding        = true

	var sky := Sky.new()
	sky.sky_material  = _sky_mat
	sky.process_mode  = Sky.PROCESS_MODE_REALTIME
	_env.sky          = sky
	_env.background_mode = Environment.BG_SKY
	_env.background_energy_multiplier = 0.85

	# Ambient from sky so it automatically darkens at night
	_env.ambient_light_source          = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_sky_contribution = 0.85
	_env.ambient_light_color           = Color.WHITE
	_env.ambient_light_energy          = 0.0   # will be driven each frame

	# Fog ──────────────────────────────────────────────────────────────────────
	_env.fog_enabled            = true
	_env.fog_aerial_perspective = 0.0
	_env.fog_sun_scatter        = 0.3
	_env.fog_light_energy       = 0.5
	var lod_dist := float(LodSettings.lod2_distance)
	_base_fog_density = clampf(0.04 / lod_dist, 0.0001, 0.0006)

	# Tonemapping ───────────────────────────────────────────────────────────────
	_env.tonemap_mode     = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.0
	_env.tonemap_white    = 6.0

	# Glow / bloom ──────────────────────────────────────────────────────────────
	_env.glow_enabled       = true
	_env.set_glow_level(1, 0.4)
	_env.set_glow_level(2, 0.3)
	_env.set_glow_level(3, 0.1)
	_env.glow_intensity     = 0.5
	_env.glow_strength      = 0.8
	_env.glow_bloom         = 0.05
	_env.glow_hdr_threshold = 1.2
	_env.glow_blend_mode    = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# Adjustment ────────────────────────────────────────────────────────────────
	_env.adjustment_enabled    = true
	_env.adjustment_brightness = 1.0
	_env.adjustment_contrast   = 1.05
	_env.adjustment_saturation = 0.90

	# Sun DirectionalLight ─────────────────────────────────────────────────────
	_sun = get_parent().find_child("DirectionalLight3D") as DirectionalLight3D
	if _sun == null:
		_sun = DirectionalLight3D.new()
		_sun.name = "SunLight"
		get_parent().add_child(_sun)
	_sun.shadow_enabled  = true
	_sun.shadow_bias     = 0.03
	_sun.shadow_normal_bias = 1.0
	_sun.directional_shadow_max_distance     = 128.0
	_sun.directional_shadow_mode            = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_split_1         = 0.25
	_sun.directional_shadow_blend_splits    = true
	_sun.sky_mode       = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY

	# Moon DirectionalLight ────────────────────────────────────────────────────
	_moon = DirectionalLight3D.new()
	_moon.name           = "MoonLight"
	_moon.shadow_enabled = false
	_moon.sky_mode       = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	_moon.light_color    = Color(0.56, 0.66, 0.92)
	_moon.light_energy   = 0.0
	get_parent().add_child(_moon)


# ── Per-frame update ───────────────────────────────────────────────────────────

func _update(t: float) -> void:
	# t: 0.0 = midnight  0.25 = dawn  0.5 = noon  0.75 = dusk
	var sun_angle := (t - 0.5) * TAU

	# Sun direction: moves in the X-Y plane with a slight Z tilt for realism
	var sun_dir := Vector3(
		sin(sun_angle) * 0.95,
		cos(sun_angle),
		sin(sun_angle) * 0.25
	).normalized()

	# Moon is almost opposite (slight offset so it's never exactly behind the sun)
	var moon_dir := Vector3(-sun_dir.x, -sun_dir.y, -sun_dir.z + 0.08).normalized()

	# ── Blend factors ──────────────────────────────────────────────────────────
	var sun_h := sun_dir.y   # −1 (midnight) → +1 (noon)

	# day_blend: 0=night, 1=full day — smooth transition near horizon
	var day_blend := clampf((sun_h + 0.08) / 0.32, 0.0, 1.0)

	# sunrise_blend: peaks when sun is near horizon (dawn / dusk)
	var horizon_prox := clampf(1.0 - abs(sun_h) * 4.2, 0.0, 1.0)
	var sunrise_blend := horizon_prox * clampf((sun_h + 0.20) / 0.28, 0.0, 1.0)

	var moon_brightness := TimeManager.get_moon_brightness()

	# ── Sky colours ────────────────────────────────────────────────────────────
	# Base day↔night lerp
	var sky_top := _SKY_TOP_DAY.lerp(_SKY_TOP_NIGHT, 1.0 - day_blend)
	var sky_hor := _SKY_HOR_DAY.lerp(_SKY_HOR_NIGHT, 1.0 - day_blend)

	# Layer sunset/sunrise tint on top
	var ss := sunrise_blend * clampf(1.0 - abs(sun_h) * 3.5, 0.0, 1.0)
	sky_top = sky_top.lerp(_SKY_TOP_SUNSET, ss * 0.55)
	sky_hor = sky_hor.lerp(_SKY_HOR_SUNSET, ss * 0.90)

	var gnd_hor := _GND_HOR_DAY.lerp(_GND_HOR_NIGHT, 1.0 - day_blend)
	var gnd_bot := _GND_BOT_DAY.lerp(_GND_BOT_NIGHT, 1.0 - day_blend)

	# ── Seasonal sky tint (daytime only, 30% blend) ────────────────────────────
	sky_top = sky_top.lerp(_SEASON_SKY_TOP[_season_idx], 0.30 * day_blend)
	sky_hor = sky_hor.lerp(_SEASON_SKY_HOR[_season_idx], 0.25 * day_blend)

	# ── Weather sky darkening (daytime only) ───────────────────────────────────
	if _weather_sky_darken > 0.0:
		sky_top = sky_top.darkened(_weather_sky_darken * day_blend)
		sky_hor = sky_hor.darkened(_weather_sky_darken * day_blend)

	# ── Blood moon tint (only visible at night) ────────────────────────────────
	var night_factor := 1.0 - day_blend   # 1 at full night, 0 at full day
	var bm := _blood_moon_blend * night_factor
	if bm > 0.0:
		sky_top = sky_top.lerp(_SKY_TOP_BLOOD, bm)
		sky_hor = sky_hor.lerp(_SKY_HOR_BLOOD, bm)

	if _sky_mat:
		_sky_mat.sky_top_color            = sky_top
		_sky_mat.sky_horizon_color        = sky_hor
		_sky_mat.sky_energy_multiplier    = lerpf(0.02, 2.0, day_blend) + ss * 0.35
		_sky_mat.ground_horizon_color     = gnd_hor
		_sky_mat.ground_bottom_color      = gnd_bot
		_sky_mat.ground_energy_multiplier = lerpf(0.01, 0.35, day_blend)

	# ── Sun light ──────────────────────────────────────────────────────────────
	if _sun:
		var up := Vector3.FORWARD if abs(sun_dir.y) > 0.95 else Vector3.UP
		_sun.basis = Basis.looking_at(-sun_dir, up)

		# Energy: 0 below horizon, full at midday
		var sun_energy := clampf((sun_h + 0.04) / 0.22, 0.0, 1.0)
		_sun.light_energy = sun_energy

		# Temperature: warm orange at horizon → neutral white at zenith
		_sun.light_color = Color(
			1.0,
			lerpf(1.00, 0.65, ss),
			lerpf(1.00, 0.28, ss))

	# ── Moon light ─────────────────────────────────────────────────────────────
	if _moon:
		var up := Vector3.FORWARD if abs(moon_dir.y) > 0.95 else Vector3.UP
		_moon.basis = Basis.looking_at(-moon_dir, up)

		# Moon is visible at night when above horizon
		var moon_above := clampf((moon_dir.y + 0.02) / 0.18, 0.0, 1.0)
		_moon.light_energy = moon_above * (1.0 - day_blend) * 0.18 * moon_brightness
		# Blood moon: shift light to deep red
		_moon.light_color = Color(0.56, 0.66, 0.92).lerp(Color(0.95, 0.10, 0.10), bm)

	# ── Ambient light ──────────────────────────────────────────────────────────
	if _env:
		_env.ambient_light_sky_contribution = lerpf(0.15, 0.90, day_blend)
		# Extra manual energy so caves aren't pitch black at night
		_env.ambient_light_energy = lerpf(0.04, 0.28, day_blend) + ss * 0.08

		# ── Fog ────────────────────────────────────────────────────────────────
		# Warm tint at sunrise, neutral blue-white during day, cold at night
		var fog_r: float = lerpf(0.04, lerpf(0.56, 0.95, ss), day_blend)
		var fog_g: float = lerpf(0.06, lerpf(0.70, 0.58, ss), day_blend)
		var fog_b: float = lerpf(0.13, lerpf(0.92, 0.46, ss), day_blend)
		var fog_col := Color(fog_r, fog_g, fog_b)
		# Blood moon: deep red fog at night
		if bm > 0.0:
			fog_col = fog_col.lerp(Color(0.40, 0.02, 0.02), bm)
		# Blizzard: white-grey fog (only during day)
		if _weather_idx == 4:
			fog_col = fog_col.lerp(Color(0.82, 0.87, 0.92), 0.65 * day_blend)
		_env.fog_light_color = fog_col
		# Slightly denser fog at night (atmospheric scattering effect), amplified by weather
		_env.fog_density = _base_fog_density * lerpf(1.2, 1.0, day_blend) * clampf(_weather_fog_mult, 1.0, 2.0)
