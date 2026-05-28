## GameManager.gd
## Autoload singleton. Manages high-level game state (menus, world loading, etc.)
extends Node

enum GameState {
	MAIN_MENU,
	LOADING,
	PLAYING,
	PAUSED,
	GAME_OVER,
}

var current_state: GameState = GameState.MAIN_MENU
var current_world_name: String = ""
var current_dimension: String = "overworld"
var is_multiplayer: bool = false
var is_server: bool = false
var world_seed: int = 0

# References set when world is loaded
var world_node: Node = null
var local_player: Node = null

const MAIN_MENU_SCENE := "res://scenes/ui/MainMenu.tscn"
const WORLD_SCENE := "res://scenes/world/World.tscn"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.ready.connect(_on_root_ready)


func _on_root_ready() -> void:
	# Load main menu on start
	change_state(GameState.MAIN_MENU)


func change_state(new_state: GameState) -> void:
	current_state = new_state
	match new_state:
		GameState.MAIN_MENU:
			_show_main_menu()
		GameState.PLAYING:
			pass  # World already loaded
		GameState.PAUSED:
			_pause_game()
		GameState.GAME_OVER:
			_handle_game_over()


func _show_main_menu() -> void:
	if ResourceLoader.exists(MAIN_MENU_SCENE):
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _pause_game() -> void:
	get_tree().paused = true
	EventBus.game_paused.emit()


func resume_game() -> void:
	get_tree().paused = false
	current_state = GameState.PLAYING
	EventBus.game_resumed.emit()


func _handle_game_over() -> void:
	pass


func start_new_world(world_name: String, wseed: int = 0, modules: Array = []) -> void:
	current_world_name = world_name
	self.world_seed = wseed if wseed != 0 else randi()
	change_state(GameState.LOADING)
	ModuleManager.set_active_modules(modules)
	_load_world_scene()


func load_existing_world(world_name: String) -> void:
	current_world_name = world_name
	change_state(GameState.LOADING)
	_load_world_scene()


func _load_world_scene() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and current_state == GameState.PLAYING:
		change_state(GameState.PAUSED)


func get_world_save_path() -> String:
	return "user://worlds/" + current_world_name + "/"


func set_player(player: Node) -> void:
	local_player = player
	EventBus.player_spawned.emit(player)


func set_world(world: Node) -> void:
	world_node = world
	current_state = GameState.PLAYING


# ── Archives location (seed-derived, cached) ─────────────────────────────────

var _archives_location:  Vector2i = Vector2i.ZERO
var _archives_computed:  bool     = false

func get_archives_location() -> Vector2i:
	if not _archives_computed:
		var angle := fmod(float(world_seed) * 1.6180339, TAU)
		var dist  := 1500 + (world_seed % 1000)
		_archives_location  = Vector2i(int(cos(angle) * dist), int(sin(angle) * dist))
		_archives_computed  = true
	return _archives_location


# ── UI mouse management ───────────────────────────────────────────────────────
# Multiple UIs can be open simultaneously (e.g. RecipeBook + Inventory).
# Only restore CAPTURED when the last UI closes.

var _ui_open_count: int = 0

func ui_open() -> void:
	_ui_open_count += 1
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func ui_close() -> void:
	_ui_open_count = maxi(0, _ui_open_count - 1)
	if _ui_open_count == 0:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
