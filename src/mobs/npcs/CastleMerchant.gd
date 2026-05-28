## CastleMerchant.gd — Stationary merchant tied to a castle type.
## Stays near its spawn point. Offers castle-type-specific trades on interact.
class_name CastleMerchant
extends WanderingMerchant

# Per-type trade pools — override parent's generic pool
const _CASTLE_TRADES: Array = [
	# 0 — Plaines : armures, boucliers, nourriture
	["axiom:iron_helmet", "axiom:iron_chestplate", "axiom:shield",
	 "axiom:bread", "axiom:apple", "axiom:iron_ingot"],

	# 1 — Désert : artefacts, or, rares
	["axiom:gold_ingot", "axiom:emerald", "axiom:echo_fragment",
	 "axiom:compass", "axiom:name_tag", "axiom:golden_apple"],

	# 2 — Forêt : potions, nature, semences
	["axiom:arcane_feather", "axiom:lead", "axiom:bone_meal",
	 "axiom:leather", "axiom:feather", "axiom:sugar_cane"],

	# 3 — Taïga : outils, survie
	["axiom:iron_pickaxe", "axiom:iron_axe", "axiom:flint_and_steel",
	 "axiom:coal", "axiom:arrow", "axiom:cooked_beef"],
]

var castle_type: int = 0


func setup_castle(type: int, pos: Vector3) -> void:
	castle_type    = type
	_patrol_nodes  = [pos]   # stationary — single patrol node = stays in place
	_patrol_idx    = 0


func try_interact(player: Node) -> void:
	if _trade_cooldown > 0.0:
		EventBus.show_message.emit("Le marchand n'a rien de nouveau pour l'instant.", 3.0)
		return
	if global_position.distance_to((player as Node3D).global_position) > TRADE_RANGE:
		return
	var pool: Array = _CASTLE_TRADES[clampi(castle_type, 0, 3)]
	var item_id: String = pool[randi() % pool.size()]
	var inv = player.get("inventory")
	if inv != null:
		inv.call("add_item", item_id, 1)
	_trade_cooldown = TRADE_COOLDOWN
	EventBus.show_message.emit("%s : « Voilà pour vous. »  [%s]" % [_merchant_name(), item_id.replace("axiom:", "")], 4.0)


func _merchant_name() -> String:
	match castle_type:
		0: return "Armurier"
		1: return "Brocanteur du Désert"
		2: return "Druide"
		3: return "Marchand Nordique"
		_: return "Marchand"


func _build_name_label() -> void:
	var lbl           := Label3D.new()
	lbl.text          = _merchant_name()
	lbl.font_size     = 28
	lbl.modulate      = Color(1.0, 0.85, 0.2)
	lbl.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position      = Vector3(0.0, 2.0, 0.0)
	add_child(lbl)
