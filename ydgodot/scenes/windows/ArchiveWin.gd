class_name ArchiveWin
extends SysWindow
## 档案窗（对齐 Web 版 12-panels.js 的 ARCHIVE // 档案）：
## 顶部「现在」，往下把已获得的时刻倒序排开（越往下越早）。
## 每档一行：日期 + 简介（地点 —— 人物　开场摘要），行尾是「当前 / 已回顾」。
## 点别的档 = 切时刻；点当前档 = 重放那段回忆。

signal time_selected(time_id: String)

var graph: GraphState
var case_def: CaseLoader
var _rows: VBoxContainer


func setup_archive(p_graph: GraphState, p_case: CaseLoader, w: float = 300.0, h: float = 330.0) -> void:
	graph = p_graph
	case_def = p_case
	setup("档案", w, h)

	var scroll := ScrollContainer.new()
	scroll.name = "archive_scroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.name = "rows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 3)
	scroll.add_child(_rows)
	refresh_archive()


func refresh_archive() -> void:
	if _rows == null or graph == null or case_def == null:
		return
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()

	var cur := graph.time
	var known: Array = graph.timeline_known()
	known.reverse()
	var ids: Array = [GraphState.PRESENT_TIME]
	ids.append_array(known)
	for i in ids.size():
		_rows.add_child(_make_row(String(ids[i]), String(ids[i]) == cur, i == ids.size() - 1))


func _make_row(tid: String, current: bool, last: bool = false) -> Control:
	var row := Button.new()
	row.name = "row_" + tid
	row.custom_minimum_size = Vector2(0, 46)
	row.focus_mode = Control.FOCUS_NONE
	row.add_theme_stylebox_override("normal", TecTheme.flat(TecTheme.NONE, TecTheme.R_BTN, TecTheme.NONE, 0))
	row.add_theme_stylebox_override("hover", TecTheme.flat(TecTheme.BG, TecTheme.R_BTN, TecTheme.NONE, 0))
	row.add_theme_stylebox_override("pressed", TecTheme.flat(TecTheme.FACE_LO, TecTheme.R_BTN, TecTheme.NONE, 0))
	row.pressed.connect(_on_row_pressed.bind(tid))

	var pad := MarginContainer.new()
	pad.name = "pad"
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.offset_left = 8
	pad.offset_right = -8
	pad.offset_top = 4
	pad.offset_bottom = -4
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pad)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(line)

	var meta := VBoxContainer.new()
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_theme_constant_override("separation", 0)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(meta)

	var title_text := case_def.time_label_of(tid)
	var title := TecTheme.label(title_text, TecTheme.FS_BODY, TecTheme.TEXT)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.tooltip_text = title_text
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(title)

	var brief := _brief_of(tid)
	var sub := TecTheme.label(brief, TecTheme.FS_BODY, TecTheme.MUTED)
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.tooltip_text = brief
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(sub)

	var st := TecTheme.label(_status_of(tid, current), TecTheme.FS_BODY, TecTheme.MUTED)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(st)
	if not last:
		var sep := ColorRect.new()
		sep.name = "sep"
		sep.color = TecTheme.edge(0.18)
		sep.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		sep.offset_left = 8
		sep.offset_right = -8
		sep.offset_top = -1
		sep.offset_bottom = 0
		sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(sep)
	return row


func _brief_of(tid: String) -> String:
	if tid == GraphState.PRESENT_TIME:
		return "侦查进行中"
	var b := case_def.time_brief_of(tid)
	var parts: Array = []
	var where := String(b.get("where", ""))
	var who := String(b.get("who", ""))
	if where != "":
		parts.append(where)
	if who != "":
		parts.append(who)
	var head := " —— ".join(parts)
	var sum := String(b.get("sum", ""))
	if head == "" and sum == "":
		return "（还没有关于这一天的记录）"
	if head == "":
		return sum
	if sum == "":
		return head
	return head + "　" + sum


func _status_of(tid: String, current: bool) -> String:
	if current:
		return "当前"
	if tid != GraphState.PRESENT_TIME and bool(graph.card_seen.get(tid, false)):
		return "已回顾"
	return ""


func _on_row_pressed(tid: String) -> void:
	press_time(tid)


## 供真实点击与无头测试共用：选中一档后把窗收起来（与 Web 的 closeGotoWin 一致）
func press_time(tid: String) -> bool:
	if graph == null:
		return false
	var known: Array = graph.timeline_known()
	if tid != GraphState.PRESENT_TIME and not known.has(tid):
		return false
	time_selected.emit(tid)
	closed.emit()
	queue_free()
	return true


## 测试钩子：每档的显示信息（顺序 = 窗里的顺序）
func rows_info() -> Array:
	if _rows == null or graph == null:
		return []
	var out: Array = []
	var cur := graph.time
	for c in _rows.get_children():
		var tid := String(c.name).trim_prefix("row_")
		var parts := _row_labels(c)
		out.append({
			"id": tid,
			"label": parts[0],
			"sub": parts[1],
			"status": parts[2],
			"current": tid == cur,
		})
	return out


func _row_labels(row: Control) -> Array:
	var out: Array = ["", "", ""]
	var pad := row.get_node_or_null("pad")
	if pad == null:
		return out
	var line := pad.get_child(0) as HBoxContainer
	if line == null:
		return out
	var meta := line.get_child(0) as VBoxContainer
	if meta != null:
		out[0] = (meta.get_child(0) as Label).text
		out[1] = (meta.get_child(1) as Label).text
	if line.get_child_count() > 1:
		out[2] = (line.get_child(1) as Label).text
	return out
