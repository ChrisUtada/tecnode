class_name CaseMapWin
extends SysWindow

signal enter_requested(case_id: String)

var catalog: CaseCatalog
var current_id: String = ""
var case_open := true

var _rows: VBoxContainer
## 教学第 6 幕：地图只开放 A-001，即使玩家进度里已有别的案子。
var only_id := ""


func setup_map(p_catalog: CaseCatalog, p_current: String, p_open: bool, p_only_id: String = "") -> void:
	catalog = p_catalog
	current_id = p_current
	case_open = p_open
	only_id = p_only_id
	setup("案件", 430, 260)
	_build_map()


func _build_map() -> void:
	var tip := TecTheme.label(
		"每个地址对应一宗案件；捕获「真名」后下一案才会解锁。\n"
		+ "「–」收进右下角卡片，「×」收进本图标，点本案那行展开。",
		TecTheme.FS_BODY, TecTheme.MUTED)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_constant_override("line_spacing", 3)
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(tip)

	## D1：列表是独立小节，用黑条白字标题与说明 / 行分开。
	content.add_child(TecTheme.section_bar("案件索引"))

	_rows = VBoxContainer.new()
	_rows.name = "rows"
	_rows.add_theme_constant_override("separation", 0)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_rows)
	refresh_map()


func refresh_map() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var all := CaseCatalog.all()
	for i in all.size():
		_rows.add_child(_make_row(all[i], i == all.size() - 1))


func _make_row(c: Dictionary, last: bool = false) -> Control:
	var id := String(c["id"])
	var known := catalog != null and catalog.is_unlocked(id) and (only_id == "" or id == only_id)
	var current := id == current_id
	var clickable := known and not (current and case_open)

	## D2：与档案 / 名册 / 物品同一套列表语法 —— 不再给每行套一个圆角盒子。
	## 行间只留 1px 发丝线（左右缩进 8px），行高 56 给「编号 + 标题 + 说明」两行用。
	var row := PanelContainer.new()
	row.name = "row_" + id
	row.custom_minimum_size = Vector2(0, 56)
	row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := TecTheme.flat(TecTheme.NONE, 0, TecTheme.NONE, 0)
	style.border_color = TecTheme.edge(0.18)
	if not last:
		style.border_width_bottom = 1
		style.expand_margin_left = -8.0
		style.expand_margin_right = -8.0
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	row.add_theme_stylebox_override("panel", style)
	if clickable:
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.mouse_entered.connect(func(): style.bg_color = TecTheme.BG)
		row.mouse_exited.connect(func(): style.bg_color = TecTheme.NONE)
		row.gui_input.connect(_on_row_input.bind(id, clickable))

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hb)

	## 行首编号牌：a-001 / a-002。比旧版「▣ / ▢」有信息量，也只占一个短格。
	var code_box := PanelContainer.new()
	code_box.name = "code"
	code_box.custom_minimum_size = Vector2(52, 24)
	code_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	code_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	code_box.add_theme_stylebox_override("panel", TecTheme.flat(
		TecTheme.CARD, TecTheme.R_SM, TecTheme.INK if known else TecTheme.EDGE_SOFT, 1))
	hb.add_child(code_box)
	var code_text := String(c["code"]).replace("CASE ", "")
	var code := TecTheme.label(code_text, TecTheme.FS_BODY,
		TecTheme.TEXT if known else TecTheme.INK_FAINT)
	code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	code.clip_text = true
	code.mouse_filter = Control.MOUSE_FILTER_IGNORE
	code_box.add_child(code)

	var meta := VBoxContainer.new()
	meta.add_theme_constant_override("separation", 2)
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(meta)

	var title_text := String(c["title"]) if known else "？？？？？？"
	var title := TecTheme.label(title_text, TecTheme.FS_TITLE,
		TecTheme.TEXT if known else TecTheme.MUTED)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.tooltip_text = title_text
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(title)

	var note_text := catalog.note_for(id) if known else String(c["note"])
	var note := TecTheme.label(note_text, TecTheme.FS_BODY,
		TecTheme.MUTED if known else TecTheme.INK_FAINT)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.clip_text = true
	note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	note.tooltip_text = note_text
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(note)

	var state_text := ""
	var state_kind := ""
	if not known:
		state_text = "锁定"
		state_kind = "lock"
	elif current:
		## W28：当前案件统一显示「进行中」，不再用「当前 / 进入」两套词。
		state_text = "进行中"
		state_kind = "on"
	elif not CaseCatalog.data_ready(id):
		state_text = "待接入"
		state_kind = "pend"
	else:
		state_text = "可进入"

	## 状态牌按**按钮**的语法画（P4.2）：当前 = 双键线，可进入 = 1px，
	## 锁定 / 待接入 = 淡键线 + 淡字。高度与编号牌同为 24，行内基线对齐。
	var badge := Panel.new()
	badge.name = "state"
	badge.custom_minimum_size = Vector2(56, 24)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var faded := state_kind == "lock" or state_kind == "pend"
	badge.add_theme_stylebox_override("panel", TecTheme.flat(
		TecTheme.CARD, TecTheme.R_PILL, TecTheme.INK_FAINT if faded else TecTheme.INK, 1))
	hb.add_child(badge)
	if state_kind == "on":
		TecTheme.keyline_ring(badge, 3.0, TecTheme.R_PILL)

	var state := TecTheme.label(state_text, TecTheme.FS_BODY,
		TecTheme.INK_FAINT if faded else TecTheme.TEXT)
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge.add_child(state)

	return row


func _on_row_input(event: InputEvent, id: String, clickable: bool) -> void:
	if not clickable:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		enter_requested.emit(id)


func set_case_state(p_current: String, p_open: bool) -> void:
	current_id = p_current
	case_open = p_open
	refresh_map()


func dbg_click(id: String) -> bool:
	for c in CaseCatalog.all():
		if String(c["id"]) != id:
			continue
		if catalog == null or not catalog.is_unlocked(id) or (only_id != "" and id != only_id):
			return false
		if id == current_id and case_open:
			return false
		enter_requested.emit(id)
		return true
	return false


func dbg_row_state(id: String) -> String:
	var row := find_child("row_" + id, true, false)
	if row == null:
		return ""
	for child in row.find_children("*", "Label", true, false):
		var text := String((child as Label).text)
		if text in ["进行中", "当前", "进入", "锁定", "待接入", "可进入"]:
			return text
	return ""


func dbg_row_count() -> int:
	return _rows.get_child_count() if _rows != null else 0
