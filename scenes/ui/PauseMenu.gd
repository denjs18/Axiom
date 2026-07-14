## PauseMenu.gd — Pause overlay shown when the player presses Escape.
extends CanvasLayer

var _overlay: ColorRect = null
var _panel:   Panel     = null


func _ready() -> void:
	# Must stay active while the tree is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer        = 10   # above HUD

	_build_ui()
	visible = false

	EventBus.game_paused.connect(_on_paused)
	EventBus.game_resumed.connect(_on_resumed)


func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.color = Color(0.01, 0.02, 0.04, 0.62)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left   = -190
	_panel.offset_right  =  190
	_panel.offset_top    = -190
	_panel.offset_bottom =  190
	_panel.add_theme_stylebox_override("panel", UITheme.card())
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 26; vbox.offset_right = -26
	vbox.offset_top = 24;  vbox.offset_bottom = -24
	vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "Pause"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", UITheme.TEXT)
	vbox.add_child(title)

	var hint := UITheme.caption("Le monde retient son souffle...", 12)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	var btn_resume := UITheme.primary_button("Reprendre", Vector2(0, 50))
	btn_resume.pressed.connect(_on_resume)
	vbox.add_child(btn_resume)

	var btn_menu := Button.new()
	btn_menu.text = "Sauvegarder et menu principal"
	btn_menu.custom_minimum_size = Vector2(0, 44)
	btn_menu.pressed.connect(_on_main_menu)
	vbox.add_child(btn_menu)

	var btn_quit := UITheme.danger_button("Sauvegarder et quitter", Vector2(0, 44))
	btn_quit.pressed.connect(_on_quit)
	vbox.add_child(btn_quit)


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_on_resume()
		get_viewport().set_input_as_handled()


func _on_paused() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_resumed() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_resume() -> void:
	GameManager.resume_game()


func _on_main_menu() -> void:
	var world := GameManager.world_node
	if world != null and world.has_method("save_world"):
		world.save_world()
	get_tree().paused = false
	visible = false
	GameManager.change_state(GameManager.GameState.MAIN_MENU)


func _on_quit() -> void:
	var world := GameManager.world_node
	if world and world.has_method("_save_and_quit"):
		world._save_and_quit()
	else:
		get_tree().quit()
