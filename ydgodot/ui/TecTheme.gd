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
