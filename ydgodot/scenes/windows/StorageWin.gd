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
## S11：案件收起后禁止再写进度（取回 / 拖出 / 去推演）。
var writes_enabled := true
var _action_btns: Array[Button] = []
var _rows: VBoxContainer
var _scroll: ScrollContainer
var _list_sig := ""


func setup_store(p_title: String, p_kind: String, p_graph: GraphState, p_case: CaseLoader, w: float = 240.0, h: float = 220.0) -> void:
	store_kind = p_kind
	graph = p_graph
	case_def = p_case
	setup(p_title, w, h)

	content.add_theme_constant_override("separation", 0)
	_scroll = ScrollContainer.new()
	_scroll.name = "store_scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_scroll)

	_rows = VBoxContainer.new()
	_rows.name = "rows"
	_rows.add_theme_constant_override("separation", 4)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_rows)
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
		var hint := "证物袋是空的。把物品或证据拖到左侧「证物袋」图标或窗口上收纳；点一行可取回。"
		if store_kind == GraphState.LEDGER:
			hint = "线索册是空的。把线索拖到左侧「线索册」图标或窗口上收纳；点一行可取回。"
		var empty := TecTheme.label(hint, TecTheme.FS_BODY, TecTheme.MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(180.0, 0)
		_rows.add_child(empty)
		return
	for key in list:
		_rows.add_child(_make_row(String(key)))


## 一行：标签 + 「取回」按钮；**整行可按住拖走**（Web `06-storage.js` 的行拖拽）
func _make_row(key: String) -> Control:
	var n := graph.node(key)
	var row := PanelContainer.new()
	row.name = "row_" + key.replace(":", "_")
	row.custom_minimum_size = Vector2(0, 30)
	row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	## D2：清单行不再做成独立盒子，只留底部 1px 发丝线；左右内容缩进 8，
	## 发丝线也各缩 8（负 expand margin 只影响绘制，不动内容排版）。
	var sb := TecTheme.flat(TecTheme.NONE, 0, TecTheme.NONE, 0)
	sb.border_color = TecTheme.edge(0.18)
	sb.border_width_bottom = 1
	sb.expand_margin_left = -8.0
	sb.expand_margin_right = -8.0
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	row.add_theme_stylebox_override("panel", sb)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(func(ev: InputEvent): _on_row_input(ev, key))
	var hb := HBoxContainer.new()
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hb)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_col.add_theme_constant_override("separation", 1)
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(text_col)

	var label_text := String(n.get("label", key))
	var label := TecTheme.label(label_text, TecTheme.FS_BODY, TecTheme.TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.tooltip_text = label_text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(label)

	# 袋清单标注来源（Web 版 bagFrom 口径）。放第二行：长来源只在自己的
	# 文本列里省略，不会把「取回 / 上桌布」挤出条目。
	if store_kind == GraphState.BAG:
		var from_id := String(n.get("bag_from", ""))
		if from_id != "":
			var from_text := "来自 " + case_def.label_of(CaseLoader.kind_of_ref(from_id), from_id)
			var src := TecTheme.label(from_text, TecTheme.FS_BODY, TecTheme.MUTED)
			src.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			src.clip_text = true
			src.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			src.tooltip_text = from_text
			src.mouse_filter = Control.MOUSE_FILTER_IGNORE
			text_col.add_child(src)

	var actions := HBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_SHRINK_END
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.add_theme_constant_override("separation", 4)
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(actions)

	if store_kind == GraphState.LEDGER:
		var to_mx := TecTheme.button("去推演")
		to_mx.tooltip_text = "把这条线索放到推演桌布"
		to_mx.custom_minimum_size = Vector2(54, 22)
		to_mx.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		to_mx.add_theme_font_size_override("font_size", TecTheme.FS_BODY)
		to_mx.pressed.connect(func():
			if writes_enabled:
				to_matrix.emit(key))
		to_mx.disabled = not writes_enabled
		_action_btns.append(to_mx)
		actions.add_child(to_mx)

	var btn := TecTheme.button("取回画布")
	btn.custom_minimum_size = Vector2(66, 22)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", TecTheme.FS_BODY)
	btn.pressed.connect(func():
		if writes_enabled:
			_take(key))
	btn.disabled = not writes_enabled
	_action_btns.append(btn)
	actions.add_child(btn)
	return row


func set_writes_enabled(on: bool) -> void:
	writes_enabled = on
	for b in _action_btns:
		if b != null and is_instance_valid(b):
			b.disabled = not on


func _on_row_input(ev: InputEvent, key: String) -> void:
	if not writes_enabled:
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			row_pressed.emit(key, store_kind, mb.global_position)
			accept_event()


func _take(key: String) -> void:
	if not writes_enabled or graph == null or not graph.stored.has(key):
		return
	will_take.emit(key)
	if not graph.take_back(key):
		return
	took.emit(key)
	refresh_store()
