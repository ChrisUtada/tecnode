class_name CertWin
extends SysWindow
## 第 5 幕：调查员证填写。
## 只保留四项：姓名 / 编号 / 日期 / 照片。没有测验、没有 sense。
## 编号与日期自动生成；照片用三张档案照代替旧版的头像选择页。

signal completed(card: Dictionary)

const PHOTOS := [
	{"id": "CHARS_EXEC", "label": "执行者", "path": "res://assets/raw/executor-avatar.png"},
	{"id": "CHARS_TEC", "label": "TEC", "path": "res://assets/raw/tec-avatar.png"},
	{"id": "CHARS_ANON", "label": "档案照", "path": "res://assets/raw/cert-avatar.png"},
]
const COL_W := 270.0

var store_path := Investigator.PATH
var card: Dictionary = {}

var _name := ""
var _cert_id := ""
var _date := ""
var _avatar_id := "CHARS_EXEC"
var _name_edit: LineEdit = null
var _error: Label = null
var _preview_name: Label = null
var _preview_id: Label = null
var _preview_date: Label = null
var _photo_holder: Control = null
var _photo_buttons: Dictionary = {}


func setup_cert(p_name: String = "") -> void:
	_name = p_name.strip_edges()
	_cert_id = Investigator.gen_id()
	_date = Time.get_date_string_from_system()
	setup("调查员证 · 签发", 640, 438)
	## W27：签发期可以没有 ×（流程强制），但标题栏拖动必须保留。
	set_drag_enabled(true)
	var close := get_node_or_null("bar/close") as Control
	if close != null:
		close.visible = false
	_build_content()


func place_center(vw: float, vh: float) -> void:
	var x := clampf((vw - size.x) * 0.5, 8.0, maxf(8.0, vw - size.x - 8.0))
	var y := clampf(54.0, 8.0, maxf(8.0, vh - size.y - 8.0))
	position = Vector2(x, y)


func _build_content() -> void:
	content.add_theme_constant_override("separation", 9)
	var lead := TecTheme.label("推演成立。补齐姓名、编号、日期、照片后签发。",
		TecTheme.FS_BODY, TecTheme.MUTED)
	lead.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(lead)

	var cols := HBoxContainer.new()
	cols.name = "cert_cols"
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cols)

	var form := VBoxContainer.new()
	form.name = "cert_form"
	form.custom_minimum_size = Vector2(COL_W, 0)
	form.add_theme_constant_override("separation", 6)
	form.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cols.add_child(form)

	_field_label(form, "姓名")
	_name_edit = LineEdit.new()
	_name_edit.name = "cert_name"
	_name_edit.placeholder_text = "请输入姓名"
	_name_edit.max_length = 12
	_name_edit.text = _name
	_name_edit.add_theme_font_override("font", TecTheme.font())
	_name_edit.add_theme_font_size_override("font_size", TecTheme.FS_TITLE)
	_name_edit.add_theme_color_override("font_color", TecTheme.TEXT)
	_name_edit.add_theme_color_override("font_placeholder_color", TecTheme.FAINT)
	_name_edit.add_theme_stylebox_override("normal", _input_style(false))
	_name_edit.add_theme_stylebox_override("focus", _input_style(true))
	_name_edit.custom_minimum_size = Vector2(0, 34)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_submitted.connect(func(_v: String): _confirm())
	form.add_child(_name_edit)

	_field_label(form, "编号（自动生成）")
	var id_label := TecTheme.label(_cert_id, TecTheme.FS_TITLE, TecTheme.TEXT)
	id_label.name = "cert_id_value"
	form.add_child(id_label)

	_field_label(form, "签发日期")
	var date_label := TecTheme.label(_date, TecTheme.FS_TITLE, TecTheme.TEXT)
	date_label.name = "cert_date_value"
	form.add_child(date_label)

	_field_label(form, "照片")
	var photos := HBoxContainer.new()
	photos.name = "cert_photos"
	photos.add_theme_constant_override("separation", 8)
	form.add_child(photos)
	for p in PHOTOS:
		photos.add_child(_photo_button(String(p["id"]), String(p["label"]), String(p["path"])))

	_error = TecTheme.label("", TecTheme.FS_BODY, TecTheme.TEXT)
	_error.name = "cert_error"
	_error.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_error)

	var confirm := TecTheme.primary_button("[ 签发调查员证 ]")
	confirm.name = "cert_confirm"
	confirm.custom_minimum_size = Vector2(0, 32)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.pressed.connect(_confirm)
	form.add_child(confirm)

	var preview := _build_preview()
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(preview)

	_name_edit.grab_focus.call_deferred()
	_refresh_photos()
	_refresh_preview()


func _field_label(parent: VBoxContainer, text: String) -> void:
	var l := TecTheme.label(text, TecTheme.FS_BODY, TecTheme.MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)


func _input_style(focused: bool) -> StyleBoxFlat:
	var sb := TecTheme.flat(TecTheme.BG, TecTheme.R_BTN,
		TecTheme.LINE if focused else TecTheme.EDGE_SOFT)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _photo_button(id: String, label: String, path: String) -> Button:
	var b := TecTheme.button("")
	b.name = "cert_photo_" + id
	b.custom_minimum_size = Vector2(76, 82)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(_pick_photo.bind(id))
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 4
	col.offset_right = -4
	col.offset_top = 4
	col.offset_bottom = -4
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var img := TextureRect.new()
	img.texture = load(path)
	img.custom_minimum_size = Vector2(52, 52)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	img.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(img)
	var l := TecTheme.label(label, TecTheme.FS_BODY, TecTheme.MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(l)
	_photo_buttons[id] = b
	return b


func _build_preview() -> Control:
	var panel := PanelContainer.new()
	panel.name = "cert_preview"
	panel.custom_minimum_size = Vector2(250, 0)
	panel.add_theme_stylebox_override("panel",
		TecTheme.flat(TecTheme.FACE_RISE, TecTheme.R_SM, TecTheme.EDGE))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)

	var head := ColorRect.new()
	head.color = TecTheme.LINE
	head.custom_minimum_size = Vector2(0, 32)
	col.add_child(head)
	var head_label := TecTheme.label("T.E.C-OS 调查员证", TecTheme.FS_TITLE, TecTheme.TEXT_ON_DARK)
	head_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	head_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(head_label)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	col.add_child(pad)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	pad.add_child(body)

	var photo_center := CenterContainer.new()
	body.add_child(photo_center)
	var photo_frame := PanelContainer.new()
	photo_frame.custom_minimum_size = Vector2(104, 104)
	photo_frame.add_theme_stylebox_override("panel",
		TecTheme.flat(TecTheme.BG, 0, TecTheme.EDGE))
	photo_center.add_child(photo_frame)
	var photo_pad := MarginContainer.new()
	photo_pad.add_theme_constant_override("margin_left", 5)
	photo_pad.add_theme_constant_override("margin_right", 5)
	photo_pad.add_theme_constant_override("margin_top", 5)
	photo_pad.add_theme_constant_override("margin_bottom", 5)
	photo_frame.add_child(photo_pad)
	_photo_holder = Control.new()
	_photo_holder.custom_minimum_size = Vector2(94, 94)
	photo_pad.add_child(_photo_holder)

	_preview_name = TecTheme.label("（未填写）", TecTheme.FS_DISPLAY, TecTheme.TEXT)
	_preview_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_name.clip_text = true
	body.add_child(_preview_name)
	_preview_id = TecTheme.label(_cert_id, TecTheme.FS_BODY, TecTheme.MUTED)
	_preview_id.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_preview_id)
	_preview_date = TecTheme.label("签发日期：" + _date, TecTheme.FS_BODY, TecTheme.MUTED)
	_preview_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_preview_date)
	var level := TecTheme.label("等级：初级调查员", TecTheme.FS_BODY, TecTheme.MUTED)
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(level)
	var stamp := TecTheme.label("T.E.C 核准", TecTheme.FS_BODY, TecTheme.SPOT_DANGER)
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	body.add_child(stamp)
	return panel


func _on_name_changed(v: String) -> void:
	_name = v
	if _error != null:
		_error.text = ""
	_refresh_preview()


func _pick_photo(id: String) -> void:
	_avatar_id = id
	_refresh_photos()
	_refresh_preview()


func _refresh_photos() -> void:
	for id in _photo_buttons.keys():
		var b: Button = _photo_buttons[id]
		var selected := String(id) == _avatar_id
		var border := TecTheme.LINE if selected else TecTheme.EDGE
		var width := 2 if selected else 1
		b.add_theme_stylebox_override("normal",
			TecTheme.flat(TecTheme.CARD, TecTheme.R_SM, border, width))
		b.add_theme_stylebox_override("hover",
			TecTheme.flat(TecTheme.FACE_HI, TecTheme.R_SM, TecTheme.LINE, 2))
		b.add_theme_stylebox_override("pressed",
			TecTheme.flat(TecTheme.FACE_LO, TecTheme.R_SM, TecTheme.LINE, 2))


func _refresh_preview() -> void:
	if _preview_name != null:
		var shown := _name.strip_edges()
		_preview_name.text = shown if shown != "" else "（未填写）"
	if _photo_holder == null:
		return
	for c in _photo_holder.get_children():
		c.queue_free()
	var tex := TextureRect.new()
	tex.name = "cert_photo_preview"
	var path := ""
	for p in PHOTOS:
		if String(p["id"]) == _avatar_id:
			path = String(p["path"])
			break
	tex.texture = load(path) if path != "" else load("res://assets/raw/cert-avatar.png")
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_photo_holder.add_child(tex)


func _confirm() -> void:
	if _name_edit != null:
		_name = _name_edit.text.strip_edges()
	if _name == "":
		if _error != null:
			_error.text = "姓名不能为空"
		_shake()
		return
	card = {
		"name": _name,
		"id": _cert_id,
		"sense": "vision",
		"date": _date,
		"avatarId": _avatar_id,
	}
	if not Investigator.save_to(card, store_path):
		if _error != null:
			_error.text = "证件写入失败，请重试"
		return
	completed.emit(card.duplicate(true))
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "modulate:a", 0.0, 0.22)
	t.chain().tween_callback(queue_free)


func _shake() -> void:
	var base := position
	var t := create_tween()
	t.tween_property(self, "position:x", base.x + 6.0, 0.04)
	t.tween_property(self, "position:x", base.x - 6.0, 0.08)
	t.tween_property(self, "position:x", base.x + 4.0, 0.07)
	t.tween_property(self, "position:x", base.x, 0.04)


func dbg_set_name(v: String) -> void:
	_name = v
	if _name_edit != null:
		_name_edit.text = v
	_refresh_preview()


func dbg_pick(id: String) -> void:
	_pick_photo(id)


func dbg_confirm() -> void:
	_confirm()


func dbg_card() -> Dictionary:
	return card.duplicate(true)


func dbg_cert_id() -> String:
	return _cert_id


func dbg_avatar() -> String:
	return _avatar_id
