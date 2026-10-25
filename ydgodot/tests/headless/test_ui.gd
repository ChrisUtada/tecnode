extends SceneTree
## P0 界面级回归：真的往 NodeCard 里塞鼠标事件，验证「拖拽 = 组合 / 双击 = 点亮」这条接线。
## 运行：godot --headless --path ydgodot --script res://tests/headless/test_ui.gd

const StartScreenScript := preload("res://ui/StartScreen.gd")

var fails := 0
var total := 0
var scene: Control

const TORCH := "item:ITEM_shoudiantong"
const SHADOW := "item:ITEM_something"


func check(name: String, cond: bool, detail: String = "") -> void:
	total += 1
	if cond:
		print("  PASS  ", name)
	else:
		fails += 1
		print("  FAIL  ", name, ("  [" + detail + "]") if detail != "" else "")


func _initialize() -> void:
	print("=== P0 界面级回归（拖拽 / 双击）===")
	scene = load("res://scenes/Desktop.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	check("桌面建起来了", scene != null and scene.dbg_state()["cards"] == 1, str(scene.dbg_state()))
	check("开局只有一张卡：未探索的起始场景（Web `17-boot.js` 同口径）",
		_cards().size() == 1 and _cards().has("loc:SCENES_garden"), str(_cards().keys()))

	# 相机钉在 1x 原生格：本文件所有点击/坐标断言都是按「世界坐标 → 屏幕」1:1 写的。
	# `_view_user = true` 同时关掉 `_relayout` 的自动 fit，否则每加一个节点镜头都会重缩。
	scene._view_k = 1.0
	scene._view_pos = Vector2.ZERO
	scene._view_user = true
	scene._apply_view()

	scene.dbg_expand("SCENES_garden")
	await process_frame
	var cards: Dictionary = _cards()
	check("展开后卡片数增加", cards.size() >= 5, str(cards.size()))
	check("开局不凭空给手电筒（它在左侧抽屉里，要自己开）", not cards.has(TORCH))
	check("黑影已上画布", cards.has(SHADOW))

	# C3：卡片落 8px 网格；宽度只有「场景 160 / 实体 128」两档。
	var off_grid: Array = []
	for k in cards.keys():
		var c := cards[k] as NodeCard
		if c != null and c.visible \
			and (absf(c.position.x - roundf(c.position.x / 8.0) * 8.0) > 0.01
				or absf(c.position.y - roundf(c.position.y / 8.0) * 8.0) > 0.01):
			off_grid.append(String(k) + "@" + str(c.position))
	check("C3 自动摆卡落 8px 网格", off_grid.is_empty(), str(off_grid))
	var scene_card := cards["loc:SCENES_garden"] as NodeCard
	var ent_card := cards[SHADOW] as NodeCard
	check("C3 卡片宽度档：场景 160 / 实体 128",
		scene_card != null and ent_card != null
			and absf(scene_card._w - GraphState.SCENE_W) < 0.01
			and absf(ent_card._w - GraphState.ENT_W) < 0.01,
		"%.0f / %.0f" % [scene_card._w if scene_card else -1, ent_card._w if ent_card else -1])

	# ── 容器链（P1.2）：双击书桌 → 抽屉 → 选项 → 左侧抽屉 → 手电筒 ──
	scene.dbg_activate("item:ITEM_shuzhuo")
	await process_frame
	var cards2: Dictionary = _cards()
	check("双击书桌：抽屉上画布", cards2.has("item:ITEM_chouti"))
	check("双击书桌：笔记与台灯也上画布", cards2.has("item:ITEM_sxbj") and cards2.has("item:ITEM_taideng"))

	scene.dbg_activate("item:ITEM_chouti")
	await process_frame
	var cards3: Dictionary = _cards()
	check("双击抽屉（choice）：两个抽屉场景都上画布",
		cards3.has("loc:SCENES_choutiyi") and cards3.has("loc:SCENES_choutier"))

	scene.dbg_activate("loc:SCENES_choutiyi")
	await process_frame
	check("展开左侧抽屉：手电筒出现", _cards().has("item:ITEM_shoudiantong"))
	cards = _cards()

	# 1) 没点亮直接拖：发光门拦下
	_drag(cards[TORCH], cards[SHADOW])
	await process_frame
	check("没点亮时拖过去：不推进到尸体", not scene.dbg_state()["explored"].has("SCENES_body"))
	check("拦下时给了提示（toast 可见）", scene.get_node("desk/toast").visible)
	check("手电筒没被误点亮", scene.dbg_state()["lit"].get("ITEM_shoudiantong", false) == false)

	# 2) 双击手电筒 = 点亮
	_double_click(cards[TORCH])
	await process_frame
	check("双击手电筒：亮起", scene.dbg_state()["lit"].get("ITEM_shoudiantong", false) == true)

	# 3) 点亮后再拖 = 组合成功，尸体场景上画布
	_drag(cards[TORCH], cards[SHADOW])
	await process_frame
	await process_frame
	var st: Dictionary = scene.dbg_state()
	check("点亮后拖过去：尸体场景已探索", st["explored"].has("SCENES_body"), str(st["explored"]))
	check("尸体场景卡片已出现", _cards().has("loc:SCENES_body"))
	check("尸体的实体卡片已出现（绷带）", _cards().has("item:ITEMS_bd"))

	# 再双击书桌 = 收起：它的孩子被藏起来
	scene.dbg_activate("item:ITEM_shuzhuo")
	await process_frame
	var st2: Dictionary = scene.dbg_state()
	check("再次双击书桌：折叠记账", (st2["collapsed"] as Array).has("ITEM_shuzhuo"))
	# 抽屉有 cond 边连到场外的抽屉场景 → 按 Web 的 recomputeHidden 口径「跟场外有连线的留下」
	check("折叠后：有场外连线的节点留在画布上", (_cards()["item:ITEM_chouti"] as NodeCard).visible == true)
	check("折叠后：没有场外连线的节点被藏起来", (_cards()["item:ITEM_taideng"] as NodeCard).visible == false)
	# 手电筒挂在被折叠的左侧抽屉上，随之收起（Web 同口径）；后面的用例还要用它 → 重新展开书桌
	scene.dbg_activate("item:ITEM_shuzhuo")
	await process_frame
	check("重新展开书桌：手电筒回到画布", (_cards()[TORCH] as NodeCard).visible)

	# ── 密码弹窗（P1.3）：木盒 → 错码 → 对码 ──
	scene.dbg_ensure("item", "ITEMS_jzmh")
	await process_frame
	scene.dbg_pw_open("item:ITEMS_jzmh")
	await process_frame
	var pop := scene.get_node_or_null("desk/pw_pop") as SysWindow
	check("双击木盒：LOCK 弹窗出现", pop != null)
	if pop != null:
		check("A4 密码浮层 opt-in 硬影", pop.offset_shadow and pop._offset_shadow != null)
		if pop._offset_shadow != null:
			check("A4 密码影偏移 = OFFSET_SHADOW",
				pop._offset_shadow.position.is_equal_approx(Vector2(SysWindow.PAD, SysWindow.PAD)
					+ SysWindow.OFFSET_SHADOW), str(pop._offset_shadow.position))
			check("A4 密码影在窗体内容之下", pop._offset_shadow.get_index() < pop.get_child_count() - 1)
		# 顶栏统一：标题按文字宽度居中，窄窗不压关闭键，横纹不越出栏。
		var pw_bar := pop.get_node("bar") as Control
		var pw_title := pop._title_label as Control
		var pw_close := pop.get_node("bar/close") as Control
		var pw_stripes := pop._title_stripes as Control
		check("顶栏标题居中（窄弹窗）",
			absf(pw_title.position.x + pw_title.size.x * 0.5 - pw_bar.size.x * 0.5) < 0.5,
			"%s / bar %s" % [pw_title.position, pw_bar.size])
		check("窄弹窗标题不压关闭键",
			pw_title.position.x + pw_title.size.x <= pw_close.position.x,
			"%s / close %s" % [pw_title.position + pw_title.size, pw_close.position])
		check("窄弹窗横纹不越出顶栏",
			pw_stripes.size.x <= pw_bar.size.x and pw_stripes.size.y <= pw_bar.size.y
				and float(pw_stripes.get("line_right")) <= pw_bar.size.x,
			"%s / bar %s" % [pw_stripes.size, pw_bar.size])
		var pw_in := pop.find_child("pw_in", true, false) as LineEdit
		check("密码输入数字为墨色",
			pw_in != null and pw_in.get_theme_color("font_color").is_equal_approx(TecTheme.TEXT),
			"null" if pw_in == null else pw_in.get_theme_color("font_color").to_html(false))
	scene.dbg_password("item:ITEMS_jzmh", "1111")
	await process_frame
	check("密码错：弹窗还在", scene.get_node_or_null("desk/pw_pop") != null)
	check("密码错：还没开箱", not _cards().has("item:ITEMS_htys"))
	scene.dbg_password("item:ITEMS_jzmh", "2222")
	await process_frame
	check("G11 连续错两次：仍未开箱", not _cards().has("item:ITEMS_htys"))
	var last_pw_log := String(scene.dbg_log_texts()[-1]) if not scene.dbg_log_texts().is_empty() else ""
	check("G11 连续错两次：日志指向 TEC 分析",
		last_pw_log.contains("TEC") and last_pw_log.contains("木盒"), last_pw_log)
	var last_pw_tec := String(scene._tec.dbg_lines()[-1]) if not scene._tec.dbg_lines().is_empty() else ""
	check("G11 TEC 对话留下密码提示",
		last_pw_tec.contains("密码") and last_pw_tec.contains("木盒"), last_pw_tec)
	scene.dbg_password("item:ITEMS_jzmh", "0321")
	await process_frame
	check("密码对：弹窗收走", scene.get_node_or_null("desk/pw_pop") == null)
	check("密码对：钥匙上画布", _cards().has("item:ITEMS_htys"))

	# ── 收纳三态（P1.2）：证物袋 / 线索册两扇窗 ──
	scene.dbg_ensure("item", "ITEM_taideng")
	await process_frame
	scene.dbg_select("item:ITEM_taideng")
	await process_frame
	check("台灯收进证物袋", scene.dbg_store("BAG"))
	await process_frame
	check("收进袋后画布上不再显示", (_cards()["item:ITEM_taideng"] as NodeCard).visible == false)

	scene.dbg_open_storage("BAG")
	await process_frame
	var bag := scene.get_node_or_null("desk/bag_win")
	check("证物袋窗能打开", bag != null)
	check("证物袋标题仅中文", bag != null and (bag as StorageWin).title == "证物袋",
		(bag as StorageWin).title if bag != null else "")
	check("袋里列出台灯", bag != null and (bag as StorageWin).items().has("item:ITEM_taideng"))
	var bag_row := (bag as StorageWin).find_child("row_item_ITEM_taideng", true, false) as PanelContainer
	var bag_sb := bag_row.get_theme_stylebox("panel") as StyleBoxFlat if bag_row != null else null
	check("D2 证物袋行：仅底部 1px 发丝线，无盒框",
		bag_sb != null
			and bag_sb.border_width_bottom == 1
			and bag_sb.border_width_top == 0
			and bag_sb.border_width_left == 0
			and bag_sb.border_width_right == 0
			and bag_sb.border_color.is_equal_approx(TecTheme.edge(0.18)),
		str(bag_sb))
	check("D2 证物袋发丝线左右缩进 8px",
		bag_sb != null and bag_sb.expand_margin_left == -8.0
			and bag_sb.expand_margin_right == -8.0, str(bag_sb))

	scene.dbg_ensure("clue", "CLUES_nm")
	await process_frame
	scene.dbg_select("clue:CLUES_nm")
	await process_frame
	check("线索收进线索册", scene.dbg_store("LEDGER"))
	await process_frame
	scene.dbg_open_storage("LEDGER")
	await process_frame
	var ledger := scene.get_node_or_null("desk/clue_win")
	check("线索册窗能打开", ledger != null)
	check("线索册标题仅中文", ledger != null and (ledger as StorageWin).title == "线索册",
		(ledger as StorageWin).title if ledger != null else "")
	check("册里列出线索", ledger != null and (ledger as StorageWin).items().has("clue:CLUES_nm"))
	check("台灯不在册里（册只收线索）",
		ledger != null and not (ledger as StorageWin).items().has("item:ITEM_taideng"))
	# K6：拒收话术按目标分派，场景拖到线索册不能再报「收纳袋」，且必须写日志。
	scene._hide_toast()
	var k6_log0: int = scene.graph.log_count()
	scene._store_into(GraphState.LEDGER, "loc:SCENES_garden")
	check("K6 场景拖线索册话术按目标",
		scene.dbg_toast_text().contains("线索册") and not scene.dbg_toast_text().contains("收纳袋"),
		scene.dbg_toast_text())
	check("K6 拒收写一条 warning 日志",
		scene.graph.log_count() == k6_log0 + 1
			and String(scene.dbg_log_kinds()[-1]) == "warn",
		str(scene.graph.log_count() - k6_log0))

	# 从册里取回
	(ledger as StorageWin)._take("clue:CLUES_nm")
	await process_frame
	check("从册里取回：线索重新可见", (_cards()["clue:CLUES_nm"] as NodeCard).visible == true)
	check("取回后册里少了一条", not (ledger as StorageWin).items().has("clue:CLUES_nm"))
	# A2：收起两扇存储窗，把激活态还给案件主窗，下面才能继续按 2px 激活框验窗框。
	scene.dbg_open_storage("BAG")
	scene.dbg_open_storage("LEDGER")
	if scene._detail_win != null and is_instance_valid(scene._detail_win):
		scene._detail_win.hide()
	await process_frame
	check("A2：存储 / 详情窗收起后案件主窗恢复激活",
		(scene.get_node("desk/case_win") as SysWindow).is_window_active())

	# ── P3 页眉 / 窗框：把「对拍追平」的成果钉成契约，免得以后某次改版又把人赶回起点 ──
	var head := scene.get_node_or_null("header")
	check("页眉存在且高 52", head != null and absf(head.size.y - 52.0) < 0.5)
	var brand := scene.get_node_or_null("header/brand") as Label
	check("品牌字是 T.E.C-OS（14px）", brand != null and brand.text == "T.E.C-OS"
		and brand.get_theme_font_size("font_size") == TecTheme.FS_TITLE)
	var sub := scene.get_node_or_null("header/brand_sub") as Label
	check("副题沿用 Web 文案", sub != null and sub.text == "节点原型 v2 · 案件 A-001")
	var crumb := scene.get_node_or_null("header/crumb") as Label
	check("面包屑用计数口径", crumb != null and crumb.text.begins_with("节点 ")
		and crumb.text.contains("已探索场景"))
	var goal := scene.get_node_or_null("header/goal") as Label
	check("G6 页眉有可读的当前目标", goal != null and goal.visible
		and goal.text.begins_with("当前目标：") and goal.size.x >= 280.0,
		("null" if goal == null else goal.text + " / " + str(goal.size.x)))
	check("G6 目标条不挤占计数面包屑", crumb != null and crumb.size.x >= 280.0,
		"null" if crumb == null else str(crumb.size.x))
	# A1：右侧只留正式「撤销」+「调试」入口；调试项不再摊在页眉上。
	var slots := {"btn_撤销": 1144.0, "btn_调试": 1202.0}
	var bad_slots: Array = []
	for nm in slots.keys():
		var c := scene.get_node_or_null("header/" + String(nm)) as Control
		if c == null or absf(c.position.x - float(slots[nm])) > 0.5:
			bad_slots.append(String(nm))
	check("页眉只留撤销 / 调试两个入口", bad_slots.is_empty(), str(bad_slots))
	# 页眉拉满视口宽：不缩放之后它是自适应的，1280 口径下必须正好 1280
	check("页眉宽 = 视口宽（自适应）", head != null and absf(head.size.x - scene._vw()) < 0.5,
		str(head.size.x) if head != null else "null")
	scene._open_debug_panel()
	await process_frame
	var dbg_pop := scene.get_node_or_null("debug_pop") as Control
	check("调试面板可打开", dbg_pop != null and dbg_pop.visible)
	var dbg_shadow := scene.get_node_or_null("debug_shadow") as ColorRect
	check("A4 调试菜单 3px 偏移影",
		dbg_shadow != null and dbg_shadow.visible
			and dbg_shadow.position.is_equal_approx(dbg_pop.position + SysWindow.OFFSET_SHADOW)
			and dbg_shadow.size.is_equal_approx(dbg_pop.size),
		"null" if dbg_shadow == null else str(dbg_shadow.position) + " / " + str(dbg_pop.position))
	var dbg_togs := ["tog_合成消耗", "tog_聚焦选中", "tog_新节点自动居中"]
	var dbg_actions := ["dbg_btn_适应窗口", "dbg_btn_重置", "dbg_btn_检查可达性"]
	var missing: Array = []
	for nm in dbg_togs + dbg_actions:
		if scene.find_child(String(nm), true, false) == null:
			missing.append(String(nm))
	check("调试开关 / 动作都在弹出面板里", missing.is_empty(), str(missing))
	var tog := scene.find_child("tog_合成消耗", true, false) as Button
	var tog_img: Image = tog.icon.get_image() if tog != null and tog.icon != null else null
	check("页眉 checkbox 13×13 圆角", tog_img != null
		and tog_img.get_size() == Vector2i(13, 13)
		and tog_img.get_pixel(0, 0).a == 0.0 and tog_img.get_pixel(2, 0).a > 0.0,
		str(tog_img.get_size()) if tog_img != null else "null")
	scene._close_debug_panel()
	check("调试面板可关闭", dbg_pop != null and not dbg_pop.visible)
	check("A4 调试影随面板隐藏", dbg_shadow == null or not dbg_shadow.visible)
	# 主窗跟着桌面长：1280×720 下画布必须是 1162 × 608（Web 标题栏 28px 口径）
	var stage := scene.get_node_or_null("desk/case_win/body/stage") as Control
	check("画布 1280 口径 = 1162×608", stage != null and stage.size == Vector2(1162, 608),
		str(stage.size) if stage != null else "null")
	var chip := scene.get_node_or_null("header/inv_chip") as Button
	check("证章摆在 318 / 宽 190", chip != null and absf(chip.position.x - 318.0) < 0.5
		and absf(chip.size.x - 190.0) < 0.5)
	# 窗框（P2）：程序化硬框取代烘焙九切片 —— 1px 黑边 + 0 圆角，位置仍在 PAD 处
	var case_win := scene.get_node_or_null("desk/case_win")
	check("案件窗不再用烘焙九切片", case_win != null and not case_win._uses_baked_frame()
		and case_win.get_node_or_null("frame") == null)
	var cw_bar := case_win.get_node("bar") as Control
	var cw_title := case_win._title_label as Control
	var cw_stripes := case_win._title_stripes as Control
	check("顶栏标题居中（主窗）",
		absf(cw_title.position.x + cw_title.size.x * 0.5 - cw_bar.size.x * 0.5) < 0.5,
		"%s / bar %s" % [cw_title.position, cw_bar.size])
	check("主窗横纹在顶栏内",
		cw_stripes.size.x <= cw_bar.size.x and cw_stripes.size.y <= cw_bar.size.y
			and float(cw_stripes.get("line_left")) >= 0.0
			and float(cw_stripes.get("line_right")) <= cw_bar.size.x,
		"%s / bar %s" % [cw_stripes.size, cw_bar.size])
	var frame_bg := scene.get_node_or_null("desk/case_win/bg") as Panel
	check("案件窗底板是程序化 Panel", frame_bg != null)
	if frame_bg != null:
		var fsb := frame_bg.get_theme_stylebox("panel") as StyleBoxFlat
		# 1-bit：白底上没有灰阶可分层，窗口与卡片叠在一起时唯一的线索就是**边框粗细**，
		# 所以窗框取 2px（卡片是 1px）。圆角归零 —— 圆角是柔光语法的残留。
		check("窗框是 2px 黑边 + 零圆角（比卡片 1px 重一档）",
			fsb != null and fsb.border_width_left == 2
				and fsb.border_color.is_equal_approx(TecTheme.LINE) and fsb.corner_radius_top_left == 0,
			str(fsb))
		check("窗框仍是 PAD 内缩（调用方坐标一个都没改）",
			frame_bg.position.is_equal_approx(Vector2(SysWindow.PAD, SysWindow.PAD))
				and frame_bg.size.is_equal_approx(case_win.size - Vector2(SysWindow.PAD, SysWindow.PAD) * 2.0),
			str(frame_bg.position) + " " + str(frame_bg.size))
	# 枢纽场景：双线框（对应 Web 的 3px double）
	var hub_card: NodeCard = _cards().get("loc:SCENES_garden")
	var border := hub_card.get_node_or_null("border") as Control
	check("枢纽场景走双线框", border != null and border.visible and bool(border.get("double_line")))
	# C1：黑色圆点退场，改成纸底墨字 + 1px 键线的小药丸，挂在卡片上缘居中。
	var unread_sb := hub_card._badge.get_theme_stylebox("normal") as StyleBoxFlat
	check("C1「新」角标 20×18 纸底墨字 + 1px 键线",
		hub_card._badge.size == Vector2(20, 18)
			and unread_sb != null
			and unread_sb.bg_color.is_equal_approx(TecTheme.CARD)
			and unread_sb.border_width_left == 1
			and unread_sb.border_color.is_equal_approx(TecTheme.EDGE)
			and unread_sb.corner_radius_top_left >= 100
			and hub_card._badge.get_theme_color("font_color").is_equal_approx(TecTheme.TEXT),
		str(hub_card._badge.size) + " " + str(unread_sb))
	check("C1「新」角标挂在卡上缘居中",
		hub_card._badge.position.is_equal_approx(
			Vector2(NodeCard.PAD + (hub_card._w - 20.0) * 0.5, -2.0)),
		str(hub_card._badge.position))

	# ── P0 交互（2026-10-21）：单击/双击分流 · 右键钉住 · 位置写回 · 落点表 · 连线 · 缩放 · 详情窗 ──
	var all2: Dictionary = _cards()
	var torch: NodeCard = all2.get(TORCH, null)
	check("手电筒还在画布上", torch != null)

	# 1) 单击只选中、不激活（旧版单击 = 双击，是最伤手感的一条）
	if scene.dbg_state()["lit"].get("ITEM_shoudiantong", false):
		scene.dbg_toggle_light("ITEM_shoudiantong")
	var lit0 := bool(scene.dbg_state()["lit"].get("ITEM_shoudiantong", false))
	_single_click(torch)
	await process_frame
	check("单击不激活（灯不变）", bool(scene.dbg_state()["lit"].get("ITEM_shoudiantong", false)) == lit0)
	check("单击会选中", String(scene.dbg_state()["selected"]) == TORCH, String(scene.dbg_state()["selected"]))
	_double_click(torch)
	await process_frame
	check("双击才激活（灯翻了）", bool(scene.dbg_state()["lit"].get("ITEM_shoudiantong", false)) != lit0)

	# 2) K11：右键 = 上下文菜单（钉住 / 查看详情），不再直接改状态。
	var rev := InputEventMouseButton.new()
	rev.button_index = MOUSE_BUTTON_RIGHT
	rev.pressed = true
	rev.global_position = torch.get_global_rect().get_center()
	torch._gui_input(rev)
	await process_frame
	check("K11 右键打开上下文菜单", scene._card_ctx != null)
	check("K11 菜单出现前不改钉住态", not bool(scene.graph.node(TORCH).get("pinned", false)))
	var ctx_pin := scene._card_ctx.find_child("ctx_pin", true, false) as Button
	check("K11 菜单有钉住项", ctx_pin != null and ctx_pin.text == "钉住")
	ctx_pin.pressed.emit()
	await process_frame
	check("K11 点菜单项后钉住", bool(scene.graph.node(TORCH).get("pinned", false)))
	check("钉住挂「已固定」角标", (torch.get_node("pin") as Label).visible)
	torch._gui_input(rev)
	await process_frame
	var ctx_unpin := scene._card_ctx.find_child("ctx_pin", true, false) as Button
	check("K11 再开菜单显示取消钉住", ctx_unpin != null and ctx_unpin.text == "取消钉住")
	ctx_unpin.pressed.emit()
	await process_frame
	check("再右键取消钉住", not bool(scene.graph.node(TORCH).get("pinned", false)))

	# 3) 拖到空白 = 停在原地并**写回数据**（旧版从不写回，下一次重排必然推翻）
	var drop_blank := _blank_point_near(scene, torch)
	_press(torch, torch.get_global_rect().get_center())
	_motion(torch, drop_blank)
	_release(torch, drop_blank)
	await process_frame
	check("拖到空白：坐标写回数据",
		absf(float(scene.graph.node(TORCH)["x"]) - torch.position.x) < 0.5
		and absf(float(scene.graph.node(TORCH)["y"]) - torch.position.y) < 0.5,
		str(torch.position) + " / " + str(scene.graph.node(TORCH).get("x")))
	check("C3 手动拖卡落 8px 网格",
		absf(torch.position.x - roundf(torch.position.x / 8.0) * 8.0) < 0.01
		and absf(torch.position.y - roundf(torch.position.y / 8.0) * 8.0) < 0.01,
		str(torch.position))

	# 3b) 纯状态互动不得重排（2026-10-21 现场问题：「每次和节点互动，整块画布的卡都会轻微偏移」）
	#     根因：`_relayout()` 无条件跑 260 轮力导向，而这套参数**不收敛** —— 实测同一批节点连跑 8 次，
	#     单次最大位移 194 → 72 → 38 → 21 → 12 → 6.9 → 3.9 → 2.3 → 1.3px，每跑一次全画布漂一次。
	#     Web 只在「真长出节点」时 `layout()`（09-commands.js：「开关灯只重绘 —— 重排会让灯自己跳位置」）。
	#     前面折叠 / 展开的 0.34s 落位补间可能还在飞，先等它落地，否则快照拍到的是动画中间态。
	await create_timer(0.45).timeout
	var pos_struct := {}
	for k in _cards().keys():
		pos_struct[String(k)] = (_cards()[k] as Control).position
	scene.dbg_activate(TORCH)                 # 点亮 / 熄灭手电筒 = 纯状态变化，结构没变
	await process_frame
	scene._relayout()                         # 结构没变的普通重排
	scene._relayout()
	await process_frame
	var drift_max := 0.0
	for k in pos_struct.keys():
		if _cards().has(k):
			drift_max = maxf(drift_max, (pos_struct[k] as Vector2).distance_to((_cards()[k] as Control).position))
	check("纯状态互动（点亮 / 普通重排）不挪任何一张卡", drift_max < 0.01, str(drift_max))
	scene.dbg_activate(TORCH)                 # 熄回去，保持后面用例的前提（未点亮）
	await process_frame

	# 4) 落点表：线索册拒收非线索 / 证物袋什么都收（并回原位）
	var bag_icon: Control = scene.get_node("desk/icons/icon_bag")
	var clue_icon: Control = scene.get_node("desk/icons/icon_clue")
	var pos_before := torch.position
	_drag(torch, clue_icon)
	await process_frame
	check("拖到线索册图标：非线索被拒", not scene.graph.stored.has(TORCH))
	await create_timer(0.45).timeout        # spring_back 是 300ms 缓出
	check("拒收后回原位", torch.position.distance_to(pos_before) < 1.5, str(torch.position))
	var edges_bag: EdgeLayer = scene.get_node("desk/case_win/body/stage/cards/edges")
	var drop_card: NodeCard = null
	for e in scene.graph.edges:
		var ka := String(e["a"])
		var kb := String(e["b"])
		for raw_key in [ka, kb]:
			var other_key := kb if raw_key == ka else ka
			var c := _cards().get(raw_key) as NodeCard
			var other := _cards().get(other_key) as NodeCard
			if c == null or other == null or c == torch or not c.visible or not other.visible:
				continue
			if String(scene.graph.node(raw_key).get("kind", "")) != "item":
				continue
			if scene.graph.is_container_node(raw_key) or not scene.graph.can_bag(raw_key):
				continue
			drop_card = c
			break
		if drop_card != null:
			break
	check("找到一张带连线的物品卡", drop_card != null)
	var store_at := drop_card.get_global_rect().get_center()
	_press(drop_card, store_at)
	_motion(drop_card, store_at + Vector2(12, 8))
	_motion(drop_card, bag_icon.get_global_rect().get_center())
	await process_frame
	await process_frame
	var had_edge := false
	var edge_start := drop_card.visual_center()
	for raw in edges_bag._segments:
		var seg0: Dictionary = raw
		if (seg0["a"] as Vector2).is_equal_approx(edge_start) \
			or (seg0["b"] as Vector2).is_equal_approx(edge_start):
			had_edge = true
			break
	check("收纳前物品有连线", had_edge)
	_release(drop_card, bag_icon.get_global_rect().get_center())
	var drop_center := drop_card.visual_center()
	var stale_edge := false
	for raw in edges_bag._segments:
		var seg1: Dictionary = raw
		if (seg1["a"] as Vector2).is_equal_approx(drop_center) \
			or (seg1["b"] as Vector2).is_equal_approx(drop_center):
			stale_edge = true
			break
	check("收进袋后旧连线立即断开", not stale_edge)
	await process_frame
	await process_frame
	check("拖到证物袋图标：收进袋",
		String(scene.graph.stored.get(drop_card.card_key, "")) == GraphState.BAG,
		String(scene.graph.stored.get(drop_card.card_key, "")))
	check("收进袋后卡片离场", not drop_card.visible)
	_drag(torch, bag_icon)
	await process_frame
	check("手电筒也收进袋", String(scene.graph.stored.get(TORCH, "")) == GraphState.BAG,
		String(scene.graph.stored.get(TORCH, "")))

	# 4b) 落点表完整性：id 一律来自 11 项白名单
	#     Web 的 nodeDropTargets() 是 10 项，推演桌布在松手处单独判一遍（11 个元素）；
	#     Godot 合并成同一条表，悬停高亮与松手分派共用 —— 不会"亮了却不生效"。
	var ids: Array = scene.dbg_drop_target_ids()
	var whitelist := ["chat-win", "bag-win", "clue-win", "bag-dock", "clue-icon",
		"tec-dock", "infer-icon", "tec-avatar", "tec-chip", "mx-board"]
	var stray: Array = []
	for did in ids:
		if not whitelist.has(String(did)):
			stray.append(did)
	check("K5 落点 id 全部在 10 项白名单内（档案不再是落点）", stray.is_empty(), str(stray))
	check("K5 档案图标已从落点表移除", not ids.has("goto-icon"), str(ids))
	var icons_all := true
	for need in ["bag-dock", "clue-icon", "tec-dock", "infer-icon"]:
		if not ids.has(need):
			icons_all = false
	check("四个桌面图标落点都在表里", icons_all, str(ids))
	# K5：拖场景到档案图标不再「前往」，但仍要拦住并说明原因。
	var goto_icon := scene.get_node("desk/icons/icon_goto") as Control
	if goto_icon != null and goto_icon.visible:
		scene._hide_toast()
		var before_explored: Array = (scene.dbg_state()["explored"] as Array).duplicate()
		var k_goto := "loc:SCENES_garden"
		check("K5 拖场景到档案被拦截",
			scene._handle_card_drop(k_goto, goto_icon.get_global_rect().get_center()))
		check("K5 档案拒收不改探索状态",
			(scene.dbg_state()["explored"] as Array) == before_explored)
		check("K5 档案拒收给 warning toast",
			scene.dbg_toast_text().contains("档案") and scene.dbg_toast_text().contains("时间点"),
			scene.dbg_toast_text())

	# 5) 推演器图标：线索能归位，非线索给提示
	var clue_card: NodeCard = null
	for key in _cards().keys():
		var c: NodeCard = _cards()[key]
		if String(scene.graph.node(String(key)).get("kind", "")) == "clue" and c.visible:
			clue_card = c
			break
	if clue_card != null:
		_drag(clue_card, scene.get_node("desk/icons/icon_infer"))
		await process_frame
		check("拖到推演器图标：线索归位", scene.graph.stored.has(clue_card.card_key)
			or scene.graph.matrix_ids().size() > 0, str(scene.dbg_state()["matrix_ids"]))

	# 6) 连线：实体边必须真的画出来（旧版画布一根线都没有）
	var edges: EdgeLayer = scene.get_node_or_null("desk/case_win/body/stage/cards/edges") as EdgeLayer
	check("连线层存在且画了线", edges != null and edges.segment_count() > 0,
		str(edges.segment_count()) if edges != null else "null")
	var edge_style := EdgeLayer.STYLE
	check("C2 已连通边：1px 实线",
		float(edge_style["entity"]["width"]) == 1.0
			and float(edge_style["move"]["width"]) == 1.0
			and float(edge_style["move"]["dash"]) == 0.0
			and (edge_style["move"]["color"] as Color).is_equal_approx(TecTheme.INK),
		str(edge_style["move"]))
	check("C2 可连未试边：1px 灰线",
		float(edge_style["cond"]["width"]) == 1.0
			and float(edge_style["cond"]["dash"]) == 0.0
			and (edge_style["cond"]["color"] as Color).is_equal_approx(TecTheme.EDGE_UNTRIED),
		str(edge_style["cond"]))
	check("C2 试过未成边：1px 虚线",
		float(edge_style["tried"]["width"]) == 1.0
			and float(edge_style["tried"]["dash"]) > 0.0
			and (edge_style["tried"]["color"] as Color).is_equal_approx(TecTheme.EDGE_TRIED),
		str(edge_style["tried"]))
	check("C2 拖动线：2px 实线 + 箭头",
		EdgeLayer.GHOST_WIDTH == 2.0 and EdgeLayer.GHOST_ARROW > 0.0,
		"%s / %s" % [EdgeLayer.GHOST_WIDTH, EdgeLayer.GHOST_ARROW])

	# 7) 滚轮 = 以光标为锚连续缩放（0.45~2.0，×1.12）
	var k0: float = scene._view_k
	var pos0: Vector2 = scene._view_pos
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = Vector2(500, 300)
	scene._on_stage_input(wheel)
	check("滚轮放大", scene._view_k > k0 + 0.001, "%f -> %f" % [k0, scene._view_k])
	var wheel2 := InputEventMouseButton.new()
	wheel2.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel2.pressed = true
	wheel2.position = Vector2(500, 300)
	scene._on_stage_input(wheel2)
	check("滚轮缩小", absf(scene._view_k - k0) < 0.005, "%f" % scene._view_k)

	# 7b) 连续缩放的下限：「看全貌」靠缩到 1x 以下，不是靠 1x/2x 两档
	for i in 14:
		scene._on_stage_input(wheel2)
	check("滚轮能一直缩到 0.45（连滚 14 格）", absf(scene._view_k - 0.45) < 0.001,
		"%f" % scene._view_k)
	for i in 14:
		scene._on_stage_input(wheel)
	check("滚轮能一直放大到 2.0", absf(scene._view_k - 2.0) < 0.001, "%f" % scene._view_k)

	# 7c) 卡面只有名字：类型靠左侧类型色符号，状态靠边框与填充
	var lod_card: NodeCard = null
	for key in _cards().keys():
		var c: NodeCard = _cards()[key]
		if c.visible:
			lod_card = c
			break
	check("卡面没有副标节点", lod_card != null and lod_card.get_node_or_null("sub") == null,
		"null" if lod_card == null else "sub 还在")
	check("标题不再拼 ■□●▲ 前缀", lod_card != null
		and not ("\u25a0" in lod_card._title.text or "\u25a1" in lod_card._title.text
			or "\u25cf" in lod_card._title.text or "\u25b2" in lod_card._title.text),
		"null" if lod_card == null else lod_card._title.text)
	check("类型符号常驻且带类型色", lod_card != null and lod_card._glyph.visible
		and lod_card._glyph.col == TecTheme.kind_color(lod_card.kind),
		"null" if lod_card == null else "%s %s" % [lod_card._glyph.visible,
			lod_card._glyph.col.to_html(false)])
	check("类型符号用圆形描边汉字", KindGlyph.GLYPH_TEXT.get("loc", "") == "地"
		and KindGlyph.GLYPH_TEXT.get("item", "") == "物"
		and KindGlyph.GLYPH_TEXT.get("char", "") == "人"
		and KindGlyph.GLYPH_TEXT.get("clue", "") == "线"
		and KindGlyph.GLYPH_TEXT.get("time", "") == "时",
		str(KindGlyph.GLYPH_TEXT))
	## U1：0.95 以下直接切纯符号档。0.9x 不再显示被重采样的标题。
	scene._view_k = 0.9
	scene._apply_view()
	check("U1 0.9x：标题退场、只留放大符号", lod_card != null and not lod_card._title.visible
		and lod_card._glyph.visible and lod_card._glyph.size.x > 60.0,
		"null" if lod_card == null else "%s/%.0f" % [lod_card._title.visible,
			lod_card._glyph.size.x])
	scene._view_k = 0.96
	scene._apply_view()
	check("U1 0.96x：标题回来", lod_card != null and lod_card._title.visible,
		"null" if lod_card == null else str(lod_card._title.visible))
	## 0.88x 实测标题已缺笔（「注射器」被压成「注器」）⇒ 再往下只留放大的类型符号
	scene._view_k = 0.6
	scene._apply_view()
	check("0.6x：文字退场、符号放大铺满", lod_card != null and not lod_card._title.visible
		and lod_card._glyph.visible and lod_card._glyph.size.x > 60.0,
		"null" if lod_card == null else "%s/%.0f" % [lod_card._title.visible,
			lod_card._glyph.size.x])
	check("0.6x：角标退场", lod_card != null and not lod_card._pin_badge.visible
		and not lod_card._warn_badge.visible, "badges")
	check("0.6x：连线收到了倍率", edges != null and absf(edges._zoom - 0.6) < 0.001,
		"%f" % edges._zoom if edges != null else "null")
	scene._view_k = 1.0
	scene._apply_view()
	check("1x：标题回来、符号缩回左侧", lod_card != null and lod_card._title.visible
		and lod_card._glyph.size.x <= NodeCard.GLYPH_BOX,
		"null" if lod_card == null else "%.0f" % lod_card._glyph.size.x)

	## 7c1) 符号必须**贴着首字**（不是钉在卡沿）：用一张短标题的合成卡做定值检验。
	## 旧版把符号固定在 `PAD+5`、标题另外居中，两字标题时符号离文字一大截、又压着卡边。
	var demo: NodeCard = NodeCard.new()
	demo.setup("loc:demo", "loc", {"label": "门锁"}, 152.0, 54.0)
	root.add_child(demo)
	await process_frame
	var g: Control = demo._glyph
	var tl: Label = demo._title
	check("符号右边 + 间隙 = 标题左边（符号紧贴首字）",
		absf(g.position.x + g.size.x + NodeCard.GLYPH_GAP - tl.position.x) < 0.6,
		"%.2f / %.2f" % [g.position.x + g.size.x, tl.position.x])
	check("符号不再钉在卡沿（左沿内缩 ≥ 6px，旧值 5px）",
		g.position.x - NodeCard.PAD >= 6.0,
		"%.2f" % (g.position.x - NodeCard.PAD))
	var dfont := tl.get_theme_font("font")
	var dfsz := tl.get_theme_font_size("font_size")
	var dtw := dfont.get_string_size(tl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, dfsz).x
	dtw = minf(dtw, demo._w - 12.0 - NodeCard.GLYPH_BOX - NodeCard.GLYPH_GAP)
	var dgroup := g.position.x - NodeCard.PAD + (NodeCard.GLYPH_BOX + NodeCard.GLYPH_GAP + dtw) * 0.5
	check("符号 + 标题作为一组在卡片里水平居中（±1px）",
		absf(dgroup - demo._w * 0.5) < 1.0,
		"组心 %.2f / 卡心 %.2f" % [dgroup, demo._w * 0.5])
	## 7c1b) 竖向：符号与文字挂在**同一个基准**（卡中线）上。
	## 标题用 TOP 对齐、矩形顶边落在「卡中线 − TITLE_INK_CY」，墨迹中心因此在卡中线上；
	## 符号中心也直接取卡中线。不再依赖 Godot 的「行盒居中」——那条规则在不同倍率/DPI 下
	## 会让墨迹漂 1.6px，方块只能对着某一档调，换台机器就歪（用户两次反馈「偏上/偏下」）。
	var dmid := NodeCard.PAD + demo._h * 0.5
	check("符号中心 = 卡中线（与文字同一基准）",
		absf(g.position.y + g.size.y * 0.5 - dmid) < 0.01,
		"符号心 %.2f / 卡中线 %.2f" % [g.position.y + g.size.y * 0.5, dmid])
	check("标题矩形顶边 = 卡中线 − TITLE_INK_CY（TOP 对齐，墨迹中心落在卡中线）",
		tl.vertical_alignment == VERTICAL_ALIGNMENT_TOP
			and absf(tl.position.y - (dmid - NodeCard.TITLE_INK_CY)) < 0.01,
		"顶边 %.2f / 期望 %.2f / valign %d" % [
			tl.position.y, dmid - NodeCard.TITLE_INK_CY, tl.vertical_alignment])
	check("符号边长 = GLYPH_BOX（18 = 圆形字牌外径）",
		absf(g.size.x - NodeCard.GLYPH_BOX) < 0.01 and absf(g.size.y - NodeCard.GLYPH_BOX) < 0.01,
		"%.1f×%.1f" % [g.size.x, g.size.y])
	demo.queue_free()
	await process_frame

	## 7c1c) 字牌笔画必须留缝：字号按圈内径的 ~2/3 取，笔画高度 < 内径。
	## （旧版文字档画 12px：CJK 墨高 16 > 内径 13.8，直接顶到弧线上。）
	var glyph_r := NodeCard.GLYPH_BOX * 0.5
	var gpx := KindGlyph.glyph_font_px(glyph_r, 1.0)
	var gfont := TecTheme.font()
	var gink := gfont.get_ascent(gpx) + gfont.get_descent(gpx)
	var ginner := NodeCard.GLYPH_BOX - 2.0 * 1.1
	check("U1 文字档字号 = 12px（原生格）", gpx == 12, "px %d" % gpx)
	check("U1 字牌笔画高度 < 圈内径（四边留缝）",
		gink < ginner, "墨高 %.1f / 内径 %.1f" % [gink, ginner])
	## 缩略档圈径足够大才跳到 24px，绝不再是 22/13 这类重采样档。
	var big_px := KindGlyph.glyph_font_px(22.0, 1.0)
	check("U1 缩略档字号 = 24px", big_px == 24, "px %d" % big_px)
	var big_ink := gfont.get_ascent(big_px) + gfont.get_descent(big_px)
	check("U1 缩略档笔画仍 < 圈内径", big_ink < (22.0 - 1.1) * 2.0,
		"墨高 %.1f / 内径 %.1f" % [big_ink, (22.0 - 1.1) * 2.0])

	## 7c1d) 打字机必须**全程按全文**占位：`visible_characters` 会让 Label 只在
	## 剩余字里算最小高度，窗体会塌成一行、正文溢出框外（用户反馈）。
	## 判据：打字期间的最小高度 == 同宽纯 Label（visible_characters=-1）的最小高度。
	var long_text := "植物学家的花园里种着许多花草，花盆沿上还摆着一把小铲子。".repeat(12)
	var tbox := Control.new()
	tbox.size = Vector2(360.0, 480.0)
	root.add_child(tbox)
	var tw := TecTheme.narrative_label(long_text, TecTheme.TEXT)
	tw.custom_minimum_size = Vector2(300.0, 0.0)
	tbox.add_child(tw)
	tw.start_typing()
	await process_frame
	await process_frame
	var ref := Label.new()
	ref.text = long_text
	ref.add_theme_font_override("font", TecTheme.font())
	ref.add_theme_font_size_override("font_size", 12)
	ref.add_theme_constant_override("line_spacing", TecTheme.NARR_LINE_SPACING)
	ref.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ref.size = Vector2(tw.size.x, 480.0)
	tbox.add_child(ref)
	await process_frame
	check("打字进行中（只揭示了几个字）",
		tw.is_typing() and tw.visible_characters >= 0 and tw.visible_characters < 6,
		"typing=%s vc=%d" % [tw.is_typing(), tw.visible_characters])
	check("打字期间最小高度 = 全文高度（不会塌回一行）",
		absf(tw.get_combined_minimum_size().y - ref.get_combined_minimum_size().y) < 0.5,
		"打字 %.1f / 全文 %.1f（宽 %.0f）" % [tw.get_combined_minimum_size().y,
			ref.get_combined_minimum_size().y, tw.size.x])
	# F7：同一整数档位不重复写 visible_characters；基准开关能复现旧行为。
	tw.set_process(false)
	tw.start_typing()
	tw.set_process(false)
	tw.dbg_reset_visible_writes()
	tw._process(0.0)
	tw._process(0.0)
	check("F7 打字机同一档位不重复写", tw.dbg_visible_writes() == 0,
		str(tw.dbg_visible_writes()))
	tw.dbg_set_legacy_writes(true)
	tw.start_typing()
	tw.set_process(false)
	tw.dbg_reset_visible_writes()
	tw._process(0.0)
	tw._process(0.0)
	check("F7 基准开关复现旧版逐帧写", tw.dbg_visible_writes() == 2,
		str(tw.dbg_visible_writes()))
	tw.dbg_set_legacy_writes(false)
	tbox.queue_free()

	## 7c1e) 叙事卡：底板盖满整窗 + 按全文增高。长文打字期间若只长一点，
	## 正文会画在底板之外 —— 读起来就是「窗口是透明的」。
	var nc := NarrCard.new()
	nc.setup_narr("测试", long_text)
	root.add_child(nc)
	await process_frame
	await process_frame
	await process_frame
	var nbg := nc.get_node_or_null("bg") as Control
	var ntxt := nc.get_node_or_null("body/content/narr_text") as TypewriterLabel
	check("叙事卡底板与整窗同比（长高后不露桌面）",
		nbg != null and absf(nbg.size.y - (nc.size.y - SysWindow.PAD * 2.0)) < 0.01
			and absf(nbg.size.x - (nc.size.x - SysWindow.PAD * 2.0)) < 0.01,
		"null" if nbg == null else "底板 %s / 窗 %s" % [nbg.size, nc.size])
	check("叙事卡按全文增高（打字期间不缩回一行）",
		ntxt != null and absf(nc.size.y - SysWindow.PAD * 2.0
			- (SysWindow.BAR_H + 20.0 + ntxt.get_combined_minimum_size().y)) < 1.0,
		"null" if ntxt == null else "窗内高 %.1f / 文字 %.1f" % [
			nc.size.y - SysWindow.PAD * 2.0, ntxt.get_combined_minimum_size().y])
	nc.queue_free()
	await process_frame

	# 7c2) 状态三态：副标删掉后，折叠与未探索必须能只靠「纸 + 框」区分
	#   未探索 = 纸色平面 + 虚线框；折叠 = 白纸 + 虚线框；已探索 = 白纸 + 实线框
	if lod_card != null:
		lod_card.set_shell_state(true, false, false, false)
		var unexp := [lod_card._border.visible,
			bool(lod_card._mat.get_shader_parameter("flat_fill"))]
		lod_card.set_shell_state(true, true, true, false)
		var coll := [lod_card._border.visible,
			bool(lod_card._mat.get_shader_parameter("flat_fill"))]
		lod_card.set_shell_state(true, true, false, false)
		var expl := [lod_card._border.visible,
			bool(lod_card._mat.get_shader_parameter("flat_fill"))]
		check("未探索 = 虚线 + 纸色平面", unexp[0] and unexp[1], str(unexp))
		check("已折叠 = 虚线 + 白纸（不再和未探索同款）", coll[0] and not coll[1], str(coll))
		check("已探索 = 实线 + 白纸", not expl[0] and not expl[1], str(expl))
		lod_card.set_shell_state(true, true, false, false)
	# 7d) 「适应窗口」按包围盒缩放：装不下才缩，且真的写进图层变换
	scene._view_user = false
	scene._fit_cards()
	check("U1 适应窗口落在 0.45~1.0（只缩不放）",
		scene._view_k >= 0.45 - 0.001 and scene._view_k <= 1.0 + 0.001,
		"%f" % scene._view_k)
	check("适应窗口写进图层缩放", scene._card_layer.scale.is_equal_approx(
		Vector2(scene._view_k, scene._view_k)), str(scene._card_layer.scale))
	scene._view_user = true
	# 相机还原：后面几节按投影换算点击落点，镜头被留在 2x/0.6x 上会把坐标算飞
	scene._view_k = k0
	scene._view_pos = pos0
	scene._view_user = true
	scene._apply_view()

	# 8) 点空白 = 清选中 + 收起详情窗
	var vis_card: NodeCard = null
	for key in _cards().keys():
		var c2: NodeCard = _cards()[key]
		if c2.visible:
			vis_card = c2
			break
	_single_click(vis_card)
	await process_frame
	await process_frame
	check("选中后有选中的 key", String(scene.dbg_state()["selected"]) != "")
	var blank := InputEventMouseButton.new()
	blank.button_index = MOUSE_BUTTON_LEFT
	blank.pressed = true
	blank.position = Vector2(420, 260)
	scene._on_stage_input(blank)
	var blank_up := InputEventMouseButton.new()
	blank_up.button_index = MOUSE_BUTTON_LEFT
	blank_up.pressed = false
	blank_up.position = Vector2(420, 260)
	scene._on_stage_input(blank_up)
	await process_frame
	check("点空白清选中", String(scene.dbg_state()["selected"]) == "")

	# 9) 详情窗：选中即显示，三种内容（简介 / 状态），且不剧透「装着什么 / 谁指向它」
	_single_click(vis_card)
	await process_frame
	await process_frame
	check("C-B 节点选中环 = 强调青",
		vis_card._sel.visible and vis_card._sel.sel_color.is_equal_approx(TecTheme.SPOT_ACCENT))
	var dw: DetailWin = scene.get_node_or_null("desk/detail_win") as DetailWin
	check("详情窗跟随选中", dw != null and dw.visible)
	if dw != null:
		var body_txt: String = dw._compose(scene.graph.node(vis_card.card_key))
		check("详情窗有简介段", body_txt.contains("D:"))
		check("详情窗不剧透关系", not body_txt.contains("装着") and not body_txt.contains("指向它"))
		# A3：详情窗贴右沿按视口现算，不再写死 1280。
		dw.place_right(960.0)
		check("A3 960 宽详情窗贴右沿",
			absf(dw.position.x + SysWindow.PAD + DetailWin.W - (960.0 - DetailWin.PAD_R)) < 0.01,
			"%s / size %s" % [dw.position, dw.size])
		dw.place_right()

		# W6：× 只收起，不再销毁；后台 commit 不能把它重新弹开。
		dw._on_close_pressed()
		await process_frame
		check("W6 × 关闭详情窗", not dw.visible)
		check("W6 关闭后实例保留（可再次打开）", is_instance_valid(dw))
		var commit_before: Dictionary = scene._save.snapshot()
		scene.graph.mark_fresh(vis_card.card_key)
		scene._commit(commit_before)
		await process_frame
		check("W6 任意操作不复活已关闭详情", not dw.visible)
		scene._on_card_selected(vis_card.card_key)
		await process_frame
		check("W6 再点卡片可重新打开详情", dw.visible)

		# U2：叙事打字中详情挂起，播完 / 点击补全后整段出现。
		scene._show_narr("SCENES_garden")
		await process_frame
		var u2_narr: NarrCard = scene._narr
		var u2_para: TypewriterLabel = null
		if dw != null:
			u2_para = dw.find_child("dt_desc", true, false) as TypewriterLabel
		check("U2 叙事卡开始打字", u2_narr != null and u2_narr.is_typing())
		check("U2 打字中详情先收起", not dw.visible)
		scene._refresh_detail()
		await process_frame
		check("U2 打字中后台刷新不弹详情", not dw.visible)
		if u2_narr != null:
			var narr_click := InputEventMouseButton.new()
			narr_click.button_index = MOUSE_BUTTON_LEFT
			narr_click.pressed = true
			narr_click.global_position = u2_narr.get_global_rect().get_center()
			u2_narr._gui_input(narr_click)
		await process_frame
		await process_frame
		check("W17 单击叙事卡补全", u2_narr == null or not u2_narr.is_typing())
		check("U2 叙事播完补显示详情", dw.visible)
		check("U2 补显示不二次打字", u2_para != null and not u2_para.is_typing(),
			"null" if u2_para == null else str(u2_para.is_typing()))
		if scene._narr != null and is_instance_valid(scene._narr):
			scene._narr.queue_free()
		scene._narr = null
		scene._pending_detail = false
		# 叙事卡 queue_free 在帧末生效；先让它离场，后面的画布落点才不会被残影挡住。
		await process_frame

	# 10) 反应表：把物品拖给人物要能说出话来（14 条反应表此前完全不可达）
	var item_key: String = scene.dbg_ensure("item", "ITEMS_changji")
	var char_key: String = scene.dbg_ensure("char", "CHARS_zs")
	var res: Dictionary = scene.combos.use_item(item_key, char_key)
	check("反应表通道：物品拖给人有台词", bool(res.get("ok", false))
		and String(res.get("message", "")).length() > 4, str(res.get("message", "")))

	# 11) 反向：从证物袋拖一行回画布，**落在松手那一点**（旧版取回只用默认位）
	var stage3: Control = scene.get_node("desk/case_win/body/stage")
	var drop_at := stage3.get_global_rect().get_center() + Vector2(80, -60)
	scene.dbg_storage_drag(TORCH, drop_at)
	await process_frame
	await process_frame
	check("袋行拖回画布：重新可见", not scene.graph.stored.has(TORCH))
	var back: NodeCard = _cards().get(TORCH, null)
	check("袋行拖回画布：落在松手那一点", back != null and back.visible
		and back.get_global_rect().has_point(drop_at),
		str(back.get_global_rect()) if back != null else "null")

	# K4/K6：收纳行拖到「另一扇收纳图标」必须被分派器接住并拒绝，不能掉回画布取回。
	scene._store_into(GraphState.BAG, TORCH)
	check("K4 先把物品收回证物袋", String(scene.graph.stored.get(TORCH, "")) == GraphState.BAG)
	scene._hide_toast()
	scene.dbg_storage_drag(TORCH, (scene.get_node("desk/icons/icon_clue") as Control).get_global_rect().get_center())
	await process_frame
	check("K4 袋行拖到线索册图标仍留在袋里",
		String(scene.graph.stored.get(TORCH, "")) == GraphState.BAG,
		String(scene.graph.stored.get(TORCH, "")))
	check("K6 物品进线索册按目标回绝",
		scene.dbg_toast_text().contains("线索册") and scene.dbg_toast_text().contains("只有线索"),
		scene.dbg_toast_text())
	scene.graph.take_back(TORCH)
	scene._apply_hidden()
	scene._refresh_or_spawn_card(TORCH)
	await process_frame
	check("K4 复原手电筒到画布", not scene.graph.stored.has(TORCH))

	# ── P0 交互（批 2）：拖动幽灵线 · 桌布 chip 带坐标取回 ──
	var mw: MatrixWin = scene.dbg_open_matrix()
	await process_frame
	check("桌布窗能打开", mw != null)
	# 挑一个不压在任何可见卡 / 开着的窗 / 桌布上的松手点（四角 + 四边各试一次）
	var blank_pt := _empty_canvas_point(scene)
	check("测试前提：落点在空画布、桌布外、开着的窗口",
		not mw.get_global_rect().has_point(blank_pt)
		and not (scene._bag_win != null and scene._bag_win.get_global_rect().has_point(blank_pt))
		and not (scene._ledger_win != null and scene._ledger_win.get_global_rect().has_point(blank_pt)),
		str(blank_pt))

	# 12) 幽灵线（Web 08-interact.js:63）：拖动中从卡片中心直连指针，松手即收
	var edges2: EdgeLayer = scene.get_node("desk/case_win/body/stage/cards/edges")
	_press(torch, torch.get_global_rect().get_center())
	_motion(torch, blank_pt)
	check("拖动中幽灵线出现", edges2.has_ghost())
	check("幽灵线起点 = 被拖卡中心",
		(edges2.ghost_points()["a"] as Vector2).is_equal_approx(torch.visual_center()),
		str(edges2.ghost_points()))
	var want_b: Vector2 = (blank_pt - stage3.get_global_position() - scene._view_pos) / scene._view_k
	check("幽灵线终点 = 指针（world）",
		((edges2.ghost_points()["b"] as Vector2) - want_b).length() < 0.5,
		str(edges2.ghost_points()))
	_release(torch, blank_pt)
	await process_frame
	check("松手幽灵线收起", not edges2.has_ghost())

	# 13) 桌布 chip → 画布（带坐标，反向 8 条路径的最后一条）/ chip → 册图标 = 收进册子
	var clue_key := "clue:CLUES_nm"
	check("测试前提：松手点在桌布外", not mw.get_global_rect().has_point(blank_pt))
	scene.dbg_matrix_assign(clue_key)
	await process_frame
	var chip_panel: Control = mw._chips.get("CLUES_nm", null) as Control
	check("归位后桌布上有芯片", chip_panel != null)
	# K2：单击芯片 = 看详情；不再用双击偷偷取回。
	_chip_press(chip_panel, chip_panel.get_global_rect().get_center())
	_chip_release(chip_panel, chip_panel.get_global_rect().get_center())
	await process_frame
	check("K2 单击桌布芯片仍留在桌布", String(scene.graph.stored.get(clue_key, "")) == GraphState.MATRIX,
		String(scene.graph.stored.get(clue_key, "")))
	check("K2 单击桌布芯片打开详情", scene._detail_win != null and scene._detail_win.visible
		and scene._selected == clue_key, scene._selected)
	var dbl := InputEventMouseButton.new()
	dbl.button_index = MOUSE_BUTTON_LEFT
	dbl.pressed = true
	dbl.double_click = true
	dbl.global_position = chip_panel.get_global_rect().get_center()
	chip_panel.gui_input.emit(dbl)
	_chip_release(chip_panel, chip_panel.get_global_rect().get_center())
	await process_frame
	check("K2 双击芯片不再取回", String(scene.graph.stored.get(clue_key, "")) == GraphState.MATRIX,
		String(scene.graph.stored.get(clue_key, "")))
	## K2（2026-10-25 改判）：chip 上不再放「取回」按钮；单击看详情，取回只走拖出桌布。
	check("K2 芯片不再有取回按钮", chip_panel.find_child("take", true, false) == null)
	_chip_press(chip_panel, chip_panel.get_global_rect().get_center())
	_chip_motion(chip_panel, blank_pt)
	_chip_release(chip_panel, blank_pt)
	await process_frame
	await process_frame
	check("chip 拖出桌布：重新回到画布", not scene.graph.stored.has(clue_key))
	var back2: NodeCard = _cards().get(clue_key, null)
	check("chip 回到画布：落在松手那一点", back2 != null and back2.visible
		and back2.get_global_rect().has_point(blank_pt),
		str(back2.get_global_rect()) if back2 != null else "null")
	var n2: Dictionary = scene.graph.node(clue_key)
	var want2: Vector2 = (blank_pt - stage3.get_global_position() - scene._view_pos) / scene._view_k
	check("chip 回画布：坐标写回数据",
		absf(float(n2["x"]) - back2.position.x) < 0.5
		and absf(float(n2["x"]) - want2.x) < 0.5
		and absf(float(n2["y"]) - want2.y) < 0.5,
		str(n2["x"]) + " / " + str(n2["y"]) + " want " + str(want2))

	# chip 拖到线索册图标 = 收进册子（Web overLedgerDrop：窗或图标都算）
	scene.dbg_matrix_assign(clue_key)
	await process_frame
	chip_panel = mw._chips.get("CLUES_nm", null) as Control
	var clue_icon2: Control = scene.get_node("desk/icons/icon_clue")
	_chip_press(chip_panel, chip_panel.get_global_rect().get_center())
	_chip_motion(chip_panel, clue_icon2.get_global_rect().get_center())
	_chip_release(chip_panel, clue_icon2.get_global_rect().get_center())
	await process_frame
	check("chip 拖到册图标：收进册",
		String(scene.graph.stored.get(clue_key, "")) == GraphState.LEDGER,
		String(scene.graph.stored.get(clue_key, "")))

	# ── 批 3（报告 §3.3 P2 残留）：warn 药丸 · pop 入场 · hover 光标 · dim 0.32 · 场景命令 · 拖动镜像 ──

	# 14) G2 修复后，「门的后面」有命令产出通路，不再是「无文本入口」。
	check("谓词：mdhm 未探索前", not (scene.dbg_state()["explored"] as Array).has("SCENES_mdhm"))
	check("谓词：枢纽花园（5 条入边）不算", not scene.graph.is_no_entry("loc:SCENES_garden"))
	check("谓词：命令产出的 choutiyi 不算", not scene.graph.is_no_entry("loc:SCENES_choutiyi"))
	var md_key: String = scene.dbg_ensure("loc", "SCENES_mdhm")
	await process_frame
	check("谓词：mdhm 有产出通路后不算无入口", not scene.graph.is_no_entry(md_key))
	var md_card: NodeCard = _cards().get(md_key, null)
	check("mdhm 上卡", md_card != null)
	check("mdhm 不再挂无文本入口药丸",
		md_card != null and not md_card._warn and not md_card._warn_badge.visible)
	check("已探索的花园不挂药丸", (_cards()["loc:SCENES_garden"] as NodeCard)._warn == false)

	# 15) V4 pop：fresh 节点初生 0.4→1.12→1（0.45s）；fresh 一次性消费、「新」角标保留
	## 推演窗还开着时，新卡可能被遮挡层冻结 process；先收掉再验入场动画。
	if scene._matrix_win != null and is_instance_valid(scene._matrix_win):
		scene._toggle_matrix()
		await process_frame
	scene._hide_toast()
	var pop_key: String = scene.dbg_ensure("clue", "CLUES_wmhj")
	await process_frame
	var pop_card: NodeCard = _cards().get(pop_key, null)
	check("前提：dbg_ensure 不标记 fresh（首次出生不弹）",
		pop_card != null and pop_card.scale.is_equal_approx(Vector2.ONE)
		and not bool(scene.graph.node(pop_key).get("fresh", false)))
	scene.graph.mark_fresh(pop_key)
	var old_pop: NodeCard = _cards().get(pop_key, null)
	if old_pop != null:
		old_pop.queue_free()
		scene._cards.erase(pop_key)
	await process_frame
	scene.dbg_ensure("clue", "CLUES_wmhj")
	var reborn: NodeCard = _cards().get(pop_key, null)
	check("pop 初生：0.4", reborn != null and reborn.scale.is_equal_approx(Vector2(0.4, 0.4)),
		str(reborn.scale if reborn != null else Vector2.ZERO))
	check("fresh 已被消费", not bool(scene.graph.node(pop_key).get("fresh", false)))
	await create_timer(0.6).timeout
	check("pop 收尾：1.0", reborn.scale.is_equal_approx(Vector2.ONE), str(reborn.scale))
	check("pop 收尾：不透明", absf(reborn.modulate.a - 1.0) < 0.02,
		str(reborn.modulate.a))
	check("「新」角标还在（unread 不随 pop 摘）", reborn._badge.visible)

	# 16) N8 hover：悬停 shade_soft 7→10、离开还原 + 手形光标（Web .node{cursor:grab}）
	md_card.mouse_entered.emit()
	check("悬停：shade 变浅",
		float(md_card._mat.get_shader_parameter("shade_soft")) == 10.0,
		str(md_card._mat.get_shader_parameter("shade_soft")))
	check("悬停：光标手形", md_card.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND)
	md_card.mouse_exited.emit()
	check("离开：shade 还原",
		float(md_card._mat.get_shader_parameter("shade_soft")) == 7.0)

	# 17) V6 dim：选中卡以外的卡片不透明度 0.32（Web .node.dim；P0 里误写成 0.25）
	_single_click(md_card)
	var dim_other: NodeCard = _cards()[pop_key]
	check("无关卡被淡化到 0.32", dim_other.modulate.is_equal_approx(Color(1, 1, 1, 0.32)),
		str(dim_other.modulate))
	check("选中卡保持不透明", md_card.modulate.is_equal_approx(Color(1, 1, 1, 1)))

	# 18) N7 场景命令：双击带 commands 的场景先跑 commands[0]（a001 数据 0/11 用到，
	# 运行时注入验证接线；无命令时回到「展开 / 折叠」默认）
	check("前提：garden 数据无命令", case_cmds_empty())
	# 第 8/9 节的两次单击 realtime 间隔 < 280ms 会合成「双击激活」把 garden 折叠
	# （与 Web dblclick 同一句话）—— 这里显式 uncollapse，再验证 N7 分支
	scene.graph.uncollapse("SCENES_garden")
	await process_frame
	check("前提：garden 展开态", not (scene.dbg_state()["collapsed"] as Array).has("SCENES_garden"))
	var tcmd := TextCommandDef.new()
	tcmd.value = "SCN-CMD-PROBE 床底下压着一行蜡笔字"
	var injected: Array[CommandDef] = [tcmd]
	var gdef = scene.case_def.scene_of("SCENES_garden")
	gdef.commands = injected
	# P2 Toast 排队：上一条还在屏上时新文案不会立即顶替，先清掉再验证命令命中。
	scene._hide_toast()
	_double_click(_cards()["loc:SCENES_garden"] as NodeCard)
	await process_frame
	check("带命令场景双击：先跑命令（toast 命中）",
		String(scene._toast_label.text).contains("SCN-CMD-PROBE"),
		String(scene._toast_label.text))
	check("带命令场景双击：不折叠",
		not (scene.dbg_state()["collapsed"] as Array).has("SCENES_garden"))
	var cleaned: Array[CommandDef] = []
	gdef.commands = cleaned
	_double_click(_cards()["loc:SCENES_garden"] as NodeCard)
	await process_frame
	check("无命令场景双击：回到折叠默认",
		(scene.dbg_state()["collapsed"] as Array).has("SCENES_garden"))

	# 19) D6 拖动镜像（Web #drag-layer）：拖起 = 镜像挂桌布最顶 + 原卡隐藏；
	# 松手 = 镜像退场 + 原卡复位；被拖卡的连线照常续画
	var stage4: Control = scene.get_node("desk/case_win/body/stage")
	var torch4: NodeCard = _cards()[TORCH]
	var m_a: Vector2 = torch4.get_global_rect().get_center()
	var m_blank: Vector2 = _empty_canvas_point(scene)
	var edges4: EdgeLayer = scene.get_node("desk/case_win/body/stage/cards/edges")
	_press(torch4, m_a)
	_motion(torch4, m_blank)
	var mir: NodeCard = scene._card_mirror
	check("拖起：镜像挂在桌布上", mir != null and is_instance_valid(mir)
		and mir.get_parent() == scene.get_node("desk"), str(mir))
	# 原件让位给镜像：**不能用 visible=false**（隐藏的 Control 会被 GUI 命中判定剔除，
	# 后续 motion 投递不到它 ⇒ 拖一下就僵住、松手也收不到）。只降透明度，事件照收。
	check("拖起：原卡让位（全透明但仍在树里）",
		torch4.visible and torch4.is_visible_in_tree() and torch4.modulate.a < 0.01,
		str(torch4.modulate.a) + " / visible=" + str(torch4.visible))
	check("拖起：镜像不收输入", mir == null or mir.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	check("拖起：镜像跟着原卡",
		mir != null and mir.global_position.is_equal_approx(torch4.get_global_position()),
		str(mir.global_position if mir != null else Vector2.ZERO))
	check("拖起：被拖卡的连线照常画", edges4.segment_count() > 0, str(edges4.segment_count()))
	check("拖起：幽灵线提升到窗体之上",
		scene._drag_line != null and scene._drag_line.has_ghost()
			and int(scene._drag_line.get_meta("zrank", 0)) > 25,
		str(scene._drag_line.get_meta("zrank", 0)) if scene._drag_line != null else "null")
	_release(torch4, m_blank)
	await process_frame
	check("松手：镜像退场", scene._card_mirror == null)
	check("松手：顶层幽灵线退场",
		scene._drag_line == null or not scene._drag_line.has_ghost())
	check("松手：原卡复位可见", torch4.visible)
	check("松手：坐标写回数据（同第 12-18 节口径）",
		absf(float(scene.graph.node(TORCH)["x"]) - torch4.position.x) < 0.5,
		str(scene.graph.node(TORCH)["x"]) + " / " + str(torch4.position.x))
	# 收掉推演窗与两扇收纳窗（S6/S7 起开着）：后面的交互章节要用整块画布，
	# 别让 mx-board / bag-win / clue-win 拦走 _drop_targets 里的落点
	if scene._matrix_win != null and is_instance_valid(scene._matrix_win):
		scene._toggle_matrix()
	if scene._bag_win != null and is_instance_valid(scene._bag_win):
		scene._toggle_storage(GraphState.BAG)
	if scene._ledger_win != null and is_instance_valid(scene._ledger_win):
		scene._toggle_storage(GraphState.LEDGER)
	mw = null
	await process_frame

	# 20) 位置过渡（Web `.node{transition: left/top .34s cubic-bezier(.4,0,.2,1)}`）：
	# 折叠 / 展开触发的那次重排才有过渡（`_relayout(true)`），普通重排秒到；
	# 动画期间连线逐帧跟画；新节点（Web 初绘没有“从哪里来”）直接落位
	var tk20: NodeCard = _cards()[TORCH]
	var start20: Vector2 = tk20.position
	# 只改数据（Web render() 前必改 n.x/n.y），卡片留在原地 → relayout 计算的目标在别处，必然要搬它
	var far20: Vector2 = start20 + Vector2(480.0, -260.0)
	scene.graph.node(TORCH)["x"] = far20.x
	scene.graph.node(TORCH)["y"] = far20.y
	scene._relayout(true, true)
	var target20: Vector2 = Vector2(float(scene.graph.node(TORCH)["x"]), float(scene.graph.node(TORCH)["y"]))
	check("重排：搬家目标离原位很远", target20.distance_to(start20) > 2.0,
		str(target20) + " / " + str(start20))
	await process_frame
	check("过渡：补间已挂上", scene._move_twens.has(TORCH))
	check("过渡：动画在路上（未到终点）", tk20.position.distance_to(target20) > 1.0,
		str(tk20.position) + " → " + str(target20))
	check("过渡：连线跟随窗口开着", scene._follow_frames > 0, str(scene._follow_frames))
	await create_timer(0.55).timeout
	check("过渡：收尾到位", tk20.position.distance_to(target20) < 1.0, str(tk20.position))
	check("过渡：补间已清空", scene._move_twens.is_empty(), str(scene._move_twens.keys()))
	var uc20 := ""
	for cid20 in ["CLUES_qsan", "CLUES_mgd", "CLUES_wmhj"]:
		if not scene.graph.has("clue", cid20):
			uc20 = cid20
			break
	var new_key20: String = scene.dbg_ensure("clue", uc20)
	await process_frame
	var new_card20: NodeCard = _cards().get(new_key20, null)
	check("新节点：直接落位（不播过渡）",
		new_card20 != null and new_card20.position.is_equal_approx(
			Vector2(float(scene.graph.node(new_key20)["x"]), float(scene.graph.node(new_key20)["y"])))
		and not scene._move_twens.has(new_key20))

	# 21) 反应表三条产出来源（Web 05-combine.js:112-123，A-001 反应表全是纯文本 —— 注入验证接线）：
	#     A) 真拖到陆珩松：results.scene + results.items 长出卡片（「新」角标）；
	#     B) 再注入一条直调数据层：断言 cond 边 / fresh / 主人右下 (60 + i*26) 这些数据级口径
	var scene_pick := ""
	for sid21 in ["SCENES_lhsdst", "SCENES_cjag"]:
		if not scene.graph.has("loc", sid21):
			scene_pick = sid21
			break
	var item_picks: Array = []
	for iid21 in ["ITEMS_dlh", "ITEMS_a4paper", "ITEMS_zbbdz", "ITEMS_yjh"]:
		if item_picks.size() < 2 and not scene.graph.has("item", iid21):
			item_picks.append(iid21)
	check("注入前提：找到没上画的场景与物品",
		scene_pick != "" and item_picks.size() == 2, scene_pick + " / " + str(item_picks))
	var lut := ReactionDef.new()
	lut.trigger_id = "ITEM_shoudiantong"
	lut.text = "REACTION-PROBE 反应表注入"
	lut.clues = [scene.case_def.clue_of("CLUES_qsan")]
	lut.results = {"scene": scene_pick, "items": item_picks}
	var lg: CharDef = scene.case_def.char_of("CHARS_luhengs")
	lg.item_reactions.insert(0, lut)
	scene.dbg_ensure("char", "CHARS_luhengs")
	await process_frame
	var lc21: NodeCard = _cards().get("char:CHARS_luhengs", null)
	check("前提：陆珩松卡片在画布", lc21 != null)
	var before21: int = scene.graph.logs.size()
	_drag(_cards()[TORCH], lc21)
	await process_frame
	check("反应表命中（案卷多了组合条目）", scene.graph.logs.size() > before21)
	var sk21: String = scene.graph.key_of("loc", scene_pick)
	check("产出①：新场景卡片上画布", _cards().has(sk21))
	check("产出①：cond 边连向反应表主人（新建才连）",
		scene.graph.has_edge("char:CHARS_luhengs", sk21, "cond"),
		str(scene.graph.has_edge("char:CHARS_luhengs", sk21, "cond")))
	for i21a in item_picks.size():
		var ik21a: String = scene.graph.key_of("item", String(item_picks[i21a]))
		var icard21a: NodeCard = _cards().get(ik21a, null)
		check("产出②：物品卡片上画布", icard21a != null)
		check("产出②：物品挂着「新」", icard21a != null and icard21a._badge.visible)
	var last_log: String = ""
	if not scene.graph.logs.is_empty():
		last_log = String((scene.graph.logs[scene.graph.logs.size() - 1] as Dictionary).get("text", ""))
	check("桌面：获得清单进案卷", last_log.contains("获得")
		and last_log.contains(String(scene.graph.node("char:CHARS_luhengs").get("label", ""))), last_log)
	# B) 数据层：再注入一条（换 trigger），直调数据层验证 fresh / cond / spawnItems 偏移公式
	var scene_pick2 := ""
	for sid21b in ["SCENES_lhsdst", "SCENES_cjag"]:
		if sid21b != scene_pick and not scene.graph.has("loc", sid21b):
			scene_pick2 = sid21b
			break
	var item_picks2: Array = []
	for iid21b in ["ITEMS_dlh", "ITEMS_a4paper", "ITEMS_zbbdz", "ITEMS_yjh"]:
		if item_picks2.size() < 2 and not scene.graph.has("item", iid21b) \
			and not item_picks.has(iid21b):
			item_picks2.append(iid21b)
	check("注入前提 B：还有没上画的场景与物品",
		scene_pick2 != "" and item_picks2.size() == 2, scene_pick2 + " / " + str(item_picks2))
	var lut2 := ReactionDef.new()
	lut2.trigger_id = "ITEMS_htys"
	lut2.text = "REACTION-PROBE-2 数据层注入"
	lut2.results = {"scene": scene_pick2, "items": item_picks2}
	lg.item_reactions.insert(1, lut2)
	scene.dbg_ensure("item", "ITEMS_htys")
	await process_frame
	var r21b: Dictionary = scene.combos.use_item("item:ITEMS_htys", "char:CHARS_luhengs")
	check("数据层：反应表命中", bool(r21b.get("ok", false)), str(r21b))
	var sk21b: String = scene.graph.key_of("loc", scene_pick2)
	var snode21b: Dictionary = scene.graph.node(sk21b)
	check("数据层：新场景 fresh/unread 已挂",
		bool(snode21b.get("fresh", false)) and bool(snode21b.get("unread", false)), str(snode21b.get("fresh")))
	check("数据层：cond 边连向反应表主人",
		scene.graph.has_edge("char:CHARS_luhengs", sk21b, "cond"),
		str(scene.graph.has_edge("char:CHARS_luhengs", sk21b, "cond")))
	var src21b: Vector2 = Vector2(float(scene.graph.node("char:CHARS_luhengs")["x"]),
		float(scene.graph.node("char:CHARS_luhengs")["y"]))
	for i21b in item_picks2.size():
		var ik21b: String = scene.graph.key_of("item", String(item_picks2[i21b]))
		check("数据层：物品 %s fresh 已挂" % String(item_picks2[i21b]),
			scene.graph.has("item", String(item_picks2[i21b]))
			and bool(scene.graph.node(ik21b).get("fresh", false)))
		check("数据层：位置 = 主人右下 60 + %d*26" % i21b,
			Vector2(float(scene.graph.node(ik21b)["x"]), float(scene.graph.node(ik21b)["y"]))
				.is_equal_approx(src21b + Vector2(60.0 + 26.0 * float(i21b), 60.0 + 26.0 * float(i21b))),
			str(scene.graph.node(ik21b)))
	check("§7-2 结构化反应线索建卡（回归）", scene.graph.has("clue", "CLUES_qsan"))

	# 22) z 序：新打开 / 被点击的系统窗提到浮动窗栈顶；
	# icons 在浮动窗之下；toast(30) 在 TEC(28) 之上；镜像(40) 在 toast 之上
	var desk22: Control = scene.get_node("desk")
	scene._toggle_case_map()
	await process_frame
	scene._toggle_log()
	await process_frame
	var e_log: Control = scene._log_win
	var e_map: Control = scene._map_win
	var e_icons: Control = desk22.get_node("icons")
	check("z：后开的日志提到浮动窗栈顶", e_log.get_index() > e_map.get_index(),
		str(e_log.get_index()) + " / " + str(e_map.get_index()))
	check("z：icons(24) 在地图窗之下", e_icons.get_index() < e_map.get_index())
	check("z：icons(24) 在日志窗之下", e_icons.get_index() < e_log.get_index())
	# A2：激活态跟随实际层序 —— 刚打开的日志就是当前窗
	var map_w := e_map as SysWindow
	var log_w := e_log as SysWindow
	check("A2：当前窗（日志）为激活态", log_w.is_window_active())
	check("A2：地图窗转为非激活", not map_w.is_window_active())
	var log_stripes = log_w._rules[0]
	var map_stripes = map_w._rules[0]
	check("A2/C-B：激活窗标题横纹为强调青",
		log_stripes.visible and log_stripes.col.is_equal_approx(TecTheme.SPOT_ACCENT))
	check("A2/C-B：非激活窗标题横纹保留但用墨色",
		map_stripes.visible and map_stripes.col.is_equal_approx(TecTheme.INK))
	var map_sb := (map_w.get_node("bg") as Panel).get_theme_stylebox("panel") as StyleBoxFlat
	var log_sb := (log_w.get_node("bg") as Panel).get_theme_stylebox("panel") as StyleBoxFlat
	check("A2：激活窗 2px 框", log_sb.border_width_top == 2, str(log_sb.border_width_top))
	check("A2：非激活窗 1px 框", map_sb.border_width_top == 1, str(map_sb.border_width_top))
	check("A2：非激活标题降到 INK_FAINT",
		map_w._title_label.get_theme_color("font_color") == TecTheme.INK_FAINT)
	scene._ensure_detail()
	scene._detail_win.show()
	scene._raise_to_front(scene._detail_win)
	await process_frame
	var e_detail: Control = scene._detail_win
	var detail_sb := ((e_detail as SysWindow).get_node("bg") as Panel).get_theme_stylebox("panel") as StyleBoxFlat
	check("z：详情窗提到 icons 之上", e_icons.get_index() < e_detail.get_index())
	check("z：详情窗提到日志之上", e_log.get_index() < e_detail.get_index())
	check("A2：详情窗成为当前窗", (e_detail as SysWindow).is_window_active())
	scene._open_tec()
	await process_frame
	check("z：TEC 提到地图之上", scene._map_win.get_index() < scene._tec.get_index())
	check("z：TEC 提到详情之上", e_detail.get_index() < scene._tec.get_index())
	check("z：toast(30) 在 TEC(28) 之上", scene._tec.get_index() < desk22.get_node("toast").get_index())
	check("A2：TEC 开窗后接管激活态", (scene._tec as SysWindow).is_window_active())
	check("A2：详情转非激活", not (e_detail as SysWindow).is_window_active())
	check("A2：详情框降回 1px", detail_sb.border_width_top == 1, str(detail_sb.border_width_top))
	scene._hide_tec()
	await process_frame
	check("A2：TEC 收起后详情恢复激活", (e_detail as SysWindow).is_window_active())
	check("A2：收起后的 TEC 为非激活", not (scene._tec as SysWindow).is_window_active())
	check("A2：详情框恢复 2px", detail_sb.border_width_top == 2, str(detail_sb.border_width_top))
	check("点地图正文把地图提到 TEC 之上",
		scene._raise_window_at(scene._map_win.get_global_rect().get_center())
			and scene._map_win.get_index() > scene._tec.get_index())
	check("点地图正文后地图重新成为当前窗", map_w.is_window_active())

	# 23) 手感修复三条：双击窗口放宽到 500ms（浏览器 dblclick 默认）/ 按下冻结飞行卡 /
	#     窗口点击提层走 rank 表（不再 move_to_front 撞翻 icon/toast 之上的层级）
	var tk23: NodeCard = _cards()[TORCH]
	var d23: Vector2 = tk23.get_global_rect().get_center()
	_press(tk23, d23)
	_release(tk23, d23)
	await create_timer(0.35).timeout
	var lit23 := bool(scene.dbg_state()["lit"].get("ITEM_shoudiantong", false))
	_press(tk23, d23)
	_release(tk23, d23)
	await process_frame
	check("双击窗口 500ms：350ms 里的第二下仍算双击",
		bool(scene.dbg_state()["lit"].get("ITEM_shoudiantong", false)) != lit23)
	# 按下冻结：折牌式重排飞着的卡，一按就停在指针下（补间被杀、位置不再漂）
	var far23: Vector2 = tk23.position + Vector2(420.0, -240.0)
	scene.graph.node(TORCH)["x"] = far23.x
	scene.graph.node(TORCH)["y"] = far23.y
	scene._relayout(true, true)
	await process_frame
	check("前提：卡正处在飞行补间里", scene._move_twens.has(TORCH))
	_press(tk23, tk23.get_global_rect().get_center())
	check("按下杀掉落位补间", not scene._move_twens.has(TORCH))
	_release(tk23, tk23.get_global_rect().get_center())
	var frozen23: Vector2 = tk23.position
	await create_timer(0.2).timeout
	check("按下后卡不再自己漂", tk23.position.is_equal_approx(frozen23),
		str(tk23.position) + " / " + str(frozen23))
	scene._relayout(false, true)   # 数据位照旧收干净
	# 窗口点击提层：点正文也要把窗提到浮动窗栈顶，并成为当前激活窗。
	# 先把日志窗关到已知态（S22 里开着），再开一份新的
	if scene._log_win != null and is_instance_valid(scene._log_win):
		scene._toggle_log()   # open → close
		await process_frame
	scene._toggle_log()   # close → open
	await process_frame
	var e_icons23: Control = scene.get_node("desk/icons")
	var d23b: Vector2 = (scene._log_win as Control).get_global_rect().get_center() - Vector2(0, 80)
	scene._raise_to_front(scene._map_win)
	check("前提：地图窗先压住日志", scene._map_win.get_index() > scene._log_win.get_index())
	check("前提：地图为当前窗", (scene._map_win as SysWindow).is_window_active())
	check("点日志正文后提到地图之上", scene._raise_window_at(d23b)
		and scene._log_win.get_index() > scene._map_win.get_index())
	check("点正文提层后也在 icons 之上", scene._log_win.get_index() > e_icons23.get_index(),
		str(scene._log_win.get_index()) + " / " + str(e_icons23.get_index()))
	check("点正文提层后成为当前窗", (scene._log_win as SysWindow).is_window_active())
	check("窗提层 rank 未变", int(scene._log_win.get_meta("zrank", -1)) == 21)
	var ev23 := InputEventMouseButton.new()
	ev23.button_index = MOUSE_BUTTON_LEFT
	ev23.pressed = true
	ev23.global_position = d23b
	(scene._log_win as Control)._on_bar_input(ev23)
	await process_frame
	check("标题栏按下仍提到栈顶", scene._log_win.get_index() > scene._map_win.get_index())
	var mot23 := InputEventMouseMotion.new()
	mot23.global_position = Vector2(9999.0, 9999.0)
	(scene._log_win as Control)._on_bar_input(mot23)
	var lr23: Rect2 = scene._log_win.get_global_rect()
	var desk23: Rect2 = scene._desk.get_global_rect()
	check("W4 窗口拖动被钳在桌面内",
		lr23.position.y >= desk23.position.y
			and lr23.position.x + lr23.size.x >= desk23.position.x + 40.0
			and lr23.position.x <= desk23.end.x - 40.0
			and lr23.position.y <= desk23.end.y - 40.0,
		str(lr23))
	var up23 := InputEventMouseButton.new()
	up23.button_index = MOUSE_BUTTON_LEFT
	up23.pressed = false
	up23.global_position = mot23.global_position
	(scene._log_win as Control)._on_bar_input(up23)
	scene._tec.position = Vector2(9999.0, 9999.0)
	scene._open_tec()
	var tr23: Rect2 = scene._tec.get_global_rect()
	check("W4 TEC 重开时被钳回桌面",
		tr23.position.x <= desk23.end.x - 40.0 and tr23.position.y <= desk23.end.y - 40.0,
		str(tr23))
	var desk23_old: Vector2 = scene._desk.size
	scene._desk.size = Vector2(960.0, 508.0)
	scene._tec.position = Vector2(9999.0, 9999.0)
	scene._tec.clamp_into_parent()
	check("W4 960 下 TEC 仍留在桌面内",
		scene._tec.position.x <= 920.0 and scene._tec.position.y <= 468.0,
		str(scene._tec.position))
	scene._desk.size = desk23_old
	scene._tec.clamp_into_parent()
	scene._hide_tec()
	scene._toggle_log()
	await process_frame

	# 24) 真实事件路由下的拖动（2026-10-21 现场问题：节点拖一下就僵住，之后整块画布跟着鼠标平移）
	#     上面的用例都是直接调 `card._gui_input(ev)`，绕过了命中判定与 mouse_focus —— 恰好躲开了这个 bug。
	#     这一节把事件真的推进 viewport，逐步验「跟手 / 收尾」。
	# 前面的用例留了几扇窗口开着；真实事件会遇到「最上面的窗吃掉按下」，
	# 先把它们收掉，让画布露出来（这一段只关心事件路由，不关心窗口）
	scene.dbg_close_mem()
	if scene._map_win != null and is_instance_valid(scene._map_win):
		scene._toggle_case_map()
	for ch in scene._desk.get_children():
		if ch is NarrCard and (ch as Control).is_visible_in_tree():
			ch.queue_free()
	await process_frame
	scene.dbg_expand("SCENES_garden")
	await process_frame
	# 前面的用例把卡片挪得很远；真实事件按屏幕坐标投递，先让画布回到「适应窗口」
	scene._relayout()
	scene._fit_view()
	await process_frame
	await process_frame
	# 1x 相机下卡片不再被缩小，前一轮重排的落位补间若还在飞，r24 会在按下前
	# 从指针底下漂走；等补间全部落地再取屏幕坐标。
	await create_timer(0.45).timeout
	var k24 := "loc:SCENES_garden"
	var c24: NodeCard = _cards().get(k24, null)
	check("前提：目标卡在画布上", c24 != null and c24.visible)
	if c24 != null:
		# 1x 的「适应窗口」只居中不缩小；卡片多时目标可能落在画布外。
		# 这里只测事件路由，先把目标卡平移到画布中央，保证按点真的落在它身上。
		scene._center_on(c24)
		await process_frame
		var r24: Vector2 = c24.get_global_rect().get_center()
		# 1x 下卡片会互相压住；真实事件命中的是最上面那张，先把目标提到最前
		c24.move_to_front()
		await process_frame
		var p24: Vector2 = c24.position
		_vpush_btn(r24, true)
		await process_frame
		_vpush_mov(r24 + Vector2(18, 10))
		await process_frame
		check("真实路由：拖动中镜像挂上", scene._card_mirror != null and is_instance_valid(scene._card_mirror))
		check("真实路由：原卡全透明（入场 pop 补间不会把透明度抢回去）",
			c24.modulate.a < 0.01, str(c24.modulate.a))
		_vpush_mov(r24 + Vector2(90, 52))
		await process_frame
		var want24: Vector2 = p24 + Vector2(90, 52) / scene._view_k
		check("真实路由：第二段 motion 仍跟手（不是只跟第一下）",
			c24.position.distance_to(want24) < 1.5, str(c24.position) + " / want " + str(want24))
		_vpush_mov(r24 + Vector2(150, 88))
		await process_frame
		check("真实路由：第三段 motion 仍跟手",
			c24.position.distance_to(p24 + Vector2(150, 88) / scene._view_k) < 1.5, str(c24.position))
		_vpush_btn(r24 + Vector2(150, 88), false)
		await process_frame
		check("真实路由：松手清空拖动会话", scene._drag_key == "")
		check("真实路由：松手镜像退场", scene._card_mirror == null)
		check("真实路由：松手透明度复原", is_equal_approx(c24.modulate.a, 1.0), str(c24.modulate.a))
		check("真实路由：松手坐标写回数据",
			absf(float(scene.graph.node(k24)["x"]) - c24.position.x) < 0.5
			and absf(float(scene.graph.node(k24)["y"]) - c24.position.y) < 0.5,
			str(scene.graph.node(k24)["x"]) + " / " + str(c24.position.x))
		# 残留会话的兜底：假装上一轮松手丢了，下一次按下应先把卡落地、不进入平移
		scene._drag_key = k24
		var world24: Vector2 = scene._card_layer.position
		var blank24: Vector2 = _empty_canvas_point(scene)
		_vpush_btn(blank24, true)
		await process_frame
		_vpush_mov(blank24 + Vector2(50, 40))
		await process_frame
		check("残留会话：新按下先收尾、不平移画布",
			scene._drag_key == "" and scene._card_layer.position.is_equal_approx(world24),
			"drag_key=" + scene._drag_key + " world=" + str(scene._card_layer.position - world24))
		_vpush_btn(blank24 + Vector2(50, 40), false)
		await process_frame

	# 25) 桌布线索卡：拖动必须真的跟手（此前只判「移动过」、位置一动不动）
	var mw25: MatrixWin = scene.dbg_open_matrix()
	await process_frame
	scene.dbg_ensure("clue", "CLUES_nm")
	scene.dbg_matrix_assign(clue_key)
	await process_frame
	var ch25: Control = mw25._chips.get("CLUES_nm", null) as Control
	check("前提：桌布上有芯片", ch25 != null)
	if ch25 != null:
		var cp25: Vector2 = ch25.get_global_rect().get_center()
		var cpos25: Vector2 = ch25.global_position
		_chip_press(ch25, cp25)
		_chip_motion(ch25, cp25 + Vector2(16, 10))
		var mir25: Control = mw25._drag_mirror
		check("桌布拖动：出镜像", mir25 != null and is_instance_valid(mir25))
		check("桌布拖动：原件让位（全透明但仍在树里）",
			ch25.is_visible_in_tree() and ch25.modulate.a < 0.01, str(ch25.modulate.a))
		_chip_motion(ch25, cp25 + Vector2(70, 40))
		check("桌布拖动：镜像跟手",
			mir25 != null and mir25.global_position.is_equal_approx(cpos25 + Vector2(54, 30)),
			str(mir25.global_position if mir25 != null else Vector2.ZERO) + " / want "
				+ str(cpos25 + Vector2(54, 30)))
		_chip_release(ch25, cp25 + Vector2(70, 40))
		await process_frame
		check("桌布内松手：镜像撤掉", mw25._drag_mirror == null)
		check("桌布内松手：原件复原", is_equal_approx(ch25.modulate.a, 1.0), str(ch25.modulate.a))
		check("桌布内松手：仍留在桌布", mw25._chips.has("CLUES_nm"))

	# ── 单色改版 P0：调色板契约 ─────────────────────────────────────────────
	# 这一组不测「某个色等于某个值」（P1~P6 会换色，那种断言一改就红），
	# 只测**结构**：别名是不是真同源、派生函数是不是只动它该动的那一位。
	# 防的是「有人在 TecTheme 里另起炉灶复制一份色值」——那会让改色改不干净。
	print("--- 单色改版 P0：调色板契约 ---")
	check("LINE 与 TEXT 都指向 INK（同一支墨，不是三份副本）",
		TecTheme.LINE.is_equal_approx(TecTheme.INK) and TecTheme.TEXT.is_equal_approx(TecTheme.INK))
	check("MUTED 指向 INK_MUTED", TecTheme.MUTED.is_equal_approx(TecTheme.INK_MUTED))
	check("FAINT 指向 INK_FAINT", TecTheme.FAINT.is_equal_approx(TecTheme.INK_FAINT))
	check("LINE2 指向 DIVIDER", TecTheme.LINE2.is_equal_approx(TecTheme.DIVIDER))
	check("KIND_LOC / KIND_ITEM / KIND_CHAR 指向 SPOT_*",
		TecTheme.KIND_LOC.is_equal_approx(TecTheme.SPOT_LOC)
			and TecTheme.KIND_ITEM.is_equal_approx(TecTheme.SPOT_ITEM)
			and TecTheme.KIND_CHAR.is_equal_approx(TecTheme.SPOT_CHAR))
	check("深色面提亮版同名同源",
		TecTheme.KIND_LOC_DARK.is_equal_approx(TecTheme.SPOT_LOC_ON_DARK)
			and TecTheme.KIND_ITEM_DARK.is_equal_approx(TecTheme.SPOT_ITEM_ON_DARK)
			and TecTheme.KIND_CHAR_DARK.is_equal_approx(TecTheme.SPOT_CHAR_ON_DARK))
	var spots := [TecTheme.SPOT_LOC, TecTheme.SPOT_ITEM, TecTheme.SPOT_CHAR]
	check("三个类型专色常量仍互不相同（留档，P4 起不再有调用方返回它们）",
		not spots[0].is_equal_approx(spots[1]) and not spots[1].is_equal_approx(spots[2])
			and not spots[0].is_equal_approx(spots[2]))
	# P4：类型不再靠色相区分 —— 五种形状（实心方/空心方/实心圆/三角/菱形）已经说完了，
	# 再叠一层彩色就是整屏唯一的「有彩色」，会把「全部单色」这句话当场破掉。
	check("类型符号已单色化（亮面一律 INK、暗面一律 TEXT_ON_DARK）",
		TecTheme.kind_color("loc").is_equal_approx(TecTheme.INK)
			and TecTheme.kind_color("item").is_equal_approx(TecTheme.INK)
			and TecTheme.kind_color("char").is_equal_approx(TecTheme.INK)
			and TecTheme.kind_color("loc", true).is_equal_approx(TecTheme.TEXT_ON_DARK)
			and TecTheme.kind_color("char", true).is_equal_approx(TecTheme.TEXT_ON_DARK))
	var e := TecTheme.edge(0.42)
	check("edge(a) 只动 alpha，rgb 与 EDGE 完全一致",
		is_equal_approx(e.a, 0.42) and e.r == TecTheme.EDGE.r
			and e.g == TecTheme.EDGE.g and e.b == TecTheme.EDGE.b, str(e))
	var sh := TecTheme.shadow(0.28)
	check("shadow(a) 用 SHADOW_BASE 做基色",
		is_equal_approx(sh.a, 0.28) and sh.r == TecTheme.SHADOW_BASE.r
			and sh.g == TecTheme.SHADOW_BASE.g and sh.b == TecTheme.SHADOW_BASE.b, str(sh))
	check("rim(0.95) 就是 BEVEL_HI（高光只有一支奶油白）",
		TecTheme.rim(0.95).is_equal_approx(TecTheme.BEVEL_HI))
	check("rim(a) 只动 alpha", is_equal_approx(TecTheme.rim(0.18).a, 0.18)
		and TecTheme.rim(0.18).r == TecTheme.RIM_BASE.r)
	var sc := TecTheme.scrim(0.85)
	check("scrim(a) 是墨的 alpha 变体（rgb 同 INK 的暖墨系）",
		is_equal_approx(sc.a, 0.85) and absf(sc.r - 0.169) < 0.001 and absf(sc.b - 0.149) < 0.001, str(sc))
	check("white(a) / black(a) 只动 alpha",
		TecTheme.white(0.28).r == 1.0 and is_equal_approx(TecTheme.white(0.28).a, 0.28)
			and TecTheme.black(0.35).r == 0.0 and is_equal_approx(TecTheme.black(0.35).a, 0.35))
	check("NONE 是全透明", is_equal_approx(TecTheme.NONE.a, 0.0))
	check("kind_color 回落：亮面走 INK、暗面走 TEXT_ON_DARK",
		TecTheme.kind_color("clue").is_equal_approx(TecTheme.INK)
			and TecTheme.kind_color("time").is_equal_approx(TecTheme.INK)
			and TecTheme.kind_color("clue", true).is_equal_approx(TecTheme.TEXT_ON_DARK))

	# ── 单色改版 P1：桌布平涂 ────────────────────────────────────────────────
	# 只验接线与色值，不验像素（像素由 `--shot` 1x 截图人工验收）。
	print("--- 单色改版 P1：桌布平涂 ---")
	var stage_bg := scene.get_node_or_null("desk/case_win/body/stage/stage_bg") as ColorRect
	check("桌布节点存在且是 ColorRect", stage_bg != null)
	if stage_bg != null:
		check("桌布是平涂（不再挂任何 material）", stage_bg.material == null,
			"" if stage_bg.material == null else str(stage_bg.material))
		check("桌布底色 = DESK_GRAY（中性灰，不是纸白）",
			stage_bg.color.is_equal_approx(TecTheme.DESK_GRAY), str(stage_bg.color))
	var clear_col = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color")
	check("默认清屏色同步桌面色",
		clear_col is Color and (clear_col as Color).is_equal_approx(TecTheme.DESK_GRAY), str(clear_col))
	var wm := scene.get_node_or_null("desk/case_win/body/stage/desk_watermark") as Control
	check("E1 画布不挂水印（按用户反馈取消）", wm == null)

	# ── 单色改版 P4.2：按钮语法统一 ──────────────────────────────────────────
	# 参考图（System 6 Control Panel）只有两枚键：Set = 白底 + 1px 黑键线；
	# Find = 同一条键线里再套一条内键线。**都不是黑底**，也都不是浅灰线。
	print("--- 单色改版 P4.2：按钮键线 / 图标按下态 ---")
	var p42_btn := TecTheme.button("确定")
	var p42_n := p42_btn.get_theme_stylebox("normal") as StyleBoxFlat
	var p42_h := p42_btn.get_theme_stylebox("hover") as StyleBoxFlat
	var p42_p := p42_btn.get_theme_stylebox("pressed") as StyleBoxFlat
	# 键线必须是**纯黑 1px**。上一版走 `flat()` 的默认参数 `EDGE`（30% 黑），
	# 那条线在白底上读作浅灰 —— 案件地图里 34px 的小方框整片「看着没改」就是它。
	check("按钮常态 = 白底 + 1px 纯黑键线 + R_BTN 圆角",
		p42_n.bg_color.is_equal_approx(TecTheme.CARD)
			and p42_n.border_width_left == 1
			and p42_n.border_color.is_equal_approx(TecTheme.INK)
			and p42_n.corner_radius_top_left == TecTheme.R_BTN,
		str(p42_n))
	check("C-B 悬停把键线加到 2px 并用强调青（填充仍是白）",
		p42_h.border_width_left == 2 and p42_h.border_color.is_equal_approx(TecTheme.SPOT_ACCENT)
			and p42_h.bg_color.is_equal_approx(TecTheme.CARD), str(p42_h))
	check("按下反白（黑底 + 白字），不引入灰阶填充",
		p42_p.bg_color.is_equal_approx(TecTheme.INK)
			and p42_p.border_color.is_equal_approx(TecTheme.INK)
			and (p42_btn.get_theme_color("font_pressed_color") as Color).is_equal_approx(TecTheme.CARD),
		str(p42_p))
	var p42_pb := TecTheme.primary_button("开始")
	var p42_ring := p42_pb.get_node_or_null("keyline") as Panel
	var p42_rsb := p42_ring.get_theme_stylebox("panel") as StyleBoxFlat if p42_ring != null else null
	check("默认键多一道内键线（双键线 = 参考图的 Find）",
		p42_rsb != null and p42_rsb.border_width_left == 1
			and p42_rsb.border_color.is_equal_approx(TecTheme.INK)
			and is_equal_approx(p42_rsb.bg_color.a, 0.0), str(p42_rsb))
	check("默认键不再填黑（黑底是深色面的语法，不属于按钮）",
		(p42_pb.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.is_equal_approx(TecTheme.CARD))
	p42_pb.queue_free()
	p42_btn.queue_free()

	# 桌面图标（P4.2）：按下**只反白标签条**，图标本体不垫底板。
	# 原来图标后面那块 44×44 黑圆角 + 黑标签条 = 屏上两个黑块夹一道白缝，
	# 也就是「多一个框出来的全黑」。
	var p42_bag := scene.get_node_or_null("desk/icons/icon_bag") as DeskIcon
	check("桌面图标常态不垫底板（图标直接躺在桌面上）",
		p42_bag != null and p42_bag._glyph.material == null
			and is_equal_approx(p42_bag._glyph.color.a, 0.0),
		"null" if p42_bag == null else str(p42_bag._glyph.color))
	if p42_bag != null:
		p42_bag.set_selected(true)
		var p42_lab := p42_bag._label.get_theme_stylebox("normal") as StyleBoxFlat
		check("按下只反白标签条（实心黑 + 白字 + 直角）",
			p42_lab != null and p42_lab.bg_color.is_equal_approx(TecTheme.INK)
				and (p42_bag._label.get_theme_color("font_color") as Color).is_equal_approx(TecTheme.CARD)
				and p42_lab.corner_radius_top_left == 0, str(p42_lab))
		check("黑条按字宽收紧（不是铺满 64px 的整条横幅）",
			p42_bag._label.size.x < DeskIcon.ROOT_SIZE and p42_bag._label.size.x >= 24.0,
			str(p42_bag._label.size))
		check("图标本体始终是黑线稿（它没有底板可衬白线）",
			p42_bag._icon.modulate.is_equal_approx(TecTheme.LINE))
		p42_bag.set_selected(false)

	# 案件地图：列表行与其它列表同一套语法 —— 行首编号牌 + 发丝线，不再套圆角盒子。
	var p42_map: CaseMapWin = scene.dbg_open_case_map()
	var p42_r1: Control = p42_map.find_child("row_A001", true, false) if p42_map != null else null
	var p42_c1: Panel = p42_r1.find_child("state", true, false) as Panel if p42_r1 != null else null
	var p42_rs := p42_r1.get_theme_stylebox("panel") as StyleBoxFlat if p42_r1 != null else null
	check("案件地图行 = 底部 1px 发丝线（不再是圆角盒）",
		p42_rs != null and p42_rs.border_width_bottom == 1
			and p42_rs.border_width_top == 0
			and p42_rs.border_width_left == 0
			and p42_rs.border_width_right == 0
			and p42_rs.border_color.is_equal_approx(TecTheme.edge(0.18))
			and p42_rs.expand_margin_left == -8.0
			and p42_rs.expand_margin_right == -8.0,
		str(p42_rs))
	var p42_code: PanelContainer = p42_r1.find_child("code", true, false) as PanelContainer if p42_r1 != null else null
	var p42_code_txt := p42_code.get_child(0) as Label if p42_code != null and p42_code.get_child_count() > 0 else null
	check("案件地图行首 = A-001 编号牌",
		p42_code != null and p42_code.custom_minimum_size == Vector2(52, 24)
			and p42_code_txt != null and p42_code_txt.text == "A-001",
		"null" if p42_code_txt == null else p42_code_txt.text)
	check("案件地图「当前」牌 = 白底 + 双键线",
		p42_c1 != null and p42_c1.get_node_or_null("keyline") != null
			and (p42_c1.get_theme_stylebox("panel") as StyleBoxFlat).border_color.is_equal_approx(TecTheme.INK),
		"null" if p42_c1 == null else str(p42_c1.get_theme_stylebox("panel")))
	var p42_r2: Control = p42_map.find_child("row_A002", true, false) if p42_map != null else null
	var p42_c2: Panel = p42_r2.find_child("state", true, false) as Panel if p42_r2 != null else null
	check("案件地图锁定牌 = 淡键线 + 淡字，且没有内键线",
		p42_c2 != null and p42_c2.get_node_or_null("keyline") == null
			and (p42_c2.get_theme_stylebox("panel") as StyleBoxFlat).border_color.is_equal_approx(TecTheme.INK_FAINT),
		"null" if p42_c2 == null else str(p42_c2.get_theme_stylebox("panel")))

	# E4：同屏一条、后来者排队；清场时队列一起丢掉，避免截图流程留下尾巴。
	scene._hide_toast()
	scene._show_toast("队列一")
	check("E4 首条立即显示", scene._toast_label.text == "队列一" and scene._toast.visible)
	var toast_sb := scene._toast.get_theme_stylebox("panel") as StyleBoxFlat
	check("E4 Toast = 黑底药丸",
		toast_sb != null and toast_sb.bg_color.is_equal_approx(TecTheme.LINE)
			and toast_sb.corner_radius_top_left >= 100,
		str(toast_sb))
	check("E4 Toast 底部水平居中",
		absf(scene._toast.position.x + scene._toast.size.x * 0.5 - scene._vw() * 0.5) < 1.0,
		str(scene._toast.position) + " / " + str(scene._toast.size))
	scene._show_toast("队列二")
	check("E4 第二条排队不抢屏", scene._toast_label.text == "队列一"
		and scene._toast_queue.size() == 1, str(scene._toast_queue))
	scene._hide_toast()
	check("E4 清场同时清队列", not scene._toast.visible and scene._toast_queue.is_empty())
	scene._show_toast("队列三")
	check("E4 清场后新消息立即显示", scene._toast_label.text == "队列三" and scene._toast.visible)
	scene._hide_toast()

	# 详情窗：长简介 + 动作按钮不能溢出窗框；超过视口时由滚动区吸收。
	scene._hide_toast()
	var detail_key: String = scene.dbg_ensure("item", "ITEM_shuzhuo")
	scene.graph.explored["ITEM_shuzhuo"] = true
	scene._on_card_selected(detail_key)
	await process_frame
	await process_frame
	await process_frame
	var dlong: DetailWin = scene._detail_win
	var dbtn: Button = null
	if dlong != null:
		for b in dlong.find_children("*", "Button", true, false):
			var bt := b as Button
			if bt != null and String(bt.text).begins_with("重看"):
				dbtn = bt
				break
	check("详情窗不使用滚动条", dlong != null and dlong.content.get_child_count() == 1
		and dlong.content.get_child(0) == dlong._rows)
	check("详情窗动作按钮不溢出窗框",
		dlong != null and dbtn != null and dlong.get_global_rect().encloses(dbtn.get_global_rect()),
		"null" if dlong == null or dbtn == null else "%s / %s" % [
			dlong.get_global_rect(), dbtn.get_global_rect()])

	# 第 0 幕：开始界面。无档时「继续」禁用；有档时开始要先确认覆盖。
	var ss = StartScreenScript.new()
	ss.setup(false)
	root.add_child(ss)
	await process_frame
	var start_btn := ss.find_child("btn_start", true, false) as Button
	var continue_btn := ss.find_child("btn_continue", true, false) as Button
	var settings_btn := ss.find_child("btn_settings", true, false) as Button
	var demon := ss.find_child("demon", true, false) as TextureRect
	check("G0 开始界面四键齐全",
		start_btn != null and continue_btn != null and settings_btn != null
			and ss.find_child("btn_quit", true, false) != null)
	check("G0 无档时继续置灰", continue_btn != null and continue_btn.disabled)
	var started: Array = []
	ss.start_requested.connect(func(overwrite: bool): started.append(overwrite))
	start_btn.pressed.emit()
	check("G0 无档时开始直接新调查", started == [false], str(started))
	ss.set_has_save(true)
	check("G0 有档时继续可用", continue_btn != null and not continue_btn.disabled)
	start_btn.pressed.emit()
	var dialog := ss.find_child("dialog_layer", true, false) as Control
	check("G0 有档时开始先确认覆盖", dialog != null and dialog.visible)
	var overwrite_btn := ss.find_child("dialog_btn_覆盖并开始", true, false) as Button
	if overwrite_btn != null:
		overwrite_btn.pressed.emit()
	check("G0 确认覆盖后发出 overwrite=true", started.size() == 2 and bool(started[1]))
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	demon.gui_input.emit(ev)
	check("G0 点击恶魔有晃动反馈（无表情节点）", demon != null
		and ss.find_child("emote", true, false) == null)
	settings_btn.pressed.emit()
	check("G0 设置面板可打开", dialog != null and dialog.visible)
	ss.queue_free()
	await process_frame

	# 第 0 幕与 Desktop 接线：开始后撤掉开始界面并进入第 1 幕（空白桌面 + TEC + 调查员）。
	scene._inv_path = "user://test_ui_tutorial_inv.json"
	Investigator.clear(scene._inv_path)
	scene._open_start_screen()
	await process_frame
	check("G0 Desktop 能挂开始界面", scene._start_screen != null)
	if scene._start_screen != null:
		scene._investigator = {"name": "保留的调查员"}
		scene._on_start_continue()
		await process_frame
		check("C8 读档失败仍留在开始界面", scene._start_screen != null)
		check("C8 读档失败不清调查员证",
			String(scene._investigator.get("name", "")) == "保留的调查员")
		check("C8 读档失败给出可读提示",
			scene._start_screen._dialog_layer != null and scene._start_screen._dialog_layer.visible)
		scene._start_screen._close_dialog()
		scene._start_screen.start_requested.emit(false)
		await process_frame
	check("G1 开始后进入空白桌面", scene._start_screen == null and scene._tutorial_active)
	check("G1 图表隐藏、TEC 常驻、TEC办公室节点已出现",
		not scene._icon_layer().visible and scene._tec.visible
			and scene._cards.has("loc:SCENES_TEC_OFFICE"))
	var office_g1: NodeCard = scene._cards["loc:SCENES_TEC_OFFICE"]
	check("G1 TEC办公室没有无文本入口角标",
		not office_g1._warn and not office_g1._warn_badge.visible)
	check("G1 TEC 开场白",
		not scene._tec.dbg_lines().is_empty()
			and String(scene._tec.dbg_lines()[0]).contains("欢迎来到 TEC"))
	check("G1 顶栏只剩品牌（撤销/调试隐藏）",
		not (scene.get_node("header/btn_撤销") as Control).visible
			and not (scene.get_node("header/btn_调试") as Control).visible
			and (scene.get_node("header/brand") as Control).visible)
	check("G1 TEC 与普通窗一样可拖 / 可关",
		scene._tec.dbg_drag_enabled()
			and (scene._tec.get_node("bar/close") as Control).visible
			and (scene._tec.get_node("bar/min") as Control).visible)
	var tec_home: Vector2 = scene._tec.position
	scene._tec.position = Vector2(40, 120)
	scene._place_floating_windows()
	check("G1 TEC 拖动后不被重排拉回", scene._tec.position == Vector2(40, 120))
	scene._tec.position = tec_home
	scene._place_floating_windows()
	scene._close_tec()
	await process_frame
	check("G1 关掉 TEC 后出现 TEC 图标", scene._icon_by_app("tec").visible)
	scene._open_tec()
	await process_frame
	check("G1 重开 TEC 后图标收起", not scene._icon_by_app("tec").visible)

	# ── 第 2 幕：TEC办公室 → 调查员证 → 证件交给 TEC 核对 ──
	var tut_office_key := "loc:SCENES_TEC_OFFICE"
	var tut_cert_key := "item:ITEMS_investigator_cert"
	var tut_cert_clue_key := "clue:CLUES_INVESTIGATOR_CERT"
	check("G2 从第①步开始", scene._tutorial_step == 0)
	var tec_target := Rect2()
	for t in scene._drop_targets():
		if String(t["id"]) == "tec-dock":
			tec_target = t["rect"]
	check("G2 整个 TEC 窗体都是落点", tec_target == scene._tec.get_global_rect())
	# 用真实鼠标事件走完拖拽收尾，回归「拖给 TEC 后节点被 visible_node 藏掉」。
	var tut_office_card: NodeCard = scene._cards[tut_office_key]
	var office_from: Vector2 = tut_office_card.get_global_rect().get_center()
	## 故意丢在 TEC 窗体中央（正文，不是头像），验证整窗都是分析落点。
	var office_to: Vector2 = scene._tec.get_global_rect().get_center()
	_press(tut_office_card, office_from)
	_motion(tut_office_card, office_to)
	check("G2 拖进 TEC 出现统一虚线框", scene._drop_outline.visible)
	check("G2 虚线框贴合 TEC 窗体", scene._drop_outline.outline_rect().size.x > 100.0)
	_release(tut_office_card, office_to)
	await process_frame
	check("G2 松手后虚线框收起", not scene._drop_outline.visible)
	check("G2 TEC办公室拖给 TEC 开始分析", scene._tec.is_analyzing())
	check("G2 拖给 TEC 后办公室节点仍在", tut_office_card.visible)
	var office_node: Dictionary = scene.graph.node(tut_office_key)
	check("G2 办公室拖拽回位锚点正确",
		tut_office_card._home == Vector2(float(office_node["x"]), float(office_node["y"])))
	scene.dbg_tec_complete()
	for i in 6:
		await process_frame
	check("G2 TEC 分析办公室只给提示、不产证件",
		not scene._cards.has(tut_cert_key) and scene._tutorial_step == 0
			and _last_line(scene._tec).contains("双击"))
	check("G2 分析后办公室节点仍在", tut_office_card.visible)
	# 调查员证由 TEC办公室节点本身产出，TEC 分析不产出证件。
	scene._on_card_activated(tut_office_key)
	check("G2 双击办公室产出调查员证",
		scene._cards.has(tut_cert_key) and scene._tutorial_step == 1)
	check("G2 证件连线来自 TEC办公室", scene.graph.has_edge(tut_office_key, tut_cert_key))
	check("G2 不再产出调查员线索",
		not scene.graph.captured.has("CLUES_INVESTIGATOR")
			and not scene.graph.nodes.has("clue:CLUES_INVESTIGATOR"))
	check("G2 办公室→证件一条线", scene._edge_layer.segment_count() == 1)
	tut_office_card.modulate.a = 0.0
	scene._repaint_edges()
	check("U5 透明卡不再画连线", scene._edge_layer.segment_count() == 0)
	tut_office_card.modulate.a = 1.0
	scene._repaint_edges()
	check("U5 恢复可见后连线回来", scene._edge_layer.segment_count() == 1)
	check("G2 TEC 提示把证件拖过去", _last_line(scene._tec).contains("调查员证"))
	scene._on_card_selected(tut_cert_key)
	check("G2 选中节点显示详情窗",
		scene._detail_win != null and scene._detail_win.visible)
	check("G2 详情窗压在 TEC 之上",
		scene._detail_win.get_index() > scene._tec.get_index())
	# 证件已出现后再双击办公室不会重复产出。
	scene._on_card_activated(tut_office_key)
	check("G2 双击办公室不重复产证件",
		scene.graph.nodes.size() == 2 and scene._tutorial_step == 1)
	check("G2 双击后 TEC 仍指向证件", _last_line(scene._tec).contains("调查员证"))
	scene._apply_drop("tec-avatar", tut_office_key)
	check("G2 办公室不再交给 TEC", not scene._tec.is_analyzing())
	check("G2 错拖由 TEC 口头纠正", _last_line(scene._tec).contains("调查员证"))
	check("G2 错拖不弹系统 toast", not scene._toast_active)
	scene._tec_talk()
	check("G2 点 TEC 仍只指证件", _last_line(scene._tec).contains("调查员证"))
	scene._apply_drop("tec-avatar", tut_cert_key)
	check("G2 证件拖给 TEC 开始分析", scene._tec.is_analyzing())
	scene.dbg_tec_complete()
	for i in 6:
		await process_frame
	check("G2 产出调查员证线索",
		scene.graph.captured.has("CLUES_INVESTIGATOR_CERT") and scene._cards.has(tut_cert_clue_key))
	check("G2 证书线索从证件连出", scene.graph.has_edge(tut_cert_key, tut_cert_clue_key))
	check("G2 进入第③幕收纳", scene._tutorial_step == 2)
	check("G2 TEC 收尾台词", _last_line(scene._tec).contains("核对完成"))

	# ── 第 3 幕：三枚 app 解锁 + 物品进袋 / 线索进册 ──
	check("G3 图标栏解锁",
		scene._icon_layer().visible and scene._icon_by_app("bag").visible
			and scene._icon_by_app("clue").visible and scene._icon_by_app("infer").visible)
	var bag_rect := Rect2()
	for t in scene._drop_targets():
		if String(t["id"]) == "bag-dock":
			bag_rect = t["rect"]
	scene._update_drop_over(bag_rect.get_center())
	check("G3 收纳图标也显示统一虚线框", scene._drop_outline.visible)
	scene._clear_drop_over()
	scene._toggle_storage("BAG")
	await process_frame
	var bag_empty := scene._bag_win._rows.get_child(0) as Label
	check("G3 空证物袋有收纳指引",
		bag_empty != null and bag_empty.text.contains("拖"))
	scene._update_drop_over(scene._bag_win.get_global_rect().get_center())
	check("G3 收纳窗口也显示统一虚线框", scene._drop_outline.visible)
	check("G3 窗口虚线框在窗框外 4px",
		scene._drop_outline.outline_rect().size == scene._bag_win.size - Vector2(20.0, 20.0))
	scene._toggle_storage("BAG")
	await process_frame
	scene._update_drop_over(tut_office_card.get_global_rect().get_center())
	check("G3 卡片目标也显示统一虚线框", scene._drop_outline.visible)
	scene._update_drop_over(Vector2(8.0, 8.0))
	check("G3 移出落点虚线框收起", not scene._drop_outline.visible)
	var ghost_at := Vector2(520.0, 330.0)
	var ghost_expect: Vector2 = scene._desk.get_global_transform().affine_inverse() * ghost_at + Vector2(12.0, 10.0)
	check("G3 收纳拖拽幽灵使用 desk 局部坐标",
		scene._sdrag_ghost_position(ghost_at) == ghost_expect)
	check("G3 地图 / 档案未出，TEC 图标按普通 app 常驻",
		not scene._icon_by_app("map").visible and scene._icon_by_app("tec").visible
			and not scene._icon_by_app("goto").visible)
	# C5：教学期错收由 TEC 口头纠正，不弹系统 toast。
	var tutorial_soft := _last_line(scene._tec)
	check("G3 TEC 只提醒整理、不强制", tutorial_soft.contains("不整理"), tutorial_soft)
	scene._hide_toast()
	scene._apply_drop("clue-icon", tut_cert_key)
	check("G3 物品不能进线索册", not scene.graph.stored.has(tut_cert_key))
	check("C5 教学期错收走 TEC，不弹 toast", not scene._toast_active)
	check("C5 物品进线索册由 TEC 纠正", _last_line(scene._tec).contains("线索册"),
		_last_line(scene._tec))
	scene._hide_toast()
	scene._apply_drop("bag-dock", tut_cert_clue_key)
	check("G3 线索不能进证物袋", not scene.graph.stored.has(tut_cert_clue_key))
	check("C5 线索进证物袋也不弹 toast", not scene._toast_active)
	check("C5 线索进证物袋由 TEC 纠正", _last_line(scene._tec).contains("证物袋"),
		_last_line(scene._tec))
	# C5：非线索拖到推演器图标也只走 TEC。
	scene._hide_toast()
	scene._apply_drop("infer-icon", tut_office_key)
	check("C5 非线索上桌布不弹 toast", not scene._toast_active)
	check("C5 非线索上桌布由 TEC 纠正", _last_line(scene._tec).contains("线索"),
		_last_line(scene._tec))
	# 非落点窗体也要拦截卡片，不能穿透去碰窗体下面的节点。
	check("G3 非落点窗体拦截卡片",
		scene._handle_card_drop(tut_cert_key, scene._detail_win.get_global_rect().get_center()))
	check("G3 拦截后物品没被误收", not scene.graph.stored.has(tut_cert_key))
	# 收纳是可选的：不把两样东西收起来，直接打开推演器也要能进入下一幕。
	scene._toggle_matrix()
	await process_frame
	check("G3 不收纳也能打开推演器", scene._matrix_win != null)
	check("G3 打开推演器即进入推演", scene._tutorial_step == 3)
	check("G3 TEC 改指向已打开的桌布", _last_line(scene._tec).contains("桌布"))
	# 重叠窗口：上面的推演窗必须优先接住落点，不能被下面的 TEC 抢走。
	var old_tec_pos: Vector2 = scene._tec.position
	var old_mx_pos: Vector2 = scene._matrix_win.position
	scene._tec.position = Vector2(400.0, 120.0)
	scene._matrix_win.position = Vector2(450.0, 150.0)
	scene._raise_to_front(scene._matrix_win)
	var overlap_pt: Vector2 = scene._tec.get_global_rect() \
		.intersection(scene._matrix_win.get_global_rect()).get_center()
	var top_target: Dictionary = scene._drop_target_at(overlap_pt)
	check("G3 重叠落点命中上层推演窗",
		not top_target.is_empty() and String(top_target["id"]) == "mx-board")
	scene._update_drop_over(overlap_pt)
	check("G3 重叠区域虚线框贴合上层推演窗",
		scene._drop_outline.outline_rect().size == scene._matrix_win.size - Vector2(20.0, 20.0))
	scene._clear_drop_over()
	scene._tec.position = old_tec_pos
	scene._matrix_win.position = old_mx_pos
	scene._toggle_matrix()
	await process_frame
	# 正常收纳继续可用，并且不再反过来推进/卡住教学步骤。
	scene._apply_drop("bag-dock", tut_cert_key)
	for i in 2:
		await process_frame
	check("G3 物品进证物袋", String(scene.graph.stored.get(tut_cert_key, "")) == GraphState.BAG)
	scene._apply_drop("clue-icon", tut_cert_clue_key)
	for i in 4:
		await process_frame
	check("G3 线索进线索册", String(scene.graph.stored.get(tut_cert_clue_key, "")) == GraphState.LEDGER)
	check("G3 收纳不改变当前步骤", scene._tutorial_step == 3)
	check("G3 收纳重算后办公室仍可见", scene._cards[tut_office_key].visible)
	check("G3 不自动打开推演器 / 线索册",
		scene._matrix_win == null and scene._ledger_win == null)
	check("G3 TEC 仍可拖动", scene._tec.dbg_drag_enabled())

	# C6：线索册行内「去推演」也必须走 STORE_SUPPLIES → INFER 的教学守卫。
	scene._tutorial_step = 2
	scene._on_ledger_to_matrix(tut_cert_clue_key)
	check("C6 线索册按钮推进到推演步", scene._tutorial_step == 3,
		str(scene._tutorial_step))
	check("C6 线索册按钮由 TEC 提示桌布",
		_last_line(scene._tec).contains("桌布") or _last_line(scene._tec).contains("推演"),
		_last_line(scene._tec))
	scene.graph.matrix_take(tut_cert_clue_key)
	scene._apply_hidden()
	scene._refresh_matrix_views()
	scene._store_into(GraphState.LEDGER, tut_cert_clue_key)
	check("C6 测试后线索回册", String(scene.graph.stored.get(tut_cert_clue_key, "")) == GraphState.LEDGER,
		String(scene.graph.stored.get(tut_cert_clue_key, "")))

	# ── 第 4 幕：玩家自己双击推演器 / 线索册，再上桌布 ──
	scene._toggle_matrix()
	scene._toggle_storage(GraphState.LEDGER)
	for i in 2:
		await process_frame
	check("G4 双击推演器打开桌布", scene._matrix_win != null)
	check("G4 线索册按普通 app 打开", scene._ledger_win != null)
	check("G4 桌布提示还差一条",
		scene._matrix_win.dbg_hint().contains("还需要"))
	scene._matrix_win.finish_charge()
	for i in 3:
		await process_frame
	check("G4 配方不齐不进入领证",
		scene._tutorial_step == 3 and scene._tutorial_cert_win == null)
	check("G4 桌布口头纠正",
		scene._matrix_win.dbg_hint().contains("配方不对"))
	var mx_target := Rect2()
	for t in scene._drop_targets():
		if String(t["id"]) == "mx-board":
			mx_target = t["rect"]
	check("G4 整扇推演窗都是线索落点", mx_target == scene._matrix_win.get_global_rect())
	var mx_title: Vector2 = scene._matrix_win.get_global_rect().position + Vector2(40.0, 10.0)
	check("G4 拖到推演器标题栏也归位", scene._handle_card_drop(tut_cert_clue_key, mx_title))
	check("G4 单条调查员证线索上桌布", scene.graph.matrix_count() == 1)
	check("G4 桌布提示长按", scene._matrix_win.dbg_hint().contains("长按"))
	scene._matrix_win.finish_charge()
	for i in 7:
		await process_frame
	check("G4 推演成功进入领证",
		scene._tutorial_step == 4 and scene._tutorial_cert_win != null)
	check("G4 桌布窗已收起", scene._matrix_win == null)
	check("G4 教学推演后桌布清空", scene.graph.matrix_count() == 0)
	scene._toggle_matrix()
	await process_frame
	scene._matrix_win.finish_charge()
	await process_frame
	check("G4 领证期重开推演不弹正式结局",
		not scene._ending.visible and scene._tutorial_step == 4)
	scene._toggle_matrix()
	await process_frame

	# ── 第 5 幕：姓名 / 编号 / 日期 / 照片 ──
	var cert = scene._tutorial_cert_win
	check("G5 领证窗打开", cert != null)
	check("W27 签发窗标题栏可拖动", cert != null and cert.dbg_drag_enabled())
	var cert_close := cert.get_node_or_null("bar/close") as Control if cert != null else null
	check("W27 签发期仍隐藏 ×（流程强制）", cert_close == null or not cert_close.visible)
	if cert != null:
		var stripes = cert.get_node_or_null("bar/title_stripes")
		check("A9 隐藏按钮后标题条纹补到右沿",
			stripes != null and stripes.line_right >= cert._inner_w - 2.0,
			"null" if stripes == null else "%.1f / %.1f" % [stripes.line_right, cert._inner_w])
		check("A10 签发窗有 3px 偏移影",
			cert.get_node_or_null("offset_shadow") != null and cert.offset_shadow)
	check("G5 四项字段齐全",
		cert != null and cert.find_child("cert_name", true, false) != null
			and cert.find_child("cert_id_value", true, false) != null
			and cert.find_child("cert_date_value", true, false) != null
			and cert.find_child("cert_photos", true, false) != null)
	var cert_date := cert.find_child("cert_date_value", true, false) as Label
	check("G5 编号日期自动生成",
		cert.dbg_cert_id().begins_with("TEC-") and cert_date != null and cert_date.text != "")
	if cert != null:
		cert.dbg_set_name("")
		cert.dbg_confirm()
	check("G5 空姓名不能签发", cert != null and scene._tutorial_cert_win != null)
	var cert_err := cert.find_child("cert_error", true, false) as Label
	check("G5 空姓名给出提示", cert_err != null and cert_err.text != "")
	if cert != null:
		cert.dbg_set_name("测试调查员")
		cert.dbg_pick("CHARS_TEC")
	check("G5 照片可选", cert != null and cert.dbg_avatar() == "CHARS_TEC")
	if cert != null:
		cert.dbg_confirm()
	for i in 7:
		await process_frame
	var saved := Investigator.load_from(scene._inv_path)
	check("G5 证件写入并落盘",
		scene._investigator.get("name", "") == "测试调查员"
			and saved.get("name", "") == "测试调查员"
			and saved.get("avatarId", "") == "CHARS_TEC")
	check("C4 证件数据层不含 sense", not scene._investigator.has("sense"))
	check("C4 读盘证件不含 sense", not saved.has("sense"))
	check("G5 领证窗关闭", scene._tutorial_cert_win == null)
	check("G5 案件地图弹出", scene._map_win != null)
	check("G5 地图图标解锁", scene._icon_by_app("map").visible)
	check("G5 TEC 提示选案",
		scene._tec.visible and _last_line(scene._tec).contains("选择"))

	# ── 第 6 幕：选 A-001，进入完整桌面 ──
	var case_map = scene._map_win
	check("G6 A-001 显示可进入",
		case_map != null and case_map.dbg_row_state("A001") in ["可进入", "进入"])
	check("G6 A-002 仍锁定",
		case_map != null and case_map.dbg_row_state("A002") == "锁定")
	check("G6 锁定案件点不进去", case_map != null and not case_map.dbg_click("A002"))
	check("G6 点击 A-001", case_map != null and case_map.dbg_click("A001"))
	for i in 10:
		await process_frame
	check("G6 进入正式案件",
		not scene._tutorial_active and scene._active_case == "A001"
			and scene.case_def.case_def.id == "a001")
	check("G6 起始场景已上桌", scene.graph.nodes.has("loc:SCENES_garden"))
	scene._on_card_selected("loc:SCENES_garden")
	await process_frame
	check("G6 换案后节点详情仍可用",
		scene._detail_win != null and scene._detail_win.visible
			and scene._detail_win._graph == scene.graph)
	check("G6 完整图标栏恢复",
		scene._icon_layer().visible and scene._icon_by_app("goto").visible
			and scene._icon_by_app("people").visible and scene._icon_by_app("tec").visible
			and scene._icon_by_app("log").visible)
	check("G6 顶栏恢复",
		(scene.get_node("header/brand_sub") as Control).visible
			and (scene.get_node("header/btn_撤销") as Control).visible
			and scene._inv_chip.visible)
	check("G6 案件窗控件恢复",
		(scene._case_win.get_node("bar/close") as Control).visible
			and (scene._case_win.get_node("bar/min") as Control).visible)
	check("G6 TEC 收起并恢复拖动",
		not scene._tec.visible and scene._tec.dbg_drag_enabled())
	check("G6 TEC 控件恢复",
		(scene._tec.get_node("bar/close") as Control).visible
			and (scene._tec.get_node("bar/min") as Control).visible)

	# 签发后的证件复核：内容不溢出，并能更换照片。
	scene._open_cert_review()
	await process_frame
	var review = scene._cert_win
	check("G6 证件复核窗打开", review != null)
	check("G6 证件内容不溢出窗框",
		review != null and review.content.get_combined_minimum_size().y <= review.body.size.y + 1.0)
	var change_photo := review.find_child("cert_change_photo", true, false) as Button
	check("G6 有更换照片入口", change_photo != null)
	if change_photo != null:
		change_photo.pressed.emit()
	await process_frame
	check("G6 更换照片窗打开", scene._photo_win != null)
	var picker = scene._photo_win
	if picker != null:
		picker.dbg_pick("CHARS_ANON")
	await process_frame
	check("G6 照片写进证件", scene._investigator.get("avatarId", "") == "CHARS_ANON")
	Investigator.clear(scene._inv_path)

	# 展开容器：旧卡不整体漂移、镜头不自动缩小，新卡保持完整标题。
	var stable_sid := ""
	for s in scene.case_def.scenes.values():
		if not scene.graph.explored.has(s.id) and not scene.case_def.is_time_id(s.id) \
				and scene.case_def.nodes_of_scene(s).size() > 0:
			stable_sid = s.id
			break
	if stable_sid != "":
		scene.dbg_ensure("loc", stable_sid)
		await process_frame
		scene._view_k = 1.0
		scene._view_user = true
		scene._apply_view()
		var stable_before: Dictionary = {}
		for key in _cards().keys():
			var c := _cards()[key] as NodeCard
			if c != null and c.visible:
				stable_before[String(key)] = c.position
		var stable_k: float = scene._view_k
		scene._toggle_container("loc", stable_sid)
		await process_frame
		await process_frame
		var moved_cards: int = 0
		for key in stable_before.keys():
			var c := _cards().get(key, null) as NodeCard
			if c != null and is_instance_valid(c) and c.visible \
					and c.position.distance_to(stable_before[key]) > 0.5:
				moved_cards += 1
		check("展开容器：已有卡片不整体漂移", moved_cards == 0, str(moved_cards))
		check("展开容器：镜头不自动缩放", absf(scene._view_k - stable_k) < 0.001,
			"%f / %f" % [scene._view_k, stable_k])
		var new_titles: int = 0
		var new_cards: int = 0
		for key in _cards().keys():
			if stable_before.has(String(key)):
				continue
			var c := _cards()[key] as NodeCard
			if c != null and c.visible:
				new_cards += 1
				if c._title.visible:
					new_titles += 1
		check("展开容器：新卡先显示完整文字", new_cards > 0 and new_titles == new_cards,
			"%d / %d" % [new_titles, new_cards])
		check("展开容器：连线立即出现", scene._edge_layer.segment_count() > 0,
			str(scene._edge_layer.segment_count()))
		var edge_fades := false
		for raw in scene._edge_layer._segments:
			var seg: Dictionary = raw
			if float(seg.get("alpha", 1.0)) < 0.95:
				edge_fades = true
				break
		check("展开容器：连线随节点同步淡入（不先出线）", edge_fades)
		var stage_r: Rect2 = scene._stage.get_global_rect()
		var all_visible := true
		for key in _cards().keys():
			if stable_before.has(String(key)):
				continue
			var c := _cards()[key] as NodeCard
			if c != null and c.visible and not stage_r.encloses(c.get_global_rect()):
				all_visible = false
				break
		check("展开容器：镜头平移跟随新节点", all_visible)
		if scene._narr != null and is_instance_valid(scene._narr):
			scene._narr.queue_free()
			scene._narr = null
			await process_frame

	# ── W 组收口：图标边界 / 重叠命中 / 键盘 / 平移边界 / 镜像 LOD / G14 ──
	# W7：窗口尺寸变化只同步拖动边界，不把玩家摆好的图标归位。
	var w7_icon := scene._icon_by_app("tec") as DeskIcon
	var w7_pos: Vector2 = w7_icon.position if w7_icon != null else Vector2.ZERO
	if w7_icon != null:
		w7_icon.position = Vector2(700.0, 500.0)
		scene._desk.size = Vector2(960.0, 700.0)
		scene._sync_icon_bounds()
		check("W7 resize 后图标夹回可见区",
			w7_icon.position.x <= 960.0 - w7_icon.size.x + 0.01
				and w7_icon.position.y <= 700.0 - w7_icon.size.y + 0.01,
			str(w7_icon.position))
		scene._desk.size = Vector2(1280.0, 720.0)
		w7_icon.position = w7_pos
		scene._sync_icon_bounds()

	# W8：悬停高亮与组合命中都取「最上层」那张卡。
	var w8_cards: Array = []
	for key in _cards().keys():
		var c := _cards()[key] as NodeCard
		if c != null and c.visible:
			w8_cards.append(c)
	if w8_cards.size() >= 2:
		var w8_a: NodeCard = w8_cards[0]
		var w8_b: NodeCard = w8_cards[1]
		var w8_a_pos: Vector2 = w8_a.position
		var w8_b_pos: Vector2 = w8_b.position
		w8_b.position = w8_a.position
		w8_b.move_to_front()
		var w8_pt: Vector2 = w8_b.get_global_rect().get_center()
		for _i8 in 6:
			if scene._floating_window_at(w8_pt) == null:
				break
			scene._close_top_window()
		await process_frame
		check("W8 重叠命中与高亮同为最上层卡",
			w8_a._card_under(w8_pt) == w8_b.card_key
				and scene._card_key_at(w8_pt) == w8_b.card_key,
			"%s / %s" % [w8_a._card_under(w8_pt), scene._card_key_at(w8_pt)])
		w8_a.position = w8_a_pos
		w8_b.position = w8_b_pos

	# W11：Esc 关最上层窗，Ctrl+Z 撤销。
	scene._toggle_storage(GraphState.LEDGER)
	await process_frame
	check("W11 前置：线索册已打开", scene._ledger_win != null)
	var w11_esc := InputEventKey.new()
	w11_esc.keycode = KEY_ESCAPE
	w11_esc.pressed = true
	scene._unhandled_input(w11_esc)
	check("W11 Esc 关闭最上层窗", scene._ledger_win == null)
	var w11_card: NodeCard = w8_cards[0] if not w8_cards.is_empty() else null
	if w11_card != null:
		var w11_key: String = w11_card.card_key
		var w11_pin_before: bool = bool(scene.graph.node(w11_key).get("pinned", false))
		var w11_hist: int = scene.dbg_history_size()
		scene._on_card_pin_toggled(w11_key)
		check("W11 前置：置钉进入撤销栈", scene.dbg_history_size() > w11_hist)
		var w11_undo := InputEventKey.new()
		w11_undo.keycode = KEY_Z
		w11_undo.ctrl_pressed = true
		w11_undo.pressed = true
		scene._unhandled_input(w11_undo)
		check("W11 Ctrl+Z 撤销置钉",
			bool(scene.graph.node(w11_key).get("pinned", false)) == w11_pin_before)

	# W12：平移边界至少留 80px 世界可见，且按下载入拖动光标。
	var w12_stage := scene.get_node("desk/case_win/body/stage") as Control
	var w12_far: Vector2 = scene._clamp_view_pos(Vector2(99999.0, 99999.0))
	var w12_near: Vector2 = scene._clamp_view_pos(Vector2(-99999.0, -99999.0))
	check("W12 平移右上边界留出世界",
		w12_far.x <= w12_stage.size.x - 80.0 + 0.01
			and w12_far.y <= w12_stage.size.y - 80.0 + 0.01, str(w12_far))
	check("W12 平移左下边界留出世界", w12_near.x >= 80.0 - 2000.0 * scene._view_k
		and w12_near.y >= 80.0 - 1300.0 * scene._view_k, str(w12_near))

	# W14：缩放档下拖卡，镜像的 scale / LOD 与原件一致。
	# 注意 W11 的撤销会全量重建卡片，这里要重新取当前实例。
	var w14_card: NodeCard = null
	for key in _cards().keys():
		var c := _cards()[key] as NodeCard
		if c != null and c.visible:
			w14_card = c
			break
	if w14_card != null:
		var w14_old_k: float = scene._view_k
		scene._view_k = 0.6
		scene._apply_view()
		scene._on_card_dragged(w14_card.card_key)
		var w14_mirror: NodeCard = scene._card_mirror
		check("W14 镜像跟随缩放倍率",
			w14_mirror != null and absf(w14_mirror.scale.x - 0.6) < 0.01,
			str(w14_mirror.scale) if w14_mirror != null else "null")
		check("W14 镜像跟随 LOD（0.6 档只留符号）",
			w14_mirror != null and not w14_mirror._title.visible
				and w14_mirror._glyph.size.x > 60.0,
			"null" if w14_mirror == null else str(w14_mirror._title.visible))
		scene._drop_card_mirror(w14_card)
		scene._drag_key = ""
		scene._view_k = w14_old_k
		scene._apply_view()

	# G14：真名线索行反白 + 强调青首符号 + 打字机停顿。
	var g14: EndingDef = scene.case_def.ending_by_id("TRUE_E")
	if g14 != null and not g14.recipe.is_empty():
		var g14_key: String = scene.dbg_ensure("clue", String(g14.recipe[0].id))
		check("G14 识别真名配方线索", scene._has_true_name_clue([g14_key]))
		scene._tec.append_true_clue("真名线索测试行")
		var g14_line: Node = scene._tec._lines.get_child(scene._tec._lines.get_child_count() - 3)
		check("G14 真名行反白 + 青色首符号",
			g14_line is TypewriterLabel
				and (g14_line as TypewriterLabel).get_theme_stylebox("normal") != null
				and (g14_line as TypewriterLabel).find_child("true_clue_mark", true, false) != null)
		check("G14 真名行有打字前停顿",
			g14_line is TypewriterLabel and (g14_line as TypewriterLabel).pause_ms > 0.0)
		scene._tec.finish_typing()

	# G6：普通结局后，目标条要接着指路，而不是演完就静场。
	var normal_end: EndingDef = scene.case_def.ending_by_id("END_NORMAL")
	check("G6 普通结局样本存在", normal_end != null and not normal_end.is_true_capture)
	if normal_end != null:
		scene.graph.mark_ending(normal_end.id)
		scene._last_ending_id = normal_end.id
		scene._refresh_crumbs()
		check("G6 普通结局后显示已记录 X/Y 与真名",
			scene._goal.text.contains("已记录") and scene._goal.text.contains("真名"),
			scene._goal.text)

	print("=== %d 项，失败 %d ===" % [total, fails])
	quit(0 if fails == 0 else 1)


func _last_line(tec: TecWindow) -> String:
	var lines := tec.dbg_lines()
	return String(lines[lines.size() - 1]) if not lines.is_empty() else ""


func _cards() -> Dictionary:
	var out := {}
	var layer: Node = scene.get_node("desk/case_win/body/stage/cards")
	for c in layer.get_children():
		if c is NodeCard:
			out[(c as NodeCard).card_key] = c
	return out


## 画布上任意一个「没有卡片、没有落点窗口」的点。1x 相机下卡片可能铺满画布，
## 不能再写死一个坐标当空白。
func _empty_canvas_point(scene: Control) -> Vector2:
	var r: Rect2 = scene._stage.get_global_rect()
	var y := r.position.y + 12.0
	while y < r.end.y - 12.0:
		var x := r.position.x + 12.0
		while x < r.end.x - 12.0:
			var p := Vector2(x, y)
			var clear: bool = scene._card_key_at(p) == ""
			if clear:
				for t in scene._drop_targets():
					if (t["rect"] as Rect2).has_point(p):
						clear = false
						break
			if clear:
				return p
			x += 28.0
		y += 24.0
	return r.get_center()


## 「拖到空白」用的落点：必须在**任何落点之外、也没被别的卡压住**。
## 不能写死 `center + (-40, 30)` —— 布局会随卡片集合变（2026-10-21：开局不再预置手电筒后，
## 它被弹簧推到证物袋窗上，那一拖直接判成「收进袋」，后面两条断言跟着崩）。
func _blank_point_near(scene: Control, card: NodeCard) -> Vector2:
	var base := card.get_global_rect().get_center()
	for off in [Vector2(-40, 30), Vector2(70, 45), Vector2(-80, -55), Vector2(95, -35), Vector2(0, 90)]:
		var p: Vector2 = base + off
		var clear := true
		for t in scene._drop_targets():
			if (t["rect"] as Rect2).has_point(p):
				clear = false
				break
		if not clear:
			continue
		if scene._floating_window_at(p) != null:
			continue
		for k in scene._cards.keys():
			var c: NodeCard = scene._cards[k]
			if c == card or not c.visible:
				continue
			if c.get_global_rect().has_point(p):
				clear = false
				break
		if clear:
			return p
	return _empty_canvas_point(scene)


func _press(card: NodeCard, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.global_position = pos
	card._gui_input(ev)


func _release(card: NodeCard, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.global_position = pos
	card._gui_input(ev)


func _motion(card: NodeCard, pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	card._gui_input(ev)


## 把事件真的推进 viewport（走命中判定 + mouse_focus），与直接调 `_gui_input` 互补：
## 后者绕过了事件投递，看不出「隐藏的 Control 收不到 motion」这类问题。
func _vpush_btn(at: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = at
	ev.global_position = at
	root.push_input(ev, true)


func _vpush_mov(at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(ev, true)


## 拖动：`to` 可以是另一张卡（组合），也可以是桌面图标 / 窗口（落点）
func _drag(from: NodeCard, to: Control) -> void:
	var a := from.get_global_rect().get_center()
	var b := to.get_global_rect().get_center()
	_press(from, a)
	_motion(from, a + Vector2(12, 8))
	_motion(from, b)
	_release(from, b)


## 单击 = 选中（不激活）；双击 = 两下（500ms 窗口内）才激活 —— 与 Web 的 pointerup + dblclick 同口径
func _single_click(card: NodeCard) -> void:
	var p := card.get_global_rect().get_center()
	_press(card, p)
	_release(card, p)


func _double_click(card: NodeCard) -> void:
	_single_click(card)
	_single_click(card)


# 桌布 chip 走的是 `gui_input` 信号（矩阵窗把 handler bind 上去），不走 `_gui_input` 重载，
# 所以 chip 的手套事件直接 emit 信号 —— 与 NodeCard 手套路径两条并存。
func _chip_press(chip: Control, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.global_position = pos
	chip.gui_input.emit(ev)


func _chip_motion(chip: Control, pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	chip.gui_input.emit(ev)


func _chip_release(chip: Control, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.global_position = pos
	chip.gui_input.emit(ev)


func case_cmds_empty() -> bool:
	var s = scene.case_def.scene_of("SCENES_garden")
	return s != null and s.commands.is_empty()
