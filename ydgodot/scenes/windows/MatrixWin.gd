class_name MatrixWin
extends SysWindow
## 推演桌布（对齐 Web 版 13-matrix.js 的 .infer-win / .mx-board）
##
## 五感锚点环绕中央执行者，归位的线索按感官叠在锚点下方；
## 外圆 + 五芒星构成逻辑阵列，长按执行者 2.5 秒描线并触发推演。
## 线索卡可拖出桌布 / 双击取回画布。

signal clue_dropped(key: String, at_global: Vector2)
signal clue_taken(key: String)
signal inference_requested
signal seed_dropped(at_global: Vector2)

const BOARD_W := 560.0
const BOARD_H := 420.0
const RITE_SEC := 2.5
const CHIP_W := 120.0
const CHIP_H := 42.0
const CIRCLE_R := 195.0
const STAR_ORDER := ["vision", "touch", "taste", "hearing", "smell"]
const ANCHORS := {
	"vision": Vector2(0.5000, 0.0192),
	"hearing": Vector2(0.7971, 0.3073),
	"touch": Vector2(0.6840, 0.7727),
	"smell": Vector2(0.3160, 0.7727),
	"taste": Vector2(0.2029, 0.3073),
}
## 推演阵列的几何骨架（虚线圆 / 虚线连线 / 点亮五边形的实线）。
## 原来是朱红 `#c0392b` —— 整屏唯一的彩色，在纯白桌布上像一根天线。
## 1-bit 里「错误 / 试错」由**线型**承担：虚线（0.42 alpha 的黑虚线 = 浅灰虚线）。
## 变量名保留 RED 以免大改调用点，但值已是墨黑。
const RED := TecTheme.INK
const AvatarFrameScript = preload("res://ui/AvatarFrame.gd")

var graph: GraphState
var case_def: CaseLoader

var _board: Control
var _chip_layer: Control
var _exec: Control
var _emote: PanelContainer = null
var _seed_pop: PanelContainer = null
var _hint: Label
var _chips: Dictionary = {}          # clue id -> PanelContainer
var _charging := false
var _charge := 0.0
var _rite_duration := RITE_SEC
var _pressed_chip := ""
var _chip_press := Vector2.ZERO
var _chip_moved := false
var _seed_dragging := false
var _seed_press := Vector2.ZERO
var _seed_grab := Vector2.ZERO
var _seed_moved := false

## 线索卡拖动（Web `makeMatrixNodeDraggable`）：原件留在原位当锚，跟着指针的是镜像。
## 镜像必须挂在桌布外面 —— `_board` 是 clip_contents，挂在里面拖到边缘就被裁掉。
var drag_host: Control = null
var _drag_chip: PanelContainer = null
var _drag_mirror: PanelContainer = null
var _drag_off := Vector2.ZERO


func setup_matrix(p_graph: GraphState, p_case: CaseLoader) -> void:
	graph = p_graph
	case_def = p_case
	var fast := OS.get_cmdline_args().has("--fast") or OS.get_cmdline_user_args().has("--fast")
	setup("逻辑阵列", 580, 476)
	_rite_duration = 0.08 if fast else RITE_SEC
	body.clip_contents = true

	_board = Control.new()
	_board.name = "mx_board"
	_board.position = Vector2.ZERO
	_board.size = Vector2(BOARD_W, BOARD_H)
	_board.clip_contents = true
	_board.mouse_filter = Control.MOUSE_FILTER_PASS
	_board.draw.connect(_draw_board)
	body.add_child(_board)

	_chip_layer = Control.new()
	_chip_layer.name = "chips"
	_chip_layer.size = _board.size
	_chip_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	_board.add_child(_chip_layer)

	_build_executor()
	_build_seed_pop()

	_hint = TecTheme.label("长按执行者蓄力推演 · 双击 / 拖出桌布取回线索", TecTheme.FS_BODY, TecTheme.MUTED)
	_hint.position = Vector2(12, BOARD_H - 20)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(_hint)

	refresh_matrix()


func _build_executor() -> void:
	_exec = Control.new()
	_exec.name = "mx_exec"
	_exec.size = Vector2(84, 84)
	_exec.position = Vector2(BOARD_W * 0.5 - 42.0, BOARD_H * 0.5 - 42.0)
	_exec.mouse_filter = Control.MOUSE_FILTER_STOP
	_exec.tooltip_text = "长按 2.5 秒激活归因"
	_exec.gui_input.connect(_on_exec_input)
	_board.add_child(_exec)

	var frame := AvatarFrameScript.new()
	frame.name = "frame"
	frame.position = Vector2(6, 6)
	frame.setup("res://assets/raw/executor-avatar.png", 72.0, "E")
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_exec.add_child(frame)


func _build_seed_pop() -> void:
	_seed_pop = PanelContainer.new()
	_seed_pop.name = "mx_seedpop"
	_seed_pop.size = Vector2(44, 44)
	_seed_pop.position = _seed_home()
	_seed_pop.mouse_filter = Control.MOUSE_FILTER_STOP
	_seed_pop.tooltip_text = "真名留下的种子 · 拖进花园"
	var sb := TecTheme.flat(TecTheme.CARD, TecTheme.R_SM, TecTheme.EDGE, 1)
	_seed_pop.add_theme_stylebox_override("panel", sb)
	var img := TextureRect.new()
	img.name = "seed"
	img.texture = load("res://assets/raw/flower/plant_seed.png")
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	img.offset_left = 5
	img.offset_top = 5
	img.offset_right = -5
	img.offset_bottom = -5
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seed_pop.add_child(img)
	_seed_pop.gui_input.connect(_on_seed_input)
	_board.add_child(_seed_pop)
	refresh_seed()


func _seed_home() -> Vector2:
	return Vector2(BOARD_W * 0.5 - 22.0, BOARD_H * 0.5 - 42.0 - 52.0)


func refresh_seed() -> void:
	if _seed_pop == null or not is_instance_valid(_seed_pop):
		return
	var has := graph != null and graph.garden is Dictionary and bool(graph.garden.get("seed", false))
	_seed_pop.visible = has
	if has:
		_seed_pop.position = _seed_home()
		_seed_pop.modulate = Color.WHITE


func _on_seed_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_seed_dragging = true
			_seed_moved = false
			_seed_press = event.global_position
			_seed_grab = _seed_pop.global_position
			_seed_pop.move_to_front()
		else:
			if not _seed_dragging:
				return
			_seed_dragging = false
			if _seed_moved:
				seed_dropped.emit(event.global_position)
				if _seed_pop.visible:
					_snap_seed_home()
			else:
				_bounce_seed()
		return
	if event is InputEventMouseMotion and _seed_dragging:
		if event.global_position.distance_to(_seed_press) > 3.0:
			_seed_moved = true
		if _seed_moved:
			_seed_pop.global_position = _seed_grab + (event.global_position - _seed_press)


func _snap_seed_home() -> void:
	var t := create_tween()
	t.tween_property(_seed_pop, "position", _seed_home(), 0.16).set_ease(Tween.EASE_OUT)


func _bounce_seed() -> void:
	var home := _seed_home()
	var t := create_tween()
	t.tween_property(_seed_pop, "position", home + Vector2(0, -5), 0.08)
	t.tween_property(_seed_pop, "position", home, 0.1)


# ── 渲染 ────────────────────────────────────────────────────────────────

func refresh_matrix() -> void:
	if _chip_layer == null:
		return
	_cancel_chip_drag()          # 重排会重建 chip，拖动中的镜像与原件引用都得先放掉
	for child in _chip_layer.get_children():
		_chip_layer.remove_child(child)
		child.queue_free()
	_chips.clear()
	for sense in GraphState.SENSES:
		var list: Array = graph.matrix.get(sense, [])
		var anchor: Vector2 = ANCHORS[sense]
		var ax := anchor.x * BOARD_W
		var ay := anchor.y * BOARD_H
		for i in list.size():
			var cid := String(list[i])
			var chip := _make_chip(cid, ax, ay + i * (CHIP_H + 4.0))
			_chip_layer.add_child(chip)
			_chips[cid] = chip
	_board.queue_redraw()


func _make_chip(cid: String, ax: float, ay: float) -> PanelContainer:
	var key := graph.key_of("clue", cid)
	var n := graph.node(key)
	var chip := PanelContainer.new()
	chip.name = "chip_" + cid
	chip.position = Vector2(ax - CHIP_W * 0.5, ay)
	chip.size = Vector2(CHIP_W, CHIP_H)
	chip.custom_minimum_size = Vector2(CHIP_W, CHIP_H)
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.tooltip_text = "双击 = 取回画布；拖出桌布 = 取回；拖到线索册 = 收进册子"
	var sb := TecTheme.flat(TecTheme.CARD, TecTheme.R_SM, TecTheme.EDGE, 1)
	chip.add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(col)

	var title := TecTheme.label(String(n.get("label", cid)), TecTheme.FS_BODY, TecTheme.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title)

	var sub := TecTheme.label("线索 · 已归位", TecTheme.FS_BODY, TecTheme.MUTED)
	if not bool(n.get("captured", false)):
		sub.text = "线索"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sub)

	chip.gui_input.connect(_on_chip_input.bind(key, chip))
	return chip


func _draw_board() -> void:
	_board.draw_rect(Rect2(Vector2.ZERO, _board.size), TecTheme.BG)
	var center := Vector2(BOARD_W * 0.5, BOARD_H * 0.5)
	_draw_dashed_circle(center, CIRCLE_R, Color(RED, 0.42), 1.25)
	var pts := _star_points()
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		_board.draw_dashed_line(a, b, Color(RED, 0.42), 1.25, 5.0, true, true)
	if _charge > 0.0:
		_draw_rite(center, pts)


func _star_points() -> Array:
	var out: Array = []
	for sense in STAR_ORDER:
		var a: Vector2 = ANCHORS[sense]
		out.append(Vector2(a.x * BOARD_W, a.y * BOARD_H + 27.0))
	return out


func _draw_dashed_circle(center: Vector2, radius: float, color: Color, width: float) -> void:
	var steps := 72
	var prev := center + Vector2(radius, 0)
	for i in range(1, steps + 1):
		var ang := TAU * float(i) / float(steps)
		var cur := center + Vector2(cos(ang), sin(ang)) * radius
		_board.draw_dashed_line(prev, cur, color, width, 4.0, true, true)
		prev = cur


## 蓄力描线：先外圆、再五芒星，按 2.5 秒匀速走完整条路径（Web 的 pathLength=100 同款）
func _draw_rite(center: Vector2, pts: Array) -> void:
	var circumference := TAU * CIRCLE_R
	var star_len := 0.0
	for i in pts.size():
		star_len += (pts[i] as Vector2).distance_to(pts[(i + 1) % pts.size()])
	var remain := clampf(_charge, 0.0, 1.0) * (circumference + star_len)

	if remain > 0.0:
		var steps := 96
		var prev := center + Vector2(CIRCLE_R, 0)
		var lit := PackedVector2Array([prev])
		var done := 0.0
		for i in range(1, steps + 1):
			var ang := TAU * float(i) / float(steps)
			var cur := center + Vector2(cos(ang), sin(ang)) * CIRCLE_R
			var seg := prev.distance_to(cur)
			if done + seg >= remain:
				var t := (remain - done) / maxf(seg, 0.0001)
				lit.append(prev.lerp(cur, t))
				done = remain
				break
			lit.append(cur)
			done += seg
			prev = cur
		if lit.size() >= 2:
			_board.draw_polyline(lit, RED, 1.75, true)
		remain -= done

	if remain > 0.0:
		var star_points := PackedVector2Array()
		for i in pts.size():
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			if star_points.is_empty():
				star_points.append(a)
			var seg := a.distance_to(b)
			if remain <= seg:
				star_points.append(a.lerp(b, remain / maxf(seg, 0.0001)))
				remain = 0.0
				break
			star_points.append(b)
			remain -= seg
			if remain <= 0.0:
				break
		if star_points.size() >= 2:
			_board.draw_polyline(star_points, RED, 1.75, true)


# ── 交互：线索卡 ────────────────────────────────────────────────────────

func _on_chip_input(event: InputEvent, key: String, chip: PanelContainer) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.double_click:
				clue_taken.emit(key)
				_pressed_chip = ""
				return
			_pressed_chip = key
			_chip_press = event.global_position
			_chip_moved = false
			accept_event()
		else:
			if _pressed_chip == key:
				_finish_chip_drag(event.global_position)
			_pressed_chip = ""
			_chip_moved = false
			accept_event()
	elif event is InputEventMouseMotion and _pressed_chip == key:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			return
		var at: Vector2 = (event as InputEventMouseMotion).global_position
		if not _chip_moved and (at - _chip_press).length() > 5.0:
			_chip_moved = true
			_begin_chip_drag(key, at, chip)
		if _chip_moved:
			_move_chip_mirror(at)
		accept_event()


## ── 线索卡拖动：镜像跟手（Web 里克隆到 #drag-layer，原件 visibility:hidden）──

func _begin_chip_drag(key: String, at: Vector2, chip: PanelContainer) -> void:
	if chip == null or not is_instance_valid(chip):
		return
	if drag_host == null:
		# 没有注入宿主（单元测试直接喂事件）：仍然标记在拖，只是不出镜像
		_drag_chip = chip
		return
	_drag_chip = chip
	var rect := chip.get_global_rect()
	_drag_off = at - rect.position
	var m := chip.duplicate() as PanelContainer
	if m == null:
		return
	_strip_chip_input(m)
	drag_host.add_child(m)
	m.size = chip.size
	m.scale = chip.get_global_transform().get_scale()
	m.global_position = rect.position
	m.z_index = 40                      # 与 Desktop 的 ZR_MIRROR 同档：桌面最高层
	_drag_mirror = m
	# 原件让位但不隐藏：隐藏会被 GUI 命中判定剔除，后续 motion 就收不到了
	# （与画布卡片同一个坑，见 NodeCard.set_ghost 的注释）
	chip.modulate.a = 0.0


func _move_chip_mirror(at: Vector2) -> void:
	if _drag_mirror == null or not is_instance_valid(_drag_mirror):
		return
	_drag_mirror.global_position = at - _drag_off


## 松手：只有「拖出桌布」才有动作 —— 桌布内松手 = 归位（原件本来就没动过）
func _finish_chip_drag(at: Vector2) -> void:
	var key := _pressed_chip
	var moved := _chip_moved
	_cancel_chip_drag()
	if not moved or key == "":
		return
	if not _board.get_global_rect().has_point(at):
		clue_dropped.emit(key, at)


## 摘镜像 / 原件恢复 / 会话清零。重排（refresh_matrix）打断拖动时也走这里。
func _cancel_chip_drag() -> void:
	if _drag_mirror != null and is_instance_valid(_drag_mirror):
		_drag_mirror.queue_free()
	_drag_mirror = null
	if _drag_chip != null and is_instance_valid(_drag_chip):
		_drag_chip.modulate.a = 1.0
	_drag_chip = null
	_pressed_chip = ""
	_chip_moved = false


func _strip_chip_input(n: Node) -> void:
	var c := n as Control
	if c != null:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in n.get_children():
		_strip_chip_input(ch)


# ── 交互：长按执行者 ────────────────────────────────────────────────────

func _on_exec_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			start_charge()
		else:
			cancel_charge()


func start_charge() -> void:
	if _charging:
		return
	_charging = true
	_charge = 0.0
	set_process(true)
	_board.queue_redraw()


func cancel_charge() -> void:
	if not _charging:
		return
	_charging = false
	_charge = 0.0
	set_process(false)
	_board.queue_redraw()


func finish_charge() -> void:
	_charging = false
	_charge = 1.0
	set_process(false)
	_board.queue_redraw()
	inference_requested.emit()


func _process(delta: float) -> void:
	if not _charging:
		return
	_charge += delta / maxf(_rite_duration, 0.001)
	if _charge >= 1.0:
		_charge = 1.0
		_charging = false
		set_process(false)
		_board.queue_redraw()
		inference_requested.emit()
		return
	_board.queue_redraw()


# ── 反馈 ────────────────────────────────────────────────────────────────

func show_heartbroken() -> void:
	if _exec == null:
		return
	if _emote != null and is_instance_valid(_emote):
		_emote.queue_free()
	var pop := PanelContainer.new()
	pop.name = "mx_emote"
	pop.position = Vector2(19, -54)
	pop.size = Vector2(46, 46)
	pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := TecTheme.flat(TecTheme.CARD, TecTheme.R_SM, TecTheme.EDGE, 1)
	pop.add_theme_stylebox_override("panel", sb)
	var img := TextureRect.new()
	img.texture = load("res://assets/raw/emote-heartbroken.png")
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pop.add_child(img)
	_exec.add_child(pop)
	_emote = pop
	var t := create_tween()
	t.tween_interval(1.1)
	t.tween_property(pop, "modulate:a", 0.0, 0.3)
	t.tween_callback(func():
		if _emote == pop:
			_emote = null
		pop.queue_free())


func play_shock() -> void:
	var base := position
	var t := create_tween()
	for off in [Vector2(-4, 3), Vector2(4, -3), Vector2(-3, 2), Vector2(3, -2), Vector2(-2, 1), Vector2(2, -1)]:
		t.tween_property(self, "position", base + off, 0.055)
	t.tween_property(self, "position", base, 0.1)


# ── 查询（测试 / Desktop 用）────────────────────────────────────────────

func board_global_rect() -> Rect2:
	return _board.get_global_rect()


func chip_count(sense: String = "") -> int:
	if sense == "":
		return _chips.size()
	var list: Array = graph.matrix.get(sense, [])
	return list.size()


func chip_keys() -> Array:
	return _chips.keys()


func has_chip(id: String) -> bool:
	return _chips.has(id)


func emote_visible() -> bool:
	return _emote != null and is_instance_valid(_emote)


func charge_ratio() -> float:
	return _charge


func is_charging() -> bool:
	return _charging


func seed_visible() -> bool:
	return _seed_pop != null and is_instance_valid(_seed_pop) and _seed_pop.visible


func seed_global_rect() -> Rect2:
	if _seed_pop == null or not is_instance_valid(_seed_pop):
		return Rect2()
	return _seed_pop.get_global_rect()


func dbg_drop_seed(at_global: Vector2) -> void:
	if seed_visible():
		seed_dropped.emit(at_global)
