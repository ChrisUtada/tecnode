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


## 是否用烘焙九切片当底板。
## **P2 起默认 false**：`win_frame.png` 是「米色底 + 13px 圆角 + 四层柔光投影」，
## 换成中性灰之后它是全屏唯一的暖色残留（0.9% 面积，但正好是窗框那一圈，极显眼）。
## 而且单色骨架的层次该由 **1px 黑框**承担 —— 框越软越像「贴了张纸」，
## 1-bit 要的是「划出来的边」。烘焙图留着（`assets/baked/`），需要时改回 true。
func _uses_baked_frame() -> bool:
	return false


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


## 窗框底色：与外壳同一块灰。**框不发白** —— 白框包灰画布会读成「纸边的窗」，
## 而这里要的是「灰桌面里嵌了一块中灰垫板」。子类（暗纸血统）可覆盖。
func _frame_fill() -> Color:
	return TecTheme.BG


## 窗体底板（P2）：**程序化硬框**，不用 shader、不用烘焙图。
## 位置仍从 `PAD` 起算、尺寸扣掉两倍 `PAD`，所以调用方的坐标一个都不用改
## —— 窗框依旧落在原来的 PAD 处，只是外面那圈「投影 / 圆角」没了。
func _build_shader_bg(radius: int) -> void:
	var bg := Panel.new()
	bg.name = "bg"
	bg.position = Vector2(PAD, PAD)
	bg.size = Vector2(size.x - PAD * 2.0, size.y - PAD * 2.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = _frame_fill()
	sb.border_color = TecTheme.LINE
	## **2px**，而卡片是 1px。纯白纸上没有灰阶可用，窗口与卡片叠在一起时
	## 唯一的「谁压着谁」线索就是边框粗细 —— 窗口是容器，必须比内容重一档。
	## （参考图的窗口内部还有一层内框承担同样的职责。）
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	bg.add_theme_stylebox_override("panel", sb)
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
	## 字距 2 → 1：换字体后 12px 黑体的西文本身比点阵宋体宽，再 +2 就散了。
	spaced.set_spacing(TextServer.SPACING_GLYPH, 1)
	_title_label.add_theme_font_override("font", spaced)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.clip_text = true
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.custom_minimum_size = Vector2(240, 0)
	_title_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(_title_label)
	title_row.add_child(_title_rule())

	var sep := ColorRect.new()
	sep.name = "sep"
	## 1-bit 的分隔线就是黑线，不用半透明 —— 白底上 35% 的黑读作「灰」
	sep.color = TecTheme.INK
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


## 内容流的最小高度。`get_combined_minimum_size()` 在刚增删子节点、还没排下一帧时
## 可能仍是旧值；这里按可见子节点逐项求和兜底，避免窗框底边落在内容上。
func content_min_height() -> float:
	if content == null:
		return 0.0
	var n := content.get_child_count()
	var sum := 0.0
	for child in content.get_children():
		if child.visible:
			sum += child.get_combined_minimum_size().y
	sum += maxf(n - 1, 0) * content.get_theme_constant("separation")
	return maxf(content.get_combined_minimum_size().y, sum)


func _title_rule() -> Control:
	## 标题两侧的装饰条：**三道 1px 纯黑横纹**（参考图即为此）。
	## 原来是一条 30% 半透明灰线 —— 在 1-bit 里「淡」不能靠 alpha，只能靠线宽与线数。
	## 三道刚好填满 28px 标题栏的视觉中线，且与「1px 分隔线」拉开层次。
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(12.0, BAR_H - 1.0)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mid := BAR_H * 0.5
	for i in 3:
		var rule := ColorRect.new()
		rule.color = TecTheme.INK
		rule.anchor_left = 0.0
		rule.anchor_right = 1.0
		rule.anchor_top = 0.0
		rule.anchor_bottom = 0.0
		rule.offset_left = 0.0
		rule.offset_right = 0.0
		## 间距 4px：三条线占 9px，在 28px 里居中
		rule.offset_top = mid - 4.5 + float(i) * 4.0
		rule.offset_bottom = rule.offset_top + 1.0
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(rule)
	return wrap


func _mini_button(text: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.size = Vector2(CTRL, CTRL)
	b.custom_minimum_size = b.size
	var normal := TecTheme.flat(TecTheme.CARD, TecTheme.R_BTN, TecTheme.INK, 1)
	normal.content_margin_left = 0
	normal.content_margin_right = 0
	normal.content_margin_top = 0
	normal.content_margin_bottom = 0
	b.add_theme_stylebox_override("normal", normal)
	## 与全站按钮同一套语法（P4.2）：键线 1px → 悬停 2px → 按下反白。
	## 原来常态用 `EDGE`（30% 黑），这两个小圆在标题栏上淡得像没画框。
	b.add_theme_stylebox_override("hover", TecTheme.flat(TecTheme.CARD, TecTheme.R_BTN, TecTheme.INK, 2))
	b.add_theme_stylebox_override("pressed", TecTheme.flat(TecTheme.INK, TecTheme.R_BTN, TecTheme.INK, 1))
	var glyph := TecTheme.label(text, TecTheme.FS_BODY, TecTheme.TEXT)
	glyph.name = "glyph"
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(glyph)
	b.set_meta("glyph_normal", TecTheme.TEXT)
	b.set_meta("glyph_hot", TecTheme.CARD)
	## 只有**按下**才反白；悬停只加粗键线，字形不动。
	b.button_down.connect(func(): _paint_mini_glyph(b, true))
	b.button_up.connect(func(): _paint_mini_glyph(b, false))
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
	var bg := get_node_or_null("bg") as Control
	if bg != null:
		bg.size = inner


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
