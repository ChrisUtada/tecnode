class_name TecWindow
extends SysWindow

signal analysis_started(target: String, label: String)
signal analysis_progress(ratio: float)
signal analysis_done(target: String)
signal talk_requested

const MIN_SEC := 5.0
const MAX_SEC := 8.0

var _lines: VBoxContainer
var _analysis: PanelContainer
var _analysis_label: Label
var _bar: ProgressBar
var _avatar: TextureRect
var _hint: Label

var _analyzing := false
var _elapsed := 0.0
var _duration := 0.0
var _target: String = ""
var _target_label: String = ""
var _fast := false
var _done_count := 0
var _line_count := 0


func setup_tec() -> void:
	_fast = OS.get_cmdline_args().has("--fast") or OS.get_cmdline_user_args().has("--fast")
	setup("TEC 对话", 332, 360)
	enable_controls("收起：缩成桌面右下角的助手卡片", "关闭：收起对话窗（内容保留）")
	_build_content()


func _build_content() -> void:
	content.add_theme_constant_override("separation", 0)
	var row := HBoxContainer.new()
	row.name = "tec_body"
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)

	var av_col := VBoxContainer.new()
	av_col.custom_minimum_size = Vector2(74, 0)
	av_col.alignment = BoxContainer.ALIGNMENT_BEGIN
	av_col.add_theme_constant_override("separation", 5)
	row.add_child(av_col)

	var av_box := PanelContainer.new()
	av_box.custom_minimum_size = Vector2(60, 60)
	av_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	av_box.clip_contents = true
	av_box.add_theme_stylebox_override("panel", TecTheme.flat(TecTheme.FACE_HI, TecTheme.R_SM, TecTheme.EDGE))
	av_col.add_child(av_box)

	_avatar = TextureRect.new()
	_avatar.name = "tec_avatar"
	_avatar.texture = load("res://assets/raw/tec-avatar.png")
	_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_avatar.custom_minimum_size = Vector2(60, 60)
	_avatar.mouse_filter = Control.MOUSE_FILTER_STOP
	_avatar.tooltip_text = "TEC 助手：拖节点到我身上分析，点对话窗任意位置闲聊"
	_avatar.gui_input.connect(_on_talk_input)
	av_box.add_child(_avatar)

	var av_label := TecTheme.label("TEC", TecTheme.FS_BODY, TecTheme.MUTED)
	av_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	av_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av_col.add_child(av_label)

	var main := VBoxContainer.new()
	main.name = "tec_main"
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.mouse_filter = Control.MOUSE_FILTER_PASS
	main.add_theme_constant_override("separation", 6)
	row.add_child(main)

	_lines = VBoxContainer.new()
	_lines.name = "tec_lines"
	_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lines.add_theme_constant_override("separation", 0)
	_lines.mouse_filter = Control.MOUSE_FILTER_PASS
	main.add_child(_lines)

	_analysis = PanelContainer.new()
	_analysis.name = "tec_analyzing"
	_analysis.visible = false
	_analysis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := TecTheme.flat(TecTheme.BG, TecTheme.R_BTN, TecTheme.EDGE_SOFT)
	box.content_margin_left = 9
	box.content_margin_right = 9
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	_analysis.add_theme_stylebox_override("panel", box)
	main.add_child(_analysis)

	var acol := VBoxContainer.new()
	acol.add_theme_constant_override("separation", 6)
	acol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_analysis.add_child(acol)

	_analysis_label = TecTheme.label("", TecTheme.FS_BODY, TecTheme.MUTED)
	_analysis_label.name = "tec_analysis_label"
	_analysis_label.clip_text = true
	_analysis_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_analysis_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	acol.add_child(_analysis_label)

	_bar = ProgressBar.new()
	_bar.name = "tec_bar"
	_bar.min_value = 0
	_bar.max_value = 100
	_bar.value = 0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 6)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := TecTheme.flat(TecTheme.FACE_LO, 0, TecTheme.FACE_LO, 0)
	var fill := TecTheme.flat(TecTheme.LINE, 0, TecTheme.LINE, 0)
	_bar.add_theme_stylebox_override("background", bg)
	_bar.add_theme_stylebox_override("fill", fill)
	acol.add_child(_bar)

	_hint = TecTheme.label("拖节点到我身上分析 · 点框内任意位置闲聊", TecTheme.FS_BODY, TecTheme.MUTED)
	_hint.name = "tec_hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## 提示行放**整行页脚**，不再塞在 224px 的对话列里：12px 下一行要 252px，
	## 挤在列里必然折成两行、第二行被 body 裁掉（10px 时刚好一行）。
	content.add_child(_hint)


func _gui_input(event: InputEvent) -> void:
	_on_talk_input(event)


func _on_talk_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		talk_requested.emit()


func append_line(text: String, color: Color = TecTheme.TEXT) -> void:
	if text == "":
		return
	var l := TecTheme.narrative_label(text, color)
	_lines.add_child(l)
	l.start_typing()
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.add_child(gap)
	var sep := ColorRect.new()
	sep.color = TecTheme.EDGE_SOFT
	sep.custom_minimum_size = Vector2(0, 1)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.add_child(sep)
	_line_count += 1
	call_deferred("_fit_height")


func _fit_height() -> void:
	if content == null:
		return
	if not is_inside_tree():
		await tree_entered
	await get_tree().process_frame
	var content_h := content_min_height()
	var target := maxf(240.0, SysWindow.BAR_H + 20.0 + content_h)
	if absf(size.y - (target + SysWindow.PAD * 2.0)) > 0.5:
		set_inner_height(target)


func is_analyzing() -> bool:
	return _analyzing


func analyze(target: String, label: String = "") -> bool:
	if _analyzing:
		return false
	if target == "":
		append_line("先选一处展开过的场景，我才有东西可看。", TecTheme.MUTED)
		return false
	_target = target
	_target_label = label if label != "" else target
	_analyzing = true
	_elapsed = 0.0
	_duration = 0.05 if _fast else randf_range(MIN_SEC, MAX_SEC)
	_bar.value = 0
	_analysis_label.text = "分析中 · " + _target_label
	_analysis.visible = true
	call_deferred("_fit_height")
	analysis_started.emit(_target, _target_label)
	append_line("（接收「%s」，开始分析…）" % _target_label)
	set_process(true)
	return true


func _process(delta: float) -> void:
	if not _analyzing:
		return
	_elapsed += delta
	var ratio := clampf(_elapsed / maxf(_duration, 0.001), 0.0, 1.0)
	_bar.value = ratio * 100.0
	analysis_progress.emit(ratio)
	if _elapsed < _duration:
		return
	_finish_analysis()


func _finish_analysis() -> void:
	_analyzing = false
	set_process(false)
	_analysis.visible = false
	_done_count += 1
	call_deferred("_fit_height")
	analysis_done.emit(_target)


func finish_now() -> void:
	if _analyzing:
		_elapsed = _duration
		set_process(true)


func cancel_analysis() -> void:
	if not _analyzing:
		return
	_analyzing = false
	set_process(false)
	_analysis.visible = false
	call_deferred("_fit_height")


func reset_tec() -> void:
	cancel_analysis()
	for c in _lines.get_children():
		_lines.remove_child(c)
		c.queue_free()
	_line_count = 0
	_done_count = 0
	_target = ""
	_target_label = ""
	_bar.value = 0
	call_deferred("_fit_height")


func done_count() -> int:
	return _done_count


func line_count() -> int:
	return _line_count


func target() -> String:
	return _target


func target_label() -> String:
	return _target_label


func progress() -> float:
	return _bar.value / 100.0 if _bar != null else 0.0


func analysis_visible() -> bool:
	return _analysis != null and _analysis.visible


func avatar_global_rect() -> Rect2:
	return _avatar.get_global_rect() if _avatar != null else Rect2()


func dbg_lines() -> Array:
	var out: Array = []
	for c in _lines.get_children():
		if c is Label:
			out.append((c as Label).text)
	return out


func dbg_status() -> Dictionary:
	return {
		"analyzing": _analyzing,
		"progress": progress(),
		"target": _target,
		"label": _target_label,
		"lines": _line_count,
		"done": _done_count,
		"analysis_visible": analysis_visible(),
	}
