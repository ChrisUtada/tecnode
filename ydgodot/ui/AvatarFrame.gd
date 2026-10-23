extends PanelContainer
## B1：彩色头像只允许装在统一的「档案照」容器里。
## 方角 · 1px INK 键线 · BG 灰青打底；纹理本身不铺出框外。

var art: TextureRect
var initial: Label


func setup(path: String, px: float, fallback: String = "", fallback_color: Color = TecTheme.MUTED) -> void:
	custom_minimum_size = Vector2(px, px)
	size = Vector2(px, px)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", TecTheme.flat(TecTheme.BG, 0, TecTheme.EDGE, 1))
	if path != "" and ResourceLoader.exists(path):
		art = TextureRect.new()
		art.name = "art"
		art.texture = load(path)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(art)
		return
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var isize := TecTheme.FS_TITLE if px <= 32.0 else TecTheme.FS_DISPLAY
	initial = TecTheme.label(fallback, isize, fallback_color)
	initial.name = "ini"
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(initial)
