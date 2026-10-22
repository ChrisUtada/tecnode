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

var _audio: AudioStreamPlayer
var _current := ""
var _paused := false
var _rows: Dictionary = {}
var _head: Label
var _list: VBoxContainer
var _player: VBoxContainer
var _prog: ProgressBar
var _time_label: Label
var _play_btn: Button
var _stop_btn: Button
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
	_head = TecTheme.label("内置音乐 · %d 首" % TRACKS.size(), TecTheme.FS_BODY, TecTheme.MUTED)
	content.add_child(_head)

	_list = VBoxContainer.new()
	_list.name = "music_list"
	_list.add_theme_constant_override("separation", 4)
	content.add_child(_list)
	for t in TRACKS:
		var id := String(t["id"])
		var row := Button.new()
		row.name = "row_" + id
		row.text = String(t["title"])
		row.custom_minimum_size = Vector2(0, 32)
		row.focus_mode = Control.FOCUS_NONE
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_theme_font_size_override("font_size", TecTheme.FS_TITLE)
		row.add_theme_color_override("font_hover_color", TecTheme.TEXT)
		row.add_theme_stylebox_override("normal", TecTheme.flat(Color(0, 0, 0, 0), TecTheme.R_BTN, Color(0, 0, 0, 0), 0))
		row.add_theme_stylebox_override("hover", TecTheme.flat(TecTheme.BG, TecTheme.R_BTN, Color(0, 0, 0, 0), 0))
		row.add_theme_stylebox_override("pressed", TecTheme.flat(TecTheme.FACE_LO, TecTheme.R_BTN, Color(0, 0, 0, 0), 0))
		row.pressed.connect(func(): play_track(id))
		_list.add_child(row)
		_rows[id] = row

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
	_prog.add_theme_stylebox_override("background", TecTheme.flat(TecTheme.FACE_LO, 5, TecTheme.FACE_LO, 0))
	_prog.add_theme_stylebox_override("fill", TecTheme.flat(TecTheme.LINE, 5, TecTheme.LINE, 0))
	_prog.gui_input.connect(_on_prog_input)
	_player.add_child(_prog)

	_time_label = TecTheme.label("--:-- / --:--", TecTheme.FS_BODY, TecTheme.MUTED)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_player.add_child(_time_label)

	var ctrl := HBoxContainer.new()
	ctrl.alignment = BoxContainer.ALIGNMENT_END
	ctrl.add_theme_constant_override("separation", 6)
	_player.add_child(ctrl)
	_play_btn = _icon_button("▶", "播放 / 暂停")
	_play_btn.pressed.connect(toggle_current)
	ctrl.add_child(_play_btn)
	_stop_btn = _icon_button("■", "停止")
	_stop_btn.pressed.connect(stop)
	ctrl.add_child(_stop_btn)


func _icon_button(text: String, tip: String) -> Button:
	var b := TecTheme.button(text)
	b.custom_minimum_size = Vector2(34, 26)
	b.size = Vector2(34, 26)
	b.add_theme_font_size_override("font_size", TecTheme.FS_BODY)
	b.tooltip_text = tip
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
		var row: Button = _rows[id]
		var cur := String(id) == _current
		row.add_theme_color_override("font_color", TecTheme.CARD if cur else TecTheme.TEXT)
		row.add_theme_color_override("font_pressed_color", TecTheme.CARD if cur else TecTheme.TEXT)
		row.add_theme_stylebox_override("normal",
			TecTheme.flat(TecTheme.LINE if cur else Color(0, 0, 0, 0), TecTheme.R_BTN,
				Color(0, 0, 0, 0) if cur else Color(0, 0, 0, 0), 0))
	_player.visible = _current != ""
	if _play_btn != null:
		_play_btn.text = "❚❚" if is_playing() else "▶"
	_refresh_progress()


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
