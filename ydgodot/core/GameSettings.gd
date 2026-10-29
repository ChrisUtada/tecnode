class_name GameSettings
extends RefCounted
## 启动设置：显示 / 主音量 / 文字速度。
##
## 存在 `user://settings.cfg`，开始页的设置面板改一项就写一次盘；
## 下次启动由 Desktop 在读窗口尺寸之前载入，保证全屏 / 分辨率预设先于布局生效。
##
## 为什么不放更多：本作是单色 1-bit、纯鼠标、单语言、自动存档，
## 画质 / 按键 / 语言暂时没有可调项。设置页只保留真正改变体验的三组。

const CONFIG_PATH := "user://settings.cfg"
const DEFAULT_VOLUME := 70

## 窗口尺寸预设。`-1` 表示「适应屏幕」——铺满当前屏幕可用区（旧版默认行为）。
const WINDOW_PRESETS := [
	{"label": "1280×720", "size": Vector2i(1280, 720)},
	{"label": "1600×900", "size": Vector2i(1600, 900)},
	{"label": "1920×1080", "size": Vector2i(1920, 1080)},
]

## 文字速度：相对 TypewriterLabel 默认 45ms/字的倍率；瞬间 = 0。
const TEXT_SPEEDS := ["慢", "标准", "快", "瞬间"]
const TEXT_SPEED_FACTORS := [1.6, 1.0, 0.55, 0.0]
enum TextSpeed { SLOW, NORMAL, FAST, INSTANT }

static var config_path := CONFIG_PATH
static var fullscreen := false
static var window_preset := -1
static var volume := DEFAULT_VOLUME
static var text_speed := TextSpeed.NORMAL


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return
	fullscreen = bool(cfg.get_value("display", "fullscreen", false))
	window_preset = clampi(int(cfg.get_value("display", "window_preset", -1)),
		-1, WINDOW_PRESETS.size() - 1)
	volume = clampi(int(cfg.get_value("audio", "volume", DEFAULT_VOLUME)), 0, 100)
	text_speed = clampi(int(cfg.get_value("text", "speed", TextSpeed.NORMAL)),
		0, TEXT_SPEEDS.size() - 1)


static func save_settings() -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "window_preset", window_preset)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("text", "speed", text_speed)
	return cfg.save(config_path)


## 只重置内存值；需要落盘时由调用方再 `save_settings()`。
static func reset_defaults() -> void:
	fullscreen = false
	window_preset = -1
	volume = DEFAULT_VOLUME
	text_speed = TextSpeed.NORMAL


static func window_preset_size() -> Vector2i:
	if window_preset < 0 or window_preset >= WINDOW_PRESETS.size():
		return Vector2i.ZERO
	return WINDOW_PRESETS[window_preset]["size"]


static func text_speed_factor() -> float:
	return float(TEXT_SPEED_FACTORS[clampi(text_speed, 0, TEXT_SPEED_FACTORS.size() - 1)])


static func apply_audio() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	if volume <= 0:
		AudioServer.set_bus_mute(bus, true)
		return
	AudioServer.set_bus_mute(bus, false)
	AudioServer.set_bus_volume_db(bus, linear_to_db(float(volume) / 100.0))


## 把设置里的显示模式与窗口尺寸落到实际窗口。无头测试不改 DisplayServer。
static func apply_display(win: Window) -> void:
	if win == null or DisplayServer.get_name() == "headless":
		return
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	if fullscreen:
		win.mode = Window.MODE_FULLSCREEN
		return
	win.mode = Window.MODE_WINDOWED
	var usable := DisplayServer.screen_get_usable_rect()
	var target := window_preset_size()
	if target == Vector2i.ZERO:
		target = usable.size
	## 预设比当前屏幕可用区还大时先夹到可用区（例如 1920×1080 屏去掉任务栏只剩
	## 1920×1032），否则窗口会顶出屏幕、标题栏抓不到。
	target.x = mini(target.x, usable.size.x)
	target.y = mini(target.y, usable.size.y)
	target.x = maxi(target.x, win.min_size.x)
	target.y = maxi(target.y, win.min_size.y)
	win.position = usable.position + (usable.size - target) / 2
	win.size = target
