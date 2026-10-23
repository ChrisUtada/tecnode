class_name TecChip
extends Button

const AvatarFrameScript = preload("res://ui/AvatarFrame.gd")

var _status: Label
var _bar: ProgressBar
var _dot: PanelContainer


func setup_chip() -> void:
	name = "tec_chip"
	custom_minimum_size = Vector2(196, 56)
	size = Vector2(196, 56)
	focus_mode = Control.FOCUS_NONE
	tooltip_text = "TEC 已收起：单击展开对话窗"
	var normal := TecTheme.flat(TecTheme.CARD, TecTheme.R_WIN)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", TecTheme.flat(TecTheme.BG, TecTheme.R_WIN))
	add_theme_stylebox_override("pressed", TecTheme.flat(TecTheme.FACE_LO, TecTheme.R_WIN))
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
