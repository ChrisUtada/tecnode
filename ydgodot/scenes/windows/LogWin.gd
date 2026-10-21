class_name LogWin
extends SysWindow
## 因果追踪窗（对齐 Web `#log-win` / `SYS_LOGS // 因果追踪`）
##
## 案卷式清单：一条一条往下堆，新的在底部、自动滚到底。
## 条目样式照抄 `06-shell.css:94-102`：
##   · 普通  —— 正文色 + 底部 1px 细线
##   · sys   —— 加粗，前缀「▍ 」
##   · warn  —— 灰（MUTED），前缀「※ 」
##   · err   —— 反白（深底浅字）
##   · cap   —— 下划线（捕获到线索）
##   · act   —— 浅底（做成了某件事）
## 内容本身不在这里判断 —— 写不写、写什么由调用方按 Web 的日志口径决定（见 GraphState.add_log）。

const PREFIX := {"sys": "▍ ", "warn": "※ "}

var graph: GraphState
var _scroll: ScrollContainer
var _list: VBoxContainer
var _rows: Array[Control] = []


## h 是 **body 高**。Web `.log-win .log-body{max-height:340px}`，body 还要扣掉标题栏 23
## 与上下 20 —— 传 383 才对应 340 的列表区。
func setup_log(p_graph: GraphState, w: float = 320.0, h: float = 383.0) -> void:
	graph = p_graph
	setup("SYS_LOGS // 因果追踪", w, h)
	_scroll = ScrollContainer.new()
	_scroll.name = "log_scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.name = "log_list"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 0)
	_scroll.add_child(_list)
	refresh_log()


func refresh_log() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows.clear()
	var entries: Array = graph.logs if graph != null else []
	if entries.is_empty():
		var empty := TecTheme.label("（还没有记录）", TecTheme.FS_BODY, TecTheme.FAINT)
		_list.add_child(empty)
		return
	for e in entries:
		var kind := String((e as Dictionary).get("kind", ""))
		var text := String((e as Dictionary).get("text", ""))
		_list.add_child(_make_row(text, kind))
	_scroll_to_end()


func _make_row(text: String, kind: String) -> Control:
	var row := PanelContainer.new()
	row.name = "log_row"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(0)
	sb.border_width_bottom = 1
	sb.border_color = TecTheme.LINE2
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	if kind == "err":
		sb.bg_color = TecTheme.TEXT
	elif kind == "act":
		sb.bg_color = TecTheme.BG
	row.add_theme_stylebox_override("panel", sb)
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var lab := RichTextLabel.new()
	lab.name = "log_text"
	lab.bbcode_enabled = true
	lab.fit_content = true
	lab.scroll_active = false
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.custom_minimum_size = Vector2(body.size.x - 12.0, 0)
	lab.add_theme_font_override("normal_font", TecTheme.font())
	lab.add_theme_font_override("bold_font", TecTheme.font())
	lab.add_theme_font_size_override("normal_font_size", TecTheme.FS_BODY)
	lab.add_theme_font_size_override("bold_font_size", TecTheme.FS_BODY)
	lab.add_theme_constant_override("line_separation", 5)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var col := TecTheme.TEXT
	if kind == "warn":
		col = TecTheme.MUTED
	elif kind == "err":
		col = TecTheme.CARD
	lab.add_theme_color_override("default_color", col)
	var body_text := String(PREFIX.get(kind, "")) + text
	if kind == "sys":
		body_text = "[b]%s[/b]" % body_text
	elif kind == "cap":
		body_text = "[u]%s[/u]" % body_text
	lab.text = body_text
	row.add_child(lab)
	_rows.append(row)
	return row


func _scroll_to_end() -> void:
	if _scroll == null:
		return
	# 内容高度下一帧才定下来；无头环境里 call_deferred 同样会跑到
	_scroll.set_deferred("scroll_vertical", 1 << 20)


## ── 测试钩子 ──────────────────────────────────────────────────────────
func entry_count() -> int:
	return _rows.size()


func entry_label(i: int) -> String:
	if i < 0 or i >= _rows.size():
		return ""
	var lab := _rows[i].get_node_or_null("log_text") as RichTextLabel
	return lab.text if lab != null else ""


func kinds() -> Array:
	var out: Array = []
	if graph == null:
		return out
	for e in graph.logs:
		out.append(String((e as Dictionary).get("kind", "")))
	return out
