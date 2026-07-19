## SoundManager.gd — Procedural audio for the whole game.
## Every clip is synthesized at startup into a small AudioStreamWAV
## (same philosophy as BlockTextureAtlas: zero audio assets, web-friendly).
##
## Public API:
##   SoundManager.play("pickup")                    — non-positional (UI/self)
##   SoundManager.play_at("hit", pos)               — positional, with pitch jitter
##   SoundManager.step_on(block_id, pos)            — footstep by block material
##   SoundManager.dig_block(id, pos) / break_at(id, pos) / place_at(id, pos)
## Ambient loops (wind / crickets / rain / nether drone) crossfade automatically
## from TimeManager + SeasonManager + current dimension.
extends Node

const _RATE      := 22050   # one-shot SFX sample rate
const _LOOP_RATE := 16000   # ambient loop sample rate (cheaper, low-freq content)
const _SILENT    := -60.0

var _sounds: Dictionary = {}   # name → AudioStreamWAV

var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_ui: Array[AudioStreamPlayer]   = []
var _idx_3d: int = 0
var _idx_ui: int = 0

# Ambient loop players, crossfaded every frame toward _amb_target
var _amb: Dictionary        = {}   # name → AudioStreamPlayer
var _amb_target: Dictionary = {}   # name → target volume (db)
var _thunder_cd: float = 8.0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 0xA010
	_build_sounds()
	_build_pools()
	_build_ambient()
	EventBus.block_broken.connect(_on_block_broken)
	EventBus.block_placed.connect(_on_block_placed)
	EventBus.mob_damaged.connect(_on_mob_damaged)
	EventBus.mob_died.connect(_on_mob_died)
	EventBus.item_picked_up.connect(_on_item_picked_up)
	EventBus.container_opened.connect(_on_container_opened)
	EventBus.container_closed.connect(_on_container_closed)
	EventBus.player_died.connect(_on_player_died)
	EventBus.player_dimension_changed.connect(_on_dimension_changed)
	# Global UI click: every button in the game gets a soft tick, for free.
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is BaseButton and not (node as BaseButton).pressed.is_connected(_on_any_button_pressed):
		(node as BaseButton).pressed.connect(_on_any_button_pressed)


func _on_any_button_pressed() -> void:
	play("click", -12.0)


# ── Playback API ───────────────────────────────────────────────────────────────

func play(sound: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	var wav: AudioStreamWAV = _sounds.get(sound)
	if wav == null or _pool_ui.is_empty():
		return
	var p := _pool_ui[_idx_ui]
	_idx_ui = (_idx_ui + 1) % _pool_ui.size()
	p.stream      = wav
	p.volume_db   = vol_db
	p.pitch_scale = pitch
	p.play()


func play_at(sound: String, pos: Vector3, vol_db: float = 0.0, jitter: float = 0.08) -> void:
	var wav: AudioStreamWAV = _sounds.get(sound)
	if wav == null or _pool_3d.is_empty():
		return
	var p := _pool_3d[_idx_3d]
	_idx_3d = (_idx_3d + 1) % _pool_3d.size()
	p.stream          = wav
	p.global_position = pos
	p.volume_db       = vol_db
	p.pitch_scale     = 1.0 + _rng.randf_range(-jitter, jitter)
	p.play()


func step_on(block_id: int, pos: Vector3, vol_db: float = -8.0) -> void:
	play_at("step_" + _material_of(block_id), pos, vol_db, 0.12)


func dig_block(block_id: int, pos: Vector3) -> void:
	play_at("dig_" + _material_of(block_id), pos, -5.0, 0.15)


func break_at(block_id: int, pos: Vector3) -> void:
	play_at("break_" + _material_of(block_id), pos, -2.0)


func place_at(_block_id: int, pos: Vector3) -> void:
	play_at("place", pos, -4.0)


## Map a block id to a footstep/dig material family.
func _material_of(block_id: int) -> String:
	var b := BlockRegistry.get_block(block_id)
	if b == null:
		return "stone"
	if BlockRegistry.get_shape(block_id) == BlockRegistry.SHAPE_CROSS:
		return "grass"
	var n := b.name
	if b.fluid or "sand" in n or "gravel" in n:
		return "sand"
	if "grass" in n or "leaves" in n or "moss" in n or "wool" in n or "mycelium" in n:
		return "grass"
	if "log" in n or "plank" in n or "wood" in n or b.tool == "axe":
		return "wood"
	if b.tool == "shovel":
		return "dirt"
	return "stone"


# ── Event wiring ───────────────────────────────────────────────────────────────

func _on_block_broken(position: Vector3i, block_id: int, _player: Node) -> void:
	break_at(block_id, Vector3(position) + Vector3(0.5, 0.5, 0.5))


func _on_block_placed(position: Vector3i, block_id: int, _meta: Dictionary) -> void:
	place_at(block_id, Vector3(position) + Vector3(0.5, 0.5, 0.5))


func _on_mob_damaged(mob: Node, _amount: float, _source: Node) -> void:
	if mob is Node3D:
		play_at("hit", (mob as Node3D).global_position, -3.0)


func _on_mob_died(mob: Node, _killer: Node) -> void:
	if mob is Node3D:
		play_at("hit", (mob as Node3D).global_position, -2.0, 0.0)


func _on_item_picked_up(_stack: Dictionary, _player: Node) -> void:
	play("pickup", -8.0, 1.0 + _rng.randf_range(-0.05, 0.1))


func _on_container_opened(container: Node, _player: Node) -> void:
	if container is Node3D:
		play_at("chest_open", (container as Node3D).global_position, -4.0)
	else:
		play("chest_open", -6.0)


func _on_container_closed(container: Node, _player: Node) -> void:
	if container is Node3D:
		play_at("chest_close", (container as Node3D).global_position, -4.0)
	else:
		play("chest_close", -6.0)


func _on_player_died(_player: Node, _cause: String) -> void:
	play("death", -2.0)


func _on_dimension_changed(_player: Node, _from: String, _to: String) -> void:
	play("portal", -4.0)


# ── Ambient crossfade ──────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _amb.is_empty():
		return
	_update_ambient_targets(delta)
	for key in _amb:
		var p: AudioStreamPlayer = _amb[key]
		var target: float = _amb_target.get(key, _SILENT)
		p.volume_db = lerpf(p.volume_db, target, minf(delta * 1.2, 1.0))


func _update_ambient_targets(delta: float) -> void:
	for key in _amb_target:
		_amb_target[key] = _SILENT
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
	var dim: String = GameManager.current_dimension
	if dim == "nether":
		_amb_target["nether"] = -14.0
		return
	if dim == "the_end":
		_amb_target["wind"] = -16.0
		return
	# Overworld: weather first, then day/night ambience
	var blizzard := SeasonManager.is_blizzard()
	if blizzard:
		_amb_target["wind"] = -6.0
	elif SeasonManager.is_precipitating():
		_amb_target["rain"] = -10.0
		_amb_target["wind"] = -20.0
	elif TimeManager.is_day():
		_amb_target["wind"] = -24.0
	else:
		_amb_target["wind"] = -26.0
		if not SeasonManager.is_winter():
			_amb_target["crickets"] = -18.0
	# Occasional thunder during storms
	if SeasonManager.current_weather == SeasonManager.Weather.THUNDERSTORM:
		_thunder_cd -= delta
		if _thunder_cd <= 0.0:
			_thunder_cd = _rng.randf_range(9.0, 26.0)
			play("thunder", -3.0, _rng.randf_range(0.8, 1.1))


# ── Node pools ─────────────────────────────────────────────────────────────────

func _build_pools() -> void:
	for _i in 12:
		var p := AudioStreamPlayer3D.new()
		p.unit_size    = 6.0
		p.max_distance = 44.0
		p.max_db       = 0.0
		add_child(p)
		_pool_3d.append(p)
	for _i in 5:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool_ui.append(p)


func _build_ambient() -> void:
	for key in ["wind", "crickets", "rain", "nether"]:
		var p := AudioStreamPlayer.new()
		p.stream    = _sounds["amb_" + key]
		p.volume_db = _SILENT
		p.autoplay  = true
		add_child(p)
		p.play()
		_amb[key]        = p
		_amb_target[key] = _SILENT


# ── Synthesis helpers ──────────────────────────────────────────────────────────

static func _to_wav(samples: PackedFloat32Array, rate: int, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format   = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo   = false
	wav.data     = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end  = samples.size()
	return wav


## Filtered noise burst. lp = one-pole lowpass coefficient (0..1, lower = darker),
## attack in seconds, decay_pow shapes the tail (higher = snappier).
func _noise(dur: float, lp: float, attack: float, decay_pow: float, gain: float,
		rate: int = _RATE) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var f := 0.0
	var atk := maxf(attack, 0.0005)
	for i in n:
		var t := float(i) / float(n)
		f += lp * (_rng.randf_range(-1.0, 1.0) - f)
		var env := minf(t * dur / atk, 1.0) * pow(1.0 - t, decay_pow)
		out[i] = f * env * gain
	return out


## Sine sweep f0→f1 with optional harmonics (adds warmth/edge).
func _tone(dur: float, f0: float, f1: float, decay_pow: float, gain: float,
		harmonics: float = 0.0, rate: int = _RATE) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		phase += TAU * lerpf(f0, f1, t) / float(rate)
		var s := sin(phase)
		if harmonics > 0.0:
			s += harmonics * 0.5 * sin(phase * 2.0) + harmonics * 0.25 * sin(phase * 3.0)
		out[i] = s * pow(1.0 - t, decay_pow) * gain
	return out


## Mix `add` into `base` starting at sample offset `at` (grows base if needed).
static func _mix(base: PackedFloat32Array, add: PackedFloat32Array, at: int = 0) -> PackedFloat32Array:
	var need := at + add.size()
	if base.size() < need:
		base.resize(need)
	for i in add.size():
		base[at + i] += add[i]
	return base


## Crossfade the tail of a loop into its head so it loops seamlessly.
static func _loopify(samples: PackedFloat32Array, fade: int) -> PackedFloat32Array:
	var n := samples.size()
	fade = mini(fade, n / 4)
	var out := samples.slice(0, n - fade)
	for i in fade:
		var w := float(i) / float(fade)
		out[i] = out[i] * w + samples[n - fade + i] * (1.0 - w)
	return out


# ── Sound recipes ──────────────────────────────────────────────────────────────

func _build_sounds() -> void:
	# Footsteps (one per material family)
	_sounds["step_stone"] = _to_wav(_noise(0.07, 0.35, 0.002, 3.0, 0.50), _RATE)
	_sounds["step_grass"] = _to_wav(_noise(0.10, 0.10, 0.004, 2.2, 0.55), _RATE)
	_sounds["step_dirt"]  = _to_wav(_noise(0.09, 0.08, 0.004, 2.5, 0.50), _RATE)
	_sounds["step_sand"]  = _to_wav(_noise(0.12, 0.13, 0.008, 1.8, 0.40), _RATE)
	_sounds["step_wood"]  = _to_wav(_mix(
		_tone(0.09, 95.0, 70.0, 3.0, 0.45, 0.4),
		_noise(0.05, 0.20, 0.002, 3.0, 0.25)), _RATE)

	# Mining ticks (brighter, shorter than steps)
	_sounds["dig_stone"] = _to_wav(_noise(0.05, 0.45, 0.001, 3.5, 0.55), _RATE)
	_sounds["dig_grass"] = _to_wav(_noise(0.06, 0.14, 0.002, 2.8, 0.50), _RATE)
	_sounds["dig_dirt"]  = _to_wav(_noise(0.06, 0.10, 0.002, 3.0, 0.50), _RATE)
	_sounds["dig_sand"]  = _to_wav(_noise(0.07, 0.15, 0.004, 2.2, 0.42), _RATE)
	_sounds["dig_wood"]  = _to_wav(_mix(
		_tone(0.06, 140.0, 110.0, 3.5, 0.40, 0.5),
		_noise(0.04, 0.25, 0.001, 3.5, 0.30)), _RATE)

	# Block break (low thump + material crunch)
	var thump := _tone(0.15, 90.0, 55.0, 2.5, 0.50)
	_sounds["break_stone"] = _to_wav(_mix(_noise(0.20, 0.30, 0.002, 3.0, 0.60), thump.duplicate()), _RATE)
	_sounds["break_grass"] = _to_wav(_mix(_noise(0.18, 0.10, 0.003, 2.5, 0.55), thump.duplicate()), _RATE)
	_sounds["break_dirt"]  = _to_wav(_mix(_noise(0.18, 0.09, 0.003, 2.8, 0.55), thump.duplicate()), _RATE)
	_sounds["break_sand"]  = _to_wav(_mix(_noise(0.22, 0.12, 0.005, 2.0, 0.45), thump.duplicate()), _RATE)
	_sounds["break_wood"]  = _to_wav(_mix(_mix(
		_noise(0.18, 0.18, 0.002, 3.0, 0.45),
		_tone(0.12, 130.0, 85.0, 2.5, 0.40, 0.5)), thump.duplicate()), _RATE)

	_sounds["place"] = _to_wav(_mix(
		_tone(0.08, 110.0, 70.0, 3.0, 0.45),
		_noise(0.04, 0.25, 0.002, 3.0, 0.20)), _RATE)

	# Combat / player
	_sounds["hurt"] = _to_wav(_mix(
		_tone(0.20, 200.0, 95.0, 1.8, 0.50, 0.8),
		_noise(0.08, 0.20, 0.002, 3.0, 0.15)), _RATE)
	_sounds["hit"] = _to_wav(_mix(
		_noise(0.06, 0.50, 0.001, 3.5, 0.60),
		_tone(0.09, 160.0, 70.0, 3.0, 0.50)), _RATE)
	_sounds["death"] = _to_wav(_tone(0.90, 330.0, 65.0, 1.2, 0.50, 0.5), _RATE)

	# Eating: three soft munches, then a gulp is played separately
	var eat := PackedFloat32Array()
	for k in 3:
		_mix(eat, _noise(0.07, 0.12 + 0.02 * k, 0.004, 2.5, 0.45), int(0.12 * k * _RATE))
	_sounds["eat"]  = _to_wav(eat, _RATE)
	_sounds["gulp"] = _to_wav(_tone(0.12, 300.0, 90.0, 2.0, 0.35, 0.3), _RATE)

	# Items / UI
	_sounds["pickup"] = _to_wav(_mix(
		_tone(0.10, 740.0, 1150.0, 2.0, 0.30),
		_tone(0.08, 1480.0, 1480.0, 3.0, 0.12), int(0.02 * _RATE)), _RATE)
	_sounds["click"] = _to_wav(_noise(0.025, 0.60, 0.0005, 4.0, 0.40), _RATE)

	# Advancement / progress chime (C–E–G–C arpeggio)
	var chime := PackedFloat32Array()
	var notes: Array[float] = [523.25, 659.25, 783.99, 1046.50]
	for k in notes.size():
		_mix(chime, _tone(0.45, notes[k], notes[k], 2.5, 0.22, 0.3), int(0.09 * k * _RATE))
	_sounds["chime"] = _to_wav(chime, _RATE)

	# Containers
	_sounds["chest_open"] = _to_wav(_mix(
		_tone(0.18, 160.0, 230.0, 1.5, 0.30, 0.6),
		_noise(0.06, 0.20, 0.002, 3.0, 0.25)), _RATE)
	_sounds["chest_close"] = _to_wav(_mix(
		_tone(0.12, 200.0, 120.0, 2.5, 0.35, 0.5),
		_noise(0.05, 0.22, 0.002, 3.2, 0.28)), _RATE)

	# Big one-shots
	_sounds["fuse"] = _to_wav(_noise(1.40, 0.25, 0.02, 0.4, 0.35), _RATE)
	_sounds["explosion"] = _to_wav(_mix(
		_noise(0.90, 0.06, 0.002, 2.0, 1.00),
		_tone(0.50, 55.0, 28.0, 1.5, 0.80)), _RATE)
	_sounds["thunder"] = _to_wav(_noise(1.60, 0.045, 0.15, 1.6, 0.90), _RATE)
	_sounds["portal"] = _to_wav(_mix(
		_noise(0.70, 0.20, 0.25, 1.5, 0.40),
		_tone(0.70, 250.0, 950.0, 1.2, 0.18)), _RATE)
	_sounds["splash"] = _to_wav(_noise(0.25, 0.20, 0.010, 2.0, 0.50), _RATE)

	# Ambient loops
	_sounds["amb_wind"]     = _to_wav(_gen_wind(), _LOOP_RATE, true)
	_sounds["amb_crickets"] = _to_wav(_gen_crickets(), _LOOP_RATE, true)
	_sounds["amb_rain"]     = _to_wav(_loopify(_noise(2.2, 0.35, 0.01, 0.05, 0.35, _LOOP_RATE),
		int(0.2 * _LOOP_RATE)), _LOOP_RATE, true)
	_sounds["amb_nether"]   = _to_wav(_gen_nether_drone(), _LOOP_RATE, true)


## Wind loop: brown-ish noise with a slow amplitude wobble (whole cycles → loops clean).
func _gen_wind() -> PackedFloat32Array:
	var n := int(2.5 * _LOOP_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var f := 0.0
	for i in n:
		var t := float(i) / float(n)
		f += 0.03 * (_rng.randf_range(-1.0, 1.0) - f)
		var wobble := 0.65 + 0.35 * sin(TAU * 2.0 * t)   # 2 full cycles per loop
		out[i] = f * wobble * 0.9
	return _loopify(out, int(0.25 * _LOOP_RATE))


## Cricket loop: two chirp triplets (4.3 kHz carrier, 28 Hz AM), silence between.
func _gen_crickets() -> PackedFloat32Array:
	var n := int(2.0 * _LOOP_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var starts: Array[float] = [0.00, 0.09, 0.18, 1.00, 1.09, 1.18]
	for s in starts:
		var i0 := int(s * _LOOP_RATE)
		var len := int(0.06 * _LOOP_RATE)
		for i in len:
			var t := float(i) / float(len)
			var env := sin(PI * t)
			var am := 0.5 + 0.5 * sin(TAU * 28.0 * i / float(_LOOP_RATE))
			out[i0 + i] += sin(TAU * 4300.0 * i / float(_LOOP_RATE)) * env * am * 0.12
	return out


## Nether drone: two low sines beating against each other + faint dark noise.
## Frequencies are exact multiples of 1/3 Hz so the 3 s loop is seamless.
func _gen_nether_drone() -> PackedFloat32Array:
	var n := int(3.0 * _LOOP_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var f := 0.0
	for i in n:
		var ph := float(i) / float(_LOOP_RATE)
		f += 0.05 * (_rng.randf_range(-1.0, 1.0) - f)
		out[i] = (sin(TAU * 55.0 * ph) + sin(TAU * 57.333333 * ph)) * 0.22 + f * 0.10
	return _loopify(out, int(0.2 * _LOOP_RATE))
