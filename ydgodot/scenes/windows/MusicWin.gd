class_name MusicWin
extends SysWindow
## 内置音乐播放器（对齐 Web 版 16-cases.js 的 MUSIC // 播放器）
##
## 唱针装上唱机后解锁；单击曲目播放 / 暂停，同一首再点 = 暂停，再点续播。
## 窗可 – 最小化成右下角播放器卡片；关闭窗不停止音乐（与 Web 同口径）。

signal progress_changed(cur: float, dur: float)

const TRACKS := [
	{"id": "Air_Bach", "title": "Air (Bach)", "path": "res://assets/raw/Air_Bach.ogg"},
]
const WIN_W := 332.0
const WIN_H := 214.0
const TransportButton := preload("res://ui/TransportButton.gd")

var _audio: AudioStreamPlayer
var _current := ""
var _paused := false
var _rows: Dictionary = {}
var _head: Control
var _list: VBoxContainer
var _player: VBoxContainer
var _prog: ProgressBar
var _time_label: Label
var _play_btn: TransportButton
var _stop_btn: TransportButton
var _emit_acc := 0.0


static func title_of(id: String) -> String:
	for t in TRACKS:
		if String(t["id"]) == id:
			return String(t["title"])
	return ""


static func track_of(id: String) -> Dictionary:
	for t in TRACKS:
		if String(t["id"]) == id:
			return t
	return {}


func setup_music() -> void:
	setup("播放器", WIN_W, WIN_H)
	enable_controls("最小化到右下角播放器卡片", "关闭播放器（音乐继续）")
	_audio = AudioStreamPlayer.new()
	_audio.name = "audio"
	add_child(_audio)
	_build_content()
	_refresh()


func _build_content() -> void:
	## D1：曲目列表是一个小节，标题用黑条白字（h4），与窗标题的横纹语法拉开一档。
	_head = TecTheme.section_bar("曲目 · %d 首" % TRACKS.size())
	content.add_child(_head)

	_list = VBoxContainer.new()
	_list.name = "music_list"
	_list.add_theme_constant_override("separation", 4)
	content.add_child(_list)
	for t in TRACKS:
		var id := String(t["id"])
		var row := Button.new()
		row.name = "row_" + id
		row.text = ""
		row.custom_minimum_size = Vector2(0, 32)
		row.focus_mode = Control.FOCUS_NONE
		row.tooltip_text = String(t["title"])
		row.pressed.connect(func(): play_track(id))
		_list.add_child(row)
		# B2：曲目行不再整条填黑。纸底 + 1px 键线，左侧音符 glyph；
		# 当前曲目只加粗键线，播放 / 暂停由行尾 6px 方块（实心 / 空心）表达。
		var pad := MarginContainer.new()
		pad.name = "pad"
		pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pad.add_theme_constant_override("margin_left", 7)
		pad.add_theme_constant_override("margin_right", 7)
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pad)
		var line := HBoxContainer.new()
		line.name = "line"
		line.add_theme_constant_override("separation", 6)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_child(line)
		var glyph := NoteGlyph.new()
		glyph.name = "glyph"
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(glyph)
		var label := TecTheme.label(String(t["title"]), TecTheme.FS_BODY, TecTheme.TEXT)
		label.name = "title"
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(label)
		var mark := PlayMark.new()
		mark.name = "mark"
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(mark)
		_rows[id] = {"button": row, "glyph": glyph, "title": label, "mark": mark}

	_player = VBoxContainer.new()
	_player.name = "music_player"
	_player.add_theme_constant_override("separation", 6)
	_player.visible = false
	content.add_child(_player)

	var rule := ColorRect.new()
	rule.color = TecTheme.LINE2
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player.add_child(rule)

	_prog = ProgressBar.new()
	_prog.name = "music_prog"
	_prog.min_value = 0
	_prog.max_value = 100
	_prog.value = 0
	_prog.show_percentage = false
	_prog.custom_minimum_size = Vector2(0, 10)
	_prog.mouse_filter = Control.MOUSE_FILTER_STOP
	_prog.tooltip_text = "播放进度 · 点击跳转"
	_prog.add_theme_stylebox_override("background", TecTheme.flat(TecTheme.FACE_LO, 0, TecTheme.FACE_LO, 0))
	_prog.add_theme_stylebox_override("fill", TecTheme.flat(TecTheme.LINE, 0, TecTheme.LINE, 0))
	_prog.gui_input.connect(_on_prog_input)
	_player.add_child(_prog)

	_time_label = TecTheme.label("--:-- / --:--", TecTheme.FS_BODY, TecTheme.MUTED)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_player.add_child(_time_label)

	var ctrl := HBoxContainer.new()
	ctrl.alignment = BoxContainer.ALIGNMENT_END
	ctrl.add_theme_constant_override("separation", 6)
	_player.add_child(ctrl)
	_play_btn = _icon_button("play", "播放 / 暂停")
	_play_btn.pressed.connect(toggle_current)
	ctrl.add_child(_play_btn)
	_stop_btn = _icon_button("stop", "停止")
	_stop_btn.pressed.connect(stop)
	ctrl.add_child(_stop_btn)


func _icon_button(mode: String, tip: String) -> TransportButton:
	var b := TransportButton.new()
	b.setup_transport(mode, tip)
	return b


func _process(delta: float) -> void:
	if _audio == null or _current == "":
		return
	_emit_acc += delta
	if _emit_acc < 0.15:
		return
	_emit_acc = 0.0
	_refresh_progress()
	progress_changed.emit(get_time(), duration())


func play_track(id: String) -> bool:
	var t := track_of(id)
	if t.is_empty():
		return false
	if _current == id:
		if _paused:
			_audio.stream_paused = false
			_paused = false
			return true
		if _audio.playing:
			_audio.stream_paused = true
			_paused = true
			_refresh()
			return false
		_audio.play()
		_paused = false
		_refresh()
		return true
	var path := String(t["path"])
	if not ResourceLoader.exists(path):
		return false
	var stream := load(path)
	if stream == null:
		return false
	if stream.get("loop") != null:
		stream.set("loop", true)
	_audio.stream = stream
	_audio.stream_paused = false
	_audio.play()
	_current = id
	_paused = false
	_refresh()
	return true


func toggle_current() -> bool:
	if _current == "":
		return false
	return play_track(_current)


func stop() -> void:
	if _audio == null:
		return
	_audio.stop()
	_audio.stream_paused = false
	_current = ""
	_paused = false
	_refresh()
	progress_changed.emit(0.0, 0.0)


func get_time() -> float:
	if _audio == null:
		return 0.0
	return _audio.get_playback_position()


func duration() -> float:
	if _audio == null or _audio.stream == null:
		return 0.0
	return _audio.stream.get_length()


func is_playing() -> bool:
	return _audio != null and _current != "" and _audio.playing and not _paused


func current_id() -> String:
	return _current


func seek_ratio(ratio: float) -> void:
	var dur := duration()
	if dur <= 0.0:
		return
	_audio.seek(clampf(ratio, 0.0, 1.0) * dur)
	_refresh_progress()


func _on_prog_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		seek_ratio(event.position.x / maxf(_prog.size.x, 1.0))


func _refresh() -> void:
	for id in _rows.keys():
		var rec: Dictionary = _rows[id]
		var row: Button = rec["button"]
		var cur := String(id) == _current
		row.add_theme_stylebox_override("normal", _row_style(cur, false))
		row.add_theme_stylebox_override("hover", _row_style(cur, true))
		row.add_theme_stylebox_override("pressed", _row_style(cur, false, true))
		(rec["glyph"] as NoteGlyph).set_inked(cur)
		(rec["title"] as Label).add_theme_color_override("font_color",
			TecTheme.TEXT if cur else TecTheme.INK_MUTED)
		(rec["mark"] as PlayMark).set_state(cur, cur and is_playing())
	_player.visible = _current != ""
	if _play_btn != null:
		_play_btn.set_mode("pause" if is_playing() else "play")
	_refresh_progress()


func _row_style(cur: bool, hover: bool, pressed := false) -> StyleBoxFlat:
	var bg := TecTheme.FACE_LO if pressed else (TecTheme.BG if hover else TecTheme.CARD)
	var edge := TecTheme.INK if (cur or hover or pressed) else TecTheme.EDGE
	var width := 2 if (cur or hover or pressed) else 1
	var sb := TecTheme.flat(bg, TecTheme.R_BTN, edge, width)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	return sb


## 八分音符：4×3 符头 + 1px 符干 + 斜旗。自绘而不是吃字体，避免缺字 / 基线漂移。
class NoteGlyph extends Control:
	var inked := false

	func _init() -> void:
		custom_minimum_size = Vector2(12, 12)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_inked(on: bool) -> void:
		if inked == on:
			return
		inked = on
		queue_redraw()

	func _draw() -> void:
		var ink := TecTheme.INK if inked else TecTheme.MUTED
		draw_rect(Rect2(1, 8, 4, 3), ink)
		draw_line(Vector2(5, 9), Vector2(5, 1), ink, 1.0)
		draw_line(Vector2(5, 1), Vector2(9, 3), ink, 1.0)
		draw_line(Vector2(9, 3), Vector2(9, 5), ink, 1.0)


## 行尾播放标记：实心 = 正在播放，空心 = 当前曲目但暂停。
class PlayMark extends Control:
	var playing := false
	var shown := false

	func _init() -> void:
		custom_minimum_size = Vector2(6, 6)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_state(on: bool, play: bool) -> void:
		if shown == on and playing == play:
			return
		shown = on
		playing = play
		queue_redraw()

	func _draw() -> void:
		if not shown:
			return
		var r := Rect2(0, 0, 6, 6)
		if playing:
			draw_rect(r, TecTheme.INK)
		else:
			draw_rect(r, TecTheme.INK, false, 1.0)


func _refresh_progress() -> void:
	if _prog == null:
		return
	var dur := duration()
	var cur := get_time()
	_prog.value = clampf(cur / dur, 0.0, 1.0) * 100.0 if dur > 0.0 else 0.0
	_time_label.text = "%s / %s" % [_fmt(cur), _fmt(dur)]


func _fmt(s: float) -> String:
	if not is_finite(s) or s < 0.0:
		return "--:--"
	var n := int(round(s))
	return "%02d:%02d" % [int(n / 60), n % 60]


func state() -> Dictionary:
	return {
		"library": TRACKS.map(func(t): return {"id": String(t["id"]), "title": String(t["title"])}),
		"current": _current,
		"title": title_of(_current),
		"playing": is_playing(),
		"paused": _paused,
		"time": get_time(),
		"duration": duration(),
		"rows": _rows.size(),
	}
