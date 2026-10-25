class_name LogWin
extends SysWindow
## 因果追踪窗（对齐 Web `#log-win` / `SYS_LOGS // 因果追踪`）
##
## 案卷式清单：一条一条往下堆，新的在底部、自动滚到底。
## 条目样式照抄 `06-shell.css:94-102`：
##   · 普通  —— 正文色 + 底部 1px 细线
##   · sys   —— 正文色 + 前缀「▍ 」
##   · warn  —— 灰（MUTED），前缀「※ 」
##   · err   —— 反白（深底浅字）
##   · cap   —— 下划线（捕获到线索）
##   · act   —— 浅底（做成了某件事）
## 新落到最底部的一条按打字机逐字显现。
## 内容本身不在这里判断 —— 写不写、写什么由调用方按 Web 的日志口径决定（见 GraphState.add_log）。

const PREFIX := {"sys": "▍ ", "warn": "※ "}

var graph: GraphState
var _scroll: ScrollContainer
var _list: VBoxContainer
var _rows: Array[Control] = []
var _log_sig := ""
var _typing_lab: RichTextLabel
var _typing_total := 0
var _typing_shown := 0.0
## F7：整数档位缓存。旧版每帧写 `visible_characters` 并 deferred 滚到底；
## 60fps 下同一个字会被重复写约 2.7 次，滚动指令也会重复排队。
var _typing_n := -1
var _typing_writes := 0
## 基准用：强制回到 F7 之前的「每帧写 + 每帧滚动」。
var _legacy_writes := false


## h 是 **body 高**。Web `.log-win .log-body{max-height:340px}`，body 还要扣掉标题栏 23
## 与上下 20 —— 传 383 才对应 340 的列表区。
func setup_log(p_graph: GraphState, w: float = 320.0, h: float = 383.0) -> void:
	graph = p_graph
	setup("日志", w, h)
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
	var entries: Array = graph.logs if graph != null else []
	var sig := "v1:" + str(entries.size()) + ":"
	for e in entries:
		sig += String((e as Dictionary).get("kind", "")) + String.chr(31) \
			+ String((e as Dictionary).get("text", "")) + String.chr(30)
	if sig == _log_sig:
		return
	_log_sig = sig
	_stop_typing()
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows.clear()
	if entries.is_empty():
		var empty := TecTheme.label("（还没有记录）", TecTheme.FS_BODY, TecTheme.MUTED)
		_list.add_child(empty)
		return
	for i in entries.size():
		var e: Dictionary = entries[i]
		var kind := String(e.get("kind", ""))
		var text := String(e.get("text", ""))
		var row := _make_row(text, kind)
		_list.add_child(row)
		if i == entries.size() - 1:
			_start_typing(row.get_node_or_null("log_text") as RichTextLabel)
	_scroll_to_end()


func _start_typing(lab: RichTextLabel) -> void:
	if lab == null:
		return
	_typing_total = lab.get_total_character_count()
	if _typing_total <= 0:
		return
	_typing_lab = lab
	_typing_shown = 0.0
	_typing_n = 0
	_typing_writes = 0
	lab.visible_characters = 0
	set_process(true)


func _stop_typing() -> void:
	if _typing_lab != null and is_instance_valid(_typing_lab):
		_typing_lab.visible_characters = -1
	_typing_lab = null
	_typing_total = 0
	_typing_shown = 0.0
	_typing_n = -1
	set_process(false)


func _process(delta: float) -> void:
	if _typing_lab == null or not is_instance_valid(_typing_lab):
		_stop_typing()
		return
	_typing_shown += delta * (1000.0 / TypewriterLabel.CHAR_MS)
	var n := int(_typing_shown)
	if n >= _typing_total:
		_stop_typing()
		return
	if not _legacy_writes and n == _typing_n:
		return
	_typing_n = n
	_typing_writes += 1
	_typing_lab.visible_characters = n
	_scroll_to_end()


func _make_row(text: String, kind: String) -> Control:
	var row := PanelContainer.new()
	row.name = "log_row"
	var sb := StyleBoxFlat.new()
	sb.bg_color = TecTheme.NONE
	sb.set_border_width_all(0)
	sb.border_width_bottom = 1
	sb.border_color = TecTheme.LINE2
	sb.content_margin_left = 5
	## 右侧留出滚动条宽度 + 4px：原来 5px 会把最后一行文字压在滚动条下面。
	sb.content_margin_right = 12
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
	## 不再写死 `body.size.x - 12`：固定宽度加行内边距会超过 ScrollContainer
	## 的可视宽度，最后一行被裁。让 VBox 决定宽度，换行由 autowrap 处理。
	lab.custom_minimum_size = Vector2(0, 0)
	lab.add_theme_font_override("normal_font", TecTheme.font())
	lab.add_theme_font_size_override("normal_font_size", TecTheme.FS_BODY)
	lab.add_theme_constant_override("line_separation", 5)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var col := TecTheme.TEXT
	if kind == "warn":
		col = TecTheme.MUTED
	elif kind == "err":
		col = TecTheme.CARD
	lab.add_theme_color_override("default_color", col)
	var body_text := String(PREFIX.get(kind, "")) + text
	if kind == "cap":
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
## F7：`visible_characters` 实际写入次数 / 当前整数档位。
func dbg_typing_writes() -> int:
	return _typing_writes


func dbg_typing_n() -> int:
	return _typing_n


func dbg_set_legacy_writes(on: bool) -> void:
	_legacy_writes = on


func dbg_is_typing() -> bool:
	return _typing_lab != null and is_instance_valid(_typing_lab)


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
