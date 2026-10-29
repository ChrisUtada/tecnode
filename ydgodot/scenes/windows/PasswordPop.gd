class_name PasswordPop
extends SysWindow
## 密码弹窗（对齐 Web 的 `.pw-pop`：LOCK 窗 + 四位数字输入）
## 输错只抖一下、窗不关；输对由调用方收窗并执行 onSuccess。

signal submitted(text: String)

var _input: LineEdit
var _hint: Label


func setup_password(item_label: String, hint: String) -> void:
	offset_shadow = true
	setup("密码锁 · " + item_label, 200, 74, TecTheme.R_SM)

	_hint = get_node_or_null("body/content/pw_hint") as Label
	if _hint != null:
		_hint.text = hint if hint != "" else "输入密码（四位数字）"
		_hint.add_theme_font_override("font", TecTheme.font())
		_hint.add_theme_font_size_override("font_size", TecTheme.FS_BODY)
		_hint.add_theme_color_override("font_color", TecTheme.MUTED)
		_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_input = get_node_or_null("body/content/pw_row/pw_in") as LineEdit
	if _input != null:
		_input.max_length = 4
		_input.placeholder_text = "····"
		_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_input.custom_minimum_size = Vector2(96, 28)
		_input.add_theme_font_override("font", TecTheme.font())
		_input.add_theme_font_size_override("font_size", TecTheme.FS_TITLE)
		## 密码数字必须是墨色：LineEdit 默认字色来自内置主题，在灰窗上会发白看不清。
		_input.add_theme_color_override("font_color", TecTheme.TEXT)
		_input.add_theme_color_override("font_uneditable_color", TecTheme.TEXT)
		_input.add_theme_color_override("font_placeholder_color", TecTheme.MUTED)
		_input.add_theme_color_override("caret_color", TecTheme.INK)
		_input.add_theme_color_override("selection_color", Color(TecTheme.INK, 0.16))
		_input.add_theme_stylebox_override("normal",
			TecTheme.flat(TecTheme.CARD, TecTheme.R_BTN, TecTheme.EDGE_SOFT, 1))
		_input.add_theme_stylebox_override("focus",
			TecTheme.flat(TecTheme.CARD, TecTheme.R_BTN, TecTheme.LINE, 1))
		_input.text_submitted.connect(func(_t: String): _submit())
		_input.grab_focus.call_deferred()   # setup 时还没进树

	var ok := get_node_or_null("body/content/pw_row/pw_ok") as Button
	if ok != null:
		ok.text = "确定"
		TecTheme.style_button(ok)
		ok.pressed.connect(_submit)


func _submit() -> void:
	submitted.emit(_input.text if _input != null else "")


## 密码错：只抖一下（对应 CSS 的 .shake），不清空输入
func reject_wrong() -> void:
	var base := position
	var t := create_tween()
	t.tween_property(self, "position", base + Vector2(-6, 0), 0.04)
	t.tween_property(self, "position", base + Vector2(6, 0), 0.06)
	t.tween_property(self, "position", base + Vector2(-4, 0), 0.05)
	t.tween_property(self, "position", base, 0.05)
	if _input != null:
		_input.grab_focus.call_deferred()   # setup 时还没进树


func input_text() -> String:
	return _input.text if _input != null else ""


func type_into(text: String) -> void:
	if _input != null:
		_input.text = text
