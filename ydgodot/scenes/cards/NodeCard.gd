class_name NodeCard
extends Control
## 画布上的一个节点卡片。
##
## 视觉：柔和浮雕表面（surface.gdshader）+ 标题/副标题两行；与 Web 版 `.node` 同尺寸口径
## （场景 152×54、实体 130×46，圆角 11，1px 发丝描边）。
## 交互：**拖动 = 移动 / 组合**，**双击 = 激活**（手电筒开关灯；场景展开留给 Desktop 决定）。

signal activated(key: String)
signal combo_requested(tool_key: String, target_key: String)
signal selected(key: String)
signal dragged(key: String)
signal drag_released(key: String, at_global: Vector2)

const PAD := 8.0
const DRAG_THRESHOLD := 5.0

const SYMBOL := {"loc": "■ ", "item": "□ ", "char": "● ", "clue": "▲ ", "time": "◆ "}
const KIND_NAME := {"loc": "场景", "item": "物品", "char": "人物", "clue": "线索", "time": "时刻"}

var card_key: String = ""
var kind: String = ""
var node_data: Dictionary = {}

var _mat: ShaderMaterial
var _bg: ColorRect
var _title: Label
var _sub: Label
var _hover := false
var _dragging := false
var _moved := false
var _pressed := false
var _press := Vector2.ZERO
var _grab := Vector2.ZERO
var _home := Vector2.ZERO


func setup(p_key: String, p_kind: String, p_data: Dictionary, w: float, h: float) -> void:
	card_key = p_key
	kind = p_kind
	node_data = p_data
	size = Vector2(w + PAD * 2.0, h + PAD * 2.0)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build(w, h)


func _build(w: float, h: float) -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://ui/shaders/surface.gdshader")
	_mat.set_shader_parameter("rect_size", Vector2(w + PAD * 2.0, h + PAD * 2.0))
	_mat.set_shader_parameter("pad", PAD)
	_mat.set_shader_parameter("radius", float(TecTheme.R_SM))
	_mat.set_shader_parameter("shade_soft", 7.0)

	_bg = ColorRect.new()
	_bg.name = "bg"
	_bg.material = _mat
	_bg.color = Color.WHITE
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_title = TecTheme.label("", 12, TecTheme.TEXT)
	_title.name = "title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	_sub = TecTheme.label("", TecTheme.FS_SMALL, TecTheme.FAINT)
	_sub.name = "sub"
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sub)

	_title.position = Vector2(PAD + 6.0, PAD + h * 0.5 - 16.0)
	_title.size = Vector2(w - 12.0, 20.0)
	_sub.position = Vector2(PAD + 6.0, PAD + h * 0.5 + 4.0)
	_sub.size = Vector2(w - 12.0, 14.0)

	refresh()


func refresh() -> void:
	var sym: String = SYMBOL.get(kind, "")
	_title.text = sym + String(node_data.get("label", card_key))
	_sub.text = String(KIND_NAME.get(kind, kind))
	if kind == "item" and bool(node_data.get("lit", false)):
		_sub.text = "物品 · 亮着"
	if kind == "loc":
		_sub.text = "场景"
	if kind == "clue" and bool(node_data.get("captured", false)):
		_sub.text = "线索 · 已捕获"


func set_home(p: Vector2) -> void:
	_home = p
	position = p


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_press = event.global_position
			_grab = position
			_moved = false
			_dragging = false
			move_to_front()
			selected.emit(card_key)
			accept_event()
		else:
			_pressed = false
			if _dragging:
				_dragging = false
				drag_released.emit(card_key, event.global_position)
				var target := _card_under(event.global_position)
				if target != "" and target != card_key:
					combo_requested.emit(card_key, target)
					_sync_home()
				else:
					_home = position
			elif not _moved:
				activated.emit(card_key)
			accept_event()
	elif event is InputEventMouseMotion:
		if _pressed and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			var delta: Vector2 = event.global_position - _press
			if not _dragging and delta.length() > DRAG_THRESHOLD:
				_dragging = true
				_moved = true
				dragged.emit(card_key)
			if _dragging:
				position = _grab + delta
				accept_event()


## 松手时指针下面是哪张卡（排除自己）
func _card_under(global_pos: Vector2) -> String:
	var parent := get_parent()
	if parent == null:
		return ""
	for c in parent.get_children():
		if c == self or not (c is NodeCard):
			continue
		if (c as NodeCard).get_global_rect().grow(-PAD * 0.5).has_point(global_pos):
			return (c as NodeCard).card_key
	return ""


func _sync_home() -> void:
	_home = position


func is_dragging() -> bool:
	return _dragging


func set_hover_state(on: bool) -> void:
	if _hover == on:
		return
	_hover = on
	if _mat != null:
		_mat.set_shader_parameter("shade_soft", 10.0 if on else 7.0)
