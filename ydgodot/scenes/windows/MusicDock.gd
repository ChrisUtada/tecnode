class_name MusicDock
extends PanelContainer
## 播放器最小化卡片：曲名 + 迷你进度 + 时间 + 暂停 / 停止。
## 点卡片还原播放器窗；点按钮不冒泡。

signal restore_requested
signal toggle_requested
signal stop_requested
signal moved

const DOCK_W := 238.0
const DOCK_H := 60.0
const TransportButton := preload("res://ui/TransportButton.gd")

var _title: Label
var _prog: ProgressBar
var _time: Label
var _toggle_btn: TransportButton
var _close_btn: TransportButton
var _state: Dictionary = {}
## U7：拖动最小化部件。按下记原点，位移超阈值才进入拖动；松手若拖过则吞掉「还原」。
var _down := false
var _dragged := false
var _press_global := Vector2.ZERO
var _grab := Vector2.ZERO
var _user_placed := false


func setup_dock() -> void:
	name = "music_dock"
	custom_minimum_size = Vector2(DOCK_W, DOCK_H)
	size = Vector2(DOCK_W, DOCK_H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "播放器 · 拖动可挪位置 · 单击还原"
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
	_toggle_btn = _mini_button("play", "播放 / 暂停")
	_toggle_btn.pressed.connect(func(): toggle_requested.emit())
	top.add_child(_toggle_btn)
	_close_btn = _mini_button("stop", "停止")
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


func _mini_button(mode: String, tip: String) -> TransportButton:
	var b := TransportButton.new()
	b.setup_transport(mode, tip)
	return b


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_down = true
			_dragged = false
			_press_global = event.global_position
			_grab = position
			accept_event()
		elif _down:
			var was_dragged := _dragged
			_down = false
			_dragged = false
			if not was_dragged:
				restore_requested.emit()
			accept_event()
		return
	if event is InputEventMouseMotion and _down:
		var at := (event as InputEventMouseMotion).global_position
		var d := at - _press_global
		if not _dragged and absf(d.x) + absf(d.y) < 5.0:
			return
		if not _dragged:
			_dragged = true
			move_to_front()
		position = _clamp_pos(_grab + d)
		_user_placed = true
		moved.emit()
		accept_event()


func user_placed() -> bool:
	return _user_placed


func clamp_into_parent() -> void:
	position = _clamp_pos(position)


func _clamp_pos(p: Vector2) -> Vector2:
	var parent := get_parent() as Control
	if parent == null:
		return p
	return Vector2(
		clampf(p.x, 0.0, maxf(0.0, parent.size.x - size.x)),
		clampf(p.y, 0.0, maxf(0.0, parent.size.y - size.y)))


func update_state(s: Dictionary) -> void:
	_state = s
	_title.text = String(s.get("title", "")) if String(s.get("title", "")) != "" else "未播放"
	var dur := float(s.get("duration", 0.0))
	var cur := float(s.get("time", 0.0))
	_prog.value = clampf(cur / dur, 0.0, 1.0) * 100.0 if dur > 0.0 else 0.0
	_time.text = "%s / %s" % [_fmt(cur), _fmt(dur)]
	_toggle_btn.set_mode("pause" if bool(s.get("playing", false)) else "play")
	_toggle_btn.disabled = String(s.get("current", "")) == ""
	_close_btn.disabled = String(s.get("current", "")) == ""
	_toggle_btn.queue_redraw()
	_close_btn.queue_redraw()


func _fmt(s: float) -> String:
	if not is_finite(s) or s < 0.0:
		return "--:--"
	var n := int(round(s))
	return "%02d:%02d" % [int(n / 60), n % 60]


func state() -> Dictionary:
	return _state.duplicate(true)
