## DeathScreen.gd — Shown when the player dies. Offers respawn or main menu.
## The world keeps its state; the inventory is kept (friendlier baseline).
class_name DeathScreen
extends CanvasLayer

var _root: Control       = null
var _fade: ColorRect     = null
var _fade_t: float       = 0.0
var _showing: bool       = false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	EventBus.player_died.connect(_on_player_died)


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_fade = ColorRect.new()
	_fade.color = Color(0.25, 0.02, 0.02, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_fade)

	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.offset_left = -220; center.offset_right = 220
	center.offset_top = -160;  center.offset_bottom = 160
	center.add_theme_constant_override("separation", 14)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(center)

	var title := Label.new()
	title.text = "Vous êtes mort"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.90))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 3)
	center.add_child(title)

	var sub := Label.new()
	sub.name = "SubLabel"
	sub.text = ""
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(1.0, 0.80, 0.76, 0.9))
	center.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 18)
	center.add_child(spacer)

	var respawn_btn := UITheme.primary_button("Réapparaître", Vector2(320, 54))
	respawn_btn.pressed.connect(_on_respawn)
	center.add_child(respawn_btn)

	var menu_btn := Button.new()
	menu_btn.text = "Menu principal"
	menu_btn.custom_minimum_size = Vector2(320, 44)
	menu_btn.pressed.connect(_on_main_menu)
	center.add_child(menu_btn)


func _on_player_died(player: Node, _cause: String) -> void:
	if _showing:
		return
	_showing = true
	_fade_t  = 0.0
	visible  = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var sub := _root.find_child("SubLabel", true, false) as Label
	if sub != null and player != null and player.get("xp_level") != null:
		sub.text = "Niveau %d conservé — votre inventaire vous attend." % int(player.xp_level)


func _process(delta: float) -> void:
	if not _showing:
		return
	_fade_t = minf(_fade_t + delta * 1.5, 1.0)
	_fade.color.a = 0.72 * _fade_t


func _on_respawn() -> void:
	_showing = false
	visible  = false
	get_tree().paused = false
	var player := GameManager.local_player
	if player != null:
		# Ensure spawn chunks have collision before dropping the player in
		var world := GameManager.world_node
		if world != null and world.has_method("prepare_respawn_area"):
			world.prepare_respawn_area(player.respawn_position)
		player.respawn()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_main_menu() -> void:
	_showing = false
	visible  = false
	get_tree().paused = false
	var world := GameManager.world_node
	if world != null and world.has_method("save_world"):
		world.save_world()
	GameManager.change_state(GameManager.GameState.MAIN_MENU)
