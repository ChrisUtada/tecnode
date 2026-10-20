class_name MemCard
extends SysWindow
## 记忆放映卡（对齐 Web 版 13-matrix.js 的 showMemoryCard）：
## 暗纸 + 双线黑框的「另一种纸」，正文逐行打字，单击推进，按住整卡可拖动。
## 卡片只负责放映；正文行由 Desktop 按当前时刻 / 地点拼好。

const CHAR_MS := 45.0
const MARGIN := 14.0
const TALK_COLOR := Color("5c584a")
const SAY_BG := Color("ccc7ad")
const SAY_EDGE := Color("8a8672")
const AVATAR_ART := {
	"CHARS_TEC": "res://assets/raw/tec-avatar.png",
	"CHARS_EXEC": "res://assets/raw/executor-avatar.png",
}

var _scroll: ScrollContainer
var _line_box: VBoxContainer
var _lines: Array = []
var _idx := 0
var _typing := false
var _cur: Label = null
var _cur_text := ""
var _shown := 0.0
var _play_mode := false

var _pressing := false
var _dragged := false
var _drag_press := Vector2.ZERO
var _drag_grab := Vector2.ZERO


func setup_memory(p_title: String, p_lines: Array, w: float = 330.0, h: float = 300.0) -> void:
	var specs: Array = []
	for raw in p_lines:
		specs.append({"t": "narr", "text": String(raw), "who": "", "name": ""})
	_setup_lines(p_title, specs, w, h, false)


func setup_play(p_title: String, p_lines: Array, w: float = 420.0, h: float = 300.0) -> void:
	var specs: Array = []
	for raw in p_lines:
		if raw is Dictionary:
			var d := raw as Dictionary
			var t := String(d.get("t", "narr"))
			if t != "say" and t != "talk":
				t = "narr"
			specs.append({
				"t": t,
				"text": String(d.get("text", "")),
				"who": String(d.get("who", "")),
				"name": String(d.get("name", "")),
			})
		else:
			specs.append({"t": "narr", "text": String(raw), "who": "", "name": ""})
	_setup_lines(p_title, specs, w, h, true)


func _setup_lines(p_title: String, p_lines: Array, w: float, h: float, play_mode: bool) -> void:
	_lines = p_lines
	_play_mode = play_mode
	setup(p_title, w, h)
	_apply_memory_skin()

	_scroll = ScrollContainer.new()
	_scroll.name = "mem_scroll"
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.gui_input.connect(_on_card_input)
	content.add_child(_scroll)

	_line_box = VBoxContainer.new()
	_line_box.name = "mem_lines"
	_line_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line_box.add_theme_constant_override("separation", 6)
	_scroll.add_child(_line_box)

	gui_input.connect(_on_card_input)
	_play_next()


func _apply_memory_skin() -> void:
	var bg := get_node_or_null("bg") as ColorRect
	if bg != null and bg.material is ShaderMaterial:
		var mat := bg.material as ShaderMaterial
		mat.set_shader_parameter("col_hi", Color("e2deca"))
		mat.set_shader_parameter("col_mid", Color("dcd8c2"))
		mat.set_shader_parameter("col_lo", Color("d2ceb8"))
		mat.set_shader_parameter("edge_col", Color("2b2b26"))
		mat.set_shader_parameter("rim_col", Color(1.0, 0.988, 0.945, 0.18))
		mat.set_shader_parameter("shade_col", Color(0.169, 0.169, 0.149, 0.34))
		mat.set_shader_parameter("gradient_mix", 0.35)

	var border := Panel.new()
	border.name = "mem_border"
	border.position = Vector2(PAD, PAD)
	border.size = size - Vector2(PAD * 2.0, PAD * 2.0)
	border.add_theme_stylebox_override("panel", TecTheme.flat(Color(0, 0, 0, 0), TecTheme.R_WIN, Color("2b2b26"), 3))
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)
	move_child(border, 1)

	var bar := get_node_or_null("bar") as Control
	if bar != null:
		var bar_bg := ColorRect.new()
		bar_bg.name = "mem_bar_bg"
		bar_bg.color = Color("2b2b26")
		bar_bg.position = Vector2.ZERO
		bar_bg.size = bar.size
		bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(bar_bg)
		bar.move_child(bar_bg, 0)
	var title := get_node_or_null("bar/win_title") as Label
	if title != null:
		title.add_theme_color_override("font_color", Color("e6e3d2"))
	var close := get_node_or_null("bar/close") as Button
	if close != null:
		close.add_theme_color_override("font_color", Color("e6e3d2"))
		close.add_theme_color_override("font_hover_color", Color("e6e3d2"))
		close.add_theme_color_override("font_pressed_color", Color("e6e3d2"))
		close.add_theme_stylebox_override("normal", TecTheme.flat(Color("2b2b26"), 4, Color("8a8672")))
		close.add_theme_stylebox_override("hover", TecTheme.flat(Color("3a3a33"), 4, Color("8a8672")))
		close.add_theme_stylebox_override("pressed", TecTheme.flat(Color("1f1f19"), 4, Color("8a8672")))
	var sep := get_node_or_null("sep") as ColorRect
	if sep != null:
		sep.color = Color("8a8672")


func _play_next() -> void:
	if _idx >= _lines.size():
		_typing = false
		set_process(false)
		return
	var spec := _lines[_idx] as Dictionary
	_idx += 1
	var text := String(spec.get("text", ""))
	var kind := String(spec.get("t", "narr"))
	if kind == "say":
		_append_say(spec, text)
	else:
		_append_text(kind, text)
	_cur_text = text
	_shown = 0.0
	_typing = true
	set_process(true)
	_scroll_to_bottom()


func _new_text_label(color: Color) -> Label:
	var label := TecTheme.label("", 13, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible_characters = 0
	return label


func _append_text(kind: String, text: String) -> void:
	var label := _new_text_label(TALK_COLOR if kind == "talk" else Color("2b2b26"))
	label.text = text
	_line_box.add_child(label)
	_cur = label


func _append_say(spec: Dictionary, text: String) -> void:
	var who := String(spec.get("who", ""))
	var name := String(spec.get("name", ""))
	if name == "":
		name = who
	var row := HBoxContainer.new()
	row.name = "mem_say"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 9)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_say_avatar(who, name))

	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 1)
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := TecTheme.label(name, 11, TALK_COLOR)
	name_label.name = "mem_say_name"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(name_label)
	var label := _new_text_label(Color("2b2b26"))
	label.text = text
	main.add_child(label)
	row.add_child(main)
	_line_box.add_child(row)
	_cur = label


func _say_avatar(who: String, name: String) -> Control:
	var frame := PanelContainer.new()
	frame.name = "mem_say_avatar"
	frame.custom_minimum_size = Vector2(40, 40)
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", TecTheme.flat(SAY_BG, 9, SAY_EDGE))
	var art := String(AVATAR_ART.get(who, ""))
	if art != "" and ResourceLoader.exists(art):
		var tex := TextureRect.new()
		tex.texture = load(art)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(tex)
	else:
		var ini := TecTheme.label(name.substr(0, 1) if name != "" else "?", 19, TALK_COLOR)
		ini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ini.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ini.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(ini)
	return frame


func _process(delta: float) -> void:
	if not _typing or _cur == null:
		return
	_shown += delta * (1000.0 / CHAR_MS)
	var n := int(_shown)
	if n >= _cur_text.length():
		_finish_line()
	else:
		_cur.visible_characters = n


func _finish_line() -> void:
	if _cur != null:
		_cur.visible_characters = -1
	_typing = false
	set_process(false)


## 单击推进：本行还在打字就先补全；已打完就出下一行。
func advance() -> bool:
	if _typing:
		_finish_line()
		return true
	if _idx >= _lines.size():
		return false
	_play_next()
	return true


func _on_card_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressing = true
			_dragged = false
			_drag_press = event.global_position
			_drag_grab = position
			move_to_front()
		elif _pressing:
			_pressing = false
			if not _dragged:
				advance()
	elif event is InputEventMouseMotion and _pressing:
		if not _dragged and event.global_position.distance_to(_drag_press) > 4.0:
			_dragged = true
		if _dragged:
			position = _drag_grab + (event.global_position - _drag_press)


func _scroll_to_bottom() -> void:
	if _scroll != null:
		_scroll.set_deferred("scroll_vertical", 1_000_000)


# ── 测试钩子 ────────────────────────────────────────────────────────────

func line_count() -> int:
	return _lines.size()


func line_at(i: int) -> String:
	if i < 0 or i >= _lines.size():
		return ""
	return String((_lines[i] as Dictionary).get("text", ""))


func line_kind_at(i: int) -> String:
	if i < 0 or i >= _lines.size():
		return ""
	return String((_lines[i] as Dictionary).get("t", "narr"))


func line_who_at(i: int) -> String:
	if i < 0 or i >= _lines.size():
		return ""
	return String((_lines[i] as Dictionary).get("who", ""))


func line_name_at(i: int) -> String:
	if i < 0 or i >= _lines.size():
		return ""
	return String((_lines[i] as Dictionary).get("name", ""))


func say_count() -> int:
	var n := 0
	for spec in _lines:
		if String((spec as Dictionary).get("t", "")) == "say":
			n += 1
	return n


func is_play() -> bool:
	return _play_mode


func current_text() -> String:
	return _cur_text


func typed_text() -> String:
	if _cur == null:
		return ""
	if _cur.visible_characters < 0:
		return _cur.text
	return _cur.text.substr(0, _cur.visible_characters)


func index() -> int:
	return _idx


func is_typing() -> bool:
	return _typing


func finish_line() -> void:
	_finish_line()
