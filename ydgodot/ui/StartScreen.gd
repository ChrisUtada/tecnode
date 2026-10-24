class_name StartScreen
extends Control
## 第 0 幕：开始界面。
## 全屏黑底 + 红色恶魔 + 开始 / 继续 / 设置 / 退出。
## 这是全游戏唯一允许跳出桌面隐喻的画面；红色只属于恶魔这个内容形象。

signal start_requested(overwrite: bool)
signal continue_requested
signal quit_requested

const DEMON_ART := "res://assets/raw/executor-avatar.png"
const EMOTE_ART := "res://assets/raw/emote-heartbroken.png"
const DEMON_PX := 72.0

var has_save := false
var _continue_btn: Button
var _demon: TextureRect
var _emote: PanelContainer
var _emote_tween: Tween
var _dialog_layer: Control
var _dialog_title: Label
var _dialog_body: Label
var _dialog_actions: HBoxContainer


func setup(p_has_save: bool) -> void:
	has_save = p_has_save
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func set_has_save(on: bool) -> void:
	has_save = on
	if _continue_btn != null:
		_continue_btn.disabled = not on


func _build() -> void:
	var bg := ColorRect.new()
	bg.name = "start_bg"
	bg.color = TecTheme.DESK_GRAY
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.name = "start_center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var card := PanelContainer.new()
	card.name = "start_card"
	card.custom_minimum_size = Vector2(360, 0)
	card.add_theme_stylebox_override("panel",
		TecTheme.flat(TecTheme.CARD, TecTheme.R_WIN, TecTheme.INK, 1))
	center.add_child(card)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_bottom", 20)
	card.add_child(pad)

	var col := VBoxContainer.new()
	col.name = "start_col"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 8)
	pad.add_child(col)

	var title := TecTheme.label("异动区域已被锁定", TecTheme.FS_DISPLAY, TecTheme.TEXT)
	title.name = "start_title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title)

	var version := TecTheme.label("demo v1.0", TecTheme.FS_BODY, TecTheme.MUTED)
	version.name = "start_version"
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(version)

	var holder := Control.new()
	holder.name = "demon_holder"
	holder.custom_minimum_size = Vector2(DEMON_PX, DEMON_PX)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(holder)

	var demon_frame := Panel.new()
	demon_frame.name = "demon_frame"
	demon_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	demon_frame.add_theme_stylebox_override("panel",
		TecTheme.flat(TecTheme.BG, TecTheme.R_WIN, TecTheme.EDGE, 1))
	demon_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(demon_frame)

	_demon = TextureRect.new()
	_demon.name = "demon"
	_demon.texture = load(DEMON_ART)
	_demon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_demon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_demon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_demon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_demon.mouse_filter = Control.MOUSE_FILTER_STOP
	_demon.tooltip_text = "点一下"
	_demon.gui_input.connect(_on_demon_input)
	holder.add_child(_demon)

	_emote = PanelContainer.new()
	_emote.name = "emote"
	_emote.position = Vector2(DEMON_PX * 0.5 - 14.0, -22.0)
	var emote_style := TecTheme.flat(TecTheme.BG, TecTheme.R_WIN, TecTheme.INK, 1)
	emote_style.content_margin_left = 4
	emote_style.content_margin_right = 4
	emote_style.content_margin_top = 4
	emote_style.content_margin_bottom = 4
	_emote.add_theme_stylebox_override("panel", emote_style)
	_emote.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emote.visible = false
	holder.add_child(_emote)
	var emote_img := TextureRect.new()
	emote_img.name = "emote_art"
	emote_img.texture = load(EMOTE_ART)
	emote_img.custom_minimum_size = Vector2(16, 16)
	emote_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emote_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emote_img.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	emote_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emote.add_child(emote_img)

	var hint := TecTheme.label("点击恶魔", TecTheme.FS_BODY, TecTheme.INK_FAINT)
	hint.name = "start_hint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(hint)

	var buttons := VBoxContainer.new()
	buttons.name = "start_buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 6)
	col.add_child(buttons)

	var start_btn := _menu_button("开始", true)
	start_btn.name = "btn_start"
	start_btn.pressed.connect(_on_start_pressed)
	buttons.add_child(start_btn)

	_continue_btn = _menu_button("继续")
	_continue_btn.name = "btn_continue"
	_continue_btn.disabled = not has_save
	_continue_btn.pressed.connect(func(): continue_requested.emit())
	buttons.add_child(_continue_btn)

	var settings_btn := _menu_button("设置")
	settings_btn.name = "btn_settings"
	settings_btn.pressed.connect(_show_settings)
	buttons.add_child(settings_btn)

	var quit_btn := _menu_button("退出")
	quit_btn.name = "btn_quit"
	quit_btn.pressed.connect(func(): quit_requested.emit())
	buttons.add_child(quit_btn)

	_build_dialog()


func _menu_button(text: String, primary: bool = false) -> Button:
	var b := TecTheme.primary_button(text) if primary else TecTheme.button(text)
	b.custom_minimum_size = Vector2(200, 32)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b


func _build_dialog() -> void:
	_dialog_layer = Control.new()
	_dialog_layer.name = "dialog_layer"
	_dialog_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_dialog_layer.z_index = 10
	_dialog_layer.visible = false
	add_child(_dialog_layer)

	var dim := ColorRect.new()
	dim.color = TecTheme.black(0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dialog_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "dialog_panel"
	panel.custom_minimum_size = Vector2(360, 0)
	panel.add_theme_stylebox_override("panel",
		TecTheme.flat(TecTheme.CARD, TecTheme.R_SM, TecTheme.INK, 1))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	_dialog_title = TecTheme.label("", TecTheme.FS_TITLE, TecTheme.TEXT)
	_dialog_title.name = "dialog_title"
	col.add_child(_dialog_title)

	_dialog_body = TecTheme.label("", TecTheme.FS_BODY, TecTheme.MUTED)
	_dialog_body.name = "dialog_body"
	_dialog_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_body.custom_minimum_size = Vector2(320, 0)
	col.add_child(_dialog_body)

	_dialog_actions = HBoxContainer.new()
	_dialog_actions.name = "dialog_actions"
	_dialog_actions.alignment = BoxContainer.ALIGNMENT_END
	_dialog_actions.add_theme_constant_override("separation", 8)
	col.add_child(_dialog_actions)


func _on_start_pressed() -> void:
	if has_save:
		_open_dialog("开始新调查？", "当前案件的调查进度与存档将被清除，且无法撤销。",
			[["取消", false, _close_dialog],
			 ["覆盖并开始", true, func(): _close_dialog(); start_requested.emit(true)]])
	else:
		start_requested.emit(false)


func _show_settings() -> void:
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	_open_dialog("设置", "当前显示：%s。切换后界面会自动重排。" % ("全屏" if fullscreen else "窗口"),
		[["切换全屏", false, _toggle_fullscreen],
		 ["返回", true, _close_dialog]])


func _toggle_fullscreen() -> void:
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen
		else DisplayServer.WINDOW_MODE_FULLSCREEN)
	_show_settings()


func _open_dialog(title: String, body: String, actions: Array) -> void:
	_dialog_title.text = title
	_dialog_body.text = body
	for c in _dialog_actions.get_children():
		c.queue_free()
	for item in actions:
		var btn := TecTheme.button(String(item[0]))
		btn.name = "dialog_btn_" + String(item[0])
		if bool(item[1]):
			btn.add_theme_stylebox_override("normal",
				TecTheme.flat(TecTheme.CARD, TecTheme.R_BTN, TecTheme.INK, 2))
		btn.pressed.connect(item[2])
		_dialog_actions.add_child(btn)
	_dialog_layer.visible = true


func _close_dialog() -> void:
	_dialog_layer.visible = false


func _on_demon_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_shake_demon()
		_show_emote()


func _shake_demon() -> void:
	var base := _demon.position
	var tw := create_tween()
	tw.tween_property(_demon, "position:x", base.x + 3.0, 0.035)
	tw.tween_property(_demon, "position:x", base.x - 3.0, 0.07)
	tw.tween_property(_demon, "position:x", base.x + 2.0, 0.06)
	tw.tween_property(_demon, "position:x", base.x, 0.04)


func _show_emote() -> void:
	if _emote == null:
		return
	if _emote_tween != null and _emote_tween.is_valid():
		_emote_tween.kill()
	_emote.visible = true
	_emote.modulate.a = 1.0
	_emote_tween = create_tween()
	_emote_tween.tween_interval(0.55)
	_emote_tween.tween_property(_emote, "modulate:a", 0.0, 0.25)
	_emote_tween.finished.connect(func():
		if _emote != null:
			_emote.visible = false
			_emote.modulate.a = 1.0)
