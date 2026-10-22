class_name DeskIcon
extends Button

## 桌面图标：单击 = 选中，双击 = 打开（对齐 Web `attachIcon`）；
## 按住拖走 = 挪位置（Web 同样可拖：位置不进撤销栈、重置不回位）。
##
## 为什么自己接管指针：Button 的 `pressed` 在「拖完松手」时也会发一次，
## 要在拖动后吞掉它就得跟 Button 的内部按下态打架。这里改成自己判
## 「5px 内 = 点击 / 超过 = 拖动」，一个信号 `clicked` 只给干净的点击。
signal clicked

const ROOT_SIZE := 64.0
const GLYPH_SIZE := 44.0
const GLYPH_PAD := 10.0
const DRAG_THRESHOLD := 5.0

var _glyph: ColorRect
var _icon: TextureRect
var _label: Label
var _mat: ShaderMaterial
var _selected := false
var _down := false
var _over := false
var _press_pos := Vector2.ZERO
var _drag_origin := Vector2.ZERO
var _moved := false
var _bounds := Rect2(Vector2.ZERO, Vector2(1280, 668))
var _root_size := ROOT_SIZE
var _glyph_size := GLYPH_SIZE
var _glyph_pad := GLYPH_PAD
var _compact := false


func setup(p_text: String, p_icon: String) -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(ROOT_SIZE, ROOT_SIZE)
	size = custom_minimum_size
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())

	_glyph = ColorRect.new()
	_glyph.name = "glyph"
	_glyph.position = Vector2(0, -GLYPH_PAD)
	_glyph.size = Vector2(ROOT_SIZE, ROOT_SIZE)
	_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://ui/shaders/surface.gdshader")
	_mat.set_shader_parameter("rect_size", Vector2(ROOT_SIZE, ROOT_SIZE))
	_mat.set_shader_parameter("pad", GLYPH_PAD)
	_mat.set_shader_parameter("radius", 11.0)
	# 阴影按 Web `.desk-icon .icon-glyph{box-shadow:var(--raise)}`（暗影 3/4 模糊 10）。
	# 「模糊」在这里是距离上的软边长度、不是 CSS 的高斯半径，所以数值要按对拍扫：
	# 暗影 11.0 / 偏移 2,3，高光 5.5 / 偏移 -2,-3（照 CSS 数字直填会糊一大圈）。
	_mat.set_shader_parameter("shade_soft", 11.0)
	_mat.set_shader_parameter("shade_offset", Vector2(2, 3))
	# 图标块四周有余量，把 CSS `--raise` 的第二盏（左上暖白高光）也画出来：
	# 不画的话，块的上/左两侧就是暗影压出来的灰，而 Web 那边是被提亮到比底色还亮。
	_mat.set_shader_parameter("glow_col", TecTheme.BEVEL_HI)
	_mat.set_shader_parameter("glow_soft", 5.5)
	_mat.set_shader_parameter("glow_offset", Vector2(-2, -3))
	_glyph.material = _mat
	_glyph.color = Color.WHITE
	add_child(_glyph)

	_icon = TextureRect.new()
	_icon.name = "icon"
	_icon.texture = load(p_icon)
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_icon.position = Vector2(10, GLYPH_PAD)
	_icon.size = Vector2(GLYPH_SIZE, GLYPH_SIZE)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glyph.add_child(_icon)

	_label = TecTheme.label(p_text, TecTheme.FS_BODY, TecTheme.MUTED)
	_label.name = "label"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.position = Vector2(0, 45)
	_label.size = Vector2(ROOT_SIZE, 14)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	# 紧凑模式会藏掉文字标签，名称仍要能从 tooltip 读出来。
	tooltip_text = p_text

	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	_apply_style()


## 矮窗口 / 图标多时切紧凑：不缩 44px 图标本体（避免 SVG 重采样发糊），
## 只收掉外圈 10px 留白与文字标签，把每个图标高度从 69 压到 48。
func set_compact(on: bool) -> void:
	if _compact == on:
		return
	_compact = on
	_root_size = 48.0 if on else ROOT_SIZE
	_glyph_size = GLYPH_SIZE
	_glyph_pad = 2.0 if on else GLYPH_PAD
	custom_minimum_size = Vector2(_root_size, _root_size)
	size = custom_minimum_size
	_glyph.position = Vector2(0, -_glyph_pad)
	_glyph.size = Vector2(_root_size, _root_size)
	_mat.set_shader_parameter("rect_size", Vector2(_root_size, _root_size))
	_mat.set_shader_parameter("pad", _glyph_pad)
	_icon.position = Vector2(_glyph_pad, _glyph_pad)
	_icon.size = Vector2(_glyph_size, _glyph_size)
	_label.visible = not on
	for ch in get_children():
		if ch is PanelContainer and String(ch.name).ends_with("badge"):
			(ch as Control).position.x = _root_size - 20.0
	queue_redraw()


## 拖动范围 = 桌面矩形（Web：`clamp(0, desktop.w - 64)`）
func set_bounds(r: Rect2) -> void:
	_bounds = r


func icon_position() -> Vector2:
	return position


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press_pos = mb.global_position
				_drag_origin = position
				_moved = false
				_down = true
				_apply_style()
			else:
				var was_moved := _moved
				_down = false
				_moved = false
				_apply_style()
				if not was_moved:
					clicked.emit()
			accept_event()
			return
	# 位移超过阈值 = 拖动：按指针位移挪位置，夹在桌面矩形内（把显卡上沿的 -10 也算进去）
	if event is InputEventMouseMotion and _down:
		var mm := event as InputEventMouseMotion
		var d := mm.global_position - _press_pos
		if not _moved and absf(d.x) + absf(d.y) < DRAG_THRESHOLD:
			return
		if not _moved:
			_moved = true
			move_to_front()
		var p := _drag_origin + d
		var max_x := maxf(_bounds.size.x - _root_size, 0.0)
		var max_y := maxf(_bounds.size.y - _root_size, 0.0)
		position = Vector2(clampf(p.x, 0.0, max_x), clampf(p.y, 0.0, max_y))
		accept_event()


func set_selected(on: bool) -> void:
	_selected = on
	_apply_style()


func _on_hover(on: bool) -> void:
	# `.desk-icon:hover .icon-glyph` 把两盏阴影各放大一档
	_mat.set_shader_parameter("shade_soft", 10.0 if on else 7.0)
	_mat.set_shader_parameter("shade_offset", Vector2(3, 4) if on else Vector2(2, 3))
	_mat.set_shader_parameter("glow_soft", 10.0 if on else 7.0)
	_mat.set_shader_parameter("glow_offset", Vector2(-3, -4) if on else Vector2(-2, -3))


## 拖动中悬停 = 落点：Web `.desk-icon.over .icon-glyph` 与按下态同一套暗底 + 2px 描边
func set_over(on: bool) -> void:
	if _over == on:
		return
	_over = on
	_apply_style()
	queue_redraw()


func _draw() -> void:
	if not _over:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(2)
	sb.border_color = TecTheme.LINE
	sb.set_corner_radius_all(12)
	draw_style_box(sb, Rect2(Vector2(0, -_glyph_pad), Vector2(_root_size, _root_size)))


func _apply_style() -> void:
	if _mat == null:
		return
	var dark := _selected or _down or _over
	_mat.set_shader_parameter("col_hi", Color("38372f") if dark else TecTheme.FACE_HI)
	_mat.set_shader_parameter("col_mid", TecTheme.LINE if dark else TecTheme.CARD)
	_mat.set_shader_parameter("col_lo", Color("1f1f19") if dark else TecTheme.FACE_LO)
	_mat.set_shader_parameter("edge_col", TecTheme.LINE if dark else TecTheme.EDGE)
	_mat.set_shader_parameter("rim_col", Color(1, 1, 1, 0.30) if dark else TecTheme.BEVEL_HI)
	_mat.set_shader_parameter("shade_col", Color(0, 0, 0, 0.55) if dark else TecTheme.BEVEL_LO)
	# 按下 / 选中态在 CSS 里只有 inset 阴影，没有外圈高光
	_mat.set_shader_parameter("glow_col", Color(0, 0, 0, 0) if dark else TecTheme.BEVEL_HI)
	_icon.modulate = TecTheme.CARD if dark else TecTheme.LINE
	_label.add_theme_color_override("font_color", TecTheme.CARD if dark else TecTheme.MUTED)
	var sb := StyleBoxFlat.new()
	sb.bg_color = TecTheme.LINE if dark else Color(0, 0, 0, 0)
	sb.set_border_width_all(0)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	_label.add_theme_stylebox_override("normal", sb)
