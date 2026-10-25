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
## 1-bit 浮层投影：右下 3px 的纯黑实块（System 1–6 的菜单/弹窗语法）。
## 只由浮层显式打开；普通窗口保持平面，避免满屏黑边。
const OFFSET_SHADOW := Vector2(3, 3)
var offset_shadow := false
var _offset_shadow: ColorRect
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
## A2：激活窗有条纹标题栏 + 2px 框；非激活窗只留空标题栏 + 1px 框。
var _active := true
var _rules: Array[Control] = []
var _title_stripes: Control = null
var _drag_enabled := true


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
	if offset_shadow:
		_offset_shadow = ColorRect.new()
		_offset_shadow.name = "offset_shadow"
		_offset_shadow.color = TecTheme.shadow(1.0)
		_offset_shadow.position = Vector2(PAD, PAD) + OFFSET_SHADOW
		_offset_shadow.size = Vector2(size.x - PAD * 2.0, size.y - PAD * 2.0)
		_offset_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_offset_shadow)

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

	## 顶栏统一语法：三道横纹铺满整条栏，标题文字居中并留出左右缺口；
	## 标题宽度按文字实测，窄窗只收窄标题，不会压到右侧按钮或把横纹挤出栏外。
	_title_stripes = TitleStripes.new()
	_title_stripes.name = "title_stripes"
	_title_stripes.position = Vector2.ZERO
	_title_stripes.size = Vector2(inner_w, BAR_H - 1.0)
	_title_stripes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## C-B：新窗默认激活，横纹走强调青；非激活时由 set_active 换回墨色。
	(_title_stripes as TitleStripes).col = TecTheme.SPOT_ACCENT
	bar.add_child(_title_stripes)
	_rules.append(_title_stripes)

	_title_label = TecTheme.label(title, TecTheme.FS_BODY, TecTheme.TEXT)
	_title_label.name = "win_title"
	var spaced := FontVariation.new()
	spaced.base_font = TecTheme.font()
	## 字距 2 → 1：换字体后 12px 黑体的西文本身比点阵宋体宽，再 +2 就散了。
	spaced.set_spacing(TextServer.SPACING_GLYPH, 1)
	_title_label.add_theme_font_override("font", spaced)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.clip_text = true
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_title_label)

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
	_sync_title_area()

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


## 顶栏标题区：按文字实测宽度居中；左右各留出控件宽度，标题永远不会压到
## 关闭 / 最小化按钮。三道横纹由 `TitleStripes` 整条绘制，并在标题处断开。
func _sync_title_area() -> void:
	if _title_label == null or not is_instance_valid(_title_label):
		return
	if _title_stripes == null or not is_instance_valid(_title_stripes):
		return
	var bar := _title_label.get_parent() as Control
	if bar == null:
		return
	## A9：按钮区按**实占可见按钮**计算。CertWin 隐藏 × 且没有 – 时，
	## 条纹必须补到右沿，不能留下一个 24px 的空缺口。
	var min_btn := bar.get_node_or_null("min") as Control
	var controls := 0.0
	if min_btn != null and min_btn.visible:
		## – 在 × 左侧 23px；只要 – 在，按钮区就占到 inner_w-47。
		controls = 47.0
	elif _close_btn != null and _close_btn.visible:
		controls = 24.0
	var margin := controls + 8.0
	var max_w := maxf(_inner_w - margin * 2.0, 24.0)
	var font := _title_label.get_theme_font("font")
	var fs := _title_label.get_theme_font_size("font_size")
	var text_w := 0.0
	if font != null and _title_label.text != "":
		text_w = font.get_string_size(_title_label.text, HORIZONTAL_ALIGNMENT_LEFT,
			-1, fs).x
	var w := clampf(text_w + 12.0, 24.0, max_w)
	var x := (_inner_w - w) * 0.5
	_title_label.position = Vector2(x, 0.0)
	_title_label.size = Vector2(w, BAR_H - 1.0)
	_title_stripes.position = Vector2.ZERO
	_title_stripes.size = Vector2(_inner_w, BAR_H - 1.0)
	var stripes := _title_stripes as TitleStripes
	stripes.line_left = 10.0
	stripes.line_right = maxf(_inner_w - controls - (8.0 if controls > 0.0 else 2.0), 10.0)
	stripes.gap_left = x - 7.0
	stripes.gap_right = x + w + 7.0
	stripes.queue_redraw()


## 标题栏横纹：三道 1px 线，按标题区留出中间缺口；整条 Control 参与
## 激活 / 非激活切换（非激活时隐藏，与 System 6 一致）。
class TitleStripes extends Control:
	var line_left := 10.0
	var line_right := 10.0
	var gap_left := 0.0
	var gap_right := 0.0
	var col := TecTheme.SPOT_ACCENT

	func _draw() -> void:
		var mid := size.y * 0.5
		for i in 3:
			var y := mid - 4.5 + float(i) * 4.0
			if gap_left > line_left:
				draw_line(Vector2(line_left, y), Vector2(gap_left, y), col, 1.0)
			if line_right > gap_right:
				draw_line(Vector2(gap_right, y), Vector2(line_right, y), col, 1.0)


func _mini_button(text: String) -> Button:
	return TecTheme.mini_button(text)


## MemCard 这类深色标题栏会把 glyph 颜色改成提亮版，再借这个方法回灌。
func _paint_mini_glyph(b: Button, hot: bool) -> void:
	var glyph := b.get_node_or_null("glyph") as Label
	if glyph == null:
		return
	glyph.add_theme_color_override("font_color",
		b.get_meta("glyph_hot" if hot else "glyph_normal", TecTheme.TEXT))


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
		_sync_title_area()


## A2：与 System 6 一致 —— 激活窗的标题栏有三道横纹、2px 框；
## 非激活窗收起横纹、框降为 1px，标题降到 INK_FAINT。只改视觉，不动几何。
func set_active(on: bool) -> void:
	if _active == on:
		return
	_active = on
	## C-B：横纹始终保留；激活 = 强调青，非激活 = 墨色。A2 的层次改由颜色承担。
	if _title_stripes != null and is_instance_valid(_title_stripes):
		(_title_stripes as TitleStripes).col = TecTheme.SPOT_ACCENT if on else TecTheme.INK
		(_title_stripes as TitleStripes).queue_redraw()
	if _title_label != null:
		_title_label.add_theme_color_override("font_color",
			TecTheme.TEXT if on else TecTheme.INK_FAINT)
	var bg := get_node_or_null("bg") as Panel
	if bg != null:
		var sb := bg.get_theme_stylebox("panel") as StyleBoxFlat
		if sb != null:
			sb.set_border_width_all(2 if on else 1)


func is_window_active() -> bool:
	return _active


## A2：只有「系统窗」参与激活态竞争。叙事卡 / 记忆卡虽然复用窗框，
## 但它们是内容卡，抢走激活标题栏会让真正开着的窗突然变灰。
func participates_in_activation() -> bool:
	return true


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
		_sync_title_area()
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
	if _offset_shadow != null and is_instance_valid(_offset_shadow):
		_offset_shadow.position = bg.position + OFFSET_SHADOW if bg != null else Vector2(PAD, PAD) + OFFSET_SHADOW
		_offset_shadow.size = inner


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
	_sync_title_area()


func _on_close_pressed() -> void:
	closed.emit()
	if not _manual_close:
		queue_free()


## 教学期 TEC 窗体常驻中央：关掉标题栏拖动，避免玩家把「角色」拖走。
func set_drag_enabled(on: bool) -> void:
	_drag_enabled = on


func dbg_drag_enabled() -> bool:
	return _drag_enabled


func _on_bar_input(event: InputEvent) -> void:
	## W1：标题栏事件必须在 bar 上吞掉，否则会继续冒泡到窗体的 `_gui_input`
	## （TEC → 白聊一句、MemCard → 翻行）。拖动禁用时也要吞，标题栏不能透给内容区。
	var bar := get_node_or_null("bar") as Control
	if bar != null:
		bar.accept_event()
	if not _drag_enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_press = event.global_position
			_grab = position
			# 点击提层：Desktop 会把窗提到浮动窗栈顶；不在桌面里用就地置顶兜底
			if raise_now.is_valid():
				raise_now.call(self)
			else:
				move_to_front()
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		position = _clamp_window_pos(_grab + (event.global_position - _press))


## 标题栏至少留 40px 在桌面内，避免窗口被拖到裁切区外永久拿不回。
func clamp_into_parent() -> void:
	position = _clamp_window_pos(position)


func _clamp_window_pos(p: Vector2) -> Vector2:
	var parent := get_parent() as Control
	if parent == null:
		return p
	var keep := 40.0
	var min_x := keep - size.x
	var max_x := maxf(min_x, parent.size.x - keep)
	var max_y := maxf(0.0, parent.size.y - keep)
	return Vector2(clampf(p.x, min_x, max_x), clampf(p.y, 0.0, max_y))


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
