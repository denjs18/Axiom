## TimeManager.gd
## Autoload singleton — server-authoritative day/night clock.
## Time encoding: 0.0 = midnight, 0.25 = dawn, 0.5 = noon, 0.75 = dusk.
## One full cycle = CYCLE_DURATION real seconds (default 30 min).
extends Node

## Seconds per full day (30 real minutes = 1 800 s)
const CYCLE_DURATION := 1800.0
## Lunar cycle in game-days (8 days = one full moon cycle)
const LUNAR_DAYS := 8

var current_time: float = 0.25   # start at dawn
var current_day:  int   = 0

# Moon phase brightness table — index = phase (0=new moon, 4=full moon)
const MOON_BRIGHTNESS: Array[float] = [0.0, 0.22, 0.50, 0.78, 1.0, 0.78, 0.50, 0.22]
# Mob spawn multiplier per lunar phase
const MOON_SPAWN: Array[float]      = [0.5, 0.70, 1.00, 1.25, 1.5, 1.25, 1.00, 0.70]

var _last_phase: int = -1

# ── Blood Moon ─────────────────────────────────────────────────────────────────
var is_blood_moon: bool  = false
var _blood_moon_day: int = 0      # set in _ready so randi works correctly
var _bm_warning_sent: bool = false
var _bm_triggered:    bool = false


func _ready() -> void:
	_blood_moon_day = randi_range(10, 15)


func _process(delta: float) -> void:
	current_time += delta / CYCLE_DURATION
	if current_time >= 1.0:
		current_time -= 1.0
		current_day  += 1
		EventBus.day_changed.emit(current_day)

	var phase := get_lunar_phase()
	if phase != _last_phase:
		_last_phase = phase
		EventBus.lunar_phase_changed.emit(phase, MOON_SPAWN[phase])

	_tick_blood_moon()

	EventBus.time_updated.emit(current_time, current_day)


func _tick_blood_moon() -> void:
	# Warning: the afternoon before blood moon night
	if not _bm_warning_sent \
			and current_day == _blood_moon_day - 1 \
			and current_time >= 0.50:
		_bm_warning_sent = true
		EventBus.blood_moon_warning.emit()

	# Start: at dusk on blood moon day (>= handles day-skip edge case)
	if not is_blood_moon and not _bm_triggered \
			and current_day >= _blood_moon_day \
			and current_time >= 0.73:
		is_blood_moon   = true
		_bm_triggered   = true
		_blood_moon_day = current_day   # pin to actual day so end-check is correct
		EventBus.blood_moon_started.emit(current_day)

	# End: at dawn the next morning (day check ensures we don't end prematurely
	# if skip_to_dawn() is called the same night, and handles large delta spikes).
	if is_blood_moon and current_day > _blood_moon_day and current_time >= 0.25:
		is_blood_moon = false
		_bm_warning_sent = false
		_bm_triggered    = false
		_blood_moon_day  = current_day + randi_range(10, 15)
		EventBus.blood_moon_ended.emit()


# ── Public API ─────────────────────────────────────────────────────────────────

## Returns the sun's elevation as a value in [-1, 1].
## +1 = directly overhead (noon), -1 = deep below horizon (midnight).
func get_sun_height() -> float:
	return cos((current_time - 0.5) * TAU)


## Returns true while the sun is above the horizon.
func is_day() -> bool:
	return get_sun_height() > 0.0


## Returns the current lunar phase index (0 = new moon, 4 = full moon, 7 = waning crescent).
func get_lunar_phase() -> int:
	return current_day % LUNAR_DAYS


## Moon brightness in [0, 1] — used by DayNightCycle to set moon light energy.
func get_moon_brightness() -> float:
	return MOON_BRIGHTNESS[get_lunar_phase()]


## Mob spawn rate multiplier from lunar phase.
func get_mob_spawn_multiplier() -> float:
	return MOON_SPAWN[get_lunar_phase()]


## Human-readable phase name for HUD / lore display.
func get_phase_name() -> String:
	match get_lunar_phase():
		0: return "Nouvelle Lune"
		1: return "Croissant Montant"
		2: return "Premier Quartier"
		3: return "Gibbeux Croissant"
		4: return "Pleine Lune"
		5: return "Gibbeux Décroissant"
		6: return "Dernier Quartier"
		7: return "Croissant Décroissant"
	return "Inconnue"


## Wall-clock string (00:00 – 23:59) from the game time.
func get_time_string() -> String:
	var h  := int(current_time * 24.0)
	var m  := int(fmod(current_time * 24.0 * 60.0, 60.0))
	return "%02d:%02d" % [h, m]


## Jump time forward to the next dawn without changing the day counter.
func skip_to_dawn() -> void:
	current_time = 0.25


## Hard-set the time. Useful for commands / world settings.
func set_time(t: float) -> void:
	current_time = fmod(t + 1.0, 1.0)


## Returns a longitude-adjusted local time for a world X coordinate.
## Players far east see the sun rise earlier; far west, later.
## Max offset: ±15 % of the cycle (≈ ±4.5 min) at ±50 000 blocks.
func get_local_time(world_x: float) -> float:
	var offset := clampf(world_x / 50000.0, -1.0, 1.0) * 0.15
	return fmod(current_time + offset + 1.0, 1.0)
