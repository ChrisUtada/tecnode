class_name TecTheme
extends RefCounted
## 主题与配色（对齐 Web 版 `src/css/02-base.css` 的 :root 变量）
##
## 只放「常量 + StyleBox 工厂」，不持有节点。界面脚本统一从这里取色，
## 免得同一种米白在十个文件里各写一遍、又各自跑偏。

const BG := Color("e9e5d6")
const CARD := Color("f5f2e8")
const FACE_HI := Color("fbf8ee")
const FACE_LO := Color("eee9d7")
const LINE := Color("2b2b26")
const LINE2 := Color("c0bcaa")
const TEXT := Color("2b2b26")
const MUTED := Color("5c584a")
const FAINT := Color("8a8672")
const EDGE := Color(0.290, 0.271, 0.204, 0.30)
const EDGE_SOFT := Color(0.290, 0.271, 0.204, 0.18)
const BEVEL_HI := Color(1.0, 0.988, 0.945, 0.95)
const BEVEL_LO := Color(0.337, 0.314, 0.235, 0.32)

const R_WIN := 13
const R_SM := 11
const R_BTN := 8

const FS_BODY := 12
const FS_TITLE := 13
const FS_SMALL := 10

static var _font: FontFile = null


## 唯一字体：凤凰点阵体。**关抗锯齿 / 关 hinting / 关次像素** —— 像素字体的命门。
static func font() -> FontFile:
	if _font == null:
		_font = load("res://assets/raw/font.ttf") as FontFile
		if _font != null:
			_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			_font.hinting = TextServer.HINTING_NONE
			_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			_font.multichannel_signed_distance_field = false
			_font.oversampling = 1.0
	return _font


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = FS_BODY
	return t


static func flat(bg: Color, radius: int, border_col: Color = EDGE, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_w)
	sb.border_color = border_col
	sb.anti_aliasing = true
	return sb


static func window_style() -> StyleBoxFlat:
	var sb := flat(CARD, R_WIN)
	sb.shadow_color = Color(0.306, 0.282, 0.212, 0.28)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(6, 8)
	return sb


static func button_style(hover: bool = false, pressed: bool = false) -> StyleBoxFlat:
	var sb := flat(LINE if hover else FACE_HI, R_BTN)
	if hover:
		sb.border_color = LINE
	elif pressed:
		sb.bg_color = FACE_LO
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	if not pressed and not hover:
		sb.shadow_color = BEVEL_LO
		sb.shadow_size = 4
		sb.shadow_offset = Vector2(2, 3)
	return sb


static func label(text: String, size: int = FS_BODY, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
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


static func brand_label(text: String, size: int = 14, color: Color = CARD) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", brand_font())
	return l


## 页眉按钮（黑底）：透明填充 + 奶油色 1px 描边；hover 反色成奶油底。
## Web 里是 `header button` 那组规则；默认按钮 stylebox 是浅底带投影，放黑条上会糊成一团。
static func header_button(text: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", FS_BODY)
	var normal := flat(CARD if primary else Color(0, 0, 0, 0), R_BTN, CARD)
	var hover := flat(Color(0, 0, 0, 0) if primary else CARD, R_BTN, CARD)
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
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", CARD)
	b.add_theme_color_override("font_pressed_color", TEXT)
	b.add_theme_stylebox_override("normal", button_style(false, false))
	b.add_theme_stylebox_override("hover", button_style(true, false))
	b.add_theme_stylebox_override("pressed", button_style(false, true))
	b.focus_mode = Control.FOCUS_NONE
	return b


static func primary_button(text: String) -> Button:
	var b := button(text)
	b.add_theme_color_override("font_color", CARD)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", CARD)
	b.add_theme_stylebox_override("normal", flat(LINE, R_BTN, LINE))
	b.add_theme_stylebox_override("hover", flat(CARD, R_BTN, LINE))
	b.add_theme_stylebox_override("pressed", flat(FACE_LO, R_BTN, LINE))
	return b
