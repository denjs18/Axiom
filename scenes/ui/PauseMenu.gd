## PauseMenu.gd — Pause overlay shown when the player presses Escape.
extends CanvasLayer

var _overlay:    ColorRect = null
var _panel:      Panel     = null


func _ready() -> void:
	# Must stay active while the tree is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer        = 10   # above HUD

	_build_ui()
	visible = false

	EventBus.game_paused.connect(_on_paused)
	EventBus.game_resumed.connect(_on_resumed)


func _build_ui() -> void:
	# Dark full-screen overlay
	_overlay               = ColorRect.new()
	_overlay.color         = Color(0, 0, 0, 0.55)
	_overlay.anchor_left   = 0.0
	_overlay.anchor_right  = 1.0
	_overlay.anchor_top    = 0.0
	_overlay.anchor_bottom = 1.0
	_overlay.mouse_filter  = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	# Centered panel
	_panel                = Panel.new()
	_panel.anchor_left    = 0.5
	_panel.anchor_right   = 0.5
	_panel.anchor_top     = 0.5
	_panel.anchor_bottom  = 0.5
	_panel.offset_left    = -140
	_panel.offset_right   =  140
	_panel.offset_top     = -120
	_panel.offset_bottom  =  120

	var panel_style         := StyleBoxFlat.new()
	panel_style.bg_color     = Color(0.10, 0.10, 0.10, 0.95)
	panel_style.border_width_left   = 2
	panel_style.border_width_right  = 2
	panel_style.border_width_top    = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color        = Color(0.45, 0.45, 0.45, 1.0)
	panel_style.corner_radius_top_left     = 6
	panel_style.corner_radius_top_right    = 6
	panel_style.corner_radius_bottom_left  = 6
	panel_style.corner_radius_bottom_right = 6
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	var vbox               := VBoxContainer.new()
	vbox.anchor_left       = 0.0
	vbox.anchor_right      = 1.0
	vbox.anchor_top        = 0.0
	vbox.anchor_bottom     = 1.0
	vbox.offset_left       = 24
	vbox.offset_right      = -24
	vbox.offset_top        = 24
	vbox.offset_bottom     = -24
	vbox.add_theme_constant_override("separation", 16)
	_panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text                = "PAUSE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(title)

	# Separator space
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	# Resume button
	var btn_resume := _make_button("Reprendre")
	btn_resume.pressed.connect(_on_resume)
	vbox.add_child(btn_resume)

	# Quit button
	var btn_quit := _make_button("Quitter")
	btn_quit.pressed.connect(_on_quit)
	vbox.add_child(btn_quit)


func _make_button(text: String) -> Button:
	var btn                    := Button.new()
	btn.text                    = text
	btn.custom_minimum_size     = Vector2(0, 44)
	btn.add_theme_font_size_override("font_size", 16)

	var normal := StyleBoxFlat.new()
	normal.bg_color     = Color(0.20, 0.20, 0.20, 1.0)
	normal.border_width_left   = 1
	normal.border_width_right  = 1
	normal.border_width_top    = 1
	normal.border_width_bottom = 1
	normal.border_color = Color(0.45, 0.45, 0.45)
	normal.corner_radius_top_left     = 4
	normal.corner_radius_top_right    = 4
	normal.corner_radius_bottom_left  = 4
	normal.corner_radius_bottom_right = 4

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.32, 0.32, 0.32, 1.0)

	var pressed_style := normal.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color(0.15, 0.15, 0.15, 1.0)

	btn.add_theme_stylebox_override("normal",   normal)
	btn.add_theme_stylebox_override("hover",    hover)
	btn.add_theme_stylebox_override("pressed",  pressed_style)
	btn.add_theme_color_override("font_color",  Color.WHITE)
	return btn


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


func _on_quit() -> void:
	# Save world before quitting
	var world := GameManager.world_node
	if world and world.has_method("_save_and_quit"):
		world._save_and_quit()
	else:
		get_tree().quit()
