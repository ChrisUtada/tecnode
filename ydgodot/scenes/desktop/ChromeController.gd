class_name ChromeController
extends Node
## 由 Desktop 挂载的子系统控制器。
## 过渡期直接通过注入的 `desk` 访问宿主成员；搬出的函数名保持不变。

var desk: Desktop


func _build_header() -> void:
	var head := Panel.new()
	head.name = "header"
	head.position = Vector2.ZERO
	head.size = Vector2(Desktop.DESIGN_W, Desktop.HEADER_H)
	desk._head = head
	var sb := StyleBoxFlat.new()
	sb.bg_color = TecTheme.LINE
	sb.border_width_bottom = 2
	sb.border_color = TecTheme.LINE
	head.add_theme_stylebox_override("panel", sb)
	desk.add_child(head)

	# 品牌：`.brand` 14px + 字距 2；副题是它的 `<small>`（11px，间距 6px）
	var brand := TecTheme.brand_label("T.E.C-OS", TecTheme.FS_TITLE, TecTheme.CARD)
	brand.name = "brand"
	brand.position = Vector2(Desktop.HDR_X_BRAND, -1.0)
	brand.size = Vector2(92.0, Desktop.HEADER_H + 2.0)
	brand.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(brand)

	var sub := TecTheme.label(Desktop.HDR_SUB, TecTheme.FS_BODY, TecTheme.LINE2)
	sub.name = "brand_sub"
	sub.position = Vector2(Desktop.HDR_X_SUB, 0.0)
	sub.size = Vector2(206.0, Desktop.HEADER_H)
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	desk._brand_sub = sub
	head.add_child(sub)

	# 调查员证章（`#inv-chip`）：11px、奶油 1px 描边、**无圆角**、内边距 4/8
	desk._inv_chip = TecTheme.button("")
	desk._inv_chip.name = "inv_chip"
	desk._inv_chip.position = Vector2(Desktop.HDR_X_CHIP, 13.5)
	desk._inv_chip.size = Vector2(Desktop.HDR_W_CHIP, 23.0)
	desk._inv_chip.clip_text = true
	desk._inv_chip.add_theme_font_size_override("font_size", TecTheme.FS_BODY)
	desk._inv_chip.add_theme_color_override("font_color", TecTheme.CARD)
	desk._inv_chip.add_theme_color_override("font_hover_color", TecTheme.TEXT)
	desk._inv_chip.add_theme_color_override("font_pressed_color", TecTheme.TEXT)
	var chip_normal := TecTheme.flat(TecTheme.NONE, TecTheme.R_SM, TecTheme.CARD)
	var chip_hover := TecTheme.flat(TecTheme.CARD, TecTheme.R_SM, TecTheme.CARD)
	for csb in [chip_normal, chip_hover]:
		csb.content_margin_left = 8
		csb.content_margin_right = 8
		csb.content_margin_top = 4
		csb.content_margin_bottom = 4
	desk._inv_chip.add_theme_stylebox_override("normal", chip_normal)
	desk._inv_chip.add_theme_stylebox_override("hover", chip_hover)
	desk._inv_chip.add_theme_stylebox_override("pressed", chip_hover)
	desk._inv_chip.visible = false
	desk._inv_chip.pressed.connect(desk.session._open_cert_review)
	head.add_child(desk._inv_chip)

	## G6：页眉中间原本空着 490px。改成两行：上行「当前目标」，下行计数。
	## 面包屑不再挤在 134px 里被裁到只剩开头。
	desk._goal = TecTheme.label("", TecTheme.FS_BODY, TecTheme.LINE)
	desk._goal.name = "goal"
	desk._goal.position = Vector2(Desktop.HDR_X_CRUMB, 8.0)
	desk._goal.size = Vector2(Desktop.HDR_GOAL_W, 18.0)
	desk._goal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	desk._goal.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desk._goal.clip_text = true
	desk._goal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(desk._goal)

	desk._crumb = TecTheme.label("", TecTheme.FS_BODY, TecTheme.LINE2)
	desk._crumb.name = "crumb"
	desk._crumb.position = Vector2(Desktop.HDR_X_CRUMB, 26.0)
	desk._crumb.size = Vector2(Desktop.HDR_GOAL_W, 18.0)
	desk._crumb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	desk._crumb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desk._crumb.clip_text = true
	desk._crumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(desk._crumb)

	# A1：右侧只留正式操作。三个调试开关 + 适应窗口 / 重置 / 检查可达性
	# 全部收进「调试」弹出面板，避免系统界面第一眼像开发工具条。
	var undo := TecTheme.header_button("撤销", true)
	undo.name = "btn_撤销"
	head.add_child(undo)
	_place_hdr(undo, Vector2(Desktop.HDR_X_UNDO, Desktop.HDR_BTN_Y), Vector2(Desktop.HDR_W_UNDO, Desktop.HDR_BTN_H), true)
	undo.pressed.connect(desk.session._undo)
	desk._undo_btn = undo

	desk._debug_btn = TecTheme.header_button("调试")
	desk._debug_btn.name = "btn_调试"
	desk._debug_btn.toggle_mode = true
	head.add_child(desk._debug_btn)
	_place_hdr(desk._debug_btn, Vector2(Desktop.HDR_X_DEBUG, Desktop.HDR_BTN_Y),
		Vector2(Desktop.HDR_W_DEBUG, Desktop.HDR_BTN_H), true)
	desk._debug_btn.toggled.connect(_on_debug_toggled)
	_refresh_crumbs()
	call_deferred("_sync_header_sizes")


## 页眉开关：奶油描边的胶囊 + 13×13 勾选框 + 文案，与 Web 的 `.tog` 同尺寸（25 高）。
## 位置 / 尺寸由调用方经 `_place_hdr()` 摆（Button 的 size 要等入树后再赋一遍才压得住）。
func _make_toggle(text: String) -> Button:
	var b := TecTheme.header_button(text)
	b.name = "tog_" + text
	b.toggle_mode = true
	b.button_pressed = true
	b.add_theme_constant_override("h_separation", 4)
	b.icon = _check_tex(true)
	# 开关的「按下」就是常态：底保持透明，字必须一直是奶油色
	b.add_theme_color_override("font_pressed_color", TecTheme.CARD)
	b.add_theme_color_override("font_hover_pressed_color", TecTheme.CARD)
	var sb := TecTheme.flat(TecTheme.NONE, TecTheme.R_BTN, TecTheme.CARD)
	# 左 10 / 右 9 / 上下 6.5：左内边距对上 Web `.tog` 的 `padding-left:10px`
	# （勾选框左边线正好落在 680）；上下 6.5 让最小高度 = 12 + 13 = 25，不会顶开 25 的目标高度。
	sb.content_margin_left = 10
	sb.content_margin_right = 9
	sb.content_margin_top = 6.5
	sb.content_margin_bottom = 6.5
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.toggled.connect(func(on: bool): b.icon = _check_tex(on); _on_header_toggle(text, on))
	return b


## 摆页眉控件并记下目标尺寸。
## ⚠ Button 的 `size` 会被「最小尺寸」反顶：控件还没进场景树时，`get_theme_font_size()`
## 取不到我们的 12px 覆盖、退回主题默认 16px，算出来的最小高度是 31 ——
## 于是 `size = 25` 当场被抬成 31，而等入树后最小尺寸掉回 24/20，控件也不会自己缩回去。
## 症状是页眉所有按钮都比 Web 高 6px、文字整体下沉 3px（P3 对拍里 tools 区 17.7% 差异的主因）。
## 解法：目标尺寸记在这里，入树之后再赋一遍（`_sync_header_sizes`）。
## `anchor_right`：坐标表是按 1280 宽量的，贴右的那组存「距右边缘多少」而不是绝对 x，
## 窗口变宽时由 `_layout_header_right()` 整体右移。
func _place_hdr(c: Control, pos: Vector2, sz: Vector2, anchor_right: bool = false) -> void:
	c.position = pos
	c.size = sz
	desk._hdr_sized.append([c, sz])
	if anchor_right:
		desk._hdr_right.append([c, Desktop.DESIGN_W - pos.x])


func _sync_header_sizes() -> void:
	for pair in desk._hdr_sized:
		var c: Control = pair[0]
		if is_instance_valid(c) and c.size != pair[1]:
			c.size = pair[1]


## 「调试」弹出面板：黑底 + 奶油字，跟页眉同一套 header_button 语法。
## 点击面板外任意位置由全屏 scrim 关闭；开关留在面板里连续调，动作按钮点完收起。
func _build_debug_panel() -> void:
	desk._debug_scrim = Control.new()
	desk._debug_scrim.name = "debug_scrim"
	desk._debug_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	desk._debug_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	desk._debug_scrim.z_index = 90
	desk._debug_scrim.gui_input.connect(_on_debug_scrim_input)
	desk._debug_scrim.visible = false
	desk.add_child(desk._debug_scrim)

	desk._debug_shadow = ColorRect.new()
	desk._debug_shadow.name = "debug_shadow"
	desk._debug_shadow.color = TecTheme.shadow(1.0)
	desk._debug_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desk._debug_shadow.z_index = 91
	desk._debug_shadow.visible = false
	desk.add_child(desk._debug_shadow)

	desk._debug_pop = PanelContainer.new()
	desk._debug_pop.name = "debug_pop"
	desk._debug_pop.custom_minimum_size = Vector2(Desktop.DEBUG_POP_W, 0)
	desk._debug_pop.mouse_filter = Control.MOUSE_FILTER_STOP
	desk._debug_pop.z_index = 91
	var sb := TecTheme.flat(TecTheme.LINE, TecTheme.R_SM, TecTheme.CARD, 1)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	desk._debug_pop.add_theme_stylebox_override("panel", sb)
	desk._debug_pop.visible = false
	desk.add_child(desk._debug_pop)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	desk._debug_pop.add_child(col)

	var cap := TecTheme.label("调试 / DEBUG", TecTheme.FS_BODY, TecTheme.white(0.62))
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(cap)

	for text in ["合成消耗", "聚焦选中", "新节点自动居中"]:
		var t := _make_toggle(text)
		t.custom_minimum_size = Vector2(0, Desktop.HDR_TOG_H)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.alignment = HORIZONTAL_ALIGNMENT_LEFT
		col.add_child(t)

	var rule := ColorRect.new()
	rule.color = TecTheme.white(0.16)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)

	var actions := [["适应窗口", desk._fit_view], ["重置", desk.session._reset_case], ["检查可达性", desk._check_reachability]]
	for item in actions:
		var b := TecTheme.header_button(String(item[0]))
		b.name = "dbg_btn_" + String(item[0])
		b.custom_minimum_size = Vector2(0, Desktop.HDR_BTN_H)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(item[1])
		b.pressed.connect(_close_debug_panel)
		col.add_child(b)


func _on_debug_toggled(on: bool) -> void:
	if on:
		_open_debug_panel()
	else:
		_close_debug_panel()


func _open_debug_panel() -> void:
	if desk._debug_pop == null or desk._debug_scrim == null:
		return
	desk._debug_scrim.visible = true
	desk._debug_pop.visible = true
	if desk._debug_shadow != null:
		desk._debug_shadow.visible = true
	desk._debug_pop.reset_size()
	_layout_debug_panel()
	if desk._debug_btn != null and not desk._debug_btn.button_pressed:
		desk._debug_btn.set_pressed_no_signal(true)


func _close_debug_panel() -> void:
	if desk._debug_pop != null:
		desk._debug_pop.visible = false
	if desk._debug_shadow != null:
		desk._debug_shadow.visible = false
	if desk._debug_scrim != null:
		desk._debug_scrim.visible = false
	if desk._debug_btn != null and desk._debug_btn.button_pressed:
		desk._debug_btn.set_pressed_no_signal(false)


func _on_debug_scrim_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		_close_debug_panel()


func _layout_debug_panel() -> void:
	if desk._debug_pop == null or not desk._debug_pop.visible:
		return
	var sz := desk._debug_pop.get_combined_minimum_size()
	desk._debug_pop.size = Vector2(Desktop.DEBUG_POP_W, sz.y)
	desk._debug_pop.position = Vector2(desk._vw() - 14.0 - Desktop.DEBUG_POP_W, Desktop.HEADER_H + 6.0)
	if desk._debug_shadow != null:
		desk._debug_shadow.size = desk._debug_pop.size
		desk._debug_shadow.position = desk._debug_pop.position + SysWindow.OFFSET_SHADOW


## 13×13 勾选框：奶油底 + 墨色勾（Web 的 `accent-color:#e6e3d2` 渲染出来就是这个样子）。
## 现画而不是切图：勾是 2px 阶梯，缩放后比切图更稳。
func _check_tex(on: bool) -> ImageTexture:
	var img := Image.create(13, 13, false, Image.FORMAT_RGBA8)
	img.fill(TecTheme.NONE)
	var radius := 2
	var inside := PackedByteArray()
	inside.resize(13 * 13)
	for y in range(13):
		for x in range(13):
			var cx := clampi(x, radius, 12 - radius)
			var cy := clampi(y, radius, 12 - radius)
			var dx := x - cx
			var dy := y - cy
			inside[y * 13 + x] = 1 if dx * dx + dy * dy <= radius * radius else 0
	if on:
		for y in range(13):
			for x in range(13):
				if inside[y * 13 + x] == 1:
					img.set_pixel(x, y, TecTheme.TEXT_ON_DARK)
		var steps := [[3, 6], [4, 7], [5, 8], [6, 9], [7, 8], [8, 7], [9, 6], [10, 5]]
		for s in steps:
			img.set_pixel(int(s[0]), int(s[1]), TecTheme.LINE)
			img.set_pixel(int(s[0]), int(s[1]) + 1, TecTheme.LINE)
	else:
		var neighbors := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		for y in range(13):
			for x in range(13):
				if inside[y * 13 + x] == 0:
					continue
				for d in neighbors:
					var nx: int = x + d.x
					var ny: int = y + d.y
					if nx < 0 or nx > 12 or ny < 0 or ny > 12 or inside[ny * 13 + nx] == 0:
						img.set_pixel(x, y, TecTheme.CARD)
						break
	return ImageTexture.create_from_image(img)


func _on_header_toggle(text: String, on: bool) -> void:
	match text:
		"合成消耗":
			if desk._cmds != null:
				desk._cmds.consume_tools = on
		"聚焦选中":
			desk._opt_focus = on
			_apply_focus()
		"新节点自动居中":
			desk._opt_reveal = on
			if on:
				desk.canvas._relayout(false, true)   # 开关本身要求「现在就居中」——签名没变也得跑


## 面包屑计数：与 Web `updateCrumbs()` 同口径（可见/总数 · 已探索场景 · 已试组合 · 线索 · 结局）
func _refresh_crumbs() -> void:
	if desk._crumb == null or desk.graph == null:
		return
	var total := desk.graph.nodes.size()
	var vis := 0
	for key in desk.graph.nodes.keys():
		if desk.graph.visible_node(desk.graph.nodes[key]):
			vis += 1
	var scene_n := 0
	var ending_n := 0
	if desk.case_def != null:
		scene_n = desk.case_def.scenes.size()
		ending_n = desk.case_def.endings.size()
	desk._crumb.text = "节点 %d/%d · 已探索场景 %d/%d · 已试组合 %d · 证据 %d · 结局 %d/%d" % [
		vis, total, desk.graph.explored.size(), scene_n, desk.graph.tried.size(),
		desk.graph.captured.size(), desk.graph.endings.size(), ending_n]
	desk._crumb.tooltip_text = desk._crumb.text
	if desk._goal != null and is_instance_valid(desk._goal):
		var goal := _goal_text()
		desk._goal.text = goal
		desk._goal.tooltip_text = goal
	desk.session._refresh_undo_btn()


## G6：可读的当前目标。普通结局后改成「已记录 X/Y，可继续找真名」。
func _goal_text() -> String:
	if desk.graph == null or desk.case_def == null:
		return "当前目标：等待案件装载"
	if desk._tutorial_active:
		match desk._tutorial_step:
			Desktop.TutorialStep.DOUBLE_CLICK_OFFICE:
				return "当前目标：双击「TEC办公室」，调出调查员证"
			Desktop.TutorialStep.DRAG_CERT:
				return "当前目标：把调查员证拖给 TEC 核对"
			Desktop.TutorialStep.STORE_SUPPLIES:
				return "当前目标：整理桌面（可选），然后双击「推演」"
			Desktop.TutorialStep.INFER:
				return "当前目标：把调查员证放到推演桌布，长按执行者"
			Desktop.TutorialStep.CERT_FORM:
				return "当前目标：填完调查员证"
			Desktop.TutorialStep.CHOOSE_CASE:
				return "当前目标：在「案件」里选择 A-001"
			_:
				return "登记完成"
	var total := desk.case_def.endings.size()
	var got := desk.graph.endings.size()
	var has_true := false
	for e in desk.case_def.endings:
		if e != null and e.is_true_capture and desk.graph.endings.has(e.id):
			has_true = true
			break
	if got > 0 and not has_true:
		return "已记录 %d/%d 个结局 · 可以继续找「真名」" % [got, total]
	if has_true:
		if total > 0 and got >= total:
			return "真名已记录 · 全部 %d 个结局已收齐" % total
		return "真名已记录 · 还可回看其它结局（%d/%d）" % [got, total]
	if desk.graph.explored.is_empty():
		return "当前目标：双击「%s」展开现场" % desk.case_def.scene_title(Desktop.SLICE_SCENE)
	if desk.graph.matrix_count() <= 0:
		return "当前目标：把证放到推演桌布，长按执行者"
	return "当前目标：核对推演桌布的证，长按执行者"


## 选中即聚焦：与选中卡既不相同、也没有连线的卡淡化（Web `applyFocus`）
func _apply_focus() -> void:
	if desk._cards == null:
		return
	var sel := desk._selected
	var live := desk._opt_focus and sel != "" and desk.graph != null and desk.graph.nodes.has(sel)
	var near := {}
	if live:
		near[sel] = true
		for nb in desk.graph.neighbors(sel):
			near[String(nb)] = true
	for key in desk._cards.keys():
		var card: NodeCard = desk._cards[key]
		if card != null:
			card.set_dim(live and not near.has(String(key)))
			# 选中环独立于「聚焦淡化」：关掉聚焦时环照样在（Web 的 `.sel` 不依赖任何开关）
			card.set_selected(desk._selected != "" and desk._selected == String(key))
	desk.canvas._repaint_edges()
