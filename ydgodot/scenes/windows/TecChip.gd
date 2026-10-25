class_name TecChip
extends Control
## U7：从 Button 改为自管手势的 Control —— 按下可拖，松手未拖才 emit pressed。

signal pressed
signal moved

const AvatarFrameScript = preload("res://ui/AvatarFrame.gd")

var _bg: Panel
var _status: Label
var _bar: ProgressBar
var _dot: PanelContainer
var _normal_style: StyleBoxFlat
var _hover_style: StyleBoxFlat
var _down := false
var _dragged := false
var _press_global := Vector2.ZERO
var _grab := Vector2.ZERO
var _user_placed := false


func setup_chip() -> void:
	name = "tec_chip"
	custom_minimum_size = Vector2(196, 56)
	size = Vector2(196, 56)
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "TEC 已收起：拖动可挪位置 · 单击展开对话窗"
	_normal_style = TecTheme.flat(TecTheme.CARD, TecTheme.R_WIN)
	_hover_style = TecTheme.flat(TecTheme.BG, TecTheme.R_WIN, TecTheme.INK, 2)
	_bg = Panel.new()
	_bg.name = "chip_bg"
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_theme_stylebox_override("panel", _normal_style)
	add_child(_bg)
	mouse_entered.connect(func(): _bg.add_theme_stylebox_override("panel", _hover_style))
	mouse_exited.connect(func(): _bg.add_theme_stylebox_override("panel", _normal_style))
	gui_input.connect(_on_chip_input)
	_add_dot()
	_build_content()


func _build_content() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_top = 8
	row.offset_right = -10
	row.offset_bottom = -8
	row.add_theme_constant_override("separation", 9)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	var av := AvatarFrameScript.new()
	av.name = "tec_chip_avatar"
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	av.setup("res://assets/raw/tec-avatar.png", 32.0, "T")
	row.add_child(av)

	var meta := VBoxContainer.new()
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.alignment = BoxContainer.ALIGNMENT_CENTER
	meta.add_theme_constant_override("separation", 1)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(meta)

	var nm := TecTheme.label("TEC 助手", TecTheme.FS_BODY, TecTheme.TEXT)
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(nm)

	_status = TecTheme.label("助手已收起 · 点此展开", TecTheme.FS_BODY, TecTheme.MUTED)
	_status.name = "tc_status"
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(_status)

	_bar = ProgressBar.new()
	_bar.name = "tc_bar"
	_bar.min_value = 0
	_bar.max_value = 100
	_bar.value = 0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 4)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.modulate = TecTheme.white(0.0)
	_bar.add_theme_stylebox_override("background", TecTheme.flat(TecTheme.FACE_LO, 0, TecTheme.FACE_LO, 0))
	_bar.add_theme_stylebox_override("fill", TecTheme.flat(TecTheme.LINE, 0, TecTheme.LINE, 0))
	meta.add_child(_bar)


func _add_dot() -> void:
	_dot = PanelContainer.new()
	_dot.name = "tc_dot"
	_dot.size = Vector2(11, 11)
	_dot.position = Vector2(181, -4)
	_dot.visible = false
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := TecTheme.flat(TecTheme.LINE, TecTheme.R_PILL, TecTheme.LINE, 0)
	_dot.add_theme_stylebox_override("panel", sb)
	add_child(_dot)


func set_idle(dot: bool = false) -> void:
	_bar.value = 0
	_bar.modulate = TecTheme.white(0.0)
	_dot.visible = dot
	_status.text = "分析完成 · 点此展开" if dot else "助手已收起 · 点此展开"


func set_analyzing(label: String, ratio: float = 0.0) -> void:
	_bar.modulate = TecTheme.white(1.0)
	_bar.value = clampf(ratio, 0.0, 1.0) * 100.0
	_dot.visible = false
	_status.text = "分析中 · " + label


func _on_chip_input(event: InputEvent) -> void:
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
				pressed.emit()
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


func reset_place() -> void:
	_user_placed = false


func _clamp_pos(p: Vector2) -> Vector2:
	var parent := get_parent() as Control
	if parent == null:
		return p
	return Vector2(
		clampf(p.x, 0.0, maxf(0.0, parent.size.x - size.x)),
		clampf(p.y, 0.0, maxf(0.0, parent.size.y - size.y)))


func status_text() -> String:
	return _status.text


func is_busy() -> bool:
	return _bar.modulate.a > 0.5


func dbg_state() -> Dictionary:
	return {
		"status": _status.text,
		"bar": _bar.value,
		"busy": is_busy(),
		"dot": _dot.visible,
	}
