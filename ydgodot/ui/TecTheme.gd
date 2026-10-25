class_name TecTheme
extends RefCounted
## 主题与配色（对齐 Web 版 `src/css/02-base.css` 的 :root 变量）
##
## 只放「常量 + StyleBox 工厂」，不持有节点。界面脚本统一从这里取色，
## 免得同一种白在十个文件里各写一遍、又各自跑偏。

## ══════════════════════════════════════════════════════════════════════════════
## 调色板 —— **色值只准写在这一段里**（其余 .gd 一律引常量名）
##
## 单色改版 P0 的产物。分四层，自上而下：
##   1. 墨与纸：画面 95% 的面积是这两层，也是唯一允许大面积的色；
##   2. 面：卡面 / 按钮 / 深色反白面 / 回忆态的做旧纸；
##   3. 线：描边 / 分隔 / 投影，全是墨的透明度变体（`edge()` / `shadow()` /
##      `scrim()` / `rim()` 四个派生函数，免得每种透明度都占一个常量名）；
##   4. 专色：**只准涂在 ≤9px 的符号与 2px 的框线上**（红线见
##      `docs/MONO_REDESIGN_PLAN.md` §4.3）。
##
## 这么分层是为了「调色只改这一段」：改主题色只动 INK / BG / CARD 两三行，
## 全站跟着走。`tools/mono_audit.py --check` 是这条约束的执行者 —— 谁在别处
## 硬写 `Color(...)`，它就报错。
## ══════════════════════════════════════════════════════════════════════════════

## ── 1. 墨与纸 ─────────────────────────────────────────────────────────────────
## 墨：一切文字、描边、深色底的基色。**只有它和 BG 允许大面积出现。**
## 单色版取纯黑（P1 起生效）：1-bit 骨架里没有「暖黑」的位置。
const INK := Color("000000")
## 兼容旧名 —— `LINE`（线）与 `TEXT`（字）在 Web 版确实是两个语义，但在单色方案里
## 是同一支墨。留成别名而不是各自定义一份，是为了「改一处、全动」。
const LINE := INK
const TEXT := INK
## 次要文字。**任何要读的字都用它**：对白 6.65:1、对外壳 #DDDDDD 5.08:1，
## 12px 也过 4.5:1 —— 这是它比 #666666 深一档的原因（#666 对外壳只有 4.23）。
const INK_MUTED := Color("000000")
const MUTED := INK_MUTED
## 只用于装饰（水印、占位符、禁用态）：对白 3.23:1、对外壳 2.38:1，**正文用它会读不清**。
const INK_FAINT := Color("8c8c8c")
const FAINT := INK_FAINT

## 外壳底板：图标栏、窗体之外那一圈桌面（`desk_bg`）。P2 起是**灰青**，
## 介于纸面与画布之间 —— 外壳读作「框」，又不像纯白那样抢窗体的亮度。
## `BG_HI` / `BG_LO` 是旧「竖向渐变」的上下端，桌底改平涂后**已无引用**，
## 名字留着给将来的「升起面 / 凹陷面」用。
const BG := Color("DCE2DD")
const BG_HI := Color("DCE2DD")
const BG_LO := Color("DCE2DD")
## 纸面（仪器灰青冷白 #EDF1EE）。**画布本身已不再用它**（改成下面的 DESK_GRAY 平涂），
## 留作「需要一张纸」的局部：卡片内页、摘录底、回忆叙事框。
const PAPER := Color("EDF1EE")

## 画布桌面（`stage_bg`）：**中性灰平涂，不铺网点**。
## 为什么平涂：桌面是屏上最大的一块面积，任何纹理都会被读成噪点。
## 试过五档点阵（2px/25% → 4px/6.25% → 6px/2.8% → 灰底+低对比点 → 平涂）——
## 拉大点距只是把「砂纸」换成「网点纸」，6px 那档反而更脏（零星黑点像脏纸）；
## 真正有效的是**降对比**，或者干脆不要。参考图看着「均匀的灰」，物理上也是网点，
## 但两色对比只有 6%，肉眼读作平涂 —— 这层窗户纸不值得在 1x 屏上复刻。
##
## P2 纸色改版：`#EFEFEF → #C4CCC6`。桌面加深后与纸面 `#EDF1EE` 的明度差
## 从 1.09:1 拉到约 1.43:1，窗/桌层次更清楚，同时全屏不再有纯白大面积。
const DESK_GRAY := Color("C4CCC6")

## ── 2. 面 ─────────────────────────────────────────────────────────────────────
## 卡面（纸面 #EDF1EE）。**它是「比桌布亮」的那一层**，窗压桌的关系靠它撑住 ——
## 对桌布 #C4CCC6 约 1.43:1，这是「窗口浮起来」的全部依据。
const CARD := Color("EDF1EE")
## 浅面两档：悬停（更亮）/ 按下（更暗）。
const FACE_HI := Color("EDF1EE")
const FACE_LO := Color("EDF1EE")
## 升起的浅面：证件底板、按钮浮起的底。
const FACE_RISE := Color("EDF1EE")

## 深色反白面（已捕获线索 / 拖动目标 / 回忆卡标题条）。
const FACE_DARK_HI := Color("333333")
const FACE_DARK_LO := Color("1a1a1a")
const FACE_DARK_HOVER := Color("3d3d3d")
## 深色面上的字与图标（冷白）。压在 `#1A1A1A` 上是 15.2:1。
const TEXT_ON_DARK := Color("f0f0f0")

## ── 3. 线 / 分隔 / 投影 ────────────────────────────────────────────────────────
## 通用发丝边。**P4.2 起取纯黑**：参考图（System 6 / Mac OS 8）是 1-bit 系统，
## 屏幕上根本没有 30% 的灰线 —— 所有方框都是 1px 纯黑。
## 上一版这里是 `Color(0,0,0,0.30)`（柔和浮雕期的遗产）：那条线在白底上读作浅灰，
## 于是头像框、输入框、案件行、卡片底盘整片「看着像没做单色改版」，
## 案件地图里的 34px 小方块与状态牌最明显。层次仍靠**线宽**分：
## 窗口 2px / 其余 1px，不是靠把 1px 稀释成灰。
const EDGE := INK
## 真正的「不可点 / 未满足条件」才降浓度：锁定行、禁用输入框、分隔细线。
## 它有明确语义（这条东西此刻无效），不是「随便淡一点好看」。
const EDGE_SOFT := Color(0, 0, 0, 0.18)
## 分隔线：中性灰实色（比发丝边实、比墨线轻）。
const DIVIDER := Color("000000")
const LINE2 := DIVIDER
## 「试过但没成」的连线（EdgeLayer 第四态）。
const EDGE_TRIED := Color("000000")
## 可连未试的连线（30% 黑）：条件/选项边已存在但还没走过。
const EDGE_UNTRIED := Color(0, 0, 0, 0.3)
## 上缘高光（纯白 95%）—— 柔和浮雕感的来源。
const BEVEL_HI := Color(1, 1, 1, 0.95)
const BEVEL_LO := Color(0, 0, 0, 0.32)
## 窗标题栏顶上那 1px 更亮的高光（比 BEVEL_HI 再亮一档）。
const BEVEL_TOP := Color(1, 1, 1, 0.90)
## 投影基色。窗影 / 图标影 / 卡影 / 按钮影都从这里取 alpha —— 色相一致才不会「各影各的」。
const SHADOW_BASE := Color(0, 0, 0)
## 卡面虚线框（未展开）。
const CARD_DASH := Color(0, 0, 0, 0.55)
## 全屏遮罩的深色（结局）。比 `scrim()` 更沉，因为下面还要压一层正文。
const DIM_HEAVY := Color(0, 0, 0, 0.88)
## 纯白的 RGB 基色（`rim(a)` 用）。
const RIM_BASE := Color(1, 1, 1)
## 透明。stylebox 里表示「无填充 / 无边框」，比 `Color(0,0,0,0)` 表意清楚得多。
const NONE := Color(0, 0, 0, 0)

## ── 4. 专色 ───────────────────────────────────────────────────────────────────
## **只准涂在 ≤9px 符号与 2px 框线上**；遮罩、按钮、正文、任何大面积底一律禁止。
## 理由：单色骨架靠「黑白灰已经把状态说完了」立住，专色一旦铺开就变回彩色界面。
## 每一色都必须有「不靠颜色也能认」的冗余（形状 / 线型 / 明度），见 §4.3 六条红线。
## ── 类型专色（P4 起**停用**，见下方 `kind_color()`）──────────────────────────
## 这四组色值只留作历史参考，不再有调用方返回它们。
## **颜色只占 8~10px 的图形，卡面 / 边框 / 角标一律不染。** 那里已经被状态占满了：
## 实线=已探索、虚线=未探索、双线=枢纽、金框=点亮、深色反白=已捕获、墨环=选中。
## 再往卡面叠一层，玩家就分不清「颜色不同是因为类型不同，还是因为状态不同」。
##
## 三个色的明度都压在 L*≈40–43、对卡面 ≈5:1 —— **没有谁更「跳」**；色相避开红/绿
## 这对色盲最易混的组合（青 / 褐 / 紫 对红绿色盲仍可分）。
##
## ⚠ 金色 `#e3b341` 已被「点亮 = 可当工具」占用，类型色**不许再用黄**（地点若是金色，
## 玩家会以为它能用）。红色留给错误态。线索与时刻不染（前者有「已捕获」的深色反白，
## 后者已有 ◆ + 双线框），都用 INK。
const SPOT_LOC := Color("4f6e74")     # 地点 · 石板青
const SPOT_ITEM := Color("8a5a3b")    # 物品 · 赭褐
const SPOT_CHAR := Color("7c4a63")    # 人物 · 绛紫
## 兼容旧名（`kind_color()` 与若干窗口已引用）。
const KIND_LOC := SPOT_LOC
const KIND_ITEM := SPOT_ITEM
const KIND_CHAR := SPOT_CHAR
## 深色面（回忆卡的黑标题条）上的提亮版：原色压在 #2b2b26 上对比不足 1.5:1，等于看不见。
const SPOT_LOC_ON_DARK := Color("93b6bb")
const SPOT_ITEM_ON_DARK := Color("c79a70")
const SPOT_CHAR_ON_DARK := Color("c894aa")
const KIND_LOC_DARK := SPOT_LOC_ON_DARK
const KIND_ITEM_DARK := SPOT_ITEM_ON_DARK
const KIND_CHAR_DARK := SPOT_CHAR_ON_DARK

## ── 点亮专色（金 → 单色版待换琥珀 `#A86A12`，见 P3）────────────────────────
## 「点亮 = 这个节点能当工具用」。四个色是同一个暖色系的四档：外框 / 底面三层。
const SPOT_LIT := Color("e3b341")
const SPOT_LIT_HI := Color("fffdf6")
const SPOT_LIT_MID := Color("fffbeb")
const SPOT_LIT_LO := Color("fcf0cd")
## 点亮态的外发光（贴图光晕里也用这个色相）。
const SPOT_LIT_GLOW := Color(1.0, 0.769, 0.259, 0.16)
## 光晕贴图的底色。**比 SPOT_LIT 亮一档**（`#ffd36e` vs `#e3b341`）：
## 光晕是往外散开、要跟纸面混色的，用边框那支深金会糊成一团脏土黄。
const SPOT_LIT_HALO := Color(1.0, 0.827, 0.431)
## ── 错误 / 警示朱 ─────────────────────────────────────────────────────────────
## 试错涂抹、核准印章。**只在这两处**，不要拿它做「危险按钮」之类的通用语义。
const SPOT_DANGER := Color("c0392b")

## ── 强调青（三层色彩体系 · 界面色）───────────────────────────────────────
## 语义 = 「系统正在注意这里」。白名单五个面：选中环 / 悬停键线 / 激活窗标题栏条纹 /
## TEC 品牌符号 / 进度与等待指示；白名单之外一律用墨，一屏强调色 ≤5%。
## 规则全文见 `docs/MONO_REDESIGN_PLAN.md` §4.3（2026-10-24 三层体系）。
const SPOT_ACCENT := Color("2f5d55")

## ── 材质色（三层体系 · 世界的样貌）──────────────────────────────────────
## 回答「这是什么」，不回答「该做什么」：只出现在物体及其影响范围，
## 不涂铬件、不做通用语义、低饱和印刷感。随内容承载逐个接入。
const MAT_FLAME := Color("c1622f")    # 火焰（刻意避开警示朱，待燃烧交互承载）
const MAT_EMBER := Color("8a4a2a")    # 余烬 / 焦痕
const MAT_DUST := Color("c9c4b8")     # 灰尘 / 陈旧纸面
const MAT_ASH := Color("7a7a74")      # 灰烬
const MAT_PLANT := Color("5a7a5c")    # 植物 / 生长

## ── 回忆态（P4 起**不再做旧纸**）──────────────────────────────────────────────
## 原来是四档暖米黄（`#e2deca → #ccc7ad`），代表「这张卡来自过去」。
## 在灰青桌面上它成了**整屏唯一一片暖色**，一眼就把 1-bit 破掉 —— 而且「做旧」本身就是
## 拟物（模仿纸张老化）。现在回忆卡与普通窗一样是纸面，区别只靠**框更粗**：
## 3px（回忆）/ 2px（普通窗）/ 1px（节点卡）。
## 四个名字保留：`MemCard` 仍按它们的语义取色，将来想恢复米黄只改这一处。
const MEM_HI := Color("EDF1EE")
const MEM_MID := Color("EDF1EE")
const MEM_LO := Color("EDF1EE")
const MEM_SAY_BG := Color("EDF1EE")

## 圆角**分级**（P4.1 修订）——不是一刀切全直角。
## 参考图（System 6 / Mac OS 8）里圆角是**按零件分的**：
##   窗口外框 = 方角（System 6 的窗就是四个直角）
##   按钮 / 输入框 / 列表行 = 小圆角（3~6px，一眼能看出「可以按」）
##   图标底板 = 大一点的圆角（8~10px）
##   进度条 / 画布卡片 = 方角（它们不是「可按的东西」）
## 上一版把全部圆角压成 0，结果按钮和画布卡片长得一样，整屏读作「一片硬纸板」。
const R_WIN := 0        # 窗口外框：方角
## 画布卡片：**方角**。它是一张「纸片」，不是控件 —— 圆角会让它读成按钮。
## 参考图里也没有「圆角卡片」这种东西：卡片是新加的，就按纸的语法来。
const R_CARD := 0
const R_SM := 5         # 小控件：列表行 / 输入框 / 卡片内小牌
const R_BTN := 6        # 按钮：比 R_SM 再圆一点，按压力度靠填充区分
## 角标（`新` / `未读` / `已固定`）：小药丸。参考图里状态牌就是圆头的。
const R_PILL := 999

## ── 字号只有三档，且必须是 12 的整数倍 ──────────────────────────────────────
## 唯一字体 `font.ttf`（VonwaonBitmap 12px）的 `unitsPerEm = 1200` ⇒ 原生格就是
## **12px**（100 units/px），只有 12 的整数倍能整像素落笔。
## 13 / 18 这类非整数倍会走重采样：**笔画从 1px 摊成 1~2px 的灰边，同时变粗和变糊**
## （实测见 docs/font_13_vs_12.png —— 同一句话 12px 锐利、13px 整行发胖）。
## 所以：
##   12 —— 一切界面文字（按钮 / 标签 / 角标 / 卡片标题 / 窗口标题 / 连续正文）
##   24 / 48 —— 仅装饰性大字（首字母、结局标题）
## **不要再新增非 12 倍数的字号**，正文也不例外：可读性靠行高与字色（TEXT / MUTED）
## 拉开层级，不靠 +1px 字号。
const FS_BODY := 12
## 连续正文沿用同一格。旧值 13 是 P3 时期从 Web 的 13px 正文直接抄的，但 Web 那边
## 是浏览器亚像素渲染、13px 不伤字形；Godot 关着抗锯齿，13px 就是硬糊。
## 保留这个名字只为语义区分（正文 / 标题），值必须等于 FS_BODY。
const FS_TITLE := 12
const FS_DISPLAY := 24
const FS_INITIAL := 48
const NARR_LINE_SPACING := 6

## ── 透明度派生 ───────────────────────────────────────────────────────────────
## 「同一种墨的 10% / 15% / 24% / 30% / 42% / 45%」如果各占一个常量名，调色板会膨胀成
## 几十行、而且看名字猜不出浓度。改成四个函数：**基色只有一个，浓度写在调用处**。
## 调用方 `TecTheme.edge(0.42)` 一眼就知道「这是 42% 的边」。

## 边：纯黑的 a 浓度。卡片 1px 描边、窗体发丝边都从这里取。
static func edge(a: float) -> Color:
	return Color(0, 0, 0, a)


## 影：投影基色的 a 浓度（窗影 0.28 / 图标影 0.24 / 卡影 0.30 / 拖动 0.45）。
static func shadow(a: float) -> Color:
	return Color(SHADOW_BASE, a)


## 上缘高光：纯白的 a 浓度（深色面上的 18% 细边、标题栏渐隐都是它）。
static func rim(a: float) -> Color:
	return Color(RIM_BASE, a)


## 遮罩 / 内阴影：墨的 a 浓度（对话框压暗 45%、拖动幽灵线 85%、回忆卡内阴影 34%）。
static func scrim(a: float) -> Color:
	return Color(0.169, 0.169, 0.149, a)


## 纯白 / 纯黑乘子。**不是调色板的一部分** —— 只给 `modulate`（改不透明度）和
## 「深色面上的 1px 白边」这种与主题色无关的场合用。
static func white(a: float) -> Color:
	return Color(1, 1, 1, a)


static func black(a: float) -> Color:
	return Color(0, 0, 0, a)


static var _font: FontFile = null


## 唯一字体：凤凰点阵体。**关抗锯齿 / 关 hinting / 关次像素** —— 像素字体的命门。
## 类型 → 符号色。
## **P4 起类型不再用颜色区分**：五种类型已经有五种形状（实心方 / 空心方 / 实心圆 /
## 三角 / 菱形），颜色是第二遍同义编码 —— 而 1-bit 里放不下第二遍。青 / 褐 / 紫
## 三个专色铺在纯白桌面上，是整屏唯一「有彩色」的东西，恰好把「全部单色」这句话破掉。
## 现在亮面一律 INK、暗面一律 TEXT_ON_DARK；函数与调用点保持不变（API 不变，
## 将来想恢复专色只改这一处）。
static func kind_color(_kind: String, on_dark: bool = false) -> Color:
	return TEXT_ON_DARK if on_dark else INK


## 字体：**缝合像素字体 12px 比例版（简体）**，SIL OFL 1.1，可商用。
## 换掉凤凰点阵体（CC0）的原因：凤凰的中文是**宋体点阵**（横细竖粗、带衬线），
## 参考图的 Chicago 是**无衬线**，两者放在同一屏里「一个字有收笔、一个字没有」，
## 这就是「字体不统一」的来源。缝合像素是黑体点阵，中英文同源、粗细一致。
## 许可证全文见 `assets/raw/font-fusion-OFL.txt`（保留字体名 Fusion Pixel）。
const FONT_PATH := "res://assets/raw/font-fusion.woff2"

static func font() -> FontFile:
	if _font == null:
		_font = load(FONT_PATH) as FontFile
		if _font != null:
			_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			_font.hinting = TextServer.HINTING_NONE
			_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			_font.multichannel_signed_distance_field = false
			## 固定 1x 栅格：实测过 `oversampling = 0`（跟随画布自动栅格），
			## 1.43x 窗口下整图只有 0.33% 像素不同、边缘梯度反而略低（6.14 vs 6.17），
			## 即「自动」既不更清晰也没变锐，不如保持这个已验证的口径。
			_font.oversampling = 1.0
	return _font


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = FS_BODY
	_style_scrollbars(t)
	return t


## 滚动条：**默认主题是整套拟物里最后一处没换的零件** —— 圆角灰槽 + 渐变滑块 +
## 浅灰箭头，在纯白窗体里像贴了一条系统控件。1-bit 版就是：白槽 + 1px 黑框、黑实心滑块，
## 宽度压到 8px（默认 12px 在窄窗里会挤掉正文一行）。
static func _style_scrollbars(t: Theme) -> void:
	var trough := flat(CARD, 0, INK, 1)
	var grab := StyleBoxFlat.new()
	grab.bg_color = INK
	grab.set_corner_radius_all(0)
	grab.anti_aliasing = false
	grab.content_margin_left = 3
	grab.content_margin_right = 3
	grab.content_margin_top = 3
	grab.content_margin_bottom = 3
	for bar in ["VScrollBar", "HScrollBar"]:
		for n in ["scroll", "scroll_focus"]:
			t.set_stylebox(n, bar, trough)
		for n in ["grabber", "grabber_highlight", "grabber_pressed"]:
			t.set_stylebox(n, bar, grab)
	t.set_constant("minimum_grab_thickness", "VScrollBar", 12)


static func flat(bg: Color, radius: int, border_col: Color = EDGE, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_w)
	sb.border_color = border_col
	## 抗锯齿**开回来**（P4.1 修订）。关掉是为了「要么黑要么白」，但 1px 正交线
	## 本来就在整数像素上，AA 不会把它抹灰；而**圆角的弧段**没有 AA 就是一圈锯齿，
	## 加上满屏纯黑线之后整屏读作「钢丝」——这就是「太锐利」的直接来源。
	sb.anti_aliasing = true
	return sb


static func window_style() -> StyleBoxFlat:
	## **没有投影**。14px 模糊阴影是「窗体浮在纸上」的语法；参考图里的窗口是
	## 一层 2px 黑框直接压在桌面上的**平面**，层次来自框的粗细，不来自影子。
	## 去掉之后窗口与桌面靠 2px 边 + 纸面区分，1x 下边界反而更硬更清楚。
	return flat(CARD, R_WIN)


## ── 按钮语法（P4.2 统一）────────────────────────────────────────────────────
## 参考图（System 6 Control Panel）里的键只有两种，**都不是黑底**：
##   普通键（Set）= 白底 + **1px 纯黑键线** + 小圆角 + 黑字；
##   默认键（Find）= 同一条键线，里面再套一条**内键线**（外框 + 3px 留白 + 内框）。
## 之前用的是 `EDGE`（30% 黑）：那条线在白底上读作浅灰，整排按钮看着「没改」——
## 案件地图里 34px 的小方块与状态牌尤其明显。**键线的浓度是这套界面的身份，不能稀释。**
##
## 三态只用 1-bit 允许的两条轴（见 MONO_REDESIGN_PLAN §4.3）：
##   常态 1px → 悬停 **2px**（线宽）→ 按下**反白**（黑底白字）。
## 不引入灰阶填充：悬停变灰等于把 V3 删掉的中间灰又请回来。
static func button_style(hover: bool = false, pressed: bool = false) -> StyleBoxFlat:
	## C-B：悬停键线叠一层强调青；按下仍是纯黑反白（错误/选中语义不混）。
	var border := INK
	if hover and not pressed:
		border = SPOT_ACCENT
	elif hover and pressed:
		border = INK
	var sb := flat(INK if pressed else CARD, R_BTN, border, 2 if hover else 1)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


## 给控件套一道**内键线**（1px 圆角框，离边缘 `inset` px）——「默认按钮」的双键线就是它。
## 为什么不用“更粗的外框”代替：参考图的双线是**两条等粗的细线 + 中间留白**，
## 加粗成 3px 会读成「一个粗框」，而不是「一颗被点名的键」。
## 用子 Panel 而不是 StyleBoxFlat：一个 StyleBox 只能画一道 border。
static func keyline_ring(host: Control, inset: float = 3.0, radius: int = -1) -> Panel:
	var p := Panel.new()
	p.name = "keyline"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel",
		flat(NONE, radius if radius >= 0 else int(R_BTN) - 2, INK, 1))
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.offset_left = inset
	p.offset_top = inset
	p.offset_right = -inset
	p.offset_bottom = -inset
	host.add_child(p)
	return p


static func label(text: String, size: int = FS_BODY, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## D1 · 小节标题（h4 级）：**黑条白字**，方角、满宽、12px。
## 四级层级里它排在窗标题（字距 + 横纹）与正文之间；只在同一扇窗确实分成
## 「小节」时使用（例如音乐窗的曲目 / 播放），不要当成第二行窗口标题。
## 注释 / 占位继续走 `INK_FAINT`，正文走 `TEXT` —— 层级靠反白与明度，不靠字号。
static func section_bar(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "section_bar"
	p.custom_minimum_size = Vector2(0, 24)
	var sb := flat(INK, 0, INK, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(text, FS_BODY, TEXT_ON_DARK)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


static func narrative_label(text: String = "", color: Color = TEXT) -> TypewriterLabel:
	var l := TypewriterLabel.new()
	l.configure(text, FS_BODY, color)
	return l


## 品牌字：Web 的 `.brand` 带 `letter-spacing:2px`。Label 没有字距接口，
## 用 FontVariation 的 spacing_glyph 补上，才追得平那 7 个字符的宽度。
static var _brand_font: FontVariation = null


static func brand_font() -> FontVariation:
	if _brand_font == null:
		_brand_font = FontVariation.new()
		_brand_font.base_font = font()
		_brand_font.spacing_glyph = 2
	return _brand_font


static func brand_label(text: String, size: int = FS_TITLE, color: Color = CARD) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", brand_font())
	return l


## 页眉按钮（黑底）：透明填充 + 白色 1px 描边；hover 反色成白底。
## Web 里是 `header button` 那组规则；默认按钮 stylebox 是浅底带投影，放黑条上会糊成一团。
static func header_button(text: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", FS_BODY)
	var normal := flat(CARD if primary else NONE, R_BTN, CARD)
	var hover := flat(NONE if primary else CARD, R_BTN, CARD)
	# 上下 7.5 → 最小高度 = 字高 12 + 15 = 27，正好是 Web `header button` 的高度。
	# 用边距把最小高度钉住，而不是靠 `size = 27` 硬压：Control 的 set_size 会被
	# 最小尺寸反顶（见 Desktop._sync_header_sizes 的注释），压不下去。
	for sb in [normal, hover]:
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 7.5
		sb.content_margin_bottom = 7.5
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", normal)
	b.add_theme_color_override("font_color", LINE if primary else CARD)
	b.add_theme_color_override("font_hover_color", CARD if primary else LINE)
	b.add_theme_color_override("font_pressed_color", CARD if primary else LINE)
	# 开关（toggle_mode）常驻「按下」态：它取的是 pressed/hover_pressed 那一组颜色，
	# 不补这两条，黑底上的开关文字会变成墨色 = 看不见。
	b.add_theme_color_override("font_hover_pressed_color", LINE if primary else CARD)
	b.add_theme_color_override("font_focus_color", LINE if primary else CARD)
	return b


static func button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", FS_BODY)
	## 字色只跟着填充走：白底黑字 / 按下反白时白字。悬停**不改字色**——
	## 悬停只加粗键线，键线粗了字不动，才是「指针指着它」而不是「它被按下了」。
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", CARD)
	b.add_theme_color_override("font_hover_pressed_color", CARD)
	b.add_theme_color_override("font_focus_color", TEXT)
	b.add_theme_color_override("font_disabled_color", INK_FAINT)
	b.add_theme_stylebox_override("normal", button_style(false, false))
	b.add_theme_stylebox_override("hover", button_style(true, false))
	b.add_theme_stylebox_override("pressed", button_style(false, true))
	b.add_theme_stylebox_override("hover_pressed", button_style(true, true))
	b.add_theme_stylebox_override("disabled", flat(CARD, R_BTN, INK_FAINT, 1))
	b.focus_mode = Control.FOCUS_NONE
	return b


static func primary_button(text: String) -> Button:
	## 默认/主按钮 = 同一条键线上再套一道**内键线**（参考图的 “Find”）。
	## 不再填黑：黑底是「深色面」的语法（标题栏 / 已捕获态），不属于按钮。
	var b := button(text)
	keyline_ring(b)
	return b
