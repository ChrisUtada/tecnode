class_name StartScreen
extends Control
## 第 0 幕：开始界面。
## 全屏黑底 + 红色恶魔 + 开始 / 继续 / 设置 / 退出。
## 这是全游戏唯一允许跳出桌面隐喻的画面；红色只属于恶魔这个内容形象。
##
## 开场节奏（2026-10-24 定稿·串行）：
##   黑场自检行 → 黑场淡出 → 卡片淡入（窗体先稳定）→ 标题逐字 → 恶魔连框缓进 → 按钮逐行亮起。
## 恶魔待机只有呼吸浮动；点击 = 晃动（无表情）。
## BGM：开机即播（现有 Air_Bach），开始/继续后快速淡出并自毁。
## 无头模式跳过全部过场与音频（测试直接面对终态）。

signal start_requested(overwrite: bool)
signal continue_requested
signal quit_requested

const GameSettingsScript := preload("res://core/GameSettings.gd")
const DEMON_ART := "res://assets/raw/executor-avatar.png"
const BGM_ART := "res://assets/raw/Air_Bach.ogg"
const DEMON_PX := 72.0
const BOOT_LINE := "T.E.C-OS // 启动自检……"

var has_save := false
var _continue_btn: Button
var _card: PanelContainer
var _title: TypewriterLabel
var _demon_holder: Control
var _demon: TextureRect
var _booting := false
var _boot_overlay: ColorRect
var _boot_label: TypewriterLabel
var _idle_tween: Tween
var _bgm: AudioStreamPlayer
var _menu_btns: Array[Button] = []
var _dialog_layer: Control
var _dialog_panel: PanelContainer
var _dialog_title: Label
var _dialog_body: Label
var _dialog_extra: VBoxContainer
var _dialog_actions: HBoxContainer


func setup(p_has_save: bool) -> void:
	has_save = p_has_save
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func set_has_save(on: bool) -> void:
	has_save = on
	if _continue_btn != null and not _booting:
		_continue_btn.disabled = not on


func _ready() -> void:
	## 播放入树后再说：setup() 是在 add_child 之前调的，直接 play 会被引擎拒绝
	if _bgm != null and not _bgm.playing:
		_bgm.play()


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
	_card = card

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

	# 标题用打字机：开机序列里逐字打出，无头/终态下整行直出
	_title = TypewriterLabel.new()
	_title.name = "start_title"
	_title.configure("异动区域已被锁定", TecTheme.FS_DISPLAY, TecTheme.TEXT)
	_title.char_ms = 120.0  # 登录界面式缓进：标题打字再慢一档
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF  # 单行标题：自动换行会把标题压成竖排
	## 显式预留一行高：打字前 visible_characters=0 时 Label 最小高度塌成 0，
	## 首字出现那刻卡片会被撑长一截（实测）；预留后高度全程恒定。
	_title.custom_minimum_size.y = TecTheme.font().get_height(TecTheme.FS_DISPLAY)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_title)

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
	_demon_holder = holder

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
	_demon.gui_input.connect(_on_demon_input)
	holder.add_child(_demon)

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
	_continue_btn.pressed.connect(func(): _stop_bgm(); continue_requested.emit())
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

	if DisplayServer.get_name() == "headless":
		## 测试直接面对终态：不过场、不待机动画、不播音频
		return
	_play_bgm()
	_play_boot()


## ── BGM：开机即播；开始/继续后快淡出并自毁 ──────────────────────────────
func _play_bgm() -> void:
	_bgm = AudioStreamPlayer.new()
	_bgm.name = "bgm"
	_bgm.stream = load(BGM_ART)
	_bgm.volume_db = -40.0  # 静音待机：恶魔登场后才淡入
	add_child(_bgm)
	# play 在 _ready 里做（此时可能还没入树）


## 恶魔登场完毕 = BGM 淡入：角色与音乐同一拍出现
func _bgm_fade_in() -> void:
	if _bgm == null or not is_instance_valid(_bgm):
		return
	var tw := create_tween()
	tw.tween_property(_bgm, "volume_db", -10.0, 1.0)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## StartScreen 会被立即销毁，而淡出需要时间：把播放器挪给父级托管，
## 淡出完自行销毁——信号同步发出，不拖慢进入游戏。
func _stop_bgm() -> void:
	if _bgm == null or not is_instance_valid(_bgm):
		return
	var p := _bgm
	_bgm = null
	remove_child(p)
	get_parent().add_child(p)
	var tw := p.create_tween()
	tw.tween_property(p, "volume_db", -40.0, 0.4)
	tw.tween_callback(p.queue_free)


## ── 开机序列（串行主轴 + 轻拍交叠，窗体稳定后才出内容）──────────────────
## 黑场自检 → 黑场淡出 → 卡片淡入落定 → 恶魔连框缓进（= BGM 淡入）→ 标题逐字 → 按钮淡入。
## 按钮全程占位只淡透明度——卡片高度从出现第一帧起就是最终高度，零撑开。
func _play_boot() -> void:
	_booting = true
	_card.modulate.a = 0.0
	_title.visible_characters = 0
	_demon_holder.modulate.a = 0.0   # 框与恶魔一起藏——不留空框
	for b in _menu_btns:
		b.modulate.a = 0.0           # 占位但透明，杜绝「逐行亮起撑开窗体」

	_boot_overlay = ColorRect.new()
	_boot_overlay.name = "boot_overlay"
	_boot_overlay.color = TecTheme.INK
	_boot_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_boot_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_boot_overlay.z_index = 5
	add_child(_boot_overlay)

	_boot_label = TypewriterLabel.new()
	_boot_label.name = "boot_line"
	_boot_label.configure(BOOT_LINE, TecTheme.FS_BODY, TecTheme.TEXT_ON_DARK)
	_boot_label.autowrap_mode = TextServer.AUTOWRAP_OFF  # 无容器宽度，必须关换行
	_boot_label.position = Vector2(18, 14)
	_boot_overlay.add_child(_boot_label)
	_boot_label.start_typing()
	await _boot_label.typing_finished
	await get_tree().create_timer(0.25).timeout

	# 黑场淡出，走完再谈下一步
	var fade := create_tween()
	fade.tween_property(_boot_overlay, "modulate:a", 0.0, 0.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade.tween_callback(_boot_overlay.queue_free)
	await fade.finished

	# 卡片淡入落定（窗体先稳定，再谈内容）
	var rise := create_tween()
	rise.tween_property(_card, "modulate:a", 1.0, 0.6)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await rise.finished

	# 恶魔连框缓进：淡入 + 上浮
	_demon.pivot_offset = Vector2(DEMON_PX * 0.5, DEMON_PX * 0.5)
	_demon.position = Vector2(0, 6.0)
	var enter := create_tween()
	enter.set_parallel(true)
	enter.tween_property(_demon_holder, "modulate:a", 1.0, 0.8)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	enter.tween_property(_demon, "position:y", 0.0, 0.8)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await enter.finished
	_start_idle()

	# 第二拍：头像出现以后 = BGM 淡入；隔一拍再出标题，别让孩子一次看太多
	_bgm_fade_in()
	await get_tree().create_timer(0.35).timeout

	# 第三拍：标题逐字（120ms/字，约 1s）
	_title.start_typing()
	await _title.typing_finished
	await get_tree().create_timer(0.3).timeout

	# 第四拍：按钮逐行缓进——每键淡入 0.35s，键与键之间留 0.25s 完整间隔
	for b in _menu_btns:
		var bf := create_tween()
		bf.tween_property(b, "modulate:a", 1.0, 0.35)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		await bf.finished
		await get_tree().create_timer(0.25).timeout
	_booting = false
	_continue_btn.disabled = not has_save


## ── 恶魔待机：只有呼吸浮动 ───────────────────────────────────────────────
func _start_idle() -> void:
	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()
	_idle_tween = create_tween()
	_idle_tween.set_loops()
	_idle_tween.tween_property(_demon, "position:y", -2.0, 1.3)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(_demon, "position:y", 0.0, 1.3)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## ── 菜单按钮：悬停键线换强调青 + 前缀指示符 ──────────────────────────────
func _menu_button(text: String, primary: bool = false) -> Button:
	var b := TecTheme.primary_button(text) if primary else TecTheme.button(text)
	b.custom_minimum_size = Vector2(200, 32)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	## 悬停键线改强调青（三层体系白名单第二面），其余三态不动
	b.add_theme_stylebox_override("hover",
		TecTheme.flat(TecTheme.CARD, TecTheme.R_BTN, TecTheme.SPOT_ACCENT, 2))
	b.set_meta("base_text", text)
	b.mouse_entered.connect(_on_menu_hover.bind(b, true))
	b.mouse_exited.connect(_on_menu_hover.bind(b, false))
	_menu_btns.append(b)
	return b


func _on_menu_hover(b: Button, on: bool) -> void:
	if _booting:
		return
	var base := String(b.get_meta("base_text", b.text))
	b.text = ("▸ " + base) if on else base


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
	_dialog_panel = panel
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

	## 设置面板的额外内容（显示 / 声音 / 文本三组）。普通确认框留空。
	_dialog_extra = VBoxContainer.new()
	_dialog_extra.name = "dialog_extra"
	_dialog_extra.add_theme_constant_override("separation", 8)
	col.add_child(_dialog_extra)

	_dialog_actions = HBoxContainer.new()
	_dialog_actions.name = "dialog_actions"
	_dialog_actions.alignment = BoxContainer.ALIGNMENT_END
	_dialog_actions.add_theme_constant_override("separation", 8)
	col.add_child(_dialog_actions)


func _on_start_pressed() -> void:
	if _booting:
		return
	if has_save:
		_open_dialog("开始新调查？", "当前案件的调查进度与存档将被清除，且无法撤销。",
			[["取消", false, _close_dialog],
			 ["覆盖并开始", true, func(): _close_dialog(); _stop_bgm(); start_requested.emit(true)]])
	else:
		_stop_bgm()
		start_requested.emit(false)


func _show_settings() -> void:
	if _booting:
		return
	_open_dialog("设置", "修改即时生效，并自动保存。",
		[["恢复默认", false, _reset_settings],
		 ["返回", true, _close_dialog]],
		_build_settings_content())


func _reset_settings() -> void:
	GameSettingsScript.reset_defaults()
	GameSettingsScript.apply_audio()
	GameSettingsScript.apply_display(get_window())
	GameSettingsScript.save_settings()
	_show_settings()


func _set_fullscreen(on: bool) -> void:
	GameSettingsScript.fullscreen = on
	GameSettingsScript.apply_display(get_window())
	GameSettingsScript.save_settings()
	_show_settings()


func _set_window_preset(idx: int) -> void:
	GameSettingsScript.fullscreen = false
	GameSettingsScript.window_preset = idx
	GameSettingsScript.apply_display(get_window())
	GameSettingsScript.save_settings()
	_show_settings()


func _set_volume(v: int) -> void:
	GameSettingsScript.volume = clampi(v, 0, 100)
	GameSettingsScript.apply_audio()
	GameSettingsScript.save_settings()
	_show_settings()


func _set_text_speed(idx: int) -> void:
	GameSettingsScript.text_speed = clampi(idx, 0, GameSettingsScript.TEXT_SPEEDS.size() - 1)
	GameSettingsScript.save_settings()
	_show_settings()


func _build_settings_content() -> VBoxContainer:
	var root := VBoxContainer.new()
	root.name = "settings_content"
	root.custom_minimum_size = Vector2(420, 0)
	root.add_theme_constant_override("separation", 12)

	# ── 显示 ──
	var display := _settings_section(root, "settings_display", "显示")
	var mode := _settings_row(display, "settings_mode_row", "窗口模式")
	var win_btn := _settings_choice("窗口", not GameSettingsScript.fullscreen,
		func(): _set_fullscreen(false))
	win_btn.name = "settings_mode_window"
	mode.add_child(win_btn)
	var full_btn := _settings_choice("全屏", GameSettingsScript.fullscreen,
		func(): _set_fullscreen(true))
	full_btn.name = "settings_mode_fullscreen"
	mode.add_child(full_btn)

	var size := _settings_row(display, "settings_size_row", "窗口尺寸")
	for i in GameSettingsScript.WINDOW_PRESETS.size():
		var size_idx := i
		var preset: Dictionary = GameSettingsScript.WINDOW_PRESETS[i]
		var size_btn := _settings_choice(String(preset["label"]),
			not GameSettingsScript.fullscreen and GameSettingsScript.window_preset == size_idx,
			func(): _set_window_preset(size_idx))
		size_btn.name = "settings_size_%d" % size_idx
		size.add_child(size_btn)
	var fit_btn := _settings_choice("适应屏幕",
		not GameSettingsScript.fullscreen and GameSettingsScript.window_preset < 0,
		func(): _set_window_preset(-1))
	fit_btn.name = "settings_size_fit"
	size.add_child(fit_btn)

	# ── 声音 ──
	var audio := _settings_section(root, "settings_audio", "声音")
	var vol := _settings_row(audio, "settings_volume_row", "主音量")
	var down := _settings_choice("-", false, func(): _set_volume(GameSettingsScript.volume - 10))
	down.name = "settings_volume_down"
	down.custom_minimum_size = Vector2(34, 26)
	down.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	down.disabled = GameSettingsScript.volume <= 0
	vol.add_child(down)
	var percent := TecTheme.label("%d%%" % GameSettingsScript.volume, TecTheme.FS_BODY, TecTheme.TEXT)
	percent.name = "settings_volume_value"
	percent.custom_minimum_size = Vector2(52, 0)
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	percent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vol.add_child(percent)
	var up := _settings_choice("+", false, func(): _set_volume(GameSettingsScript.volume + 10))
	up.name = "settings_volume_up"
	up.custom_minimum_size = Vector2(34, 26)
	up.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	up.disabled = GameSettingsScript.volume >= 100
	vol.add_child(up)

	# ── 文本 ──
	var text_box := _settings_section(root, "settings_text", "文本")
	var speed := _settings_row(text_box, "settings_speed_row", "文字速度")
	for i in GameSettingsScript.TEXT_SPEEDS.size():
		var speed_idx := i
		var speed_btn := _settings_choice(GameSettingsScript.TEXT_SPEEDS[i],
			GameSettingsScript.text_speed == speed_idx,
			func(): _set_text_speed(speed_idx))
		speed_btn.name = "settings_speed_%d" % speed_idx
		speed.add_child(speed_btn)

	return root


func _settings_section(parent: VBoxContainer, node_name: String, title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = node_name
	box.add_theme_constant_override("separation", 5)
	var head := TecTheme.label(title, TecTheme.FS_BODY, TecTheme.MUTED)
	head.name = node_name + "_title"
	box.add_child(head)
	var rule := ColorRect.new()
	rule.color = TecTheme.EDGE_SOFT
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	parent.add_child(box)
	return box


func _settings_row(parent: VBoxContainer, node_name: String, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = node_name
	row.add_theme_constant_override("separation", 6)
	var l := TecTheme.label(title, TecTheme.FS_BODY, TecTheme.MUTED)
	l.custom_minimum_size = Vector2(64, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	parent.add_child(row)
	return row


## 选项键：选中项直接反白（黑底白字），与全站的「按下 = 反白」是同一套语法。
func _settings_choice(text: String, selected: bool, on_pressed: Callable) -> Button:
	var b := TecTheme.button(text)
	b.custom_minimum_size = Vector2(0, 26)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if selected:
		## 用 button_style 而不是 flat：保留 12/6 的内容边距，选中前后键宽不跳。
		var normal := TecTheme.button_style(false, false)
		normal.bg_color = TecTheme.INK
		normal.border_color = TecTheme.INK
		var hover := TecTheme.button_style(true, false)
		hover.bg_color = TecTheme.INK
		hover.border_color = TecTheme.INK
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_color_override("font_color", TecTheme.TEXT_ON_DARK)
		b.add_theme_color_override("font_hover_color", TecTheme.TEXT_ON_DARK)
	b.pressed.connect(on_pressed)
	return b


## 读档失败等外部错误：留在开始界面给玩家一个可读提示，不关闭界面。
func show_notice(title: String, body: String) -> void:
	if _dialog_layer == null:
		return
	_open_dialog(title, body, [["知道了", true, _close_dialog]])


func _open_dialog(title: String, body: String, actions: Array,
		extra: Control = null) -> void:
	_dialog_title.text = title
	_dialog_body.text = body
	_dialog_body.visible = body != ""
	_clear_children(_dialog_actions)
	_clear_children(_dialog_extra)
	if _dialog_panel != null:
		_dialog_panel.custom_minimum_size = Vector2(460 if extra != null else 360, 0)
	if extra != null:
		_dialog_extra.add_child(extra)
	for item in actions:
		var btn := TecTheme.button(String(item[0]))
		btn.name = "dialog_btn_" + String(item[0])
		if bool(item[1]):
			## 不能直接用 flat()：它没有 12/6 的内容边距，短文案（如「返回」）
			## 会被压成贴边的窄方块。改为在标准键样式上只把键线加到 2px。
			var primary := TecTheme.button_style(false, false)
			primary.set_border_width_all(2)
			btn.add_theme_stylebox_override("normal", primary)
		btn.pressed.connect(item[2])
		_dialog_actions.add_child(btn)
	_dialog_layer.visible = true


func _clear_children(parent: Node) -> void:
	for c in parent.get_children():
		parent.remove_child(c)
		c.queue_free()


func _close_dialog() -> void:
	_dialog_layer.visible = false


func _on_demon_input(event: InputEvent) -> void:
	if _booting:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_shake_demon()


func _shake_demon() -> void:
	var base := _demon.position
	var tw := create_tween()
	tw.tween_property(_demon, "position:x", base.x + 3.0, 0.035)
	tw.tween_property(_demon, "position:x", base.x - 3.0, 0.07)
	tw.tween_property(_demon, "position:x", base.x + 2.0, 0.06)
	tw.tween_property(_demon, "position:x", base.x, 0.04)
