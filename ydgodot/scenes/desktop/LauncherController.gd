class_name LauncherController
extends Node
## 由 Desktop 挂载的子系统控制器。
## 过渡期直接通过注入的 `desk` 访问宿主成员；搬出的函数名保持不变。

var desk: Desktop


func _build_icons() -> void:
	# 容器只做「分组 + 树路径」用（`desk/icons/icon_bag` 是测试与落点表的公共锚点），
	# 不再承担排版：图标改成绝对定位，才能自由拖动。
	var col := Control.new()
	col.name = "icons"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.position = Vector2.ZERO
	col.size = desk._desk.size
	desk._desk.add_child(col)
	desk.windows._place_z(col, Desktop.ZR_ICONS)
	for d in Desktop.ICON_DEFS:
		var app := String(d[1])
		var b := DeskIcon.new()
		b.name = "icon_" + app
		b.setup(String(d[0]), "res://assets/icons/%s.svg" % String(d[2]))
		b.set_bounds(Rect2(Vector2.ZERO, desk._desk.size))
		if app == "tec":
			desk._tec_btn = b
		elif app == "map":
			desk._map_btn = b
		elif app == "goto":
			desk._archive_btn = b
		elif app == "infer":
			desk._infer_btn = b
		elif app == "bag":
			desk._bag_btn = b
		elif app == "clue":
			desk._clue_btn = b
		elif app == "people":
			desk._people_btn = b
		elif app == "log":
			desk._log_btn = b
		# 桌面图标：单击只选中，双击才打开（K9：播放器也并入同一条规则）。
		b.clicked.connect(func(): _on_icon_pressed(app, b))
		col.add_child(b)

	desk._music_btn = DeskIcon.new()
	desk._music_btn.name = "icon_music"
	desk._music_btn.setup("播放器", "res://assets/icons/music.svg")
	desk._music_btn.set_bounds(Rect2(Vector2.ZERO, desk._desk.size))
	desk._music_btn.tooltip_text = "打开音乐播放器（唱针已装上唱机）"
	desk._music_btn.visible = false
	desk._music_btn.clicked.connect(func(): _on_icon_pressed("music", desk._music_btn))
	col.add_child(desk._music_btn)

	desk._garden_btn = DeskIcon.new()
	desk._garden_btn.name = "icon_garden"
	desk._garden_btn.setup("花园", "res://assets/icons/leaf.svg")
	desk._garden_btn.set_bounds(Rect2(Vector2.ZERO, desk._desk.size))
	desk._garden_btn.tooltip_text = "去花园看看真名留下的种子"
	desk._garden_btn.visible = false
	desk._garden_btn.clicked.connect(func(): _on_icon_pressed("garden", desk._garden_btn))
	col.add_child(desk._garden_btn)

	_build_map_badge()
	_build_archive_badge()
	# 批 1 新增：推演 / 物品 / 证据的条数角标 + 日志未读角标
	desk._infer_badge = _make_badge(desk._infer_btn, "infer_badge")
	desk._bag_badge = _make_badge(desk._bag_btn, "bag_badge")
	desk._clue_badge = _make_badge(desk._clue_btn, "clue_badge")
	desk._log_badge = _make_badge(desk._log_btn, "log_badge")
	desk._garden_badge = _make_badge(desk._garden_btn, "garden_badge")
	_reset_icon_positions()


## 角标基件（Web `.desk-icon .badge`：右上角、深底浅字、999px 药丸）
func _make_badge(parent: Control, badge_name: String, text: String = "") -> PanelContainer:
	if parent == null:
		return null
	var badge := PanelContainer.new()
	badge.name = badge_name
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := TecTheme.flat(TecTheme.LINE, TecTheme.R_PILL, TecTheme.LINE)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	badge.add_theme_stylebox_override("panel", sb)
	var l := TecTheme.label(text, TecTheme.FS_BODY, TecTheme.CARD)
	l.name = "Label"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(l)
	badge.visible = false
	parent.add_child(badge)
	if parent is DeskIcon:
		(parent as DeskIcon).place_badges()
	return badge


## text == "" = 收起角标
func _set_badge(badge: PanelContainer, text: String) -> void:
	if badge == null or not is_instance_valid(badge):
		return
	if text == "":
		badge.visible = false
		return
	badge.visible = true
	var lab: Label = badge.get_node_or_null("Label")
	if lab != null:
		lab.text = text
	if badge.get_parent() is DeskIcon:
		(badge.get_parent() as DeskIcon).place_badges()


func _reset_icon_positions() -> void:
	var layer := _icon_layer()
	var list: Array = []
	for c in layer.get_children():
		if c is DeskIcon and (c as DeskIcon).visible:
			list.append(c)
	if list.is_empty():
		return
	var desk_h := desk._desk.size.y
	var n := list.size()
	# 先按可用高度压到 ≥68px；压到 68 以下才切紧凑（图标本体仍是 48px，只藏标签）。
	# 这样第 9 个图标出现时只收间距，不会让整栏标签一起消失。
	var fit_pitch := minf(Desktop.ICON_PITCH, floorf((desk_h - Desktop.ICON_TOP - 12.0) / float(n)))
	var compact := fit_pitch < Desktop.ICON_MIN_PITCH
	for b in list:
		(b as DeskIcon).set_compact(compact)
	var pitch := fit_pitch
	if compact:
		pitch = minf(Desktop.ICON_COMPACT_PITCH,
			floorf((desk_h - Desktop.ICON_TOP - 12.0) / float(n)))
	# 顺序：常驻 8 项按 ICON_DEFS，动态的（播放器 / 花园）排在后面
	var order: Array = []
	for d in Desktop.ICON_DEFS:
		var b := _icon_by_app(String(d[1]))
		if b != null and b.visible:
			order.append(b)
	for b in list:
		if not order.has(b):
			order.append(b)
	for i in order.size():
		var ic := order[i] as DeskIcon
		ic.position = Vector2(Desktop.ICON_LEFT, Desktop.ICON_TOP + float(i) * pitch)
		ic.set_bounds(Rect2(Vector2.ZERO, desk._desk.size))
		ic.place_badges()


## W7：桌布尺寸变化时不重排，只同步每枚图标的拖动边界，并把已拖出屏的夹回来。
func _sync_icon_bounds() -> void:
	var layer := _icon_layer()
	if layer == null:
		return
	var bounds := Rect2(Vector2.ZERO, desk._desk.size)
	for c in layer.get_children():
		if not (c is DeskIcon):
			continue
		var ic := c as DeskIcon
		ic.set_bounds(bounds)
		ic.position = Vector2(
			clampf(ic.position.x, 0.0, maxf(0.0, bounds.size.x - ic.size.x)),
			clampf(ic.position.y, 0.0, maxf(0.0, bounds.size.y - ic.size.y)))


## 图标层（`desk/icons`）：只做分组，不排版。
func _icon_layer() -> Control:
	var n := desk._desk.get_node_or_null("icons") as Control
	return n if n != null else desk._desk


func _icon_by_app(app: String) -> Button:
	match app:
		"infer": return desk._infer_btn
		"goto": return desk._archive_btn
		"clue": return desk._clue_btn
		"people": return desk._people_btn
		"bag": return desk._bag_btn
		"tec": return desk._tec_btn
		"log": return desk._log_btn
		"map": return desk._map_btn
		"music": return desk._music_btn
		"garden": return desk._garden_btn
	return null


## 桌面图标：单击 = 选中（`.desk-icon.sel`），双击 = 打开（对齐 Web `attachIcon`）。
## 播放器是唯一例外（Web 里传了 onQuick，单击即开）。
func _on_icon_pressed(app: String, icon: DeskIcon) -> void:
	## K9：音乐图标和其它图标同一条规则 —— 单击选中、双击打开。
	var now := Time.get_ticks_msec()
	## W20：图标双击窗口与卡片统一为 500ms。
	if desk._icon_last_app == app and now - desk._icon_last_ms <= 500:
		desk._icon_last_app = ""
		desk._icon_last_ms = -100000
		_open_icon_app(app)
		return
	desk._icon_last_app = app
	desk._icon_last_ms = now
	_select_icon(icon)


func _select_icon(icon: DeskIcon) -> void:
	if desk._icon_sel != null and is_instance_valid(desk._icon_sel) and desk._icon_sel != icon:
		desk._icon_sel.set_selected(false)
	desk._icon_sel = icon
	if icon != null and is_instance_valid(icon):
		icon.set_selected(true)


func _clear_icon_selection() -> void:
	if desk._icon_sel != null and is_instance_valid(desk._icon_sel):
		desk._icon_sel.set_selected(false)
	desk._icon_sel = null


## K3：图标双击 = 打开/提到最前，绝不因为「已经开着」就把它关掉。
## 关闭只交给窗口 × / 最小化。
func _open_icon_app(app: String) -> void:
	match app:
		"infer":
			_open_matrix()
		"goto":
			_open_archive()
		"clue":
			_open_storage(GraphState.LEDGER)
		"people":
			_open_people()
		"bag":
			_open_storage(GraphState.BAG)
		"tec":
			desk.tec._open_tec()
		"log":
			_open_log()
		"map":
			_open_case_map()
		"garden":
			desk.garden_music._open_garden()
		"music":
			desk.garden_music._open_music()
	_clear_icon_selection()


func _open_storage(kind: String) -> void:
	var win: Control = null
	if kind == GraphState.BAG:
		win = desk._bag_win
	else:
		win = desk._ledger_win
	if win != null and is_instance_valid(win):
		(win as StorageWin).refresh_store()
		desk.windows._raise_to_front(win)
		return
	desk.drag._toggle_storage(kind)


func _open_people() -> void:
	if desk._people_win != null and is_instance_valid(desk._people_win):
		desk.people._refresh_people_win()
		desk.windows._raise_to_front(desk._people_win)
		return
	desk.people._toggle_people()


func _open_log() -> void:
	if desk._log_win != null and is_instance_valid(desk._log_win):
		desk._refresh_log_win()
		desk.windows._raise_to_front(desk._log_win)
		return
	desk._toggle_log()


func _open_archive() -> void:
	if desk._archive_win != null and is_instance_valid(desk._archive_win):
		desk.windows._raise_to_front(desk._archive_win)
		return
	desk.narrative._toggle_archive()


func _open_matrix() -> void:
	if desk._matrix_win != null and is_instance_valid(desk._matrix_win):
		desk.matrix._refresh_matrix_views()
		desk.windows._raise_to_front(desk._matrix_win)
		return
	desk.matrix._toggle_matrix()


func _open_case_map() -> void:
	if desk._map_win != null and is_instance_valid(desk._map_win):
		desk.windows._raise_to_front(desk._map_win)
		return
	desk.session._toggle_case_map()


func _build_map_badge() -> void:
	desk._map_badge = _make_badge(desk._map_btn, "map_badge", "已关闭")


func _build_archive_badge() -> void:
	desk._archive_badge = _make_badge(desk._archive_btn, "archive_badge", "新")


func _refresh_app_icons() -> void:
	if desk.graph == null:
		return
	if desk._tutorial_active:
		desk.tutorial._refresh_tutorial_icons()
		return
	## 从教学桌面退回完整桌面时，教学期被隐藏的常驻 app 要重新出现。
	for app in ["infer", "goto", "clue", "people", "bag", "tec", "log", "map"]:
		var b := _icon_by_app(app)
		if b != null:
			b.visible = true
	var music: bool = desk.garden_music._music_unlocked()
	var had_music := desk._music_btn != null and desk._music_btn.visible
	if desk._music_btn != null:
		desk._music_btn.visible = music
	if not music:
		if desk._music_win != null and is_instance_valid(desk._music_win):
			desk._music_win.queue_free()
		desk._music_win = null
		if desk._music_dock != null and is_instance_valid(desk._music_dock):
			desk._music_dock.queue_free()
		desk._music_dock = null

	var garden := GardenSystem.has_garden(desk.graph)
	var had_garden := desk._garden_btn != null and desk._garden_btn.visible
	if desk._garden_btn != null:
		desk._garden_btn.visible = garden
	if not garden:
		if desk._garden_win != null and is_instance_valid(desk._garden_win):
			desk._garden_win.queue_free()
		desk._garden_win = null
		_set_badge(desk._garden_badge, "")
	else:
		GardenSystem.normalize(desk.graph, desk.case_def)
		var plots: Array = desk.graph.garden.get("plots", [])
		var has_seed := bool(desk.graph.garden.get("seed", false))
		if not plots.is_empty():
			_set_badge(desk._garden_badge, "%d 株" % plots.size())
		elif has_seed:
			_set_badge(desk._garden_badge, "种子")
		else:
			_set_badge(desk._garden_badge, "")

	_refresh_count_badges()
	# 图标增减会改步距（Web `resetIconPositions()`）。只在可见性真变时重排 ——
	# 每次提交都重排会把玩家拖过的位置收走。
	if music != had_music or garden != had_garden:
		_reset_icon_positions()


## 计数角标（Web `updateInferBadge` / `updateBagBadge` / `updateLedgerBadge` / `updateLogBadge`）：
## 推演 = 桌布上已归位的证条数、物品 = N 件、证据 = N 条、日志 = 未读条数。
func _refresh_count_badges() -> void:
	if desk.graph == null:
		return
	var infer := 0
	for sense in desk.graph.matrix.keys():
		infer += (desk.graph.matrix[sense] as Array).size()
	_set_badge(desk._infer_badge, ("%d 条" % infer) if infer > 0 else "")
	var bag := 0
	var ledger := 0
	for key in desk.graph.stored.keys():
		var where := String(desk.graph.stored[key])
		if where == GraphState.BAG:
			bag += 1
		elif where == GraphState.LEDGER:
			ledger += 1
	_set_badge(desk._bag_badge, ("%d 件" % bag) if bag > 0 else "")
	_set_badge(desk._clue_badge, ("%d 条" % ledger) if ledger > 0 else "")
	_set_badge(desk._log_badge, str(desk._log_unread) if desk._log_unread > 0 else "")
