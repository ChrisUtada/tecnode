class_name TecWindow
extends SysWindow
## TEC 助手窗（P0 只做「分析一处场景」这一件事）
##
## 对齐 Web 版：分析耗时 5–8 秒（`TEC_ANALYZE_MIN/MAX`），进度条推进，结束后吐一条解读。
## **测试旁路**：命令行带 `--fast` 时耗时压到 0.05 秒（计划 §四.3 的无头要求）。

signal analysis_done(scene_id: String)

const MIN_SEC := 5.0
const MAX_SEC := 8.0

var _log: VBoxContainer
var _bar: ProgressBar
var _btn: Button
var _avatar: TextureRect
var _hint: Label

var _analyzing := false
var _elapsed := 0.0
var _duration := 0.0
var _target: String = ""
var _fast := false
var _done_count := 0


func setup_tec() -> void:
	_fast = OS.get_cmdline_args().has("--fast") or OS.get_cmdline_user_args().has("--fast")
	setup("TEC // 助手", 360, 420)
	_build_content()


func _build_content() -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	content.add_child(head)

	_avatar = TextureRect.new()
	_avatar.texture = load("res://assets/raw/tec-avatar.png")
	_avatar.custom_minimum_size = Vector2(48, 48)
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(_avatar)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	head.add_child(col)
	col.add_child(TecTheme.label("TEC", 13, TecTheme.TEXT))
	_hint = TecTheme.label("把展开过的场景拖到我这里，我替您看看。", 11, TecTheme.FAINT)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_hint)

	_log = VBoxContainer.new()
	_log.name = "tec_log"
	_log.add_theme_constant_override("separation", 8)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size = Vector2(0, 200)
	content.add_child(_log)
	append_line("您好，我是 TEC。有任何想不通的地方，都可以交给我。", TecTheme.MUTED)

	_bar = ProgressBar.new()
	_bar.name = "tec_bar"
	_bar.min_value = 0
	_bar.max_value = 100
	_bar.value = 0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 10)
	_bar.add_theme_stylebox_override("background", TecTheme.flat(TecTheme.BG, 4, TecTheme.EDGE_SOFT, 1))
	_bar.add_theme_stylebox_override("fill", TecTheme.flat(TecTheme.LINE, 4, TecTheme.LINE, 1))
	_bar.visible = false
	content.add_child(_bar)

	_btn = TecTheme.button("分析选中的场景")
	_btn.name = "tec_analyze_btn"
	_btn.pressed.connect(func(): _on_analyze_pressed())
	content.add_child(_btn)


func append_line(text: String, color: Color = TecTheme.TEXT) -> void:
	var l := TecTheme.label(text, 13, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.add_child(l)
	_log.queue_sort()


func is_analyzing() -> bool:
	return _analyzing


func analyze(scene_id: String) -> void:
	if _analyzing:
		return
	if scene_id == "":
		append_line("先选一处展开过的场景，我才有东西可看。", TecTheme.MUTED)
		return
	_target = scene_id
	_analyzing = true
	_elapsed = 0.0
	_duration = 0.05 if _fast else randf_range(MIN_SEC, MAX_SEC)
	_bar.value = 0
	_bar.visible = true
	_btn.disabled = true
	_hint.text = "正在分析……"
	set_process(true)


func _on_analyze_pressed() -> void:
	var sel_scene: String = get_meta("selected_scene", "")
	analyze(sel_scene)


func _process(delta: float) -> void:
	if not _analyzing:
		return
	_elapsed += delta
	_bar.value = clampf(_elapsed / maxf(_duration, 0.001) * 100.0, 0.0, 100.0)
	if _elapsed < _duration:
		return
	_analyzing = false
	set_process(false)
	_bar.visible = false
	_btn.disabled = false
	_hint.text = "还要再看点什么？"
	_done_count += 1
	append_line(_line_for(_target), TecTheme.TEXT)
	analysis_done.emit(_target)


func _line_for(scene_id: String) -> String:
	if scene_id == "SCENES_body":
		return "尸体的皮肤没有明显外伤，指缝里有细微的植物纤维。死亡时间不长——至少这具身体还「新鲜」。"
	if scene_id == "SCENES_garden":
		return "这个花园被人精心改造过：帘幕、光源、通风，都在把这里变成一个不见天日的容器。"
	return "看过了。这处场景里还有我没想通的东西，先记下来。"


## 立刻跳到分析结束（截图 / 测试用；真正的收尾仍走 _process 同一路径）
func finish_now() -> void:
	if _analyzing:
		_elapsed = _duration
		set_process(true)


## 撤销 / 重开时把进行中的分析收掉（已写进日志的结果保留，不回收）
func cancel_analysis() -> void:
	if not _analyzing:
		return
	_analyzing = false
	set_process(false)
	_bar.visible = false
	_btn.disabled = false
	_hint.text = "还要再看点什么？"


func done_count() -> int:
	return _done_count
