class_name DeskIcon
extends Button

const ROOT_SIZE := 64.0
const GLYPH_SIZE := 44.0
const GLYPH_PAD := 10.0

var _glyph: ColorRect
var _icon: TextureRect
var _label: Label
var _mat: ShaderMaterial
var _selected := false
var _down := false
var _over := false


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

	_label = TecTheme.label(p_text, 11, TecTheme.MUTED)
	_label.name = "label"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.position = Vector2(0, 45)
	_label.size = Vector2(ROOT_SIZE, 14)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	button_down.connect(func(): _down = true; _apply_style())
	button_up.connect(func(): _down = false; _apply_style())
	_apply_style()


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
	draw_style_box(sb, Rect2(Vector2(0, -GLYPH_PAD), Vector2(ROOT_SIZE, ROOT_SIZE)))


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
	_icon.modulate = TecTheme.CARD if dark else Color.WHITE
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
