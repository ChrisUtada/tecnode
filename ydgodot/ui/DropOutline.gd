class_name DropOutline
extends Control
## 拖拽落点统一描边：一层虚线框，盖在所有窗口 / 图标之上。
## 只画框，不参与命中；宿主负责把目标矩形换算成 desk 局部坐标后交进来。

const DASH := 6.0
const WIDTH := 2.0

var _outline := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func show_rect(rect: Rect2) -> void:
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		clear_outline()
		return
	_outline = rect
	visible = true
	queue_redraw()


func clear_outline() -> void:
	_outline = Rect2()
	visible = false
	queue_redraw()


func outline_rect() -> Rect2:
	return _outline


func _draw() -> void:
	if _outline.size.x <= 1.0 or _outline.size.y <= 1.0:
		return
	var r := _outline
	var col := TecTheme.LINE
	draw_dashed_line(Vector2(r.position.x, r.position.y),
		Vector2(r.end.x, r.position.y), col, WIDTH, DASH, true, false)
	draw_dashed_line(Vector2(r.position.x, r.end.y),
		Vector2(r.end.x, r.end.y), col, WIDTH, DASH, true, false)
	draw_dashed_line(Vector2(r.position.x, r.position.y),
		Vector2(r.position.x, r.end.y), col, WIDTH, DASH, true, false)
	draw_dashed_line(Vector2(r.end.x, r.position.y),
		Vector2(r.end.x, r.end.y), col, WIDTH, DASH, true, false)
