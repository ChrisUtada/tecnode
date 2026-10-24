class_name PhotoWin
extends SysWindow
## 证件照片选择：签发后从调查员证复核窗打开，用来更换证件上的头像。
## 和正常 app 窗一样：可拖、可关，不改窗口形态。

signal picked(avatar_id: String)

const PHOTOS := [
	{"id": "CHARS_EXEC", "label": "执行者", "path": "res://assets/raw/executor-avatar.png"},
	{"id": "CHARS_TEC", "label": "TEC", "path": "res://assets/raw/tec-avatar.png"},
	{"id": "CHARS_ANON", "label": "档案照", "path": "res://assets/raw/cert-avatar.png"},
]

var current := "CHARS_EXEC"
var _buttons: Dictionary = {}


func setup_photo(p_current: String) -> void:
	current = p_current if p_current != "" else "CHARS_EXEC"
	setup("更换头像", 330, 176)
	var lead := TecTheme.label("选择要印在调查员证上的头像照片。", TecTheme.FS_BODY, TecTheme.MUTED)
	lead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(lead)
	var row := HBoxContainer.new()
	row.name = "photo_row"
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	for p in PHOTOS:
		row.add_child(_photo_button(String(p["id"]), String(p["label"]), String(p["path"])))
	_refresh()


func place_center(vw: float, vh: float) -> void:
	var x := clampf((vw - size.x) * 0.5, 8.0, maxf(8.0, vw - size.x - 8.0))
	var y := clampf((vh - size.y) * 0.5, 8.0, maxf(8.0, vh - size.y - 8.0))
	position = Vector2(x, y)


func _photo_button(id: String, label: String, path: String) -> Button:
	var b := TecTheme.button("")
	b.name = "photo_" + id
	b.custom_minimum_size = Vector2(76, 82)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(_pick.bind(id))
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
	_buttons[id] = b
	return b


func _refresh() -> void:
	for id in _buttons.keys():
		var b: Button = _buttons[id]
		var selected := String(id) == current
		b.add_theme_stylebox_override("normal",
			TecTheme.flat(TecTheme.CARD, TecTheme.R_SM,
				TecTheme.LINE if selected else TecTheme.EDGE, 2 if selected else 1))
		b.add_theme_stylebox_override("hover",
			TecTheme.flat(TecTheme.FACE_HI, TecTheme.R_SM, TecTheme.LINE, 2))
		b.add_theme_stylebox_override("pressed",
			TecTheme.flat(TecTheme.FACE_LO, TecTheme.R_SM, TecTheme.LINE, 2))


func _pick(id: String) -> void:
	current = id
	picked.emit(id)
	queue_free()


func dbg_pick(id: String) -> void:
	_pick(id)
