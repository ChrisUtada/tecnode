class_name ConfirmWin
extends Control
## 轻量确认浮层：不可逆操作先问一句，视觉沿用 1-bit 纸面窗口。

signal confirmed
signal cancelled

const WIDTH := 380.0

var _panel: PanelContainer
var _title: Label
var _body: Label
var _ok: Button
var _cancel: Button


func setup(p_title: String, p_body: String, ok_text: String = "确认",
		cancel_text: String = "取消") -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build(p_title, p_body, ok_text, cancel_text)


func _build(p_title: String, p_body: String, ok_text: String, cancel_text: String) -> void:
	var dim := ColorRect.new()
	dim.name = "confirm_dim"
	dim.color = TecTheme.scrim(0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.name = "confirm_center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "confirm_panel"
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	_panel.add_theme_stylebox_override("panel", TecTheme.window_style())
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	_title = TecTheme.label(p_title, TecTheme.FS_TITLE, TecTheme.TEXT)
	_title.name = "confirm_title"
	col.add_child(_title)

	_body = TecTheme.label(p_body, TecTheme.FS_BODY, TecTheme.MUTED)
	_body.name = "confirm_body"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(WIDTH - 32.0, 0)
	col.add_child(_body)

	var actions := HBoxContainer.new()
	actions.name = "confirm_actions"
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	col.add_child(actions)

	_cancel = TecTheme.button(cancel_text)
	_cancel.name = "confirm_cancel"
	_cancel.pressed.connect(_on_cancel)
	actions.add_child(_cancel)

	_ok = TecTheme.primary_button(ok_text)
	_ok.name = "confirm_ok"
	_ok.pressed.connect(_on_ok)
	actions.add_child(_ok)


func _on_ok() -> void:
	confirmed.emit()
	queue_free()


func _on_cancel() -> void:
	cancelled.emit()
	queue_free()


func dbg_confirm() -> void:
	_on_ok()


func dbg_cancel() -> void:
	_on_cancel()
