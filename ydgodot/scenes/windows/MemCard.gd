class_name MemCard
extends SysWindow
## 记忆放映卡（对齐 Web 版 13-matrix.js 的 showMemoryCard）：
## 暗纸 + 双线黑框的「另一种纸」，正文逐行打字，单击推进，按住整卡可拖动。
## 卡片只负责放映；正文行由 Desktop 按当前时刻 / 地点拼好。

const CHAR_MS := 45.0
const MARGIN := 14.0
const TALK_COLOR := TecTheme.INK_MUTED
const SAY_BG := TecTheme.MEM_SAY_BG
const SAY_EDGE := TecTheme.INK_FAINT
const AVATAR_ART := {
	"CHARS_TEC": "res://assets/raw/tec-avatar.png",
	"CHARS_EXEC": "res://assets/raw/executor-avatar.png",
}

var _line_box: VBoxContainer
var _lines: Array = []
var _rows: Array = []
var _idx := 0
var _cur: TypewriterLabel = null
var _cur_text := ""
var _play_mode := false
## 标题条上那颗类型符号的类型（时刻 = 时，人物对话 = 人）。颜色走深色面提亮版。
var _kind := "time"
var _glyph: KindGlyph

var _pressing := false
var _dragged := false
var _drag_press := Vector2.ZERO
var _drag_grab := Vector2.ZERO


func setup_memory(p_title: String, p_lines: Array, w: float = 330.0, h: float = 300.0,
		kind: String = "time") -> void:
	var specs: Array = []
	for raw in p_lines:
		specs.append({"t": "narr", "text": String(raw), "who": "", "name": ""})
	_setup_lines(p_title, specs, w, h, false, kind)


func setup_play(p_title: String, p_lines: Array, w: float = 420.0, h: float = 300.0,
		kind: String = "char") -> void:
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


func _setup_lines(p_title: String, p_lines: Array, w: float, h: float, play_mode: bool,
		kind: String = "") -> void:
	_lines = p_lines
	_play_mode = play_mode
	_kind = kind if kind != "" else ("char" if play_mode else "time")
	setup(p_title, w, h)
	_apply_memory_skin()

	_line_box = VBoxContainer.new()
	_line_box.name = "mem_lines"
	_line_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line_box.add_theme_constant_override("separation", 6)
	content.add_child(_line_box)

	gui_input.connect(_on_card_input)
	_build_rows()
	_play_next()
	call_deferred("_fit_height")


## 不走烘焙九切片（那张是米白卡面，且带固定的圆角与外影）；回忆卡自己画框。
func _uses_baked_frame() -> bool:
	return false


## 回忆卡：白面 + **3px 黑框**（普通窗 2px、节点卡 1px）。
## 层次靠线宽，不靠做旧。原来这里还挂着 18% 白高光与 34% 墨内影（模拟纸的隆起/压痕），
## 在 1-bit 里它们只会把 3px 黑框内侧糊成两档灰 —— 拟物语法，P4 一并关掉。
func _apply_memory_skin() -> void:
	var bg := get_node_or_null("bg") as ColorRect
	if bg != null and bg.material is ShaderMaterial:
		var mat := bg.material as ShaderMaterial
		mat.set_shader_parameter("col_hi", TecTheme.MEM_HI)
		mat.set_shader_parameter("col_mid", TecTheme.MEM_MID)
		mat.set_shader_parameter("col_lo", TecTheme.MEM_LO)
		mat.set_shader_parameter("edge_col", TecTheme.NONE)
		mat.set_shader_parameter("rim_col", TecTheme.NONE)
		mat.set_shader_parameter("shade_col", TecTheme.NONE)
		mat.set_shader_parameter("gradient_mix", 0.0)

	var border := Panel.new()
	border.name = "mem_border"
	border.position = Vector2(PAD, PAD)
	border.size = size - Vector2(PAD * 2.0, PAD * 2.0)
	border.add_theme_stylebox_override("panel", TecTheme.flat(TecTheme.NONE, TecTheme.R_WIN, TecTheme.INK, 3))
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)
	move_child(border, 1)

	var bar := get_node_or_null("bar") as Control
	if bar != null:
		var bar_bg := ColorRect.new()
		bar_bg.name = "mem_bar_bg"
		bar_bg.color = TecTheme.INK
		bar_bg.position = Vector2.ZERO
		bar_bg.size = bar.size
		bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(bar_bg)
		bar.move_child(bar_bg, 0)
	var title := get_node_or_null("bar/win_title") as Label
	if title != null:
		title.add_theme_color_override("font_color", TecTheme.TEXT_ON_DARK)
	var close := get_node_or_null("bar/close") as Button
	if close != null:
		close.set_meta("glyph_normal", TecTheme.TEXT_ON_DARK)
		close.set_meta("glyph_hot", TecTheme.TEXT_ON_DARK)
		_paint_mini_glyph(close, false)
		close.add_theme_stylebox_override("normal", TecTheme.flat(TecTheme.INK, TecTheme.R_BTN, TecTheme.INK_FAINT))
		close.add_theme_stylebox_override("hover", TecTheme.flat(TecTheme.FACE_DARK_HOVER, TecTheme.R_BTN, TecTheme.INK_FAINT))
		close.add_theme_stylebox_override("pressed", TecTheme.flat(TecTheme.FACE_DARK_LO, TecTheme.R_BTN, TecTheme.INK_FAINT))
	var sep := get_node_or_null("sep") as ColorRect
	if sep != null:
		sep.color = TecTheme.INK_FAINT
	_add_kind_glyph()


## 标题条左端的类型符号 —— 和画布卡片上那颗是同一个东西（`KindGlyph`），只是这里
## 压在黑条上，必须用**提亮版**类型色（原色对 #2b2b26 只有 ~1.4:1，等于没画）。
## 时刻 / 线索没有专属色，回落到米白 `#e6e3d2`（和标题同色，看得见但不抢戏）。
func _add_kind_glyph() -> void:
	if _glyph != null:
		return
	var bar := get_node_or_null("bar") as Control
	if bar == null:
		return
	_glyph = KindGlyph.new()
	_glyph.name = "mem_glyph"
	_glyph.kind = _kind
	_glyph.col = TecTheme.kind_color(_kind, true)
	_glyph.position = Vector2(9.0, (bar.size.y - 16.0) * 0.5)
	_glyph.size = Vector2(16.0, 16.0)
	_glyph.radius = 8.0
	_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_glyph)


func _build_rows() -> void:
	_rows.clear()
	for spec in _lines:
		var d := spec as Dictionary
		var text := String(d.get("text", ""))
		var kind := String(d.get("t", "narr"))
		var built := _build_say(d, text) if kind == "say" else _build_text(kind, text)
		var row := built[0] as Control
		var label := built[1] as TypewriterLabel
		row.modulate.a = 0.0
		_line_box.add_child(row)
		_rows.append({"root": row, "label": label, "text": text})


func _play_next() -> void:
	if _idx >= _rows.size():
		return
	var row := _rows[_idx] as Dictionary
	_idx += 1
	_cur = row["label"] as TypewriterLabel
	_cur_text = String(row["text"])
	(row["root"] as Control).modulate.a = 1.0
	_cur.start_typing()


func _new_text_label(color: Color) -> TypewriterLabel:
	return TecTheme.narrative_label("", color)


func _build_text(kind: String, text: String) -> Array:
	var label := _new_text_label(TALK_COLOR if kind == "talk" else TecTheme.INK)
	label.text = text
	return [label, label]


func _build_say(spec: Dictionary, text: String) -> Array:
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
	var name_label := TecTheme.label(name, TecTheme.FS_BODY, TALK_COLOR)
	name_label.name = "mem_say_name"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(name_label)
	var label := _new_text_label(TecTheme.INK)
	label.text = text
	main.add_child(label)
	row.add_child(main)
	return [row, label]


func _say_avatar(who: String, name: String) -> Control:
	var frame := PanelContainer.new()
	frame.name = "mem_say_avatar"
	frame.custom_minimum_size = Vector2(40, 40)
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", TecTheme.flat(SAY_BG, TecTheme.R_SM, SAY_EDGE))
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
		var ini := TecTheme.label(name.substr(0, 1) if name != "" else "?", TecTheme.FS_DISPLAY, TALK_COLOR)
		ini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ini.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ini.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(ini)
	return frame


func _finish_line() -> void:
	if _cur != null:
		_cur.finish_typing()


func _fit_height() -> void:
	if _line_box == null:
		return
	if not is_inside_tree():
		await tree_entered
	await get_tree().process_frame
	var lines_h := _line_box.get_combined_minimum_size().y
	var target := SysWindow.BAR_H + 20.0 + lines_h
	if absf(size.y - (target + SysWindow.PAD * 2.0)) > 0.5:
		set_inner_height(target)


func _sync_frame(inner: Vector2) -> void:
	super._sync_frame(inner)
	var border := get_node_or_null("mem_border") as Control
	if border != null:
		border.position = Vector2(PAD, PAD)
		border.size = inner


## 单击推进：本行还在打字就先补全；已打完就出下一行。
func advance() -> bool:
	if is_typing():
		_finish_line()
		return true
	if _idx >= _rows.size():
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
			if raise_now.is_valid():
				raise_now.call(self)
			else:
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
	# 「点击提层」走 SysWindow.raise_now（Desktop._place_z 接进来的 rank 表回调）


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
	return _cur.typed_text() if _cur != null else ""


func index() -> int:
	return _idx


func is_typing() -> bool:
	return _cur != null and _cur.is_typing()


func finish_line() -> void:
	_finish_line()
