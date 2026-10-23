class_name CaseMapWin
extends SysWindow

signal enter_requested(case_id: String)

var catalog: CaseCatalog
var current_id: String = ""
var case_open := true

var _rows: VBoxContainer


func setup_map(p_catalog: CaseCatalog, p_current: String, p_open: bool) -> void:
	catalog = p_catalog
	current_id = p_current
	case_open = p_open
	setup("案件地图", 430, 390)
	_build_map()


func _build_map() -> void:
	var tip := TecTheme.label(
		"每个地址对应一宗案件。\n"
		+ "在本案捕获「真名」后，下一案的地址才会点亮。\n"
		+ "案件窗「–」收进右下角案件卡片；「×」收进本图标。\n"
		+ "两种情况都会自动保存，点本案那行即可展开。", TecTheme.FS_BODY, TecTheme.MUTED)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_constant_override("line_spacing", 3)
	tip.custom_minimum_size = Vector2(content.size.x, 0)
	content.add_child(tip)

	_rows = VBoxContainer.new()
	_rows.name = "rows"
	_rows.add_theme_constant_override("separation", 8)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_rows)
	refresh_map()


func refresh_map() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for c in CaseCatalog.all():
		_rows.add_child(_make_row(c))


func _make_row(c: Dictionary) -> Control:
	var id := String(c["id"])
	var known := catalog != null and catalog.is_unlocked(id)
	var current := id == current_id
	var clickable := known and not (current and case_open)

	var row := PanelContainer.new()
	row.name = "row_" + id
	row.custom_minimum_size = Vector2(0, 66)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	## 键线一律纯黑（P4.2）—— 原来已知/可进入的行用的是 `EDGE`（30% 黑），
	## 在这扇窗里读作「还没做单色改版的旧控件」。锁定行才留淡线：它是真的「不可点」。
	var style := TecTheme.flat(TecTheme.CARD, TecTheme.R_SM, TecTheme.INK if known else TecTheme.EDGE_SOFT)
	## 显式写死内容边距：悬停要把键线从 1px 加到 2px，不钉住边距的话
	## 行内所有子控件都会被顶 1px（参考图里所有键也是一直 1px，只有悬停加粗）。
	style.content_margin_left = 2
	style.content_margin_right = 2
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	if not known:
		style.bg_color = TecTheme.BG
	row.add_theme_stylebox_override("panel", style)
	if clickable:
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		## 悬停 = 键线加粗（1px → 2px）。原来是 `CARD → BG` 换底色，
		## 而这两个常量在单色版里都是纯白 —— 等于没有反馈。
		row.mouse_entered.connect(func(): style.set_border_width_all(2))
		row.mouse_exited.connect(func(): style.set_border_width_all(1))
		row.gui_input.connect(_on_row_input.bind(id, clickable))

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hb)

	var glyph_box := PanelContainer.new()
	glyph_box.custom_minimum_size = Vector2(34, 34)
	glyph_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph_box.add_theme_stylebox_override("panel",
		TecTheme.flat(TecTheme.CARD, TecTheme.R_BTN,
			TecTheme.INK if known else TecTheme.EDGE_SOFT, 1))
	hb.add_child(glyph_box)
	var glyph := TecTheme.label("▣" if known else "▢", TecTheme.FS_BODY,
		TecTheme.LINE if known else TecTheme.FAINT)
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph_box.add_child(glyph)

	var meta := VBoxContainer.new()
	meta.add_theme_constant_override("separation", 2)
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(meta)

	var title := TecTheme.label(
		String(c["code"]) + " · " + (String(c["title"]) if known else "？？？？？？"),
		TecTheme.FS_TITLE, TecTheme.TEXT if known else TecTheme.MUTED)
	title.clip_text = true
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(title)

	var note := TecTheme.label(catalog.note_for(id) if known else String(c["note"]), TecTheme.FS_BODY, TecTheme.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(240, 0)
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(note)

	var state_text := ""
	var state_kind := ""
	if not known:
		state_text = "锁定"
		state_kind = "lock"
	elif current:
		state_text = "当前" if case_open else "进入"
		state_kind = "on"
	elif not CaseCatalog.data_ready(id):
		state_text = "待接入"
		state_kind = "pend"
	else:
		state_text = "可进入"

	## 状态牌按**按钮**的语法画（P4.2），三种档位只差键线与字色：
	##   当前     → 白底 + 1px 键线 + **内键线**（参考图 “Find” 的双线 = 「就是这一个」）
	##   可进入   → 白底 + 1px 键线
	##   锁定/待接入 → 淡键线 + 淡字（它是真的不可点，靠键线浓度区分，不靠颜色）
	## 原来是「当前 = 整块黑药丸」：那块黑是整窗最重的东西，把「可进入」压没了；
	## 而且黑底是深色面的语法，不该长在按钮上。
	var badge := Panel.new()
	badge.name = "state"
	badge.custom_minimum_size = Vector2(64, 26)
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
	## `Panel` 不是容器，子节点得自己铺满（原来的 PanelContainer 会自动排版）
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
		if catalog == null or not catalog.is_unlocked(id):
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
		if text in ["当前", "进入", "锁定", "待接入", "可进入"]:
			return text
	return ""


func dbg_row_count() -> int:
	return _rows.get_child_count() if _rows != null else 0
