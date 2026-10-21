class_name NodeCard
extends Control
## 画布上的一个节点卡片。
##
## 视觉：柔和浮雕表面（surface.gdshader）+ 标题/副标题两行；与 Web 版 `.node` 同尺寸口径
## （场景 152×54、实体 130×46，圆角 11，1px 发丝描边）。
##
## 交互口径**完全对齐 Web 版 `08-interact.js`**：
##   - 单击（未位移松手）= 选中（刷详情窗），**不激活**；
##   - 双击（280ms 内第二次点击）= 激活（场景展开 / 手电筒开关 / 跑命令）；
##   - 拖动 = 移动；松手落点在落点表上 → 触发动作并**弹回原位**；
##     落在空白 → **夹回 world 边界并写回数据**（`drag_finished`），不弹回；
##   - 右键 = 钉住 / 取消钉住（唯一入口，拖动不再自动钉住）。
##
## 坐标基准（见 INTERACTION_GAP_REPORT §4.1）：`position` 是**含 8px 阴影余量的外框**左上角，
## 视觉框 = `position + (PAD, PAD)`，尺寸 `_w × _h`。布局 / 连线端点 / 命中判定一律走
## `visual_rect()`，禁止各自手算。

signal activated(key: String)
signal combo_requested(tool_key: String, target_key: String)
signal selected(key: String)
signal dragged(key: String)
## 拖动过程中每帧抛一次（Desktop 用来刷连线 / 悬停落点高亮）
signal drag_moved(key: String, at_global: Vector2)
## 松手：handled=true 表示被落点消费（已弹回原位）；false 表示停在原位（pos 已夹回边界）
signal drag_finished(key: String, pos: Vector2, handled: bool)
signal pin_toggled(key: String)

const PAD := 8.0
const DRAG_THRESHOLD := 5.0
## 双击判定窗口（Web 是浏览器 dblclick 的默认 ~500ms，这里收紧到 280ms：
## 像素风的点选节奏本来就快，窗口太长会把「点两下看看」误判成激活）
const DBL_MS := 280

const SYMBOL := {"loc": "■ ", "item": "□ ", "char": "● ", "clue": "▲ ", "time": "◆ "}
const KIND_NAME := {"loc": "场景", "item": "物品", "char": "人物", "clue": "线索", "time": "时刻"}
const DARK_HI := Color("38372f")
const DARK_LO := Color("1f1f19")
## 点亮态的光晕直径。Web 的 `#glow` 是 560×560 挂在节点上，这里按卡片尺寸取一个
## 「近身一圈」的尺寸就够 —— 太大会把相邻节点糊成一片（一屏常有 10+ 张卡）。
const GLOW_SIZE := Vector2(220, 220)


## 程序化生成光晕贴图：两圈高斯叠起来，靠近卡片边缘最亮、往外淡出。
## 对像素画风来说这比真高斯更"干净"（没有灰阶噪点），也省一张资产。
static func _glow_texture() -> Texture2D:
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := float(n - 1) * 0.5
	for y in n:
		for x in n:
			var dx := (float(x) - c) / c
			var dy := (float(y) - c) / c
			var r := sqrt(dx * dx + dy * dy)
			var a := 0.55 * exp(-pow((r - 0.30) * 7.0, 2.0)) \
				+ 0.30 * exp(-pow((r - 0.42) * 2.6, 2.0))
			if r > 1.0:
				a = 0.0
			img.set_pixel(x, y, Color(1.0, 0.827, 0.431, clampf(a, 0.0, 0.6)))
	return ImageTexture.create_from_image(img)

var card_key: String = ""
var kind: String = ""
var node_data: Dictionary = {}

## 落点分派（Desktop 注入）：`func(key, at_global) -> bool`，true = 已消费 ⇒ 弹回原位。
var drop_sink := Callable()
## 拖出画布时的夹回边界（world 坐标；由 Desktop 注入，见 WORLD_RECT）
var world_rect := Rect2()

var _mat: ShaderMaterial
var _bg: ColorRect
var _title: Label
var _sub: Label
var _badge: Label
## 「无文本入口」药丸（Web `badge.warn`）：与「新」同一右上槽位，先加在 DOM 里
## 让「新」盖上去 —— 这里按同样的子节点顺序（warn 在前、新在后）保证叠放一致。
var _warn_badge: Label
var _pin_badge: Label
var _border: Control
## 选中环（独立一层：框是虚线 / 双线，环是 2px 实线，两者会同时存在）
var _sel: Control
## 点亮态的局部光晕（Web `#glow` 那个 560×560 径向渐变的近身版）
var _glow: TextureRect
var _w := 0.0
var _h := 0.0
var _container := false
var _explored := false
var _collapsed := false
var _unread := false
## 「无文本入口」的显示态：谓词在 GraphState（is_no_entry），这里只管画
var _warn := false
var _hover := false
var _dragging := false
var _moved := false
var _hub := false
var _pinned := false
var _over := false
var _pressed := false
var _press := Vector2.ZERO
var _grab := Vector2.ZERO
## 按下那一刻的位置：弹回 / 撤销的落点。`_home` 与它同义，保留旧名以免外部引用断掉。
var _home := Vector2.ZERO
var _last_click_ms := -100000
var _spring: Tween = null
## 入场动画补间（play_pop 建的；拖动 / 聚焦改外观时不与它打架）
var _pop: Tween = null


class DashBorder extends Control:
	var rect := Rect2()
	var radius := 11.0
	var color := Color(0.29, 0.27, 0.20, 0.55)
	## 枢纽场景用 CSS 的 `3px double`：外 1px 线、1px 空隙、内 1px 线。
	## 不能拿虚线凑 —— 两者语义不同（虚线=未探索，双线=枢纽），在 Web 里也是两套规则。
	var double_line := false
	## 选中环：Web `.node.sel{outline:2px solid #2b2b26; outline-offset:2px}`。
	## CSS 的 outline 画在**边框盒之外**、留 2px 空隙，所以这里用 `rect.grow(4)` 画 2px 实线，
	## 实际占掉 2~4px 那一圈（视觉框离卡片外沿还有 8px 的 PAD，够放）。
	var sel_line := false

	func _draw_sel() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_border_width_all(2)
		sb.border_color = Color("2b2b26")
		sb.set_corner_radius_all(int(maxf(radius, 1.0)) + 2)
		sb.anti_aliasing = true
		draw_style_box(sb, rect.grow(4.0))

	func _ring(r: Rect2, rad: float) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_border_width_all(1)
		sb.border_color = Color("2b2b26")
		sb.set_corner_radius_all(int(maxf(rad, 1.0)))
		sb.anti_aliasing = true
		draw_style_box(sb, r)

	func _draw() -> void:
		if sel_line:
			_draw_sel()
			return
		if double_line:
			_ring(rect, radius)
			_ring(rect.grow(-2.0), radius - 2.0)
			return
		var r := rect.grow(-0.5)
		var dash := 2.4
		draw_dashed_line(Vector2(r.position.x + radius, r.position.y),
			Vector2(r.end.x - radius, r.position.y), color, 1.0, dash, true, false)
		draw_dashed_line(Vector2(r.position.x + radius, r.end.y),
			Vector2(r.end.x - radius, r.end.y), color, 1.0, dash, true, false)
		draw_dashed_line(Vector2(r.position.x, r.position.y + radius),
			Vector2(r.position.x, r.end.y - radius), color, 1.0, dash, true, false)
		draw_dashed_line(Vector2(r.end.x, r.position.y + radius),
			Vector2(r.end.x, r.end.y - radius), color, 1.0, dash, true, false)
		draw_dashed_line(Vector2(r.end.x - radius, r.end.y),
			Vector2(r.position.x + radius, r.end.y), color, 1.0, dash, true, false)


func setup(p_key: String, p_kind: String, p_data: Dictionary, w: float, h: float) -> void:
	card_key = p_key
	kind = p_kind
	node_data = p_data
	size = Vector2(w + PAD * 2.0, h + PAD * 2.0)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Web `.node{cursor:grab}`：悬停手形；拖起来时 Input 全局覆盖成拖拽光标
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void: set_hover_state(true))
	mouse_exited.connect(func() -> void: set_hover_state(false))
	_pinned = bool(p_data.get("pinned", false))
	_build(w, h)


func _build(w: float, h: float) -> void:
	_w = w
	_h = h
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://ui/shaders/surface.gdshader")
	_mat.set_shader_parameter("rect_size", Vector2(w + PAD * 2.0, h + PAD * 2.0))
	_mat.set_shader_parameter("pad", PAD)
	_mat.set_shader_parameter("radius", float(TecTheme.R_SM))
	_mat.set_shader_parameter("shade_soft", 7.0)

	_bg = ColorRect.new()
	_bg.name = "bg"
	_bg.material = _mat
	_bg.color = Color.WHITE
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	# 光晕垫在卡面下面（同级先画），比卡片大一圈，超出部分不会被裁
	_glow = TextureRect.new()
	_glow.name = "glow"
	_glow.texture = _glow_texture()
	_glow.size = GLOW_SIZE
	_glow.position = Vector2(PAD + w * 0.5, PAD + h * 0.5) - GLOW_SIZE * 0.5
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_glow.visible = false
	add_child(_glow)
	move_child(_glow, 0)

	_border = DashBorder.new()
	_border.name = "border"
	_border.set_anchors_preset(Control.PRESET_FULL_RECT)
	_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_border.visible = false
	(_border as DashBorder).rect = Rect2(Vector2(PAD, PAD), Vector2(w, h))
	(_border as DashBorder).radius = float(TecTheme.R_SM)
	add_child(_border)

	_title = TecTheme.label("", 12, TecTheme.TEXT)
	_title.name = "title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	_sub = TecTheme.label("", TecTheme.FS_SMALL, TecTheme.FAINT)
	_sub.name = "sub"
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sub)

	_title.position = Vector2(PAD + 7.0, PAD + h * 0.5 - 15.0)
	_title.size = Vector2(w - 14.0, 16.0)
	_sub.position = Vector2(PAD + 7.0, PAD + h * 0.5 + 2.0)
	_sub.size = Vector2(w - 14.0, 14.0)

	_warn_badge = TecTheme.label("无文本入口", 9, TecTheme.TEXT)
	_warn_badge.name = "warn"
	_warn_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warn_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_warn_badge.position = Vector2(PAD + w - 52.0, -1.0)
	_warn_badge.size = Vector2(60.0, 17.0)
	_warn_badge.add_theme_stylebox_override("normal", TecTheme.flat(TecTheme.CARD, 9,
		TecTheme.TEXT, 2))
	_warn_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warn_badge.visible = false
	add_child(_warn_badge)

	_badge = TecTheme.label("新", 9, TecTheme.CARD)
	_badge.name = "unread"
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.position = Vector2(PAD + w - 14.0, -1.0)
	_badge.size = Vector2(20.0, 17.0)
	_badge.add_theme_stylebox_override("normal", TecTheme.flat(TecTheme.LINE, 9,
		TecTheme.LINE, 1))
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.visible = false
	add_child(_badge)

	# 「已固定」药丸：Web 放在**左上角**，与右上角的「新」各自占位、可以同时存在
	_pin_badge = TecTheme.label("已固定", 9, TecTheme.CARD)
	_pin_badge.name = "pin"
	_pin_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pin_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pin_badge.position = Vector2(PAD - 2.0, -1.0)
	_pin_badge.size = Vector2(38.0, 17.0)
	_pin_badge.add_theme_stylebox_override("normal", TecTheme.flat(TecTheme.LINE, 9,
		TecTheme.LINE, 1))
	_pin_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin_badge.visible = false
	add_child(_pin_badge)

	_sel = DashBorder.new()
	_sel.name = "sel"
	_sel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sel.visible = false
	(_sel as DashBorder).rect = Rect2(Vector2(PAD, PAD), Vector2(w, h))
	(_sel as DashBorder).radius = float(TecTheme.R_SM)
	(_sel as DashBorder).sel_line = true
	add_child(_sel)

	refresh()


func refresh() -> void:
	var sym: String = SYMBOL.get(kind, "")
	_title.text = sym + String(node_data.get("label", card_key))
	_sub.text = String(KIND_NAME.get(kind, kind))
	if _container:
		if _collapsed:
			_sub.text = "已折叠 · 双击展开"
		elif _explored:
			_sub.text = "已探索"
		else:
			_sub.text = "未探索 · 双击展开"
	if kind == "item" and bool(node_data.get("lit", false)):
		_sub.text = "物品 · 亮着"
	if kind == "clue" and bool(node_data.get("captured", false)):
		_sub.text = "线索 · 已捕获"
	_apply_shell()


func set_shell_state(container: bool, explored: bool, collapsed: bool, unread: bool,
		hub: bool = false) -> void:
	_container = container
	_explored = explored
	_collapsed = collapsed
	_unread = unread
	_hub = hub
	_pinned = bool(node_data.get("pinned", false))
	refresh()


## 外观分四套（优先级：拖动目标 > 已捕获 > 点亮 > 普通）。
## Web 的 `.got` / `.lit` 在 CSS 里是独立 class、写在 `.over` 之后，同特异性后者胜；
## 但真机上把「被拖的发光工具」压在目标卡上时，目标卡的 `.over` 才是玩家要读的信息，
## 所以这里让 `.over` 压在最上面（与 `_apply_over_look` 的既有口径一致）。
func _apply_shell() -> void:
	if _mat == null:
		return
	if _over:
		_apply_over_look()
		return
	var got := kind == "clue" and bool(node_data.get("captured", false))
	var lit := kind == "item" and bool(node_data.get("lit", false))
	if got:
		_apply_got_look()
	elif lit:
		_apply_lit_look()
	else:
		_apply_plain_look()
	_badge.visible = _unread
	_warn_badge.visible = _warn
	_pin_badge.visible = _pinned
	if _glow != null:
		_glow.visible = lit


## 「无文本入口」谓词每帧在 Desktop 算（is_no_entry），这里只负责显示态回灌
##（refresh → _apply_shell 会整块重刷外观，所以 set_warn 只改自己的标记）
func set_warn(on: bool) -> void:
	if _warn == on:
		return
	_warn = on
	_warn_badge.visible = on


## 普通态（含未探索 / 已折叠的扁平虚框）
func _apply_plain_look() -> void:
	var flat := _container and (not _explored or _collapsed)
	_mat.set_shader_parameter("flat_fill", flat)
	_mat.set_shader_parameter("col_hi", TecTheme.BG if flat else Color("fbf8ee"))
	_mat.set_shader_parameter("col_mid", TecTheme.BG if flat else Color("f5f2e8"))
	_mat.set_shader_parameter("col_lo", TecTheme.BG if flat else Color("eee9d7"))
	_mat.set_shader_parameter("edge_col", Color(0, 0, 0, 0) if flat
		else Color(0.290, 0.271, 0.204, 0.30))
	_mat.set_shader_parameter("rim_col", Color(0, 0, 0, 0) if flat
		else Color(1.0, 0.988, 0.945, 0.95))
	_mat.set_shader_parameter("shade_col", Color(0, 0, 0, 0) if flat
		else Color(0.306, 0.282, 0.212, 0.30))
	_title.add_theme_color_override("font_color", TecTheme.MUTED if flat else TecTheme.TEXT)
	_sub.add_theme_color_override("font_color", TecTheme.FAINT)
	_border.double_line = _hub
	_border.visible = flat or _hub
	_border.queue_redraw()
	if _glow != null:
		_glow.visible = false


## Web `.node.ent-clue.got`：深色反白（`linear-gradient(150deg,#38372f,#1f1f19)`）+
## 内嵌阴影 + 顶上 1px 白边。已捕获的线索「翻到背面」，一眼能和没读过的区分开。
func _apply_got_look() -> void:
	_mat.set_shader_parameter("flat_fill", false)
	_mat.set_shader_parameter("col_hi", DARK_HI)
	_mat.set_shader_parameter("col_mid", DARK_HI.lerp(DARK_LO, 0.55))
	_mat.set_shader_parameter("col_lo", DARK_LO)
	_mat.set_shader_parameter("edge_col", Color(0, 0, 0, 0))
	_mat.set_shader_parameter("rim_col", Color(1, 1, 1, 0.28))
	_mat.set_shader_parameter("shade_col", Color(0, 0, 0, 0.35))
	_title.add_theme_color_override("font_color", TecTheme.CARD)
	_sub.add_theme_color_override("font_color", TecTheme.LINE2)
	_border.visible = false
	if _glow != null:
		_glow.visible = false


## Web `.node.lit`：金框 `#e3b341` + 暖白底 `#fffbeb` + 双层外发光。
## 发光用贴图光晕近似（CSS 是 `0 0 14px 3px` + `0 0 46px 14px` 两层叠加）。
func _apply_lit_look() -> void:
	_mat.set_shader_parameter("flat_fill", false)
	_mat.set_shader_parameter("col_hi", Color("fffdf6"))
	_mat.set_shader_parameter("col_mid", Color("fffbeb"))
	_mat.set_shader_parameter("col_lo", Color("fcf0cd"))
	_mat.set_shader_parameter("edge_col", Color("e3b341"))
	_mat.set_shader_parameter("rim_col", Color(1, 0.988, 0.945, 0.95))
	_mat.set_shader_parameter("shade_col", Color(1.0, 0.769, 0.259, 0.16))
	_title.add_theme_color_override("font_color", TecTheme.TEXT)
	_sub.add_theme_color_override("font_color", Color("9a7b2a"))
	_border.visible = false
	if _glow != null:
		_glow.visible = true


## Web `.node.over{background:linear-gradient(150deg,#38372f,#1f1f19);color:var(--card);transform:scale(1.06)}`
## —— 拖动的**目标节点**整块反白。缩放 1.06 需要 pivot，会牵动连线端点，P0 先只做反白。
func _apply_over_look() -> void:
	_mat.set_shader_parameter("flat_fill", false)
	_mat.set_shader_parameter("col_hi", DARK_HI)
	_mat.set_shader_parameter("col_mid", DARK_HI.lerp(DARK_LO, 0.5))
	_mat.set_shader_parameter("col_lo", DARK_LO)
	_mat.set_shader_parameter("edge_col", Color(0, 0, 0, 0))
	_mat.set_shader_parameter("rim_col", Color(1.0, 0.988, 0.945, 0.18))
	_mat.set_shader_parameter("shade_col", Color(0.306, 0.282, 0.212, 0.45))
	_title.add_theme_color_override("font_color", TecTheme.CARD)
	_sub.add_theme_color_override("font_color", TecTheme.LINE2)
	_border.visible = false
	_badge.visible = false
	_warn_badge.visible = false
	_pin_badge.visible = false
	if _glow != null:
		_glow.visible = false


## 选中环（Web `.node.sel`）。独立于外观三态：已捕获的线索被选中时，
## 深色卡面外面照样套一圈 2px 实线。
func set_selected(on: bool) -> void:
	if _sel == null or _sel.visible == on:
		return
	_sel.visible = on
	_sel.queue_redraw()


func is_selected() -> bool:
	return _sel != null and _sel.visible


## 当前外观态：`plain` / `got` / `lit` / `over`。给无头断言一个可读的出口，
## 免得测试去反查 shader 参数（那是实现细节）。
func look_state() -> String:
	if _over:
		return "over"
	if kind == "clue" and bool(node_data.get("captured", false)):
		return "got"
	if kind == "item" and bool(node_data.get("lit", false)):
		return "lit"
	return "plain"


## 拖动悬停反馈（Desktop 每帧算一次命中后回填）
func set_over(on: bool) -> void:
	if _over == on:
		return
	_over = on
	if on:
		_apply_over_look()
	else:
		_apply_shell()


## 直接把卡片放到某处（收纳取回 / 布局）。**必须掐掉还在跑的弹回补间** ——
## 否则补间每帧继续往旧 `_home` 写位置，刚摆好的落点当场被拽回去（实测差 60×27px）。
func set_home(p: Vector2) -> void:
	if _spring != null and _spring.is_valid():
		_spring.kill()
	_spring = null
	_home = p
	position = p


## 只把「停靠点」改到 p（顺带杀掉弹簧），不动 position —— 配合 Desktop 的位置过渡：
## 补间把卡搬过去的过程中，锚点先就位，收尾再 set_home 校准。
func set_home_silent(p: Vector2) -> void:
	if _spring != null and _spring.is_valid():
		_spring.kill()
	_spring = null
	_home = p


## 视觉框（world 坐标，不含 8px 阴影余量）—— 布局 / 连线 / 命中判定的唯一来源
func visual_rect() -> Rect2:
	return Rect2(position + Vector2(PAD, PAD), Vector2(_w, _h))


func visual_center() -> Vector2:
	return position + Vector2(PAD + _w * 0.5, PAD + _h * 0.5)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				pin_toggled.emit(card_key)
				accept_event()
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_pressed = true
			_press = mb.global_position
			_grab = position
			_home = position
			_moved = false
			_dragging = false
			move_to_front()
			accept_event()
		else:
			if not _pressed:
				return
			_pressed = false
			if _dragging:
				_dragging = false
				_release_drop(mb.global_position)
			elif not _moved:
				_click()
			accept_event()
	elif event is InputEventMouseMotion:
		if _pressed and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			var delta: Vector2 = (event as InputEventMouseMotion).global_position - _press
			if not _dragging and delta.length() > DRAG_THRESHOLD:
				_dragging = true
				_moved = true
				# Web `.node.dragging{cursor:grabbing}`：拖拽期间全局覆盖为拖拽光标
				Input.set_default_cursor_shape(Input.CURSOR_DRAG)
				dragged.emit(card_key)
			if _dragging:
				var s := maxf(get_parent().scale.x, 0.01) if get_parent() != null else 1.0
				position = _grab + delta / s
				drag_moved.emit(card_key, (event as InputEventMouseMotion).global_position)
				accept_event()


## 单击 / 双击分流：280ms 内第二下 = 激活（Web 的 pointerup 选中 + dblclick 激活）
func _click() -> void:
	var now_ms := Time.get_ticks_msec()
	var near := _press.distance_to(_last_click_global) < 6.0
	if now_ms - _last_click_ms <= int(DBL_MS) and near:
		_last_click_ms = -100000          # 吃掉这一对，避免三连击再触发一次
		selected.emit(card_key)
		activated.emit(card_key)
		return
	_last_click_ms = now_ms
	_last_click_global = _press
	selected.emit(card_key)


var _last_click_global := Vector2.ZERO


func _release_drop(at_global: Vector2) -> void:
	# 拖拽光标随松手归还（悬停手形由 mouse_default_cursor_shape 天然接管）
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	# 1) 落点表（图标 / 两扇收纳窗 / 推演桌布 / TEC / 对话窗）：命中即回原位
	if drop_sink.is_valid() and bool(drop_sink.call(card_key, at_global)):
		spring_back()
		drag_finished.emit(card_key, _home, true)
		return
	# 2) 落在别的节点上 = 组合，自己也回原位
	var target := _card_under(at_global)
	if target != "" and target != card_key:
		spring_back()
		drag_finished.emit(card_key, _home, true)
		combo_requested.emit(card_key, target)
		return
	# 3) 空白：夹回 world 边界并写回数据（不弹回，停在松手处）
	var p := _clamp_pos(position)
	position = p
	_home = p
	drag_finished.emit(card_key, p, false)


func _clamp_pos(p: Vector2) -> Vector2:
	if world_rect.size.x <= 0.0 or world_rect.size.y <= 0.0:
		return p
	var lim_x := world_rect.size.x - size.x
	var lim_y := world_rect.size.y - size.y
	return Vector2(clampf(p.x, 0.0, maxf(lim_x, 0.0)),
		clampf(p.y, 0.0, maxf(lim_y, 0.0)))


## 弹回按下时的位置（三次缓出 300ms，对齐 Web 的 springBack）
func spring_back() -> void:
	_spring_to(_home)


func _spring_to(target: Vector2) -> void:
	if _spring != null and _spring.is_valid():
		_spring.kill()
	if position.is_equal_approx(target):
		position = target
		return
	_spring = create_tween()
	_spring.tween_property(self, "position", target, 0.30).set_trans(Tween.TRANS_CUBIC) \
		.set_ease(Tween.EASE_OUT)
	_spring.finished.connect(func():
		position = target
		_home = target)


## 松手时指针下面是哪张卡（排除自己；折叠的容器也算，交给 Desktop 决定放不放行）
func _card_under(global_pos: Vector2) -> String:
	var parent := get_parent()
	if parent == null:
		return ""
	for c in parent.get_children():
		if c == self or not (c is NodeCard):
			continue
		var card := c as NodeCard
		if not card.visible:
			continue
		if card.get_global_rect().grow(-PAD * 0.5).has_point(global_pos):
			return card.card_key
	return ""


func is_dragging() -> bool:
	return _dragging


func set_hover_state(on: bool) -> void:
	if _hover == on:
		return
	_hover = on
	if _mat != null and not _over:
		_mat.set_shader_parameter("shade_soft", 10.0 if on else 7.0)


## 「聚焦选中」：与选中卡无关的卡淡化（Web 04-nodes.css `.node.dim{opacity:.32}`）
func set_dim(on: bool) -> void:
	var target := Color(1, 1, 1, 0.32) if on else Color(1, 1, 1, 1)
	if modulate != target:
		modulate = target


## 入场动画（Web `.node.pop` keyframes：0% scale .4 opacity 0 → 60% scale 1.12
## → 100% scale 1 opacity 1，共 0.45s）。只在卡片初生时调一次（fresh 消费掉）。
func play_pop() -> void:
	if _pop != null and _pop.is_valid():
		_pop.kill()
	scale = Vector2.ONE * 0.4
	modulate.a = 0.0
	_pop = create_tween()
	_pop.tween_property(self, "scale", Vector2.ONE * 1.12, 0.270) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_pop.tween_property(self, "scale", Vector2.ONE, 0.180) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_pop.parallel().tween_property(self, "modulate:a", 1.0, 0.200)


## 拖动镜像（Web 的 #drag-layer 复刻）：新建一张"inert"翻版卡交给 Desktop 挂到
## 最顶层（windows 之上）。不能用 duplicate() —— 脚本成员不会一起拷贝
## （_mat/card_key 会是空值），所以走 setup() 重画一遍再回灌当前外观态。
func build_mirror() -> NodeCard:
	var m := NodeCard.new()
	m.name = "card_mirror"
	m.setup(card_key, kind, node_data, _w, _h)
	m.set_shell_state(_container, _explored, _collapsed, _unread, _hub)
	m.set_warn(_warn)
	m.position = position
	_strip_input(m)
	return m


func _strip_input(c: Node) -> void:
	var ctl := c as Control
	if ctl != null:
		ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in c.get_children():
		_strip_input(ch)
