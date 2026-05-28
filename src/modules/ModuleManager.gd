## ModuleManager.gd
## Autoload singleton. Manages toggleable game modules.
## Each module can add new blocks, items, recipes, mobs, and mechanics.
extends Node

const MODULE_DATA_DIR := "res://data/modules/"
const MODULE_SCRIPTS_DIR := "res://src/modules/"

# All available modules
const MODULE_IDS := [
	"electricity",
	"nuclear",
	"transport",
	"economy",
	"farming",
	"aether",
	"ocean_abyss",
]

var _active_modules: Dictionary = {}   # module_id -> ModuleDef
var _loaded_modules: Dictionary = {}   # module_id -> ModuleDef (all available)


class ModuleDef:
	var id: String
	var display_name: String
	var description: String
	var version: String
	var dependencies: Array
	var enabled: bool = false
	var script_path: String
	var handler: Node = null
	var raw: Dictionary

	func _init(data: Dictionary) -> void:
		raw = data
		id = data.get("id", "unknown")
		display_name = data.get("display_name", id)
		description = data.get("description", "")
		version = data.get("version", "1.0")
		dependencies = data.get("dependencies", [])
		script_path = data.get("script", "")


func _ready() -> void:
	_discover_modules()


func _discover_modules() -> void:
	for mid in MODULE_IDS:
		var path: String = MODULE_DATA_DIR + "module_" + mid + ".json"
		if FileAccess.file_exists(path):
			var file := FileAccess.open(path, FileAccess.READ)
			if file:
				var data: Variant = JSON.parse_string(file.get_as_text())
				file.close()
				if data is Dictionary:
					_loaded_modules[mid] = ModuleDef.new(data)
				else:
					# Create default module def
					_loaded_modules[mid] = ModuleDef.new({"id": mid, "display_name": mid.capitalize()})
		else:
			_loaded_modules[mid] = ModuleDef.new({"id": mid, "display_name": mid.capitalize()})


func set_active_modules(module_ids: Array) -> void:
	_active_modules.clear()
	for mid in module_ids:
		enable_module(mid)


func enable_module(module_id: String) -> bool:
	if not _loaded_modules.has(module_id):
		push_warning("[ModuleManager] Unknown module: " + module_id)
		return false
	# Check dependencies
	var mod: ModuleDef = _loaded_modules[module_id]
	for dep in mod.dependencies:
		if not _active_modules.has(dep):
			if not enable_module(dep):
				push_error("[ModuleManager] Missing dependency '%s' for module '%s'" % [dep, module_id])
				return false
	mod.enabled = true
	_active_modules[module_id] = mod
	_load_module_handler(mod)
	EventBus.module_enabled.emit(module_id)
	print("[ModuleManager] Enabled: " + module_id)
	return true


func disable_module(module_id: String) -> void:
	if not _active_modules.has(module_id):
		return
	var mod: ModuleDef = _active_modules[module_id]
	if mod.handler:
		mod.handler.queue_free()
		mod.handler = null
	mod.enabled = false
	_active_modules.erase(module_id)
	EventBus.module_disabled.emit(module_id)


func is_enabled(module_id: String) -> bool:
	return _active_modules.has(module_id)


func get_enabled_modules() -> Array:
	return _active_modules.keys()


func get_all_modules() -> Array:
	return _loaded_modules.values()


func _load_module_handler(mod: ModuleDef) -> void:
	if mod.script_path.is_empty():
		# Auto-detect handler script
		var auto_path := MODULE_SCRIPTS_DIR + mod.id.to_pascal_case() + "Module.gd"
		if FileAccess.file_exists(auto_path):
			mod.script_path = auto_path
		else:
			return
	var script: Script = load(mod.script_path)
	if script == null:
		return
	var handler := Node.new()
	handler.set_script(script)
	handler.name = mod.id + "_module"
	add_child(handler)
	mod.handler = handler
