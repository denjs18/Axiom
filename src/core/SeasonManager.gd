## SeasonManager.gd
## Autoload singleton — tracks seasons and weather.
## Season cycle: Spring → Summer → Autumn → Winter (each = DAYS_PER_SEASON game-days).
## Connects to EventBus.day_changed; emits season_changed and weather_changed.
extends Node

enum Season  { SPRING, SUMMER, AUTUMN, WINTER }
enum Weather { CLEAR, CLOUDY, RAIN, THUNDERSTORM, BLIZZARD }

const DAYS_PER_SEASON := 5

const SEASON_NAMES:  Array[String] = ["Printemps", "Été", "Automne", "Hiver"]
const SEASON_ICONS:  Array[String] = ["✿", "☀", "✦", "❄"]
const WEATHER_NAMES: Array[String] = ["Dégagé", "Nuageux", "Pluie", "Orage", "Blizzard"]
const WEATHER_ICONS: Array[String] = ["☀", "☁", "☂", "⚡", "❄"]

# Crop growth multipliers per season
const GROWTH_MULT: Array[float] = [1.0, 1.5, 0.6, 0.0]

# Fog multiplier per weather (used by DayNightCycle)
const WEATHER_FOG_MULT: Array[float] = [1.0, 1.3, 2.2, 3.5, 4.0]

# Sky darkening per weather (used by DayNightCycle) — 0=none, 1=black
const WEATHER_SKY_DARKEN: Array[float] = [0.0, 0.08, 0.22, 0.42, 0.15]

# Weighted probability tables: [CLEAR, CLOUDY, RAIN, THUNDERSTORM, BLIZZARD]
const _WEATHER_WEIGHTS := {
	0: [40, 30, 25,  5,  0],   # SPRING
	1: [65, 20, 10,  5,  0],   # SUMMER
	2: [30, 35, 25, 10,  0],   # AUTUMN
	3: [30, 25, 35,  0, 10],   # WINTER  (RAIN slot = light snow)
}

var current_season:  int = Season.SPRING
var current_weather: int = Weather.CLEAR
var day_in_season:   int     = 0

var _weather_days_left: int = 0


func _ready() -> void:
	EventBus.day_changed.connect(_on_day_changed)
	_roll_weather()


func _on_day_changed(_day: int) -> void:
	day_in_season += 1
	if day_in_season >= DAYS_PER_SEASON:
		day_in_season = 0
		current_season = (int(current_season) + 1) % 4
		EventBus.season_changed.emit(int(current_season))
		print("[SeasonManager] Saison : %s" % get_season_name())

	_weather_days_left -= 1
	if _weather_days_left <= 0:
		_roll_weather()


func _roll_weather() -> void:
	_weather_days_left = randi_range(1, 3)
	var weights: Array = _WEATHER_WEIGHTS[int(current_season)]

	var total := 0
	for w in weights:
		total += w
	var roll := randi() % maxi(total, 1)
	var acc  := 0
	for i in weights.size():
		acc += weights[i]
		if roll < acc:
			current_weather = i
			break

	EventBus.weather_changed.emit(int(current_weather))
	print("[SeasonManager] Météo : %s" % get_weather_name())


# ── Public API ─────────────────────────────────────────────────────────────────

func get_growth_multiplier() -> float:
	return GROWTH_MULT[int(current_season)]

func get_season_name() -> String:
	return SEASON_NAMES[int(current_season)]

func get_season_icon() -> String:
	return SEASON_ICONS[int(current_season)]

func get_weather_name() -> String:
	return WEATHER_NAMES[int(current_weather)]

func get_weather_icon() -> String:
	return WEATHER_ICONS[int(current_weather)]

func is_precipitating() -> bool:
	return current_weather == Weather.RAIN \
		or current_weather == Weather.THUNDERSTORM \
		or current_weather == Weather.BLIZZARD

func is_blizzard() -> bool:
	return current_weather == Weather.BLIZZARD

func is_winter() -> bool:
	return current_season == Season.WINTER
