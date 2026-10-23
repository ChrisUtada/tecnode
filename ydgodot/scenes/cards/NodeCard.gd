class_name NodeCard
extends Control
## 画布上的一个节点卡片。
##
## 视觉：柔和浮雕表面（surface.gdshader）+ 标题/副标题两行；与 Web 版 `.node` 同尺寸口径
## （P2：场景 160×56、实体 128×48，方角，1px 发丝描边）。
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
## 按下（Desktop 用它把飞行中的落位补间杀掉：卡冻结在指针下，双击才落得准）
signal pressed(key: String)
## 拖动过程中每帧抛一次（Desktop 用来刷连线 / 悬停落点高亮）
signal drag_moved(key: String, at_global: Vector2)
## 松手：handled=true 表示被落点消费（已弹回原位）；false 表示停在原位（pos 已夹回边界）
signal drag_finished(key: String, pos: Vector2, handled: bool)
signal pin_toggled(key: String)

const PAD := 8.0
const DRAG_THRESHOLD := 5.0
## 文字档类型符号的边长，以及「符号 → 首字」的间距。符号必须**贴着文字**走：
## 旧摆法是把它钉在卡片左边缘 5px 处、标题另外居中，两字标题（「书桌」「门锁」）时
## 两者之间空出一大片，符号看着像掉在框外、又挤着卡边（见 `_layout_title`）。
## 边长取 **9**（≈ 字面 3/4）：试过 11（= 字号 − 1），方块几乎与字面等高，下沿压到字脚、
## 看着比文字「低半格」；缩到 9 后上下各留 1~2px，读作标记而不是第二个字。
## P2：字牌从 16 放到 18，才容得下 10px 汉字（10px 墨高约 14，16 圈内径只有 13.8）。
const GLYPH_BOX := 18.0
const GLYPH_GAP := 6.0
## 标题 Label 的固定高度（单行，副标已删）
const TITLE_H := 16.0
## **墨迹中心距标题矩形顶边的高度**。标题用 `VERTICAL_ALIGNMENT_TOP` 而不是 CENTER ——
## CENTER 让 Godot 去居中「行盒」，实测同一条规则在不同倍率/DPI 下墨迹会漂 1.6px，
## 方块只能对着某一档去调，换台机器或换个缩放就又歪了（用户两次反馈「偏上 / 偏下」都源于此）。
## 顶部对齐后墨迹从固定高度垂下。`font-fusion` 12px 的行盒是 asc 13 / desc 3，
## 墨迹中心在 `(asc + desc) / 2 = 8px` 处 —— 符号圆心必须也落在卡中线上，两者才对齐。
const TITLE_INK_CY := 8.0
## 双击判定窗口（对齐浏览器 dblclick 的默认 ~500ms：之前收紧到 280ms，
## 玩家用正常节奏点两下就经常被判成两次单击，「双击无法展开」就是这么来的）
const DBL_MS := 500

## 类型名。**卡面上不显示它** —— 类型改由左侧的类型色符号承担（见 `ui/KindGlyph.gd`），
## 这个名字只给详情窗 `_kind_name()` 用。
const KIND_NAME := {"loc": "场景", "item": "物品", "char": "人物", "clue": "线索", "time": "时刻"}
const DARK_HI := TecTheme.FACE_DARK_HI
const DARK_LO := TecTheme.FACE_DARK_LO
## 点亮态的光晕直径。Web 的 `#glow` 是 560×560 挂在节点上，这里按卡片尺寸取一个
## 「近身一圈」的尺寸就够 —— 太大会把相邻节点糊成一片（一屏常有 10+ 张卡）。
const GLOW_SIZE := Vector2(220, 220)


## 程序化生成光晕贴图：两圈高斯叠起来，靠近卡片边缘最亮、往外淡出。
## 对像素画风来说这比真高斯更"干净"（没有灰阶噪点），也省一张资产。
static var _glow_cache: Texture2D

static func _glow_texture() -> Texture2D:
	if _glow_cache != null:
		return _glow_cache
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
			img.set_pixel(x, y, Color(TecTheme.SPOT_LIT_HALO, clampf(a, 0.0, 0.6)))
	_glow_cache = ImageTexture.create_from_image(img)
	return _glow_cache

var card_key: String = ""
var kind: String = ""
var node_data: Dictionary = {}

## ── 缩放分级（LOD）───────────────────────────────────────────────────────
## 相机缩到 1x 以下时卡片被整体重采样。实测（`--zoom=` 截图取证）：
##   0.95x 标题「注射器」还能读；0.88x 已经缺笔（读成「注器」）；0.78x 完全认不出。
## 所以文字只在接近原生格时出现，再往下只留**类型符号** —— 方块/圆/三角对下采样
## 是鲁棒的，字形不是。这也正好对上卡片本身的尺寸：128px 的卡缩到 0.62 只剩 79px，
## 两行字根本摆不下。
##   ≥ 0.86 → 类型符号 + 标题 + 三个角标
##   < 0.86 → 只剩放大的类型符号（缩略视图看的是拓扑，不是字）
##
## **副标整行已删除**（原「已探索 / 未探索 · 双击展开 / 物品 · 亮着 / 线索 · 已捕获」）：
## 这些状态本来就由边框与填充编码过一次 —— 实线=已探索、虚线+纸色=未探索、金框=亮着、
## 深色反白=已捕获。每张卡再写一遍等于「标签通胀」：一屏五六张卡都在喊同一句话，
## 玩家两天后就整行屏蔽了，连带把真正有用的也一起忽略。类型名同理，改由类型色符号承担。
const LOD_TITLE := 0.86
var _lod := 1.0


## 落点分派（Desktop 注入）：`func(key, at_global) -> bool`，true = 已消费 ⇒ 弹回原位。
var drop_sink := Callable()
## 拖出画布时的夹回边界（world 坐标；由 Desktop 注入，见 WORLD_RECT）
var world_rect := Rect2()

var _mat: ShaderMaterial
var _bg: ColorRect
var _title: Label
## 类型符号：常驻，既是标题左侧的小标记，也是缩略档里唯一的图形（见文件头 LOD 说明）
var _glyph: KindGlyph
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
## 聚焦淡化 / 拖动让位（两者共用一条 alpha：`_apply_alpha()` 里合成，见 set_dim / set_ghost）
var _dimmed := false
var _ghost := false
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
	var color := TecTheme.CARD_DASH
	## 枢纽场景用 CSS 的 `3px double`：外 1px 线、1px 空隙、内 1px 线。
	## 不能拿虚线凑 —— 两者语义不同（虚线=未探索，双线=枢纽），在 Web 里也是两套规则。
	var double_line := false
	## 选中环：Web `.node.sel{outline:2px solid #2b2b26; outline-offset:2px}`。
	## CSS 的 outline 画在**边框盒之外**、留 2px 空隙，所以这里用 `rect.grow(4)` 画 2px 实线，
	## 实际占掉 2~4px 那一圈（视觉框离卡片外沿还有 8px 的 PAD，够放）。
	var sel_line := false
	## 点亮态：**2px 实线粗框**。金框 + 金晕在纯白纸上不成立（对白 1.86:1，等于消失），
	## 1-bit 里「更粗的线」就是「更强的强调」—— 粗细是这套语言里唯一的强度轴。
	var thick_line := false

	func _draw_sel() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = TecTheme.NONE
		sb.set_border_width_all(2)
		sb.border_color = TecTheme.INK
		sb.set_corner_radius_all(0)
		## AA **开着**（P4.1）：卡片恢复了 5px 圆角，弧段没有 AA 就是一圈锯齿；
		## 正交直线本来就落在整数像素上，AA 不会把它们抹灰 —— 只有拐角变柔。
		sb.anti_aliasing = true
		draw_style_box(sb, rect.grow(4.0))

	func _ring(r: Rect2, rad: float) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = TecTheme.NONE
		sb.set_border_width_all(1)
		sb.border_color = TecTheme.INK
		sb.set_corner_radius_all(0)
		## AA **开着**（P4.1）：卡片恢复了 5px 圆角，弧段没有 AA 就是一圈锯齿；
		## 正交直线本来就落在整数像素上，AA 不会把它们抹灰 —— 只有拐角变柔。
		sb.anti_aliasing = true
		draw_style_box(sb, r)

	func _draw() -> void:
		if sel_line:
			_draw_sel()
			return
		if thick_line:
			## 1px 环画两遍 + 1px 内缩再画一遍：StyleBoxFlat 的 1px 边框在 1x 屏上
			## 刚好一个物理像素，重复叠加即可得到视觉 2px，不必引入非整数线宽。
			_ring(rect, radius)
			_ring(rect.grow(-1.0), radius)
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


func _ready() -> void:
	if _warn_badge != null:
		_warn_badge.size = Vector2(72.0, 20.0)
	if _badge != null:
		_badge.size = Vector2(22.0, 20.0)
	if _pin_badge != null:
		_pin_badge.size = Vector2(48.0, 20.0)


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
	_mat.set_shader_parameter("radius", float(TecTheme.R_CARD))
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
	(_border as DashBorder).radius = float(TecTheme.R_CARD)
	add_child(_border)

	_title = TecTheme.label("", TecTheme.FS_TITLE, TecTheme.TEXT)
	_title.name = "title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	## 类型符号：常驻。标题左侧的小标记由 `_layout_glyph()` 摆位，颜色是卡上唯一的
	## 类型色载体（`TecTheme.kind_color`）。
	_glyph = KindGlyph.new()
	_glyph.name = "glyph"
	_glyph.kind = kind
	_glyph.col = TecTheme.kind_color(kind)
	_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glyph)

	## 单行：标题恒居卡片垂直中线（副标已删，不再分上下半格）。
	## 水平位置不写死 —— 符号与文字作为一组居中，交给 `_layout_title()` 按实测字宽算。
	_layout_glyph()

	# 角标：字统一 12px 后跟着放大（9px 时「无文本入口」是 45px 宽，12px 要 60px）。
	# 位置仍按 Web 的「右上 / 左上出沿」口径，只把宽度让出来。
	_warn_badge = TecTheme.label("无文本入口", TecTheme.FS_BODY, TecTheme.TEXT)
	_warn_badge.name = "warn"
	_warn_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warn_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_warn_badge.position = Vector2(PAD + w - 64.0, -2.0)
	_warn_badge.size = Vector2(72.0, 20.0)
	_warn_badge.add_theme_stylebox_override("normal", TecTheme.flat(TecTheme.CARD, TecTheme.R_PILL,
		TecTheme.TEXT, 2))
	_warn_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warn_badge.visible = false
	add_child(_warn_badge)

	_badge = TecTheme.label("新", TecTheme.FS_BODY, TecTheme.CARD)
	_badge.name = "unread"
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.position = Vector2(PAD + w - 16.0, -2.0)
	_badge.size = Vector2(22.0, 20.0)
	_badge.add_theme_stylebox_override("normal", TecTheme.flat(TecTheme.LINE, TecTheme.R_PILL,
		TecTheme.LINE, 1))
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.visible = false
	add_child(_badge)

	# 「已固定」药丸：Web 放在**左上角**，与右上角的「新」各自占位、可以同时存在
	_pin_badge = TecTheme.label("已固定", TecTheme.FS_BODY, TecTheme.CARD)
	_pin_badge.name = "pin"
	_pin_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pin_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pin_badge.position = Vector2(PAD - 2.0, -2.0)
	_pin_badge.size = Vector2(48.0, 20.0)
	_pin_badge.add_theme_stylebox_override("normal", TecTheme.flat(TecTheme.LINE, TecTheme.R_PILL,
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
	(_sel as DashBorder).radius = float(TecTheme.R_CARD)
	(_sel as DashBorder).sel_line = true
	add_child(_sel)

	refresh()


func refresh() -> void:
	## 卡面只有名字。类型 → 标题左侧类型色符号；状态 → 边框与填充（见 `_apply_plain_look`）
	_title.text = String(node_data.get("label", card_key))
	_layout_title()            # 文字宽度变了，符号要重贴到首字左边
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
	_badge.visible = _unread and _lod_show_title()
	_warn_badge.visible = _warn and _lod_show_title()
	_pin_badge.visible = _pinned and _lod_show_title()
	## 1-bit 不再有「发光」—— `_glow` 是径向无极渐变，在纯白纸上是整套硬边语言里
	## 唯一一块软调子，留着就破功。点亮的强调改由 `_border.thick_line`（2px 黑粗框）承担。
	if _glow != null:
		_glow.visible = false


## 「无文本入口」谓词每帧在 Desktop 算（is_no_entry），这里只负责显示态回灌
##（refresh → _apply_shell 会整块重刷外观，所以 set_warn 只改自己的标记）
func set_warn(on: bool) -> void:
	if _warn == on:
		return
	_warn = on
	_warn_badge.visible = on and _lod_show_title()


## 文字与角标只在「接近原生格」的倍率出现（0.88x 实测已缺笔、0.78x 完全认不出）
func _lod_show_title() -> bool:
	return _lod >= LOD_TITLE


## 相机倍率回灌（Desktop 在 `_apply_view` 里统一分发）。
## 只切可见性与标题位置，不动卡片尺寸 —— 尺寸一动，布局求解器就会跟着抖。
func set_lod(k: float) -> void:
	var k2 := clampf(k, 0.1, 4.0)
	if absf(k2 - _lod) < 0.001:
		return
	_lod = k2
	if _title == null or _glyph == null:
		return                      # 还没 _build（Desktop 在 setup 之后才灌倍率）
	var text_on := _lod_show_title()
	_title.visible = text_on
	_layout_glyph()
	_badge.visible = _unread and text_on
	_warn_badge.visible = _warn and text_on
	_pin_badge.visible = _pinned and text_on


## 符号两套摆法：文字档 = 紧贴标题首字左侧的 9px 小标记（整组居中、竖向对墨迹中心，
## 见 `_layout_title`）；缩略档 = 铺满卡片居中。
## 文字档：方块上下各留 1~2px 嵌在字面里（9 = 12px 字面的 3/4）。
## 缩略档的半径放大一档（4.5 → 6）：卡片整体被缩了，9px 的符号在 0.62x 下只剩 5.6px。
func _layout_glyph() -> void:
	if _glyph == null:
		return
	_glyph.zoom = _lod
	if _lod_show_title():
		_layout_title()
		return
	_glyph.position = Vector2(PAD, PAD)
	_glyph.size = Vector2(_w, _h)
	_glyph.radius = minf(_w, _h) * 0.34
	_glyph.queue_redraw()


## 文字档摆位：把**符号 + 标题当成一个整体**在卡片里水平居中，符号紧贴首字。
## 上一版是「符号钉死在 PAD+5、标题独立居中」——短标题时符号孤零零挂在左边卡沿上，
## 与文字之间空出一大片，既压边又看不出它跟哪个字是一组。
## 文字宽度按当前字形实测（`get_string_size`），超长时整组吃满可用宽度、交给 ellipsis 截断。
func _layout_title() -> void:
	if _title == null or _glyph == null:
		return
	if not _lod_show_title():
		_title.visible = false
		return
	_title.visible = true
	var pad_x := PAD + 6.0                 # 符号最左不越过卡沿内缩 6px
	var avail := _w - 12.0
	var font := _title.get_theme_font("font")
	var fsize := _title.get_theme_font_size("font_size")
	var text_w := font.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var max_text := maxf(avail - GLYPH_BOX - GLYPH_GAP, 1.0)
	text_w = minf(text_w, max_text)
	var group_w := GLYPH_BOX + GLYPH_GAP + text_w
	var left := pad_x + maxf((avail - group_w) * 0.5, 0.0)
	## 竖向：方块中心 = 卡中线；标题矩形从「卡中线 − TITLE_INK_CY」起排（TOP 对齐），
	## 墨迹中心因此落在卡中线上 —— 两者同一基准，见 TITLE_INK_CY
	var mid_y := PAD + _h * 0.5
	_glyph.position = Vector2(left, mid_y - GLYPH_BOX * 0.5)
	_glyph.size = Vector2(GLYPH_BOX, GLYPH_BOX)
	_glyph.radius = GLYPH_BOX * 0.5
	_glyph.zoom = _lod
	_glyph.queue_redraw()
	## 标题左对齐贴着符号：居中排版会让文字在剩余宽度里再居中一次，符号就又飘走了
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.position = Vector2(left + GLYPH_BOX + GLYPH_GAP, mid_y - TITLE_INK_CY)
	_title.size = Vector2(maxf(pad_x + avail - _title.position.x, 1.0), TITLE_H)


## 类型色跟着**纸面深浅**走：深色反白（已捕获线索 / 拖动目标）上原色对比不足 1.5:1，
## 符号会直接消失，必须换提亮版（`kind_color(kind, true)`）。
func _sync_glyph_color(on_dark: bool) -> void:
	if _glyph == null:
		return
	var c := TecTheme.kind_color(kind, on_dark)
	if _glyph.col != c:
		_glyph.col = c
		_glyph.queue_redraw()


## 普通态。三种「非活跃」外观靠**纸面与边框的组合**区分，卡面上一个字都不写：
##   未探索（从没进去过）= 纸色平面 + 虚线框
##   已折叠（进去过又收起）= 白纸 + 虚线框   ← 白纸是「已知」、虚线是「收起」
##   已探索（展开着）      = 白纸 + 实线框
## 副标存在时「折叠」靠文字就能认；删掉副标之后必须给它自己的组合，否则和「未探索」
## 长得一模一样（旧代码 `flat = _container and (not _explored or _collapsed)`）。
func _apply_plain_look() -> void:
	var flat := _container and not _explored
	## 1-bit：**整卡平涂，只有 1px 黑边**。原先的 hi→mid→lo 三段渐变、上缘奶油白高光、
	## 右下柔光投影，全是「纸面浮雕」的语法 —— 在纯白桌面上它们只会把卡片抹成一团雾，
	## 而不是让卡片浮起来。1-bit 的层次只有两条：**线宽**（1px / 2px / 双线）
	## 与 **线型**（实线 / 虚线）。所以这里把面拉平、把影和高光关掉。
	var face: Color = TecTheme.BG if flat else TecTheme.CARD
	_mat.set_shader_parameter("flat_fill", flat)
	_mat.set_shader_parameter("col_hi", face)
	_mat.set_shader_parameter("col_mid", face)
	_mat.set_shader_parameter("col_lo", face)
	_mat.set_shader_parameter("edge_col", TecTheme.NONE if flat else TecTheme.INK)
	_mat.set_shader_parameter("rim_col", TecTheme.NONE)
	_mat.set_shader_parameter("shade_col", TecTheme.NONE)
	_title.add_theme_color_override("font_color", TecTheme.MUTED if flat else TecTheme.TEXT)
	_sync_glyph_color(false)
	_border.thick_line = false
	_border.double_line = _hub
	_border.visible = flat or _collapsed or _hub
	_border.queue_redraw()
	if _glow != null:
		_glow.visible = false


## Web `.node.ent-clue.got`：深色反白（`linear-gradient(150deg,#38372f,#1f1f19)`）+
## 内嵌阴影 + 顶上 1px 白边。已捕获的线索「翻到背面」，一眼能和没读过的区分开。
func _apply_got_look() -> void:
	_mat.set_shader_parameter("flat_fill", false)
	## 反白面取**纯黑**：`#333`→`#1a1a1a` 的三段渐变在 1-bit 里是三个不同的灰，
	## 等于把「已捕获」画成「一张脏纸」。这里只有黑与白。
	_mat.set_shader_parameter("col_hi", TecTheme.INK)
	_mat.set_shader_parameter("col_mid", TecTheme.INK)
	_mat.set_shader_parameter("col_lo", TecTheme.INK)
	_mat.set_shader_parameter("edge_col", TecTheme.NONE)
	_mat.set_shader_parameter("rim_col", TecTheme.NONE)
	_mat.set_shader_parameter("shade_col", TecTheme.NONE)
	_title.add_theme_color_override("font_color", TecTheme.CARD)
	_sync_glyph_color(true)
	_border.visible = false
	if _glow != null:
		_glow.visible = false


## Web `.node.lit`：金框 `#e3b341` + 暖白底 `#fffbeb` + 双层外发光。
## 发光用贴图光晕近似（CSS 是 `0 0 14px 3px` + `0 0 46px 14px` 两层叠加）。
func _apply_lit_look() -> void:
	## 1-bit 的「点亮」：**白底 + 2px 黑粗框**（而不是金框 + 金晕）。
	## 金色 `#e3b341` 对白只有 1.86:1，换到白纸上连自己的轮廓都画不出来；
	## 而 2px 对 1px 是这套语言里一眼可辨的强度差。卡面仍是白的 —— 强调交给线，不交给色块。
	_mat.set_shader_parameter("flat_fill", false)
	_mat.set_shader_parameter("col_hi", TecTheme.CARD)
	_mat.set_shader_parameter("col_mid", TecTheme.CARD)
	_mat.set_shader_parameter("col_lo", TecTheme.CARD)
	_mat.set_shader_parameter("edge_col", TecTheme.NONE)
	_mat.set_shader_parameter("rim_col", TecTheme.NONE)
	_mat.set_shader_parameter("shade_col", TecTheme.NONE)
	_title.add_theme_color_override("font_color", TecTheme.TEXT)
	_sync_glyph_color(false)
	_border.thick_line = true
	_border.double_line = false
	_border.visible = true
	_border.queue_redraw()
	if _glow != null:
		_glow.visible = false


## Web `.node.over{background:linear-gradient(150deg,#38372f,#1f1f19);color:var(--card);transform:scale(1.06)}`
## —— 拖动的**目标节点**整块反白。缩放 1.06 需要 pivot，会牵动连线端点，P0 先只做反白。
func _apply_over_look() -> void:
	_mat.set_shader_parameter("flat_fill", false)
	_mat.set_shader_parameter("col_hi", TecTheme.INK)
	_mat.set_shader_parameter("col_mid", TecTheme.INK)
	_mat.set_shader_parameter("col_lo", TecTheme.INK)
	_mat.set_shader_parameter("edge_col", TecTheme.NONE)
	_mat.set_shader_parameter("rim_col", TecTheme.NONE)
	_mat.set_shader_parameter("shade_col", TecTheme.NONE)
	_title.add_theme_color_override("font_color", TecTheme.CARD)
	_sync_glyph_color(true)
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
			# 按下即定住：杀掉弹回弹簧，并通知 Desktop 杀掉重排飞行的落位补间——
			# 卡停在指针下面，双击才不会因为卡「飞走了」而落空，拖动也不会跟动画打架
			if _spring != null and _spring.is_valid():
				_spring.kill()
			_spring = null
			move_to_front()
			pressed.emit(card_key)
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


## 兜底收尾：松手事件没送到时由桌面调用（见 Desktop._abort_card_drag）。
## 不跑落点判定，把卡按当前坐标直接落地，保证「拖动会话」一定能关掉。
func cancel_drag() -> void:
	if not _pressed and not _dragging:
		return
	_pressed = false
	_dragging = false
	var p := _clamp_pos(position)
	position = p
	_home = p
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	drag_finished.emit(card_key, p, false)


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
	_dimmed = on
	_apply_alpha()


## 拖动期间原件让位给镜像（Web 拖动时 `visibility:hidden` + #drag-layer 克隆）。
## ⚠ 不能用 `visible = false`：Godot 的 GUI 命中判定会跳过「树里不可见」的控件，
## 拖动第一帧之后鼠标移动就不再投递给这张卡 ⇒ 跟手断流、松手也收不到
## （现场症状：节点拖一下就僵住，之后按哪都是整块画布在平移）。
## 这里改成全透明 —— 事件照收，画面交给桌面上的镜像卡。
func set_ghost(on: bool) -> void:
	# 入场 pop 还在跑时它会把 modulate.a 逐渐补到 1，与「让位」打架 ⇒ 拖起瞬间直接掐掉
	if on and _pop != null and _pop.is_valid():
		_pop.kill()
		_pop = null
		scale = Vector2.ONE
	_ghost = on
	_apply_alpha()


func _apply_alpha() -> void:
	var target := Color(1, 1, 1, 0.0 if _ghost else (0.32 if _dimmed else 1.0))
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
