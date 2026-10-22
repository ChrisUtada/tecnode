class_name SysWindow
extends Control
## 系统窗基类（对齐 Web 版 `.syswin`）：
## 纸面 + 柔和浮雕 + 13px 圆角，标题栏可拖动，右上角关闭。
## 内容统一塞进 `body`（一个 Control），子类/调用方只往里加东西。

signal closed
signal minimized

const PAD := 14.0
const BAR_H := 28.0
const CTRL := 18.0
## P3 烘焙九切片：卡面 + 1px 发丝边 + 13px 圆角 + 四层 --win-shadow，由
## tools/pixeldiff/bake_win_frame.cjs（白/黑双底片）+ solve_alpha.py 反解 alpha 得到。
## 为什么不用 shader 近似：--win-shadow 是四条 box-shadow 叠加（含 22px 模糊与顶部 inset
## 高光），单层 SDF 永远差一口气，测下来窗框上下各有 3px / 17px 的整条横带对不上。
const FRAME_TEX := "res://assets/baked/win_frame.png"
const BLEED := 46.0   # 九切片四角尺寸 = 圆角 13 + 投影 22 + 余量；烘的那张就按这个外边距裁的

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
var _over := false
var _over_ring: Control = null


func setup(p_title: String, w: float, h: float, radius: int = TecTheme.R_WIN) -> void:
	title = p_title
	size = Vector2(w + PAD * 2.0, h + PAD * 2.0)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build(radius)


## 是否用烘焙九切片当底板。暗纸血统的窗口（放映卡 / 回忆小剧场）自己改 shader 参数，
## 覆盖成 false 即可继续走程序生成，不必为每种纸各烘一张。
func _uses_baked_frame() -> bool:
	return true


## 烘焙底板：九切片往外撑出 BLEED，框线正好落在原来 shader 画的 PAD 位置，
## 所以**调用方的坐标一个都不用改**（窗框仍在 PAD 处，只是投影终于有地方画了）。
func _build_baked_frame() -> void:
	var frame := NinePatchRect.new()
	frame.name = "frame"
	frame.texture = load(FRAME_TEX)
	frame.patch_margin_left = int(BLEED)
	frame.patch_margin_right = int(BLEED)
	frame.patch_margin_top = int(BLEED)
	frame.patch_margin_bottom = int(BLEED)
	frame.position = Vector2(PAD - BLEED, PAD - BLEED)
	frame.size = Vector2(size.x - PAD * 2.0 + BLEED * 2.0, size.y - PAD * 2.0 + BLEED * 2.0)
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)


func _build_shader_bg(radius: int) -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://ui/shaders/surface.gdshader")
	_mat.set_shader_parameter("rect_size", size)
	_mat.set_shader_parameter("pad", PAD)
	_mat.set_shader_parameter("radius", float(radius))
	_mat.set_shader_parameter("shade_soft", 12.0)
	_mat.set_shader_parameter("shade_offset", Vector2(5.0, 7.0))
	_mat.set_shader_parameter("flat_fill", true)
	_mat.set_shader_parameter("col_mid", TecTheme.CARD)
	_mat.set_shader_parameter("edge_col", Color(0.290, 0.271, 0.204, 0.10))

	var bg := ColorRect.new()
	bg.name = "bg"
	bg.material = _mat
	bg.color = Color.WHITE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


func _build(radius: int) -> void:
	var inner_w: float = size.x - PAD * 2.0
	_inner_w = inner_w
	var inner_h: float = size.y - PAD * 2.0

	if _uses_baked_frame() and ResourceLoader.exists(FRAME_TEX):
		_build_baked_frame()
	else:
		_build_shader_bg(radius)

	var bar := Control.new()
	bar.name = "bar"
	bar.position = Vector2(PAD, PAD + 1.0)
	bar.size = Vector2(inner_w, BAR_H - 1.0)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bar)
	_bar_nodes.append(bar)

	var shade := TextureRect.new()
	shade.name = "bar_shade"
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.texture = _bar_gradient()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(shade)

	var title_row := HBoxContainer.new()
	title_row.name = "title_row"
	title_row.position = Vector2(10.0, 0.0)
	title_row.size = Vector2(inner_w - 20.0, BAR_H - 1.0)
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 8)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(title_row)

	var left_rule := _title_rule()
	title_row.add_child(left_rule)
	_title_label = TecTheme.label(title, TecTheme.FS_BODY, TecTheme.TEXT)
	_title_label.name = "win_title"
	var spaced := FontVariation.new()
	spaced.base_font = TecTheme.font()
	spaced.set_spacing(TextServer.SPACING_GLYPH, 2)
	_title_label.add_theme_font_override("font", spaced)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.clip_text = true
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.custom_minimum_size = Vector2(240, 0)
	_title_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(_title_label)
	title_row.add_child(_title_rule())

	var top_hl := ColorRect.new()
	top_hl.name = "top_hl"
	top_hl.color = Color(1.0, 0.992, 0.965, 0.9)
	top_hl.position = Vector2(0, 0)
	top_hl.size = Vector2(inner_w, 1.0)
	top_hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(top_hl)

	var sep := ColorRect.new()
	sep.name = "sep"
	sep.color = Color(0.290, 0.271, 0.204, 0.15)
	sep.position = Vector2(PAD, PAD + BAR_H)
	sep.size = Vector2(inner_w, 1.0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sep)

	var close := _mini_button("×")
	close.name = "close"
	close.position = Vector2(inner_w - 24.0, (BAR_H - 1.0 - CTRL) * 0.5)
	close.pressed.connect(_on_close_pressed)
	_close_btn = close
	bar.add_child(close)

	bar.gui_input.connect(_on_bar_input)

	body = Control.new()
	body.name = "body"
	body.position = Vector2(PAD + 12.0, PAD + BAR_H + 10.0)
	body.size = Vector2(inner_w - 24.0, inner_h - BAR_H - 20.0)
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(body)

	content = VBoxContainer.new()
	content.name = "content"
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("separation", 7)
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_child(content)


func _bar_gradient() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color(1.0, 0.988, 0.945, 0.6), Color(1.0, 0.988, 0.945, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 4
	tex.height = 32
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	return tex


func _title_rule() -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(12.0, BAR_H - 1.0)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule := ColorRect.new()
	rule.color = TecTheme.EDGE
	rule.anchor_left = 0.0
	rule.anchor_right = 1.0
	rule.anchor_top = 0.0
	rule.anchor_bottom = 0.0
	rule.offset_left = 0.0
	rule.offset_right = 0.0
	rule.offset_top = 11.0
	rule.offset_bottom = 12.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(rule)
	return wrap


func _mini_button(text: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.size = Vector2(CTRL, CTRL)
	b.custom_minimum_size = b.size
	var normal := TecTheme.flat(TecTheme.FACE_HI, 7)
	normal.shadow_color = TecTheme.BEVEL_LO
	normal.shadow_size = 1
	normal.shadow_offset = Vector2(0, 1)
	normal.content_margin_left = 0
	normal.content_margin_right = 0
	normal.content_margin_top = 0
	normal.content_margin_bottom = 0
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", TecTheme.flat(TecTheme.LINE, 7))
	b.add_theme_stylebox_override("pressed", TecTheme.flat(TecTheme.FACE_LO, 7))
	var glyph := TecTheme.label(text, TecTheme.FS_BODY, TecTheme.TEXT)
	glyph.name = "glyph"
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(glyph)
	b.set_meta("glyph_normal", TecTheme.TEXT)
	b.set_meta("glyph_hot", TecTheme.CARD)
	b.mouse_entered.connect(func(): _paint_mini_glyph(b, true))
	b.mouse_exited.connect(func(): _paint_mini_glyph(b, false))
	b.button_down.connect(func(): _paint_mini_glyph(b, true))
	b.button_up.connect(func(): _paint_mini_glyph(b, b.is_hovered()))
	return b


func _paint_mini_glyph(b: Button, hot: bool) -> void:
	var glyph := b.get_node_or_null("glyph") as Label
	if glyph == null:
		return
	glyph.add_theme_color_override("font_color", b.get_meta("glyph_hot" if hot else "glyph_normal", TecTheme.TEXT))


## 拖动中悬停 = 落点：Web `.bag-win.over / .clue-win.over{outline:2px dashed var(--text);outline-offset:3px}`
func set_over(on: bool) -> void:
	if _over == on:
		return
	_over = on
	if on:
		if _over_ring == null or not is_instance_valid(_over_ring):
			_over_ring = OverRing.new()
			_over_ring.name = "over_ring"
			_over_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_over_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
			_over_ring.inset = PAD - 3.0 - 1.0
			add_child(_over_ring)
		_over_ring.visible = true
		_over_ring.queue_redraw()
	elif _over_ring != null and is_instance_valid(_over_ring):
		_over_ring.visible = false


class OverRing extends Control:
	var inset := 10.0

	func _draw() -> void:
		var r := Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)
		var rad := float(TecTheme.R_WIN)
		var dash := 5.0
		draw_dashed_line(Vector2(r.position.x + rad, r.position.y),
			Vector2(r.end.x - rad, r.position.y), TecTheme.LINE, 2.0, dash, true, false)
		draw_dashed_line(Vector2(r.position.x + rad, r.end.y),
			Vector2(r.end.x - rad, r.end.y), TecTheme.LINE, 2.0, dash, true, false)
		draw_dashed_line(Vector2(r.position.x, r.position.y + rad),
			Vector2(r.position.x, r.end.y - rad), TecTheme.LINE, 2.0, dash, true, false)
		draw_dashed_line(Vector2(r.end.x, r.position.y + rad),
			Vector2(r.end.x, r.end.y - rad), TecTheme.LINE, 2.0, dash, true, false)


func set_title(t: String) -> void:
	title = t
	if _title_label != null:
		_title_label.text = t


## 只改内高，宽度与顶边不动；对话窗按内容长高 / 缩回时用。
func set_inner_height(h: float) -> void:
	var ih := maxf(120.0, h)
	var target := Vector2(size.x, ih + PAD * 2.0)
	custom_minimum_size = target
	size = target
	_sync_frame(Vector2(size.x - PAD * 2.0, ih))
	body.size.y = ih - BAR_H - 20.0
	if _mat != null:
		_mat.set_shader_parameter("rect_size", size)


## 重设「内容区」尺寸（w × h，不含 PAD）。`content_scale_mode` 关掉之后，主窗要跟着
## **窗口像素**长，而不是跟着 1280×720 的设计基准；九切片底板、标题栏、分隔线、
## 关闭按钮、body 必须一起改，否则只有纸面变大、框线和标题还留在原处。
## `custom_minimum_size` 放松到最小可用尺寸（不是新尺寸），否则窗口从此缩不回去。
func resize_to(w: float, h: float) -> void:
	var iw := maxf(320.0, w)
	var ih := maxf(160.0, h)
	custom_minimum_size = Vector2(320.0 + PAD * 2.0, 160.0 + PAD * 2.0)
	_inner_w = iw
	size = Vector2(iw + PAD * 2.0, ih + PAD * 2.0)
	_sync_frame(Vector2(iw, ih))
	if _mat != null:
		_mat.set_shader_parameter("rect_size", size)
	var bar := get_node_or_null("bar") as Control
	if bar != null:
		bar.size.x = iw
		var row := bar.get_node_or_null("title_row") as Control
		if row != null:
			row.size.x = iw - 20.0
		var hl := bar.get_node_or_null("top_hl") as Control
		if hl != null:
			hl.size.x = iw
		if _close_btn != null and is_instance_valid(_close_btn):
			_close_btn.position.x = iw - 24.0
		# 最小化按钮在 enable_controls() 后加的，resize_to() 也得把它一起推回右沿；
		# 否则 1920 宽下它会停在 1280 设计坐标（1218），跟关闭按钮隔着半个屏幕。
		var min_btn := bar.get_node_or_null("min") as Control
		if min_btn != null:
			min_btn.position.x = iw - 47.0
	var sep := get_node_or_null("sep") as Control
	if sep != null:
		sep.size.x = iw
	if body != null and is_instance_valid(body):
		body.size = Vector2(iw - 24.0, ih - BAR_H - 20.0)


## 底板（烘焙九切片 / shader 面）跟着内容区走。九切片是 `size` 的显式子控件，
## 不会自己随父节点长 —— 忘了这一步，窗口长高时纸面就只在左上角留一块。
func _sync_frame(inner: Vector2) -> void:
	var frame := get_node_or_null("frame") as Control
	if frame != null:
		frame.position = Vector2(PAD - BLEED, PAD - BLEED)
		frame.size = inner + Vector2(BLEED, BLEED) * 2.0


func enable_case_controls() -> void:
	enable_controls("收起：缩成桌面右下角的案件卡片（进度会保存）",
		"关闭：放进左侧「案件地图」图标（进度会保存）")


func enable_controls(min_tip: String, close_tip: String = "", show_min := true) -> void:
	_manual_close = true
	if _close_btn == null:
		return
	var bar := _close_btn.get_parent()
	if show_min:
		var min_btn := _mini_button("–")
		min_btn.name = "min"
		min_btn.position = Vector2(_inner_w - 47.0, (BAR_H - 1.0 - CTRL) * 0.5)
		min_btn.tooltip_text = min_tip
		min_btn.pressed.connect(func(): minimized.emit())
		bar.add_child(min_btn)
	_close_btn.tooltip_text = close_tip


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
			# 点击提层：Desktop 会把窗按 rank 重新插队（批 4 z 序）；不在桌面里用就地置顶兜底
			if raise_now.is_valid():
				raise_now.call(self)
			else:
				move_to_front()
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		position = _grab + (event.global_position - _press)


## 提层回调（Desktop._place_z 接进来）：置 true 后标题栏按下不再 move_to_front
func set_raise_call(c: Callable) -> void:
	raise_now = c


var raise_now := Callable()


## 简单文本块（P0 用；P1 换成打字机 + 标签可点）
func add_paragraph(text: String, size_px: int = 13, color: Color = TecTheme.TEXT) -> Label:
	var l := TecTheme.label(text, size_px, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(body.size.x, 0)
	content.add_child(l)
	return l
