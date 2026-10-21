class_name GardenWin
extends SysWindow
## 花园窗（对齐 Web 版 16-cases.js / 13-matrix.js 的花园彩蛋）
##
## 无固定坛位：种子拖到哪儿就种在哪儿，原点可拖动。生长只认真实时间，
## 每 45s 一档；开花后点花逐段读结局说明。花开提示由 Desktop 负责弹 toast。

signal plant_placed(index: int)
signal plant_moved(index: int)
signal plot_bloomed(index: int, fresh: bool)
signal garden_changed

const WIN_W := 520.0
const FIELD_H := 260.0
const PLANT_W := 92.0
const PLANT_H := 112.0
const BASE_INNER_H := 360.0

var graph: GraphState
var case_def: CaseLoader

var _field: Control
var _hint: Label
var _plants: Array[Control] = []
var _narr: PanelContainer
var _narr_idx := -1
var _narr_shown := 0
var _drag_idx := -1
var _drag_moved := false
var _tick := 0.0


func setup_garden(p_graph: GraphState, p_case: CaseLoader = null) -> void:
	graph = p_graph
	case_def = p_case
	setup("GARDEN // 花园", WIN_W, BASE_INNER_H)
	enable_controls("", "关闭花园（生长照旧）", false)
	_build_content()
	refresh()
	set_inner_height(BASE_INNER_H)


func _build_content() -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(head)
	var t := TecTheme.label("真名留下的东西", TecTheme.FS_BODY, TecTheme.MUTED)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(t)
	var note := TecTheme.label("种子：拖进花圃", TecTheme.FS_BODY, TecTheme.MUTED)
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(note)

	_field = Control.new()
	_field.name = "garden_field"
	_field.custom_minimum_size = Vector2(0, FIELD_H)
	_field.size = Vector2(body.size.x, FIELD_H)
	_field.mouse_filter = Control.MOUSE_FILTER_PASS
	var bg := Panel.new()
	bg.name = "field_bg"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", TecTheme.flat(TecTheme.BG, 10, TecTheme.EDGE_SOFT, 1))
	_field.add_child(bg)
	content.add_child(_field)

	_hint = TecTheme.label("把种子拖到这里", TecTheme.FS_TITLE, TecTheme.MUTED)
	_hint.name = "garden_hint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.position = Vector2(0, FIELD_H * 0.5 - 12)
	_hint.size = Vector2(body.size.x, 24)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.add_child(_hint)


func refresh() -> void:
	if graph == null or _field == null:
		return
	if _drag_idx < 0:
		_rebuild_plants()
		return
	var plots := _plot_list()
	if _drag_idx >= plots.size():
		_drag_idx = -1
		_rebuild_plants()


func _plot_list() -> Array:
	if graph == null:
		return []
	GardenSystem.normalize(graph, case_def)
	return graph.garden["plots"] as Array


func _rebuild_plants() -> void:
	for p in _plants:
		if is_instance_valid(p):
			p.queue_free()
	_plants.clear()
	var plots := _plot_list()
	var seed := bool(graph.garden.get("seed", false))
	_hint.visible = plots.is_empty()
	if plots.is_empty():
		_hint.text = "把种子拖到这里" if seed else "还没有种子。走到真名的尽头，再回来。"
	for i in plots.size():
		var plot: Dictionary = plots[i]
		var plant := _make_plant(i, plot)
		_field.add_child(plant)
		_plants.append(plant)
	if _narr_idx >= plots.size():
		_close_narr(true)
	_fit_height()


func _make_plant(idx: int, plot: Dictionary) -> Control:
	var p := Control.new()
	p.name = "plant_%d" % idx
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.tooltip_text = "拖动可换位置" + (" · 点击花朵阅读" if GardenSystem.is_bloomed(plot) else "")
	p.size = Vector2(PLANT_W, PLANT_H)
	p.position = _plot_pos(plot)
	p.gui_input.connect(func(ev): _on_plant_input(ev, idx))

	var img := TextureRect.new()
	img.name = "img"
	var path: String = GardenSystem.STAGE_IMAGES[GardenSystem.stage_of(plot)]
	img.texture = load(path) if ResourceLoader.exists(path) else null
	img.position = Vector2(14, 0)
	img.size = Vector2(64, 64)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(img)

	var st := GardenSystem.stage_of(plot)
	var bloom := st >= 4
	var chip := PanelContainer.new()
	chip.name = "stage"
	chip.position = Vector2(10, 66)
	chip.size = Vector2(72, 20)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel",
		TecTheme.flat(TecTheme.LINE if bloom else TecTheme.CARD, 6,
			TecTheme.EDGE if bloom else TecTheme.EDGE_SOFT, 1))
	p.add_child(chip)
	var lab := TecTheme.label(GardenSystem.STAGE_NAMES[st], TecTheme.FS_BODY,
		TecTheme.TEXT if bloom else TecTheme.MUTED)
	lab.name = "Label"
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(lab)

	if not bloom:
		var bar := ProgressBar.new()
		bar.name = "growth"
		bar.position = Vector2(10, 90)
		bar.size = Vector2(72, 7)
		bar.min_value = 0
		bar.max_value = 100
		bar.value = GardenSystem.progress_of(plot) * 100.0
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_theme_stylebox_override("background", TecTheme.flat(TecTheme.FACE_LO, 3, TecTheme.FACE_LO, 0))
		bar.add_theme_stylebox_override("fill", TecTheme.flat(TecTheme.LINE, 3, TecTheme.LINE, 0))
		p.add_child(bar)
	else:
		var more := TecTheme.label("点击花朵", TecTheme.FS_BODY, TecTheme.LINE)
		more.position = Vector2(0, 88)
		more.size = Vector2(PLANT_W, 16)
		more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		more.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(more)
	return p


func _plot_pos(plot: Dictionary) -> Vector2:
	return Vector2(
		float(plot.get("x", GardenSystem.DEFAULT_X)) / 100.0 * _field.size.x - PLANT_W * 0.5,
		float(plot.get("y", GardenSystem.DEFAULT_Y)) / 100.0 * _field.size.y - PLANT_H * 0.5)


func spot_of_global(at: Vector2) -> Dictionary:
	var r := _field.get_global_rect()
	var x := (at.x - r.position.x) / maxf(r.size.x, 1.0) * 100.0
	var y := (at.y - r.position.y) / maxf(r.size.y, 1.0) * 100.0
	return GardenSystem.spot_of(x, y)


func field_global_rect() -> Rect2:
	return _field.get_global_rect() if _field != null else Rect2()


func plant_seed_at(at_global: Vector2) -> bool:
	if graph == null or _field == null:
		return false
	if not bool(graph.garden.get("seed", false)):
		return false
	var spot := spot_of_global(at_global)
	if not GardenSystem.plant(graph, float(spot["x"]), float(spot["y"])):
		return false
	GardenSystem.normalize(graph, case_def)
	_rebuild_plants()
	var idx := _plot_list().size() - 1
	plant_placed.emit(idx)
	garden_changed.emit()
	return true


func _on_plant_input(event: InputEvent, idx: int) -> void:
	var plots := _plot_list()
	if idx < 0 or idx >= plots.size():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_idx = idx
			_drag_moved = false
		else:
			if _drag_idx == idx:
				if not _drag_moved and GardenSystem.is_bloomed(plots[idx]):
					_toggle_narr(idx)
				elif _drag_moved:
					plant_moved.emit(idx)
					garden_changed.emit()
			_drag_idx = -1
		return
	if event is InputEventMouseMotion and _drag_idx == idx:
		if event.relative.length() > 2.0:
			_drag_moved = true
		if not _drag_moved:
			return
		var spot := spot_of_global(event.global_position)
		plots[idx]["x"] = spot["x"]
		plots[idx]["y"] = spot["y"]
		if idx < _plants.size() and is_instance_valid(_plants[idx]):
			_plants[idx].position = _plot_pos(plots[idx])


func _process(delta: float) -> void:
	if not visible or graph == null:
		return
	_tick += delta
	if _tick < 1.0:
		return
	_tick = 0.0
	var plots := _plot_list()
	var now := GardenSystem.now_ms_now()
	var dirty := false
	for i in plots.size():
		var plot: Dictionary = plots[i]
		if GardenSystem.is_bloomed(plot, now) and not bool(plot.get("hit", false)):
			plot["hit"] = true
			dirty = true
			var fresh := now - int(plot.get("at", now)) <= GardenSystem.BLOOM_FRESH_MS + GardenSystem.STAGE_MS[4]
			plot_bloomed.emit(i, fresh)
	if dirty:
		garden_changed.emit()
	if _drag_idx < 0:
		_refresh_growth()


func _refresh_growth() -> void:
	var plots := _plot_list()
	for i in mini(plots.size(), _plants.size()):
		var plot: Dictionary = plots[i]
		var plant := _plants[i]
		if not is_instance_valid(plant):
			continue
		var st := GardenSystem.stage_of(plot)
		var img: TextureRect = plant.get_node_or_null("img")
		var stage_path: String = GardenSystem.STAGE_IMAGES[st]
		if img != null and ResourceLoader.exists(stage_path):
			img.texture = load(stage_path)
		var chip: PanelContainer = plant.get_node_or_null("stage")
		if chip != null:
			chip.add_theme_stylebox_override("panel",
				TecTheme.flat(TecTheme.LINE if st >= 4 else TecTheme.CARD, 6,
					TecTheme.EDGE if st >= 4 else TecTheme.EDGE_SOFT, 1))
			var lab: Label = chip.get_node_or_null("Label")
			if lab != null:
				lab.text = GardenSystem.STAGE_NAMES[st]
				lab.add_theme_color_override("font_color", TecTheme.TEXT if st >= 4 else TecTheme.MUTED)
		var bar: ProgressBar = plant.get_node_or_null("growth")
		if bar != null:
			bar.value = GardenSystem.progress_of(plot) * 100.0
		if st >= 4:
			_rebuild_plants()
			return


func _toggle_narr(idx: int) -> void:
	if _narr_idx == idx and _narr != null:
		_close_narr(true)
		_fit_height()
		return
	var segs := _narr_segments()
	if segs.is_empty():
		return
	_narr_idx = idx
	_narr_shown = 1
	_rebuild_narr()
	_fit_height()


func _open_narr(idx: int) -> bool:
	var plots := _plot_list()
	if idx < 0 or idx >= plots.size():
		return false
	if not GardenSystem.is_bloomed(plots[idx]):
		return false
	var segs := _narr_segments()
	if segs.is_empty():
		return false
	_narr_idx = idx
	_narr_shown = 1
	_rebuild_narr()
	_fit_height()
	return true


func advance_narr() -> bool:
	var segs := _narr_segments()
	if _narr_idx < 0 or _narr_shown >= segs.size():
		return false
	_narr_shown += 1
	_rebuild_narr()
	_fit_height()
	return true


func close_narr() -> void:
	if _narr_idx >= 0:
		_close_narr(true)
		_fit_height()


func _close_narr(refit: bool) -> void:
	_narr_idx = -1
	_narr_shown = 0
	_drop_narr()
	if refit:
		_fit_height()


func _drop_narr() -> void:
	if _narr != null and is_instance_valid(_narr):
		if _narr.get_parent() != null:
			_narr.get_parent().remove_child(_narr)
		_narr.queue_free()
	_narr = null


func _narr_text() -> String:
	if graph == null or not (graph.garden is Dictionary):
		return ""
	return String(graph.garden.get("narr", ""))


func _narr_segments() -> Array:
	return GardenSystem.narr_segments(_narr_text())


func _rebuild_narr() -> void:
	_drop_narr()
	var segs := _narr_segments()
	if _narr_idx < 0 or segs.is_empty():
		return
	var shown := clampi(_narr_shown, 1, segs.size())
	var w := _field.size.x
	var panel := PanelContainer.new()
	panel.name = "garden_narr"
	panel.custom_minimum_size = Vector2(w, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel",
		TecTheme.flat(TecTheme.CARD, 8, TecTheme.EDGE_SOFT, 1))
	panel.gui_input.connect(func(ev): _on_narr_input(ev))
	content.add_child(panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	var t := TecTheme.label("花魄", TecTheme.FS_TITLE, TecTheme.TEXT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(t)
	var sub := TecTheme.label("真名 · 形成说明", TecTheme.FS_BODY, TecTheme.MUTED)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sub)
	var x := TecTheme.button("×")
	x.custom_minimum_size = Vector2(24, 22)
	x.size = Vector2(24, 22)
	x.add_theme_font_size_override("font_size", TecTheme.FS_BODY)
	x.pressed.connect(close_narr)
	head.add_child(x)

	for i in shown:
		var l := TecTheme.label(String(segs[i]), TecTheme.FS_TITLE, TecTheme.LINE)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(maxf(w - 28.0, 120.0), 0)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
	if shown < segs.size():
		var more := TecTheme.label("点一下 · 继续", TecTheme.FS_BODY, TecTheme.MUTED)
		more.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		more.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(more)

	_narr = panel
	panel.custom_minimum_size = Vector2(w, 0)
	panel.size = Vector2(w, panel.get_combined_minimum_size().y)


func _on_narr_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance_narr()


func _fit_height() -> void:
	if _field == null:
		return
	var content_h := content.get_combined_minimum_size().y
	var inner := maxf(BASE_INNER_H, content_h + 10.0 + BAR_H + 22.0)
	set_inner_height(inner)
	if position.y + size.y > 740.0:
		position.y = maxf(8.0, 740.0 - size.y)


func dbg_state() -> Dictionary:
	var plots := _plot_list()
	var now := GardenSystem.now_ms_now()
	var out: Array = []
	for p in plots:
		out.append({
			"at": int(p.get("at", 0)),
			"hit": bool(p.get("hit", false)),
			"x": int(p.get("x", 0)),
			"y": int(p.get("y", 0)),
			"stage": GardenSystem.stage_of(p, now),
			"progress": GardenSystem.progress_of(p, now),
		})
	return {
		"seed": bool(graph.garden.get("seed", false)) if graph != null else false,
		"plots": out,
		"narr": _narr_text(),
		"narr_segments": _narr_segments().size(),
		"narr_index": _narr_idx,
		"narr_shown": _narr_shown,
		"hint_visible": _hint != null and _hint.visible,
		"field_rect": _field.get_global_rect() if _field != null else Rect2(),
		"win_rect": get_global_rect(),
		"content_min": content.get_combined_minimum_size() if content != null else Vector2.ZERO,
	}


func dbg_open_narr(idx: int) -> bool:
	return _open_narr(idx)


func dbg_advance_narr() -> bool:
	return advance_narr()


func dbg_drag_plant(idx: int, x: float, y: float) -> bool:
	var plots := _plot_list()
	if idx < 0 or idx >= plots.size() or _field == null:
		return false
	var plant: Control = _plants[idx] if idx < _plants.size() else null
	if plant == null or not is_instance_valid(plant):
		return false
	var target := _field.get_global_rect().position + Vector2(
		x / 100.0 * _field.size.x, y / 100.0 * _field.size.y)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.global_position = plant.get_global_rect().get_center()
	_on_plant_input(down, idx)
	var move := InputEventMouseMotion.new()
	move.global_position = target
	move.relative = target - down.global_position
	_on_plant_input(move, idx)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.global_position = target
	_on_plant_input(up, idx)
	return true
