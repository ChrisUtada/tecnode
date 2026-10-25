class_name PeopleWin
extends SysWindow
## 人物名册（对齐 Web `people-win` / `ROSTER // 人物`）
##
## 点行统一 = 打开人物档案卡（PEOPLE_CARD_PLAN），不再直接跳转 / 叫人；
## 跳转降级为卡内「前往此人」。调查员（玩家自己）常驻首位，其后 TEC / 执行者 / 已结识角色。
## 左侧 48×48 小头像：有素材用像素图（TEC / 执行者复用各自窗里那张），
## 没有的用「首字方块」占位（2026-10-14 用户决定；24×24 在真机上认不出是谁）。
## 状态列只给状态词、**不给 x/y 计数**（用户要求）。

signal row_clicked(id: String)

## 与 ChatWindow / IntroWin 同一份素材（同一角色在哪儿都是这张脸）
const AVATAR := {
	"CHARS_TEC": "res://assets/raw/tec-avatar.png",
	"CHARS_EXEC": "res://assets/raw/executor-avatar.png",
}
const AvatarFrameScript = preload("res://ui/AvatarFrame.gd")

var graph: GraphState
var case_def: CaseLoader
var _investigator: Dictionary = {}
var _list: VBoxContainer
var _scroll: ScrollContainer
var _list_sig := ""


## h 是 **body 高**（SysWindow 会再加 PAD*2）。Web `.people-win .syswin-body{max-height:356px}`，
## 而 body 还要扣掉标题栏 23 与上下 20 —— 所以传 399 才能得到 356 的列表区。
func setup_people(p_graph: GraphState, p_case: CaseLoader, w: float = 324.0,
		h: float = 399.0, p_investigator: Dictionary = {}) -> void:
	graph = p_graph
	case_def = p_case
	_investigator = p_investigator.duplicate(true)
	setup("人物", w, h)
	_scroll = ScrollContainer.new()
	_scroll.name = "people_scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.name = "people_list"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	## 6 行 × (48 头像 + 上下 4) + 5 × 2 = 346，默认 body 351 内完整露出。
	_list.add_theme_constant_override("separation", 2)
	_scroll.add_child(_list)
	refresh_people()


func set_investigator(p_investigator: Dictionary) -> void:
	_investigator = p_investigator.duplicate(true)
	refresh_people()


func refresh_people() -> void:
	if _list == null:
		return
	var ids: Array = []
	if not _investigator.is_empty():
		ids.append(GraphState.INVESTIGATOR_ID)
	if graph != null:
		ids.append_array(graph.met_char_ids())
	var sig := "v2:" + String(_investigator.get("name", "")) + ":" \
		+ String(_investigator.get("id", "")) + String.chr(30)
	for id in ids:
		var pr: Dictionary = graph.char_progress(String(id)) if graph != null else {}
		sig += String(id) + String.chr(31) + str(int(pr.get("prog", 0))) + "/" \
			+ str(int(pr.get("total", 0))) + String.chr(30)
	if sig == _list_sig:
		return
	_list_sig = sig
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
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
	var investigator := id == GraphState.INVESTIGATOR_ID
	var ch := case_def.char_of(id) if case_def != null else null
	var nm := id
	var desc := ""
	var state := ""
	var done := false
	if investigator:
		nm = String(_investigator.get("name", "调查员"))
		desc = "T.E.C-OS 调查员"
		state = "调查员"
		done = true
	elif pinned:
		if GraphState.ROSTER_PINNED_NAME.has(id):
			nm = String(GraphState.ROSTER_PINNED_NAME[id])
		if GraphState.ROSTER_PINNED_DESC.has(id):
			desc = String(GraphState.ROSTER_PINNED_DESC[id])
		state = String(GraphState.ROSTER_PINNED_TAG.get(id, ""))
	else:
		if ch != null and ch.name != "":
			nm = ch.name
		if ch != null:
			desc = ch.desc if ch.desc != "" else ""
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
	lb.tooltip_text = nm
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lb)

	if desc != "":
		var ds := TecTheme.label(desc, TecTheme.FS_BODY, TecTheme.MUTED)
		ds.clip_text = true
		ds.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		ds.tooltip_text = desc
		ds.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(ds)

	var st := TecTheme.label(state, TecTheme.FS_BODY, TecTheme.TEXT if done else TecTheme.MUTED)
	st.clip_text = true
	st.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	st.tooltip_text = state
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(st)
	return row


func _row_style(hover: bool) -> StyleBoxFlat:
	var sb := TecTheme.flat(TecTheme.BG if hover else TecTheme.NONE, 0,
		TecTheme.NONE, 0)
	sb.border_color = TecTheme.edge(0.18)
	sb.border_width_bottom = 1
	## D2：发丝线左右各缩 8px（负 expand margin 只影响绘制，不动内容排版）。
	sb.expand_margin_left = -8.0
	sb.expand_margin_right = -8.0
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


## 48×48 头像位：有素材放像素图，没有放首字（Web `.people-win .goto-item .av`）
func _make_avatar(id: String, name_text: String) -> Control:
	var frame := AvatarFrameScript.new()
	frame.name = "av"
	frame.setup(_avatar_path(id), 48.0,
		name_text.substr(0, 1) if name_text != "" else "?")
	return frame


func _avatar_path(id: String) -> String:
	if id == GraphState.INVESTIGATOR_ID:
		return String(AVATAR.get(String(_investigator.get("avatarId", "")), ""))
	if AVATAR.has(id):
		return String(AVATAR[id])
	var ch := case_def.char_of(id) if case_def != null else null
	if ch == null or String(ch.avatar).strip_edges() == "":
		return ""
	var raw := String(ch.avatar)
	if raw.begins_with("res://") and ResourceLoader.exists(raw):
		return raw
	var base := raw.get_file()
	for root in ["res://assets/raw/", "res://assets/images/", "res://images/"]:
		if ResourceLoader.exists(root + base):
			return root + base
	return ""


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
