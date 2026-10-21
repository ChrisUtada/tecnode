class_name PeopleWin
extends SysWindow
## 人物名册（对齐 Web `people-win` / `ROSTER // 人物`）
##
## 两种行，长得一样、动作不同（Web `12-panels.js:401-506`）：
##   · **常驻成员**（TEC / 执行者）—— 一进游戏就在册，没有画布节点，点一行 = 打开各自的窗；
##   · **遇到的人** —— 已结识的剧情角色，点一行 = 叫到画布中央并选中，接着说下一句。
## 左侧 48×48 小头像：有素材用像素图（TEC / 执行者复用各自窗里那张），
## 没有的用「首字方块」占位（2026-10-14 用户决定；24×24 在真机上认不出是谁）。
## 状态列只给状态词、**不给 x/y 计数**（用户要求）。

signal row_clicked(id: String)

## 与 ChatWindow / IntroWin 同一份素材（同一角色在哪儿都是这张脸）
const AVATAR := {
	"CHARS_TEC": "res://assets/raw/tec-avatar.png",
	"CHARS_EXEC": "res://assets/raw/executor-avatar.png",
}

var graph: GraphState
var case_def: CaseLoader
var _list: VBoxContainer
var _scroll: ScrollContainer


## h 是 **body 高**（SysWindow 会再加 PAD*2）。Web `.people-win .syswin-body{max-height:356px}`，
## 而 body 还要扣掉标题栏 23 与上下 20 —— 所以传 399 才能得到 356 的列表区。
func setup_people(p_graph: GraphState, p_case: CaseLoader, w: float = 324.0, h: float = 399.0) -> void:
	graph = p_graph
	case_def = p_case
	setup("ROSTER // 人物", w, h)
	_scroll = ScrollContainer.new()
	_scroll.name = "people_scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.name = "people_list"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	_scroll.add_child(_list)
	refresh_people()


func refresh_people() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var ids: Array = graph.met_char_ids() if graph != null else []
	if ids.is_empty():
		var empty := TecTheme.label("（还没有结识任何人）展开场景、读一读文本，就会记下遇到的人",
			TecTheme.FS_BODY, TecTheme.FAINT)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(body.size.x - 10.0, 0)
		_list.add_child(empty)
		return
	for id in ids:
		_list.add_child(_make_row(String(id)))


func _make_row(id: String) -> Control:
	var pinned := GraphState.ROSTER_PINNED.has(id)
	var ch := case_def.char_of(id) if case_def != null else null
	var nm := id
	if pinned and GraphState.ROSTER_PINNED_NAME.has(id):
		nm = String(GraphState.ROSTER_PINNED_NAME[id])
	elif ch != null and ch.name != "":
		nm = ch.name
	var desc := ""
	if pinned and GraphState.ROSTER_PINNED_DESC.has(id):
		desc = String(GraphState.ROSTER_PINNED_DESC[id])
	elif ch != null:
		desc = case_def.strip_tags(ch.desc) if ch.desc != "" else ""

	var state := ""
	var done := false
	if pinned:
		state = String(GraphState.ROSTER_PINNED_TAG.get(id, ""))
	else:
		var pr: Dictionary = graph.char_progress(id)
		var prog := int(pr.get("prog", 0))
		var total := int(pr.get("total", 0))
		if total <= 0:
			state = "无对话文本"
		elif prog >= total:
			state = "已聊完"
			done = true
		elif prog > 0:
			state = "可继续"
		else:
			state = "未交谈"

	var row := PanelContainer.new()
	row.name = "row_" + id
	row.add_theme_stylebox_override("panel", _row_style(false))
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(func(ev: InputEvent): _on_row_input(ev, id))
	row.mouse_entered.connect(func(): row.add_theme_stylebox_override("panel", _row_style(true)))
	row.mouse_exited.connect(func(): row.add_theme_stylebox_override("panel", _row_style(false)))

	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 8)
	row.add_child(hb)

	hb.add_child(_make_avatar(id, nm))

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 1)
	hb.add_child(box)

	var lb := TecTheme.label(nm, TecTheme.FS_TITLE, TecTheme.TEXT)
	lb.clip_text = true
	lb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lb)

	if desc != "":
		var ds := TecTheme.label(desc, TecTheme.FS_SMALL, TecTheme.FAINT)
		ds.clip_text = true
		ds.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		ds.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(ds)

	var st := TecTheme.label(state, TecTheme.FS_SMALL, TecTheme.LINE2 if done else TecTheme.FAINT)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(st)
	return row


func _row_style(hover: bool) -> StyleBoxFlat:
	var sb := TecTheme.flat(TecTheme.BG if hover else Color(0, 0, 0, 0), TecTheme.R_BTN,
		Color(0, 0, 0, 0) if not hover else Color(0, 0, 0, 0))
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


## 48×48 头像位：有素材放像素图，没有放首字（Web `.people-win .goto-item .av`）
func _make_avatar(id: String, name_text: String) -> Control:
	var frame := PanelContainer.new()
	frame.name = "av"
	frame.custom_minimum_size = Vector2(48, 48)
	frame.size = Vector2(48, 48)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel",
		TecTheme.flat(TecTheme.BG, TecTheme.R_SM, TecTheme.EDGE, 1))
	var path := String(AVATAR.get(id, ""))
	if path != "" and ResourceLoader.exists(path):
		var tr := TextureRect.new()
		tr.texture = load(path)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(tr)
	else:
		var c := CenterContainer.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(c)
		var ini := TecTheme.label(name_text.substr(0, 1) if name_text != "" else "?", 22, TecTheme.MUTED)
		ini.name = "ini"
		ini.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(ini)
	return frame


func _on_row_input(ev: InputEvent, id: String) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			row_clicked.emit(id)
			accept_event()


## ── 测试钩子 ──────────────────────────────────────────────────────────
func row_ids() -> Array:
	var out: Array = []
	if _list == null:
		return out
	for c in _list.get_children():
		var nm := String(c.name)
		if nm.begins_with("row_"):
			out.append(nm.substr(4))
	return out


func row_state(id: String) -> String:
	if _list == null:
		return ""
	var row := _list.get_node_or_null("row_" + id)
	if row == null:
		return ""
	var hb := row.get_child(0) as Control
	if hb == null:
		return ""
	var st := hb.get_child(hb.get_child_count() - 1) as Label
	return st.text if st != null else ""
