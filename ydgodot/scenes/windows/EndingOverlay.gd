class_name EndingOverlay
extends Control
## 结局演出（P0 只验管线：分幕台词逐条落下 → 点击继续 → 收幕）
##
## 与 Web 版 `#ending-overlay` 同语汇：全屏暗纸遮罩 + 居中分幕文字。
## **测试旁路**：`--fast` 把每幕延迟压到 0。

signal finished

var _fast := false
var _lines: Array = []
var _idx := 0
var _wait := 0.0
var _shown := 0
var _playing := false
var _name_label: Label
var _box: VBoxContainer
var _hint: Label
var _message: String = ""
var _truename: String = ""
var _is_true := false
var _truename_shown := false
var _shown_message := ""
var _final_text := "收下这份记录"


func setup_overlay() -> void:
	_fast = OS.get_cmdline_args().has("--fast") or OS.get_cmdline_user_args().has("--fast") \
		or OS.get_cmdline_args().has("--shot") or OS.get_cmdline_user_args().has("--shot")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	visible = false

	var dim := ColorRect.new()
	dim.name = "dim"
	dim.color = Color(0.11, 0.11, 0.10, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.name = "center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.custom_minimum_size = Vector2(560, 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)

	_name_label = TecTheme.label("", 14, TecTheme.LINE2)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_name_label)

	_box = VBoxContainer.new()
	_box.name = "lines"
	_box.add_theme_constant_override("separation", 14)
	col.add_child(_box)

	_hint = TecTheme.label(_final_text, 11, TecTheme.FAINT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.visible = false
	col.add_child(_hint)


func play(ending: EndingDef) -> void:
	if ending == null:
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # 每次开演前重新贴合父级（防父级尺寸后到）
	_lines = ending.lines
	_is_true = ending.is_true_capture
	_truename = ending.truename if _is_true else ""
	# 真名结局的大段说明留给花园（Web 版同口径），遮罩上只落真名
	_message = "" if _is_true else ending.message
	_final_text = "确认捕获" if _is_true else "收下这份记录"
	_name_label.text = ending.name
	_idx = 0
	_shown = 0
	_wait = 0.0
	_truename_shown = false
	_shown_message = ""
	_hint.text = _final_text
	_hint.visible = false
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	_playing = true
	visible = true
	move_to_front()
	set_process(true)
	if _lines.is_empty():
		_show_message()


func _process(delta: float) -> void:
	if not _playing:
		return
	if _wait > 0.0:
		_wait -= delta
		if _wait > 0.0:
			return
	if _idx < _lines.size():
		var line: EndingLineDef = _lines[_idx]
		_idx += 1
		_shown += 1
		var l := TecTheme.label(line.text, 15, TecTheme.CARD)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(560, 0)
		_box.add_child(l)
		_wait = 0.0 if _fast else float(line.delay_ms) / 1000.0
	else:
		_show_message()


func _show_message() -> void:
	if _is_true and _truename != "" and not _truename_shown:
		var tn := TecTheme.label("真名已识破\n——%s——" % _truename, 26, TecTheme.CARD)
		tn.name = "truename"
		tn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tn.custom_minimum_size = Vector2(560, 0)
		tn.add_theme_constant_override("line_spacing", 8)
		_box.add_child(tn)
		_truename_shown = true
	if _message != "":
		var m := TecTheme.label(_message, 12, TecTheme.LINE2)
		m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		m.custom_minimum_size = Vector2(620, 0)
		m.add_theme_constant_override("line_spacing", 6)
		_box.add_child(m)
		_shown_message = _message
		_message = ""
	_hint.visible = true
	_playing = false
	set_process(false)


## 测试 / 截图旁路：把剩下的分幕一次放完
func finish_now() -> void:
	if not visible:
		return
	while _idx < _lines.size():
		var line: EndingLineDef = _lines[_idx]
		_idx += 1
		_shown += 1
		var l := TecTheme.label(line.text, 15, TecTheme.CARD)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(560, 0)
		_box.add_child(l)
	_show_message()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _playing:
			_wait = 0.0          # 点一下 = 快进到下一幕
		else:
			visible = false
			finished.emit()


func shown_count() -> int:
	return _shown


func total_lines() -> int:
	return _lines.size()


func truename_shown() -> bool:
	return _truename_shown


func final_text() -> String:
	return _final_text


func shown_message() -> String:
	return _shown_message


func truename() -> String:
	return _truename
