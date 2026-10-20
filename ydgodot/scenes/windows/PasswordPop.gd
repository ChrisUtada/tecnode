class_name PasswordPop
extends SysWindow
## 密码弹窗（对齐 Web 的 `.pw-pop`：LOCK 窗 + 四位数字输入）
## 输错只抖一下、窗不关；输对由调用方收窗并执行 onSuccess。

signal submitted(text: String)

var _input: LineEdit
var _hint: Label


func setup_password(item_label: String, hint: String) -> void:
	setup("LOCK // " + item_label, 200, 74, TecTheme.R_SM)
	_hint = TecTheme.label(hint if hint != "" else "输入密码（四位数字）", 11, TecTheme.MUTED)
	content.add_child(_hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)

	_input = LineEdit.new()
	_input.name = "pw_in"
	_input.max_length = 4
	_input.placeholder_text = "····"
	_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_input.custom_minimum_size = Vector2(96, 28)
	_input.add_theme_font_override("font", TecTheme.font())
	_input.add_theme_font_size_override("font_size", 13)
	_input.add_theme_stylebox_override("normal", TecTheme.flat(TecTheme.CARD, 6, TecTheme.EDGE, 1))
	_input.add_theme_stylebox_override("focus", TecTheme.flat(TecTheme.CARD, 6, TecTheme.LINE, 1))
	_input.text_submitted.connect(func(_t: String): _submit())
	row.add_child(_input)

	var ok := TecTheme.button("确定")
	ok.name = "pw_ok"
	ok.pressed.connect(_submit)
	row.add_child(ok)

	_input.grab_focus.call_deferred()   # setup 时还没进树


func _submit() -> void:
	submitted.emit(_input.text)


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
