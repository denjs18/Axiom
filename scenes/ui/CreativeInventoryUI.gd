## CreativeInventoryUI.gd — code-only creative item palette.
## Press G (open_creative) to toggle. Click any item to put a full stack into
## the currently selected hotbar slot. Only instantiated in creative worlds.
extends CanvasLayer

const COLS := 9
const CELL := 52

var _root: CenterContainer = null
var _grid: GridContainer = null
var _built := false
var _open := false


func _ready() -> void:
	layer = 50
	_build_root()
	_root.visible = false


func _build_root() -> void:
	_root = CenterContainer.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(COLS * CELL + 64, 560)
	_root.add_child(panel)

	var vb := VBoxContainer.new()
	panel.add_child(vb)

	var title := Label.new()
	title.text = "Inventaire créatif — clic pour prendre un bloc  ·  G pour fermer"
	vb.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(COLS * CELL + 44, 500)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = COLS
	scroll.add_child(_grid)


func _populate() -> void:
	if _built:
		return
	_built = true
	var ids := ItemRegistry.get_all_item_ids()
	ids.sort_custom(_sort_blocks_first)
	for id in ids:
		var item := ItemRegistry.get_item(id)
		if item == null:
			continue
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(CELL - 4, CELL - 4)
		btn.tooltip_text = "%s\n(%s)" % [item.display_name, id]
		var icon := ItemIcon.new()
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(icon)
		icon.item_id = id
		btn.pressed.connect(_give.bind(id))
		_grid.add_child(btn)


## Blocks first (what you mostly want to test), then everything else, A→Z.
func _sort_blocks_first(a: String, b: String) -> bool:
	var ia := ItemRegistry.get_item(a)
	var ib := ItemRegistry.get_item(b)
	var ba: bool = ia != null and ia.raw.get("is_block", false)
	var bb: bool = ib != null and ib.raw.get("is_block", false)
	if ba != bb:
		return ba
	return a < b


func _give(id: String) -> void:
	var player = GameManager.local_player
	if player == null or player.inventory == null:
		return
	var item := ItemRegistry.get_item(id)
	var count: int = item.max_stack if item else 1
	player.inventory.set_slot(player.selected_hotbar_slot, ItemRegistry.make_stack(id, count))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_creative"):
		_toggle()
		get_viewport().set_input_as_handled()
	elif _open and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	if _open:
		_close()
	else:
		_open_panel()


func _open_panel() -> void:
	_populate()
	_open = true
	_root.visible = true
	GameManager.ui_open()


func _close() -> void:
	_open = false
	_root.visible = false
	GameManager.ui_close()
