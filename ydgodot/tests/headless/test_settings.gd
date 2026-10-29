extends "res://tests/headless/_test_base.gd"
## 开始页设置：三组选项 / 即时生效 / 自动写盘 / 回读 / 瞬间文字。
## 运行：godot --headless --path ydgodot --script res://tests/headless/test_settings.gd
##
## 设置文件走独立测试档，避免覆盖玩家真实的 `user://settings.cfg`。

const StartScreenScript := preload("res://ui/StartScreen.gd")
const GameSettingsScript := preload("res://core/GameSettings.gd")
const TypewriterLabelScript := preload("res://ui/TypewriterLabel.gd")
const TEST_CFG := "user://test_settings.cfg"


func _initialize() -> void:
	print("=== 开始页设置 / 持久化 / 文字速度 ===")
	GameSettingsScript.config_path = TEST_CFG
	GameSettingsScript.reset_defaults()
	_remove_cfg()

	var ss = StartScreenScript.new()
	ss.setup(false)
	root.add_child(ss)
	await process_frame
	await process_frame

	var settings_btn := ss.find_child("btn_settings", true, false) as Button
	check("设置按钮存在", settings_btn != null)
	if settings_btn != null:
		settings_btn.pressed.emit()
	await process_frame
	var dialog := ss.find_child("dialog_layer", true, false) as Control
	check("设置面板可打开", dialog != null and dialog.visible)
	check("显示 / 声音 / 文本三组齐全",
		ss.find_child("settings_display", true, false) != null
			and ss.find_child("settings_audio", true, false) != null
			and ss.find_child("settings_text", true, false) != null)

	var back_btn := ss.find_child("dialog_btn_返回", true, false) as Button
	var back_sb: StyleBoxFlat = null
	if back_btn != null:
		back_sb = back_btn.get_theme_stylebox("normal") as StyleBoxFlat
	check("返回键保留内容边距（文字不贴边）",
		back_sb != null and back_sb.content_margin_left >= 8.0
			and back_sb.content_margin_right >= 8.0)

	# 文字速度：默认标准，点「快」
	var speed_btn := ss.find_child("settings_speed_2", true, false) as Button
	check("文字速度选项存在", speed_btn != null)
	if speed_btn != null:
		speed_btn.pressed.emit()
	await process_frame
	check("文字速度即时切到快",
		GameSettingsScript.text_speed == GameSettingsScript.TextSpeed.FAST)
	var cfg := ConfigFile.new()
	var cfg_ok := cfg.load(TEST_CFG) == OK
	check("设置自动写盘",
		cfg_ok and int(cfg.get_value("text", "speed", -1)) == GameSettingsScript.TextSpeed.FAST)

	# 主音量：默认 70，+ 一次到 80
	var up_btn := ss.find_child("settings_volume_up", true, false) as Button
	check("音量 + 存在", up_btn != null)
	if up_btn != null:
		up_btn.pressed.emit()
	await process_frame
	check("主音量 +10 即时生效", GameSettingsScript.volume == 80,
		str(GameSettingsScript.volume))

	# 全屏 / 窗口尺寸
	var full_btn := ss.find_child("settings_mode_fullscreen", true, false) as Button
	if full_btn != null:
		full_btn.pressed.emit()
	await process_frame
	check("全屏选项写入设置", GameSettingsScript.fullscreen)
	var size_btn := ss.find_child("settings_size_1", true, false) as Button
	if size_btn != null:
		size_btn.pressed.emit()
	await process_frame
	check("选尺寸会切回窗口并记住预设",
		not GameSettingsScript.fullscreen and GameSettingsScript.window_preset == 1)

	# 瞬间文字：下一帧直接补全，不受 char_ms 限制
	GameSettingsScript.text_speed = GameSettingsScript.TextSpeed.INSTANT
	var tw: TypewriterLabel = TypewriterLabelScript.new()
	tw.configure("瞬间文本", TecTheme.FS_BODY, TecTheme.TEXT)
	root.add_child(tw)
	tw.start_typing("瞬间文本")
	await process_frame
	await process_frame
	check("瞬间文字下一帧补全", not tw.is_typing() and tw.visible_characters == -1)
	tw.queue_free()

	# 恢复默认
	var reset_btn := ss.find_child("dialog_btn_恢复默认", true, false) as Button
	if reset_btn != null:
		reset_btn.pressed.emit()
	await process_frame
	check("恢复默认",
		GameSettingsScript.volume == GameSettingsScript.DEFAULT_VOLUME
			and GameSettingsScript.text_speed == GameSettingsScript.TextSpeed.NORMAL
			and not GameSettingsScript.fullscreen and GameSettingsScript.window_preset == -1)

	# 写盘 -> 清空内存 -> 回读
	GameSettingsScript.volume = 30
	GameSettingsScript.text_speed = GameSettingsScript.TextSpeed.SLOW
	GameSettingsScript.fullscreen = true
	GameSettingsScript.window_preset = 2
	GameSettingsScript.save_settings()
	GameSettingsScript.reset_defaults()
	GameSettingsScript.load_settings()
	check("设置可从文件回读",
		GameSettingsScript.volume == 30
			and GameSettingsScript.text_speed == GameSettingsScript.TextSpeed.SLOW
			and GameSettingsScript.fullscreen and GameSettingsScript.window_preset == 2)

	ss.queue_free()
	await process_frame
	_finish()


func _remove_cfg() -> void:
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))


func _cleanup() -> void:
	_remove_cfg()
	GameSettingsScript.config_path = GameSettingsScript.CONFIG_PATH
	GameSettingsScript.reset_defaults()
	GameSettingsScript.apply_audio()
