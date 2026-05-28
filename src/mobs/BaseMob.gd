## BaseMob.gd — Base CharacterBody3D for all living entities in Axiom.
class_name BaseMob
extends CharacterBody3D

const GRAVITY := 28.0

@export var max_health: float = 10.0
var health: float = 0.0
var species: String = ""
var loot_table: Array = []  # [{item, count_min, count_max, chance}]

var xp_reward: int = 5   # override in hostile subclasses
var damage_reduction: float = 0.0   # 0.0–1.0 fraction of incoming damage absorbed
var _dead: bool = false
var _knockback_vel: Vector3 = Vector3.ZERO
var _invincible_timer: float = 0.0
var _stun_timer: float = 0.0
var is_elite: bool = false

signal mob_died(mob: BaseMob)


func _ready() -> void:
	health = max_health
	_mob_ready()
	# Emit after _mob_ready so species (and other subclass fields) are set.
	EventBus.mob_spawned.emit(self, global_position)


func _mob_ready() -> void:
	pass  # override in subclasses


func stun(duration: float) -> void:
	_stun_timer = maxf(_stun_timer, duration)


func take_damage(amount: float, source: Node3D = null) -> void:
	if _dead or _invincible_timer > 0.0:
		return
	# Apply damage reduction (set by mace armor_pierce on the caller side)
	var effective := amount * (1.0 - damage_reduction)
	health = maxf(0.0, health - effective)
	amount = effective
	_invincible_timer = 0.5
	EventBus.mob_damaged.emit(self, amount, source)
	if source:
		var dir := (global_position - source.global_position)
		dir.y = 0.0
		if dir.length_squared() > 0.0001:
			dir = dir.normalized()
		_knockback_vel = dir * 4.5 + Vector3.UP * 5.5
	if health <= 0.0:
		_die(source)


func _die(killer: Node3D = null) -> void:
	if _dead:
		return
	_dead = true
	_drop_loot()
	EventBus.mob_died.emit(self, killer)
	mob_died.emit(self)
	queue_free()


func _drop_loot() -> void:
	if not is_inside_tree():
		return
	var parent := get_parent()
	if parent == null:
		return
	for entry in loot_table:
		if randf() > entry.get("chance", 1.0):
			continue
		var cnt: int = randi_range(
			entry.get("count_min", 1),
			entry.get("count_max", entry.get("count_min", 1))
		)
		if cnt <= 0:
			continue
		var drop := DroppedItem.new()
		parent.add_child(drop)
		var offset := Vector3(randf_range(-0.3, 0.3), 0.5, randf_range(-0.3, 0.3))
		drop.setup(entry["item"], cnt, global_position + offset)


## Call after the mob is added to the scene tree (visuals already built).
## Applies elite stat multipliers and red mesh tint.
func make_elite() -> void:
	is_elite     = true
	max_health   = ceili(max_health * 1.5)
	health       = max_health
	_tint_elite_meshes(self)
	for entry in loot_table:
		entry["count_max"] = entry.get("count_max", entry.get("count_min", 1)) + 1
		entry["chance"]    = minf(entry.get("chance", 1.0) * 1.5, 1.0)


func _tint_elite_meshes(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mat := (child as MeshInstance3D).material_override
			if mat is StandardMaterial3D:
				var m: StandardMaterial3D = mat.duplicate()
				m.albedo_color = m.albedo_color.lerp(Color(0.85, 0.05, 0.05), 0.45)
				(child as MeshInstance3D).material_override = m
		_tint_elite_meshes(child)


func get_hp_ratio() -> float:
	if max_health <= 0.0:
		return 1.0
	return health / max_health


func _apply_base_physics(delta: float) -> void:
	_invincible_timer = maxf(0.0, _invincible_timer - delta)
	_stun_timer       = maxf(0.0, _stun_timer       - delta)
	if _stun_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		if not is_on_floor():
			velocity.y -= 28.0 * delta
		return
	if _knockback_vel.length_squared() > 0.01:
		velocity = _knockback_vel
		_knockback_vel = Vector3.ZERO
	elif not is_on_floor():
		velocity.y -= GRAVITY * delta
		velocity.y = maxf(velocity.y, -25.0)
	elif velocity.y < 0.0:
		velocity.y = 0.0
