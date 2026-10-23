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
## 图标**显示尺寸 48**（原来 44）。
## 图标源是 24×24 的 1px 线稿，`.import` 里 `svg/scale = 2.0` 把它栅格化成 **48×48**
## （线宽 2px）—— 48 与显示尺寸 1:1，NEAREST 完全不重采样，线宽处处相等。
## 之前是「24px 纹理 + 44px 显示」= 1.83 倍非整数放大，1px 线被抽成 1px/2px 交替，
## 那才是「图标看着发毛」的原因；而把它重画成粗线点阵（P4 初版）又丢了细节。
const GLYPH_SIZE := 48.0
## 图标上沿 / 标签上沿 / 标签高：1 + 48 + 15 = 64 = ROOT_SIZE，一格刚好塞满。
## 旧值是 `GLYPH_PAD 10`（给「图标后面那块底板」留的出血），底板在 P4.2 被删了，
## 那 10px 出血就成了图标与标签之间一道说不清的空隙。
const GLYPH_TOP := 1.0
const LABEL_TOP := 49.0
const LABEL_H := 15.0
const DRAG_THRESHOLD := 5.0

var _glyph: ColorRect
var _icon: TextureRect
var _label: Label
var _selected := false
var _down := false
var _over := false
var _press_pos := Vector2.ZERO
var _drag_origin := Vector2.ZERO
var _moved := false
var _bounds := Rect2(Vector2.ZERO, Vector2(1280, 668))
var _root_size := ROOT_SIZE
var _compact := false


func setup(p_text: String, p_icon: String) -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(ROOT_SIZE, ROOT_SIZE)
	size = custom_minimum_size
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())

	## 图标本体**永远不垫底板**（P4.2）。参考图（Mac OS 8 桌面）里按下的图标
	## 只有**标签条反白**，图标本身仍是「黑线稿直接躺在桌面上」。
	## 我们之前在图标后面画一块 44×44 的黑圆角块 —— 于是屏上同时出现
	## 「黑方块 + 黑标签条」两个黑块，中间还夹一道白缝，这就是用户说的
	## 「多一个框出来的全黑」。底板与它的 shader 一起删掉，`_glyph` 只剩容器职责。
	_glyph = ColorRect.new()
	_glyph.name = "glyph"
	_glyph.position = Vector2.ZERO
	_glyph.size = Vector2(ROOT_SIZE, ROOT_SIZE)
	_glyph.color = TecTheme.NONE
	_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glyph)

	_icon = TextureRect.new()
	_icon.name = "icon"
	_icon.texture = load(p_icon)
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_icon.position = Vector2((ROOT_SIZE - GLYPH_SIZE) * 0.5, GLYPH_TOP)
	_icon.size = Vector2(GLYPH_SIZE, GLYPH_SIZE)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glyph.add_child(_icon)

	_label = TecTheme.label(p_text, TecTheme.FS_BODY, TecTheme.MUTED)
	_label.name = "label"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.position = Vector2(0, LABEL_TOP)
	_label.size = Vector2(ROOT_SIZE, LABEL_H)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	# 紧凑模式会藏掉文字标签，名称仍要能从 tooltip 读出来。
	tooltip_text = p_text

	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	_apply_style()


## 矮窗口 / 图标多时切紧凑：不缩 48px 图标本体（避免 SVG 重采样发糊），
## 只收掉外圈留白与文字标签，把每个图标高度从 64 压到 52。
func set_compact(on: bool) -> void:
	if _compact == on:
		return
	_compact = on
	## 紧凑模式的外框必须容得下 48px 图标 + 上下各 2px 留白（52），
	## 原来写死 48 会让图标横向溢出。文字标签仍是唯一的可压缩项。
	_root_size = 52.0 if on else ROOT_SIZE
	custom_minimum_size = Vector2(_root_size, _root_size)
	size = custom_minimum_size
	_glyph.size = Vector2(_root_size, _root_size)
	_icon.position = Vector2((_root_size - GLYPH_SIZE) * 0.5, 2.0 if on else GLYPH_TOP)
	_icon.size = Vector2(GLYPH_SIZE, GLYPH_SIZE)
	_label.visible = not on
	place_badges()
	_apply_style()
	queue_redraw()


## 徽章统一贴在**图标本体**右上角外 2px（不是距根节点边），紧凑模式也不漂。
## 宽度取实时最小尺寸，这样「1」和「12」右沿都能对齐。
func place_badges() -> void:
	if _icon == null:
		return
	var right := _icon.position.x + GLYPH_SIZE + 2.0
	var top := _icon.position.y - 2.0
	for ch in get_children():
		if ch is PanelContainer and String(ch.name).ends_with("badge"):
			var b := ch as Control
			b.reset_size()
			b.position = Vector2(right - b.size.x, top)


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


func _on_hover(_on: bool) -> void:
	## **悬停不再改外观**。原来这里在放大两盏 shader 阴影的 soft/offset ——
	## 而 P3 起 shade_col/glow_col 都是 NONE，调参已经是空转。
	## 1-bit 桌面图标没有「浮起」这回事：指针移上去只需要光标变手形（已由
	## `mouse_default_cursor_shape` 负责），底板与图标一律不动。
	pass


## 拖动中悬停 = 落点：Web `.desk-icon.over .icon-glyph` 与按下态同一套暗底 + 2px 描边
func set_over(on: bool) -> void:
	if _over == on:
		return
	_over = on
	_apply_style()
	queue_redraw()


func _draw() -> void:
	## 两种场合要一道键线框：
	##   拖动落点（`_over`）—— 告诉玩家「松手就放这儿」；
	##   紧凑模式下被选中 —— 那个模式把文字标签收掉了，没有标签可反白，
	##   不给框就**完全看不出选中**（底板删掉之后这里曾是空的）。
	var framed := _over or (_compact and (_selected or _down))
	if not framed:
		return
	## 键线一律 **1px**（与全站按钮同一条线宽）。原来是 2px 硬框 ——
	## 满屏 1px 之间突然出现一根 2px，读作「另一套零件」。
	var sb := StyleBoxFlat.new()
	sb.bg_color = TecTheme.NONE
	sb.set_border_width_all(1)
	sb.border_color = TecTheme.INK
	sb.set_corner_radius_all(TecTheme.R_SM)
	draw_style_box(sb, Rect2(_icon.position - Vector2(2, 2),
		Vector2(GLYPH_SIZE + 4.0, GLYPH_SIZE + 4.0)))


## 按下 / 选中时**只反白标签条**：一条贴着文字的实心黑条 + 白字（参考图里就是这样）。
## 图标本体不动 —— 它是黑线稿，压在灰桌面上，反白会需要一块底板，而底板正是要删的东西。
func _apply_style() -> void:
	## `set_selected` 有可能在 `setup()` 之前被调到（桌面重建时先选后建），别崩。
	if _label == null or _icon == null:
		return
	var dark := _selected or _down
	_icon.modulate = TecTheme.LINE
	_label.add_theme_color_override("font_color", TecTheme.CARD if dark else TecTheme.MUTED)
	var sb := StyleBoxFlat.new()
	sb.bg_color = TecTheme.INK if dark else TecTheme.NONE
	sb.set_border_width_all(0)
	## **直角**：参考图的标签块是个硬边小方条，圆角会把它读成「按钮」。
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	_label.add_theme_stylebox_override("normal", sb)
	_place_label(dark)
	queue_redraw()


## 黑条按文字的**实际宽度**收紧（参考图里那条黑比图标窄、贴着字）。
## 铺满 64px 的整条黑在两个字的名字上会读成「一条横幅」，不像被选中的标签。
func _place_label(dark: bool) -> void:
	var w := _root_size
	if dark:
		var f := TecTheme.font()
		if f != null:
			var tw := f.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, TecTheme.FS_BODY).x
			w = minf(ceilf(tw) + 8.0, _root_size)
	_label.size = Vector2(w, LABEL_H)
	_label.position = Vector2(floorf((_root_size - w) * 0.5), LABEL_TOP)
