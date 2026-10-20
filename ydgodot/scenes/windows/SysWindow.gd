class_name SysWindow
extends Control
## 系统窗基类（对齐 Web 版 `.syswin`）：
## 纸面 + 柔和浮雕 + 13px 圆角，标题栏可拖动，右上角关闭。
## 内容统一塞进 `body`（一个 Control），子类/调用方只往里加东西。

signal closed
signal minimized

const PAD := 14.0
const BAR_H := 34.0

var title: String = "WINDOW"
var body: Control          # 定位容器（子类往里放东西时自己管坐标，比如画布）
var content: VBoxContainer # 纵向内容流（文本类窗口默认往这里加）
var root_panel: Control
var _mat: ShaderMaterial
var _title_label: Label
var _dragging := false
var _press := Vector2.ZERO
var _grab := Vector2.ZERO
var _bar_nodes: Array[Control] = []
var _manual_close := false
var _inner_w := 0.0
var _close_btn: Button


func setup(p_title: String, w: float, h: float, radius: int = TecTheme.R_WIN) -> void:
	title = p_title
	size = Vector2(w + PAD * 2.0, h + PAD * 2.0)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build(radius)


func _build(radius: int) -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://ui/shaders/surface.gdshader")
	_mat.set_shader_parameter("rect_size", size)
	_mat.set_shader_parameter("pad", PAD)
	_mat.set_shader_parameter("radius", float(radius))
	_mat.set_shader_parameter("shade_soft", 12.0)
	_mat.set_shader_parameter("shade_offset", Vector2(5.0, 7.0))

	var bg := ColorRect.new()
	bg.name = "bg"
	bg.material = _mat
	bg.color = Color.WHITE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var inner_w: float = size.x - PAD * 2.0
	_inner_w = inner_w
	var inner_h: float = size.y - PAD * 2.0

	var bar := Control.new()
	bar.name = "bar"
	bar.position = Vector2(PAD, PAD)
	bar.size = Vector2(inner_w, BAR_H)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bar)
	_bar_nodes.append(bar)

	_title_label = TecTheme.label(title, 12, TecTheme.TEXT)
	_title_label.name = "win_title"
	_title_label.position = Vector2(12.0, 6.0)
	_title_label.size = Vector2(inner_w - 60.0, 22.0)
	_title_label.clip_text = true
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_title_label)

	var sep := ColorRect.new()
	sep.name = "sep"
	sep.color = TecTheme.EDGE_SOFT
	sep.position = Vector2(PAD + 10.0, PAD + BAR_H)
	sep.size = Vector2(inner_w - 20.0, 1.0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sep)

	var close := TecTheme.button("×")
	close.name = "close"
	close.size = Vector2(26.0, 22.0)
	close.position = Vector2(inner_w - 32.0, 6.0)
	close.add_theme_font_size_override("font_size", 12)
	close.pressed.connect(_on_close_pressed)
	_close_btn = close
	bar.add_child(close)

	bar.gui_input.connect(_on_bar_input)

	body = Control.new()
	body.name = "body"
	body.position = Vector2(PAD + 10.0, PAD + BAR_H + 10.0)
	body.size = Vector2(inner_w - 20.0, inner_h - BAR_H - 22.0)
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(body)

	content = VBoxContainer.new()
	content.name = "content"
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("separation", 7)
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_child(content)


func set_title(t: String) -> void:
	title = t
	if _title_label != null:
		_title_label.text = t


func enable_case_controls() -> void:
	enable_controls("收起：缩成桌面右下角的案件卡片（进度会保存）",
		"关闭：放进左侧「案件地图」图标（进度会保存）")


func enable_controls(min_tip: String, close_tip: String = "") -> void:
	_manual_close = true
	if _close_btn == null:
		return
	var bar := _close_btn.get_parent()
	var min_btn := TecTheme.button("–")
	min_btn.name = "min"
	min_btn.size = Vector2(26.0, 22.0)
	min_btn.position = Vector2(_inner_w - 60.0, 6.0)
	min_btn.add_theme_font_size_override("font_size", 12)
	min_btn.tooltip_text = min_tip
	_close_btn.tooltip_text = close_tip
	min_btn.pressed.connect(func(): minimized.emit())
	bar.add_child(min_btn)
	_title_label.size = Vector2(_inner_w - 92.0, 22.0)


func _on_close_pressed() -> void:
	closed.emit()
	if not _manual_close:
		queue_free()


func _on_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_press = event.global_position
			_grab = position
			move_to_front()
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		position = _grab + (event.global_position - _press)


## 简单文本块（P0 用；P1 换成打字机 + 标签可点）
func add_paragraph(text: String, size_px: int = 13, color: Color = TecTheme.TEXT) -> Label:
	var l := TecTheme.label(text, size_px, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(body.size.x, 0)
	content.add_child(l)
	return l
