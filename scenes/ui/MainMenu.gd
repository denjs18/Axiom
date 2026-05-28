## MainMenu.gd
## Main menu controller: new game, load game, settings, modules selection.
extends Control

@onready var btn_new_world: Button = $VBox/BtnNewWorld
@onready var btn_load_world: Button = $VBox/BtnLoadWorld
@onready var btn_settings: Button = $VBox/BtnSettings
@onready var btn_quit: Button = $VBox/BtnQuit
@onready var world_name_edit: LineEdit = $NewWorldPanel/VBox/WorldName
@onready var seed_edit: LineEdit = $NewWorldPanel/VBox/Seed
@onready var modules_container: VBoxContainer = $NewWorldPanel/VBox/ModulesScroll/Modules
@onready var new_world_panel: Panel = $NewWorldPanel
@onready var load_world_panel: Panel = $LoadWorldPanel
@onready var world_list: ItemList = $LoadWorldPanel/VBox/WorldList
@onready var btn_start: Button = $NewWorldPanel/VBox/BtnStart
@onready var btn_cancel_new: Button = $NewWorldPanel/VBox/BtnCancelNew
@onready var btn_load: Button = $LoadWorldPanel/VBox/BtnLoad
@onready var btn_cancel_load: Button = $LoadWorldPanel/VBox/BtnCancelLoad

var _module_checkboxes: Dictionary = {}


func _ready() -> void:
	btn_new_world.pressed.connect(_on_new_world_pressed)
	btn_load_world.pressed.connect(_on_load_world_pressed)
	btn_settings.pressed.connect(_on_settings_pressed)
	btn_quit.pressed.connect(get_tree().quit)
	if btn_start:
		btn_start.pressed.connect(_on_start_new_world)
	if btn_cancel_new:
		btn_cancel_new.pressed.connect(func(): if new_world_panel: new_world_panel.hide())
	if btn_load:
		btn_load.pressed.connect(_on_load_selected_world)
	if btn_cancel_load:
		btn_cancel_load.pressed.connect(func(): if load_world_panel: load_world_panel.hide())
	if new_world_panel:
		new_world_panel.hide()
	if load_world_panel:
		load_world_panel.hide()
	_populate_modules()
	_populate_world_list()


func _on_new_world_pressed() -> void:
	if new_world_panel:
		new_world_panel.visible = not new_world_panel.visible


func _on_load_world_pressed() -> void:
	if load_world_panel:
		load_world_panel.visible = not load_world_panel.visible


func _on_settings_pressed() -> void:
	pass  # TODO: Settings screen


func _populate_modules() -> void:
	if modules_container == null:
		return
	for child in modules_container.get_children():
		child.queue_free()
	for mod in ModuleManager.get_all_modules():
		var cb := CheckBox.new()
		cb.text = mod.display_name
		cb.tooltip_text = mod.description
		modules_container.add_child(cb)
		_module_checkboxes[mod.id] = cb


func _populate_world_list() -> void:
	if world_list == null:
		return
	world_list.clear()
	var worlds_dir := "user://worlds/"
	var dir := DirAccess.open(worlds_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while entry_name != "":
		if dir.current_is_dir() and not entry_name.begins_with("."):
			world_list.add_item(entry_name)
		entry_name = dir.get_next()


func _on_start_new_world() -> void:
	var wname := "world" if world_name_edit == null else world_name_edit.text.strip_edges()
	if wname.is_empty():
		wname = "world_%d" % Time.get_unix_time_from_system()
	var wseed := 0
	if seed_edit and not seed_edit.text.is_empty():
		wseed = seed_edit.text.hash()
	var active_mods := []
	for mod_id in _module_checkboxes:
		if _module_checkboxes[mod_id].button_pressed:
			active_mods.append(mod_id)
	GameManager.start_new_world(wname, wseed, active_mods)


func _on_load_selected_world() -> void:
	if world_list == null:
		return
	var selected := world_list.get_selected_items()
	if selected.is_empty():
		return
	var wname := world_list.get_item_text(selected[0])
	GameManager.load_existing_world(wname)
