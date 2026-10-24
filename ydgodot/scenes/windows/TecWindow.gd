class_name TecWindow
extends SysWindow

signal analysis_started(target: String, label: String)
signal analysis_progress(ratio: float)
signal analysis_done(target: String)
signal talk_requested

const MIN_SEC := 5.0
const MAX_SEC := 8.0
const AvatarFrameScript = preload("res://ui/AvatarFrame.gd")

var _lines: VBoxContainer
var _scroll: ScrollContainer
var _empty: Label
var _status: Label
var _analysis: PanelContainer
var _bar: ProgressBar
var _avatar: Control
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
	var head := HBoxContainer.new()
	head.name = "tec_head"
	head.add_theme_constant_override("separation", 10)
	content.add_child(head)

	var av_col := VBoxContainer.new()
	av_col.custom_minimum_size = Vector2(74, 0)
	av_col.alignment = BoxContainer.ALIGNMENT_BEGIN
	av_col.add_theme_constant_override("separation", 5)
	head.add_child(av_col)

	_avatar = AvatarFrameScript.new()
	_avatar.name = "tec_avatar"
	_avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_avatar.setup("res://assets/raw/tec-avatar.png", 60.0, "T")
	_avatar.mouse_filter = Control.MOUSE_FILTER_STOP
	_avatar.tooltip_text = "TEC 助手：拖节点到我身上分析，点对话窗任意位置闲聊"
	_avatar.gui_input.connect(_on_talk_input)
	av_col.add_child(_avatar)

	var av_label := TecTheme.label("TEC", TecTheme.FS_BODY, TecTheme.MUTED)
	av_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	av_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av_col.add_child(av_label)

	var info := VBoxContainer.new()
	info.name = "tec_info"
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	info.add_theme_constant_override("separation", 5)
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(info)

	_status = TecTheme.label(_idle_text(), TecTheme.FS_BODY, TecTheme.MUTED)
	_status.name = "tec_status"
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_status)

	_analysis = PanelContainer.new()
	_analysis.name = "tec_analyzing"
	_analysis.visible = false
	_analysis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := TecTheme.flat(TecTheme.NONE, 0, TecTheme.NONE, 0)
	box.content_margin_left = 0
	box.content_margin_right = 0
	box.content_margin_top = 4
	box.content_margin_bottom = 0
	_analysis.add_theme_stylebox_override("panel", box)
	info.add_child(_analysis)

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
	_analysis.add_child(_bar)

	var rule := ColorRect.new()
	rule.name = "tec_rule"
	rule.color = TecTheme.EDGE_SOFT
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(rule)

	var area := Control.new()
	area.name = "tec_area"
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.clip_contents = true
	area.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(area)

	_scroll = ScrollContainer.new()
	_scroll.name = "tec_scroll"
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	area.add_child(_scroll)

	_lines = VBoxContainer.new()
	_lines.name = "tec_lines"
	_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lines.add_theme_constant_override("separation", 0)
	_lines.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_lines)

	_empty = TecTheme.label("把节点拖到我身上，我来看看。\n点这里可以闲聊。",
		TecTheme.FS_BODY, TecTheme.INK_FAINT)
	_empty.name = "tec_empty"
	_empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(_empty)

	var foot_rule := ColorRect.new()
	foot_rule.name = "tec_foot_rule"
	foot_rule.color = TecTheme.EDGE_SOFT
	foot_rule.custom_minimum_size = Vector2(0, 1)
	foot_rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(foot_rule)

	var foot_pad := Control.new()
	foot_pad.name = "tec_foot_pad"
	foot_pad.custom_minimum_size = Vector2(0, 17)
	foot_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(foot_pad)

	_hint = TecTheme.label("拖节点到我身上分析 · 点框内任意位置闲聊", TecTheme.FS_BODY, TecTheme.MUTED)
	_hint.name = "tec_hint"
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -16
	_hint.offset_bottom = 0
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## 提示行锚在 body 底部：窗口在隐藏状态改高时也能立刻跟到底边，
	## 不依赖 VBox 的延迟排序（测试会检查 hint 始终在窗内）。
	body.add_child(_hint)


func _idle_text() -> String:
	return "待命 · 拖一个节点到我身上"


## 教学期由 Desktop 接管状态行与底边提示：只指下一步，不一次灌输全部操作。
func set_guidance(status: String, hint: String) -> void:
	if _status != null and not _analyzing:
		_status.text = status
	if _hint != null:
		_hint.text = hint


## 截图 / 演示用：把已落下的台词一次性揭示完，避免画面停在半个字上。
func finish_typing() -> void:
	for c in _lines.get_children():
		if c is TypewriterLabel:
			(c as TypewriterLabel).finish_typing()


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
	if _empty != null:
		_empty.visible = false
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
	_scroll_to_end()


func _scroll_to_end() -> void:
	if _scroll == null or not is_instance_valid(_scroll):
		return
	await get_tree().process_frame
	_scroll.set_deferred("scroll_vertical", 1 << 20)


func _fit_height() -> void:
	if content == null:
		return
	if not is_inside_tree():
		await tree_entered
	await get_tree().process_frame
	var content_h := content_min_height()
	var target := clampf(maxf(240.0, SysWindow.BAR_H + 20.0 + content_h), 240.0, 360.0)
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
	if _status != null:
		_status.text = "分析中 · " + _target_label
		_status.add_theme_color_override("font_color", TecTheme.TEXT)
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
	if _status != null:
		_status.text = _idle_text()
		_status.add_theme_color_override("font_color", TecTheme.MUTED)
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
	if _status != null:
		_status.text = _idle_text()
		_status.add_theme_color_override("font_color", TecTheme.MUTED)
	call_deferred("_fit_height")


func reset_tec() -> void:
	cancel_analysis()
	for c in _lines.get_children():
		_lines.remove_child(c)
		c.queue_free()
	if _empty != null:
		_empty.visible = true
	_line_count = 0
	_done_count = 0
	_target = ""
	_target_label = ""
	_bar.value = 0
	if _status != null:
		_status.text = _idle_text()
		_status.add_theme_color_override("font_color", TecTheme.MUTED)
	if _hint != null:
		_hint.text = "拖节点到我身上分析 · 点框内任意位置闲聊"
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
