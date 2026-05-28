## WanderingMerchant.gd — Friendly NPC that patrols road nodes and trades with the player.
class_name WanderingMerchant
extends BaseMob

const WALK_SPEED   := 2.5
const PATROL_RANGE := 160.0   # max distance between patrol targets
const TRADE_RANGE  := 3.5     # interact range
const TRADE_COOLDOWN := 60.0  # seconds between trades with same player

# Patrol
var _patrol_nodes: Array[Vector3] = []
var _patrol_idx: int = 0
var _idle_timer: float = 0.0

# Merchant state
enum State { IDLE, WALK, WAIT }
var _state: State = State.IDLE
var _trade_cooldown: float = 0.0

# Trade pool — one random item from this list per interaction
const _TRADE_POOL: Array[String] = [
	"axiom:apple",
	"axiom:bread",
	"axiom:iron_ingot",
	"axiom:coal",
	"axiom:emerald",
	"axiom:name_tag",
	"axiom:lead",
]

var _name_label: Label3D = null


func _mob_ready() -> void:
	max_health = 20.0
	health     = max_health
	xp_reward  = 0
	loot_table = []
	collision_layer = 4
	collision_mask  = 1
	_build_visual_merchant()
	_build_name_label()
	_idle_timer = randf_range(1.0, 3.0)


func setup_patrol(nodes: Array[Vector3]) -> void:
	_patrol_nodes = nodes
	_patrol_idx   = randi() % maxi(nodes.size(), 1)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_trade_cooldown = maxf(0.0, _trade_cooldown - delta)
	_update_ai(delta)
	_apply_base_physics(delta)
	move_and_slide()


func _update_ai(delta: float) -> void:
	match _state:
		State.IDLE:
			velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
			_idle_timer -= delta
			if _idle_timer <= 0.0:
				_advance_patrol()

		State.WALK:
			if _patrol_nodes.is_empty():
				_set_state(State.IDLE)
				return
			var target := _patrol_nodes[_patrol_idx]
			var diff   := target - global_position
			diff.y = 0.0
			if diff.length() < 1.2:
				_set_state(State.WAIT)
				_idle_timer = randf_range(4.0, 10.0)
			else:
				var dir := diff.normalized()
				velocity.x = lerp(velocity.x, dir.x * WALK_SPEED, 8.0 * delta)
				velocity.z = lerp(velocity.z, dir.z * WALK_SPEED, 8.0 * delta)
				rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 8.0 * delta)

		State.WAIT:
			velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
			_idle_timer -= delta
			if _idle_timer <= 0.0:
				_advance_patrol()


func _set_state(s: State) -> void:
	_state = s


func _advance_patrol() -> void:
	if _patrol_nodes.is_empty():
		_set_state(State.IDLE)
		_idle_timer = randf_range(3.0, 6.0)
		return
	_patrol_idx = (_patrol_idx + 1) % _patrol_nodes.size()
	_set_state(State.WALK)


## Called by Player on right-click interact.
func try_interact(player: Node) -> void:
	if _trade_cooldown > 0.0:
		EventBus.show_message.emit("Le marchand n'a rien de nouveau pour l'instant.", 3.0)
		return
	if global_position.distance_to((player as Node3D).global_position) > TRADE_RANGE:
		return
	var item_id: String = _TRADE_POOL[randi() % _TRADE_POOL.size()]
	var inv = player.get("inventory")
	if inv != null:
		inv.call("add_item", item_id, 1)
	_trade_cooldown = TRADE_COOLDOWN
	EventBus.show_message.emit("Marchand : « Tiens, prends ça ! »  [%s]" % item_id.replace("axiom:", ""), 4.0)


func _build_visual_merchant() -> void:
	var root := Node3D.new()
	root.name = "Visual"
	add_child(root)

	# Body
	var body     := MeshInstance3D.new()
	var body_box := BoxMesh.new()
	body_box.size = Vector3(0.6, 0.9, 0.35)
	body.mesh     = body_box
	var bmat      := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.22, 0.50, 0.80)   # blue robe
	bmat.roughness    = 0.9
	body.material_override = bmat
	body.position.y = 0.45
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(body)

	# Head
	var head     := MeshInstance3D.new()
	var head_box := BoxMesh.new()
	head_box.size = Vector3(0.5, 0.5, 0.5)
	head.mesh     = head_box
	var hmat      := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.85, 0.70, 0.55)   # skin tone
	hmat.roughness    = 0.9
	head.material_override = hmat
	head.position = Vector3(0.0, 0.95 + 0.2, 0.0)
	root.add_child(head)

	# Collision
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.6
	col.shape  = cap
	col.position.y = 0.8
	add_child(col)


func _build_name_label() -> void:
	_name_label          = Label3D.new()
	_name_label.text     = "Marchand Ambulant"
	_name_label.font_size = 28
	_name_label.modulate = Color(1.0, 0.85, 0.2)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	_name_label.position = Vector3(0.0, 2.0, 0.0)
	add_child(_name_label)
