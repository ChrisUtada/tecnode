class_name MusicDock
extends PanelContainer
## 播放器最小化卡片：曲名 + 迷你进度 + 时间 + 暂停 / 停止。
## 点卡片还原播放器窗；点按钮不冒泡。

signal restore_requested
signal toggle_requested
signal stop_requested

const DOCK_W := 238.0
const DOCK_H := 60.0

var _title: Label
var _prog: ProgressBar
var _time: Label
var _toggle_btn: Button
var _close_btn: Button
var _state: Dictionary = {}


func setup_dock() -> void:
	name = "music_dock"
	custom_minimum_size = Vector2(DOCK_W, DOCK_H)
	size = Vector2(DOCK_W, DOCK_H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "播放器 · 单击还原"
	var sb := TecTheme.flat(TecTheme.CARD, TecTheme.R_WIN, TecTheme.EDGE, 1)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.name = "dock_body"
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	_title = TecTheme.label("未播放", TecTheme.FS_BODY, TecTheme.TEXT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_title)
	_toggle_btn = _mini_button("▶", "播放 / 暂停")
	_toggle_btn.pressed.connect(func(): toggle_requested.emit())
	top.add_child(_toggle_btn)
	_close_btn = _mini_button("■", "停止")
	_close_btn.pressed.connect(func(): stop_requested.emit())
	top.add_child(_close_btn)

	_prog = ProgressBar.new()
	_prog.name = "dock_prog"
	_prog.min_value = 0
	_prog.max_value = 100
	_prog.value = 0
	_prog.show_percentage = false
	_prog.custom_minimum_size = Vector2(0, 4)
	_prog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prog.add_theme_stylebox_override("background", TecTheme.flat(TecTheme.FACE_LO, 0, TecTheme.FACE_LO, 0))
	_prog.add_theme_stylebox_override("fill", TecTheme.flat(TecTheme.LINE, 0, TecTheme.LINE, 0))
	v.add_child(_prog)

	_time = TecTheme.label("--:-- / --:--", TecTheme.FS_BODY, TecTheme.MUTED)
	_time.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_time)

	gui_input.connect(_on_gui_input)


func _mini_button(text: String, tip: String) -> Button:
	var b := TecTheme.button(text)
	b.custom_minimum_size = Vector2(22, 18)
	b.size = Vector2(22, 18)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", TecTheme.FS_BODY)
	b.tooltip_text = tip
	return b


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		restore_requested.emit()


func update_state(s: Dictionary) -> void:
	_state = s
	_title.text = String(s.get("title", "")) if String(s.get("title", "")) != "" else "未播放"
	var dur := float(s.get("duration", 0.0))
	var cur := float(s.get("time", 0.0))
	_prog.value = clampf(cur / dur, 0.0, 1.0) * 100.0 if dur > 0.0 else 0.0
	_time.text = "%s / %s" % [_fmt(cur), _fmt(dur)]
	_toggle_btn.text = "❚❚" if bool(s.get("playing", false)) else "▶"
	_toggle_btn.disabled = String(s.get("current", "")) == ""
	_close_btn.disabled = String(s.get("current", "")) == ""


func _fmt(s: float) -> String:
	if not is_finite(s) or s < 0.0:
		return "--:--"
	var n := int(round(s))
	return "%02d:%02d" % [int(n / 60), n % 60]


func state() -> Dictionary:
	return _state.duplicate(true)
