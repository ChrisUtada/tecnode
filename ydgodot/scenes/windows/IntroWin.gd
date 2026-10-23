class_name IntroWin
extends Control

signal finished(card: Dictionary)

const WIDTH := 420.0
const TOP := 90.0
const AVATAR_ART := {
	"CHARS_EXEC": "res://assets/raw/executor-avatar.png",
	"CHARS_TEC": "res://assets/raw/tec-avatar.png",
}
const AvatarFrameScript = preload("res://ui/AvatarFrame.gd")

var store_path := Investigator.PATH
var card: Dictionary = {}

var _step: Variant = "name"
var _name := ""
var _answers: Array = []
var _avatar_id := Investigator.AVATAR_DEFAULT_ID
var _pool: Array = []
var _names: Dictionary = {}
var _locked := 0
var _panel: PanelContainer
var _panel_shadow: ColorRect
var _box: VBoxContainer
var _name_edit: LineEdit = null


func setup(p_pool: Array = [], p_names: Dictionary = {}, p_locked: int = 0) -> void:
	_pool = p_pool.duplicate() if not p_pool.is_empty() else Investigator.AVATAR_INITIAL.duplicate()
	_names = p_names.duplicate()
	_locked = p_locked
	_build()
	_render()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.name = "dim"
	dim.color = TecTheme.scrim(0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel_shadow = ColorRect.new()
	_panel_shadow.name = "panel_shadow"
	_panel_shadow.color = TecTheme.shadow(1.0)
	_panel_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel_shadow)

	_panel = PanelContainer.new()
	_panel.name = "panel"
	_panel.add_theme_stylebox_override("panel", TecTheme.window_style())
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	_panel.resized.connect(_sync_panel_shadow)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	_box = VBoxContainer.new()
	_box.name = "content"
	_box.add_theme_constant_override("separation", 8)
	margin.add_child(_box)


func _render() -> void:
	_clear()
	_name_edit = null
	match _step:
		"name":
			_render_name()
		"avatar":
			_render_avatar()
		"card":
			_render_card()
		"done":
			pass
		_:
			_render_quiz(int(_step))
	_fit()


func _clear() -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()


func _fit() -> void:
	_panel.reset_size()
	## 按当前视口居中，而不是按 1280 设计稿：960 宽时弹窗会偏右、1920 时偏左。
	## `size.x` 在 NOTIFICATION_RESIZED 里已是新宽度；未入树时才回落到视口 / 设计稿。
	var vw := size.x
	if vw <= 0.0 and is_inside_tree():
		vw = get_viewport_rect().size.x
	if vw <= 0.0:
		vw = 1280.0
	_panel.position = Vector2((vw - _panel.size.x) * 0.5, TOP)
	_panel.pivot_offset = _panel.size * 0.5
	_sync_panel_shadow()


## 全屏遮罩跟随视口缩放：窗口从 960 拖到 1920 时，面板始终停在正中。
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _panel != null:
		_fit()


## 面板的最终尺寸要等子容器布局完才定；只靠 `_fit()` 会留下 3px 的旧影。
func _sync_panel_shadow() -> void:
	if _panel == null or _panel_shadow == null:
		return
	_panel_shadow.position = _panel.position + SysWindow.OFFSET_SHADOW
	_panel_shadow.size = _panel.size


func _title(text: String) -> void:
	var l := TecTheme.label(text, TecTheme.FS_BODY, TecTheme.MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(l)
	var rule := ColorRect.new()
	rule.color = TecTheme.EDGE_SOFT
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(rule)


func _paragraph(text: String, color: Color = TecTheme.TEXT) -> Label:
	var l := TecTheme.label(text, TecTheme.FS_TITLE, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(WIDTH - 36.0, 0)
	_box.add_child(l)
	return l


func _primary(text: String) -> Button:
	var b := TecTheme.primary_button(text)
	b.custom_minimum_size = Vector2(0, 32)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(b)
	return b


func _render_name() -> void:
	_title("调查员适性测试")
	_paragraph("在接入异动区域之前，T.E.C-OS 需要登记你的信息，并完成一次简短的适性测试。")
	var edit := LineEdit.new()
	edit.name = "name_edit"
	edit.placeholder_text = "请输入姓名"
	edit.max_length = 12
	edit.text = _name
	edit.add_theme_font_override("font", TecTheme.font())
	edit.add_theme_font_size_override("font_size", TecTheme.FS_TITLE)
	edit.add_theme_color_override("font_color", TecTheme.TEXT)
	edit.add_theme_color_override("font_placeholder_color", TecTheme.FAINT)
	edit.add_theme_stylebox_override("normal", _input_style(false))
	edit.add_theme_stylebox_override("focus", _input_style(true))
	edit.custom_minimum_size = Vector2(0, 36)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_changed.connect(func(v: String): _name = v)
	edit.text_submitted.connect(func(_v: String): _begin())
	_box.add_child(edit)
	_name_edit = edit
	var btn := _primary("[ 开始测试 ]")
	btn.pressed.connect(_begin)
	edit.grab_focus.call_deferred()


func _input_style(focused: bool) -> StyleBoxFlat:
	var sb := TecTheme.flat(TecTheme.BG, TecTheme.R_BTN, TecTheme.LINE if focused else TecTheme.EDGE_SOFT)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb


func _begin() -> void:
	if _step != "name":
		return
	if _name_edit != null:
		_name = _name_edit.text
	_name = _name.strip_edges()
	if _name == "":
		_shake()
		return
	_step = 0
	_render()


func _shake() -> void:
	var x := _panel.position.x
	var t := create_tween()
	t.tween_property(_panel, "position:x", x + 7.0, 0.04)
	t.tween_property(_panel, "position:x", x - 7.0, 0.08)
	t.tween_property(_panel, "position:x", x + 5.0, 0.08)
	t.tween_property(_panel, "position:x", x, 0.04)


func _render_quiz(index: int) -> void:
	_title("调查员适性测试")
	var q: Dictionary = Investigator.QUIZ[index]
	var prog := TecTheme.label("第 %d / %d 问" % [index + 1, Investigator.QUIZ.size()],
		TecTheme.FS_BODY, TecTheme.MUTED)
	prog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(prog)
	var qt := TecTheme.label(String(q["q"]), TecTheme.FS_TITLE, TecTheme.TEXT)
	qt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	qt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qt.custom_minimum_size = Vector2(WIDTH - 36.0, 0)
	_box.add_child(qt)
	var opts: Array = q["opts"]
	for i in opts.size():
		var b := TecTheme.button(String((opts[i] as Array)[1]))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(WIDTH - 36.0, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_answer.bind(i))
		_box.add_child(b)


func _answer(index: int) -> void:
	if typeof(_step) != TYPE_INT:
		return
	var qi := int(_step)
	var q: Dictionary = Investigator.QUIZ[qi]
	var opts: Array = q["opts"]
	if index < 0 or index >= opts.size():
		return
	_answers.append(String((opts[index] as Array)[0]))
	if qi < Investigator.QUIZ.size() - 1:
		_step = qi + 1
		_render()
		return
	card = Investigator.make_card(_name, _answers, _avatar_id)
	_step = "avatar"
	_render()


func _render_avatar() -> void:
	_title("选择头像")
	_paragraph("挑一张头像印在证件上。每结识一位新人物，就会多出一张可选的头像。", TecTheme.MUTED)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(grid)
	for id in _pool:
		grid.add_child(_avatar_button(String(id)))
	for i in _locked:
		grid.add_child(_locked_button())
	var count := TecTheme.label("已解锁 %d / %d" % [_pool.size(), _pool.size() + _locked],
		TecTheme.FS_BODY, TecTheme.MUTED)
	_box.add_child(count)
	var btn := _primary("[ 用这张 ]")
	btn.pressed.connect(_confirm_pick)


func _avatar_button(id: String) -> Button:
	var selected := id == _avatar_id
	var b := TecTheme.button("")
	b.custom_minimum_size = Vector2(0, 92)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var border := TecTheme.LINE if selected else TecTheme.EDGE
	var width := 2 if selected else 1
	b.add_theme_stylebox_override("normal", TecTheme.flat(TecTheme.CARD, TecTheme.R_SM, border, width))
	b.add_theme_stylebox_override("hover", TecTheme.flat(TecTheme.FACE_HI, TecTheme.R_SM, TecTheme.LINE, 2))
	b.add_theme_stylebox_override("pressed", TecTheme.flat(TecTheme.FACE_LO, TecTheme.R_SM, TecTheme.LINE, 2))
	b.pressed.connect(_pick.bind(id))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 4
	box.offset_right = -4
	box.offset_top = 6
	box.offset_bottom = -4
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var face := _avatar_face(id, 48)
	face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(face)
	var nm := TecTheme.label(String(_names.get(id, id)), TecTheme.FS_BODY, TecTheme.MUTED)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.custom_minimum_size = Vector2(0, 14)
	box.add_child(nm)
	return b


func _locked_button() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(0, 92)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", TecTheme.flat(TecTheme.NONE, TecTheme.R_SM, TecTheme.EDGE))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(box)
	var mark := TecTheme.label("?", TecTheme.FS_DISPLAY, TecTheme.FAINT)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(mark)
	var nm := TecTheme.label("未解锁", TecTheme.FS_BODY, TecTheme.MUTED)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(nm)
	return p


func _avatar_face(id: String, px: float) -> Control:
	var frame := AvatarFrameScript.new()
	frame.setup(String(AVATAR_ART.get(id, "")), px, _initial_of(id))
	return frame


func _initial_of(id: String) -> String:
	var name := String(_names.get(id, id))
	return name.substr(0, 1) if name != "" else "?"


func _pick(id: String) -> void:
	if _step != "avatar":
		return
	_avatar_id = id
	if not card.is_empty():
		card["avatarId"] = id
	_render()


func _confirm_pick() -> void:
	if _step != "avatar":
		return
	if not card.is_empty():
		card["avatarId"] = _avatar_id
	_step = "card"
	_render()


func _back_to_avatar() -> void:
	if _step != "card":
		return
	_step = "avatar"
	_render()


func _render_card() -> void:
	_title("调查员证")
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(build_cert(card))
	_box.add_child(center)
	var btn := _primary("[ 确认领证 ]")
	btn.pressed.connect(_confirm_card)
	var back := TecTheme.button("[ 换一张头像 ]")
	back.add_theme_font_size_override("font_size", TecTheme.FS_BODY)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_back_to_avatar)
	_box.add_child(back)


func _confirm_card() -> void:
	if _step != "card" or card.is_empty():
		return
	card["avatarId"] = _avatar_id
	if not Investigator.save_to(card, store_path):
		push_warning("调查员证写入失败：" + store_path)
	_step = "done"
	finished.emit(card.duplicate(true))
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_panel, "scale", Vector2(0.1, 0.1), 0.35)
	t.tween_property(self, "modulate:a", 0.0, 0.35)
	t.chain().tween_callback(queue_free)


static func build_cert(c: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.name = "cert"
	panel.custom_minimum_size = Vector2(320, 0)
	panel.add_theme_stylebox_override("panel", TecTheme.flat(TecTheme.FACE_RISE, TecTheme.R_SM, TecTheme.EDGE))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)

	var head := ColorRect.new()
	head.color = TecTheme.LINE
	head.custom_minimum_size = Vector2(0, 36)
	col.add_child(head)
	var head_label := TecTheme.label("T.E.C-OS 调查员证", TecTheme.FS_TITLE, TecTheme.TEXT_ON_DARK)
	head_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	head_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(head_label)

	var sec1 := _cert_section(col, false)
	var photo_center := CenterContainer.new()
	photo_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec1.add_child(photo_center)
	var photo := PanelContainer.new()
	photo.custom_minimum_size = Vector2(156, 156)
	photo.add_theme_stylebox_override("panel", TecTheme.flat(TecTheme.BG, 0, TecTheme.EDGE))
	photo_center.add_child(photo)
	var pm := MarginContainer.new()
	pm.add_theme_constant_override("margin_left", 6)
	pm.add_theme_constant_override("margin_right", 6)
	pm.add_theme_constant_override("margin_top", 6)
	pm.add_theme_constant_override("margin_bottom", 6)
	photo.add_child(pm)
	var face := CenterContainer.new()
	pm.add_child(face)
	face.add_child(_cert_photo(c))
	var nm := TecTheme.label(String(c.get("name", "")), TecTheme.FS_DISPLAY, TecTheme.TEXT)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sec1.add_child(nm)
	var idn := TecTheme.label(String(c.get("id", "")), TecTheme.FS_TITLE, TecTheme.MUTED)
	idn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sec1.add_child(idn)
	var level := TecTheme.label("等级：初级调查员", TecTheme.FS_TITLE, TecTheme.MUTED)
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sec1.add_child(level)

	var sec2 := _cert_section(col, true)
	var sense := String(c.get("sense", "vision"))
	var sense_label := TecTheme.label("%s主导型" % String(Investigator.SENSE_NAMES.get(sense, sense)),
		21, TecTheme.TEXT)
	sense_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sec2.add_child(sense_label)
	var flavor := TecTheme.label(String(Investigator.SENSE_FLAVOR.get(sense, "")), TecTheme.FS_TITLE, TecTheme.MUTED)
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flavor.custom_minimum_size = Vector2(292, 0)
	sec2.add_child(flavor)

	var sec3 := _cert_section(col, true)
	var row := HBoxContainer.new()
	sec3.add_child(row)
	var date := TecTheme.label("签发日期：" + String(c.get("date", "")), TecTheme.FS_TITLE, TecTheme.TEXT)
	date.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(date)
	row.add_child(_stamp())
	return panel


static func _cert_section(parent: VBoxContainer, dashed: bool) -> VBoxContainer:
	var line := ColorRect.new()
	line.color = TecTheme.LINE2 if dashed else TecTheme.LINE
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", 14)
	wrap.add_theme_constant_override("margin_right", 14)
	wrap.add_theme_constant_override("margin_top", 12)
	wrap.add_theme_constant_override("margin_bottom", 12)
	parent.add_child(wrap)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	wrap.add_child(box)
	return box


static func _cert_photo(c: Dictionary) -> Control:
	var id := String(c.get("avatarId", ""))
	if AVATAR_ART.has(id):
		var tex := TextureRect.new()
		tex.texture = load(String(AVATAR_ART[id]))
		tex.custom_minimum_size = Vector2(144, 144)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		return tex
	if id != "":
		var l := TecTheme.label(id.substr(0, 1), TecTheme.FS_INITIAL, TecTheme.MUTED)
		l.custom_minimum_size = Vector2(144, 144)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		return l
	var fallback := TextureRect.new()
	fallback.texture = load("res://assets/raw/cert-avatar.png")
	fallback.custom_minimum_size = Vector2(144, 144)
	fallback.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fallback.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fallback.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return fallback


static func _stamp() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(58, 58)
	var circle := Panel.new()
	circle.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := TecTheme.flat(TecTheme.NONE, TecTheme.R_PILL, TecTheme.INK, 2)
	circle.add_theme_stylebox_override("panel", sb)
	holder.add_child(circle)
	var label := TecTheme.label("T.E.C\n核准", TecTheme.FS_BODY, TecTheme.INK)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	circle.add_child(label)
	holder.pivot_offset = Vector2(29, 29)
	holder.rotation = deg_to_rad(-12)
	return holder


func dbg_step() -> Variant:
	return _step


func dbg_title() -> String:
	for child in _box.get_children():
		if child is Label:
			return (child as Label).text
	return ""


func dbg_set_name(v: String) -> void:
	_name = v
	if _name_edit != null:
		_name_edit.text = v


func dbg_begin() -> void:
	_begin()


func dbg_answer(index: int) -> void:
	_answer(index)


func dbg_pick(id: String) -> void:
	_pick(id)


func dbg_confirm_pick() -> void:
	_confirm_pick()


func dbg_confirm() -> void:
	_confirm_card()


func dbg_card() -> Dictionary:
	return card.duplicate(true)


func dbg_option_count() -> int:
	var n := 0
	for child in _box.get_children():
		if child is Button and String((child as Button).text).begins_with("["):
			continue
		if child is Button:
			n += 1
	return n
