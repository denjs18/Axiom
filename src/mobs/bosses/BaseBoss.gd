## BaseBoss.gd — Base class for all named bosses.
## Adds multi-phase logic, boss HUD signals, and lore drop support.
class_name BaseBoss
extends BaseHostile

var boss_name: String = "???"
var _current_phase: int = 1
var _phase_triggered: Dictionary = {}   # phase_number → bool, prevents re-triggering
var _engaged: bool = false
var _defeat_timer: float = -1.0         # counts down after death before queue_free


func _physics_process(delta: float) -> void:
	if _dead:
		if _defeat_timer >= 0.0:
			_defeat_timer -= delta
			if _defeat_timer <= 0.0:
				queue_free()
		return
	super(delta)
	_check_phase_transitions()
	_boss_tick(delta)


func _check_phase_transitions() -> void:
	var ratio := get_hp_ratio()
	for phase in _get_phase_thresholds():
		if _phase_triggered.get(phase, false):
			continue
		if ratio <= _get_phase_thresholds()[phase]:
			_phase_triggered[phase] = true
			_current_phase = phase
			_on_phase_changed(phase)
			EventBus.boss_health_changed.emit(boss_name, ratio)


## Override in subclasses: return { phase_number: hp_ratio_threshold }
## Example: { 2: 0.50, 3: 0.25 }
func _get_phase_thresholds() -> Dictionary:
	return {}


## Called when a new phase begins. Override in subclasses.
func _on_phase_changed(_phase: int) -> void:
	pass


## Per-frame boss logic beyond BaseHostile. Override in subclasses.
func _boss_tick(_delta: float) -> void:
	pass


func _check_aggro() -> void:
	super()
	if _player != null and not _engaged:
		_engaged = true
		EventBus.boss_engaged.emit(boss_name, self)


func take_damage(amount: float, source: Node3D = null) -> void:
	super(amount, source)
	if not _dead:
		EventBus.boss_health_changed.emit(boss_name, get_hp_ratio())


func _die(killer: Node3D = null) -> void:
	if _dead:
		return
	_dead = true
	_drop_loot()
	EventBus.boss_defeated.emit(boss_name)
	EventBus.mob_died.emit(self, killer)
	mob_died.emit(self)
	# Delay despawn so the player can see the death animation / loot
	_defeat_timer = 4.0
	# Freeze movement
	velocity = Vector3.ZERO
	set_physics_process(true)   # keep _physics_process running for the timer
