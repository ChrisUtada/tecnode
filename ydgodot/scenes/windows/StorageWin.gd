class_name StorageWin
extends SysWindow
## 收纳窗（证物袋 / 线索册共用一个类，只差标题与收录规则）
##
## 对齐 Web 版的 bag-win / clue-win：窗里是一份清单，每行一条；
## 单击一行 = 取回画布（回到窗旁边的位置）。
## 证物袋什么都收；线索册只有线索能进（规则在 GraphState.ledger_store 里）。

signal will_take(key: String)
signal took(key: String)
signal to_matrix(key: String)
## 行被按住（Web：按住一行拖走 = 三个落点；单击 = 取回）。桌面侧接管后续手势。
signal row_pressed(key: String, from_kind: String, at_global: Vector2)

var store_kind: String = GraphState.BAG
var graph: GraphState
var case_def: CaseLoader
var _rows: VBoxContainer
var _list_sig := ""


func setup_store(p_title: String, p_kind: String, p_graph: GraphState, p_case: CaseLoader, w: float = 240.0, h: float = 220.0) -> void:
	store_kind = p_kind
	graph = p_graph
	case_def = p_case
	setup(p_title, w, h)

	_rows = VBoxContainer.new()
	_rows.name = "rows"
	_rows.add_theme_constant_override("separation", 4)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_rows)
	refresh_store()


## 清单条目 = 收纳去向是这个窗的节点
func items() -> Array:
	var out: Array = []
	if graph == null:
		return out
	for key in graph.stored.keys():
		if String(graph.stored[key]) == store_kind:
			out.append(key)
	out.sort()
	return out


func refresh_store() -> void:
	if _rows == null:
		return
	var list := items()
	var sig := "v1:"
	for key in list:
		var n := graph.node(String(key))
		sig += String(key) + String.chr(31) + String(n.get("label", "")) + String.chr(31) \
			+ String(n.get("bag_from", "")) + String.chr(30)
	if sig == _list_sig:
		return
	_list_sig = sig
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	if list.is_empty():
		var empty := TecTheme.label("（空）", TecTheme.FS_BODY, TecTheme.MUTED)
		_rows.add_child(empty)
		return
	for key in list:
		_rows.add_child(_make_row(String(key)))


## 一行：标签 + 「取回」按钮；**整行可按住拖走**（Web `06-storage.js` 的行拖拽）
func _make_row(key: String) -> Control:
	var n := graph.node(key)
	var row := PanelContainer.new()
	row.name = "row_" + key.replace(":", "_")
	row.add_theme_stylebox_override("panel", TecTheme.flat(TecTheme.CARD, TecTheme.R_BTN, TecTheme.EDGE, 1))
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(func(ev: InputEvent): _on_row_input(ev, key))
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hb)

	var label := TecTheme.label(String(n.get("label", key)), TecTheme.FS_BODY, TecTheme.TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(label)

	# 袋清单标注来源（Web 版 bagFrom 口径）
	if store_kind == GraphState.BAG:
		var from_id := String(n.get("bag_from", ""))
		if from_id != "":
			var src := TecTheme.label("来自 " + case_def.label_of("item", from_id), TecTheme.FS_BODY, TecTheme.MUTED)
			src.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hb.add_child(src)

	if store_kind == GraphState.LEDGER:
		var to_mx := TecTheme.button("上桌布")
		to_mx.custom_minimum_size = Vector2(54, 22)
		to_mx.add_theme_font_size_override("font_size", TecTheme.FS_BODY)
		to_mx.pressed.connect(func(): to_matrix.emit(key))
		hb.add_child(to_mx)

	var btn := TecTheme.button("取回")
	btn.custom_minimum_size = Vector2(44, 22)
	btn.add_theme_font_size_override("font_size", TecTheme.FS_BODY)
	btn.pressed.connect(func(): _take(key))
	hb.add_child(btn)
	return row


func _on_row_input(ev: InputEvent, key: String) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			row_pressed.emit(key, store_kind, mb.global_position)
			accept_event()


func _take(key: String) -> void:
	if graph == null or not graph.stored.has(key):
		return
	will_take.emit(key)
	if not graph.take_back(key):
		return
	took.emit(key)
	refresh_store()
