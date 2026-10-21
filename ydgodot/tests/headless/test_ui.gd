extends SceneTree
## P0 界面级回归：真的往 NodeCard 里塞鼠标事件，验证「拖拽 = 组合 / 双击 = 点亮」这条接线。
## 运行：godot --headless --path ydgodot --script res://tests/headless/test_ui.gd

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

	scene.dbg_expand("SCENES_garden")
	await process_frame
	var cards: Dictionary = _cards()
	check("展开后卡片数增加", cards.size() >= 5, str(cards.size()))
	check("开局不凭空给手电筒（它在左侧抽屉里，要自己开）", not cards.has(TORCH))
	check("黑影已上画布", cards.has(SHADOW))

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
	var pop := scene.get_node_or_null("desk/pw_pop")
	check("双击木盒：LOCK 弹窗出现", pop != null)
	scene.dbg_password("item:ITEMS_jzmh", "1111")
	await process_frame
	check("密码错：弹窗还在", scene.get_node_or_null("desk/pw_pop") != null)
	check("密码错：还没开箱", not _cards().has("item:ITEMS_htys"))
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
	check("袋里列出台灯", bag != null and (bag as StorageWin).items().has("item:ITEM_taideng"))

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
	check("册里列出线索", ledger != null and (ledger as StorageWin).items().has("clue:CLUES_nm"))
	check("台灯不在册里（册只收线索）",
		ledger != null and not (ledger as StorageWin).items().has("item:ITEM_taideng"))

	# 从册里取回
	(ledger as StorageWin)._take("clue:CLUES_nm")
	await process_frame
	check("从册里取回：线索重新可见", (_cards()["clue:CLUES_nm"] as NodeCard).visible == true)
	check("取回后册里少了一条", not (ledger as StorageWin).items().has("clue:CLUES_nm"))

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
	# 工具组七个控件：x 坐标必须与 Web 量出来的一致（多一个少一个都会错位）
	var slots := {"tog_合成消耗": 670.0, "tog_聚焦选中": 763.0, "tog_新节点自动居中": 856.0,
		"btn_适应窗口": 985.0, "btn_撤销": 1066.0, "btn_重置": 1123.0, "btn_检查可达性": 1180.0}
	var bad_slots: Array = []
	for nm in slots.keys():
		var c := scene.get_node_or_null("header/" + String(nm)) as Control
		if c == null or absf(c.position.x - float(slots[nm])) > 0.5:
			bad_slots.append(String(nm))
	check("页眉七件套 x 坐标对齐 Web", bad_slots.is_empty(), str(bad_slots))
	# 页眉拉满视口宽：不缩放之后它是自适应的，1280 口径下必须正好 1280
	check("页眉宽 = 视口宽（自适应）", head != null and absf(head.size.x - scene._vw()) < 0.5,
		str(head.size.x) if head != null else "null")
	# 主窗跟着桌面长：1280×720 下画布必须仍是 1162 × 613（P3 对拍口径）
	var stage := scene.get_node_or_null("desk/case_win/body/stage") as Control
	check("画布 1280 口径 = 1162×613", stage != null and stage.size == Vector2(1162, 613),
		str(stage.size) if stage != null else "null")
	var chip := scene.get_node_or_null("header/inv_chip") as Button
	check("证章摆在 318 / 宽 190", chip != null and absf(chip.position.x - 318.0) < 0.5
		and absf(chip.size.x - 190.0) < 0.5)
	# 窗框九切片：烘焙的底板在，投影才有地方画（PAD 内不裁）
	var frame := scene.get_node_or_null("desk/case_win/frame") as NinePatchRect
	check("案件窗用烘焙九切片当底板", frame != null
		and frame.texture != null and frame.patch_margin_left == 46)
	check("九切片往外撑出投影余量", frame != null and frame.position.x < 0.0 and frame.position.y < 0.0)
	# 枢纽场景：双线框（对应 Web 的 3px double）
	var hub_card: NodeCard = _cards().get("loc:SCENES_garden")
	var border := hub_card.get_node_or_null("border") as Control
	check("枢纽场景走双线框", border != null and border.visible and bool(border.get("double_line")))

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

	# 2) 右键 = 钉住（唯一切入点），钉住后左上角挂「已固定」
	var rev := InputEventMouseButton.new()
	rev.button_index = MOUSE_BUTTON_RIGHT
	rev.pressed = true
	torch._gui_input(rev)
	await process_frame
	check("右键钉住", bool(scene.graph.node(TORCH).get("pinned", false)))
	check("钉住挂「已固定」角标", (torch.get_node("pin") as Label).visible)
	torch._gui_input(rev)
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

	# 3b) 纯状态互动不得重排（2026-10-21 现场问题：「每次和节点互动，整块画布的卡都会轻微偏移」）
	#     根因：`_relayout()` 无条件跑 260 轮力导向，而这套参数**不收敛** —— 实测同一批节点连跑 8 次，
	#     单次最大位移 194 → 72 → 38 → 21 → 12 → 6.9 → 3.9 → 2.3 → 1.3px，每跑一次全画布漂一次。
	#     Web 只在「真长出节点」时 `layout()`（09-commands.js：「开关灯只重绘 —— 重排会让灯自己跳位置」）。
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
	_drag(torch, bag_icon)
	await process_frame
	await process_frame
	check("拖到证物袋图标：收进袋", String(scene.graph.stored.get(TORCH, "")) == GraphState.BAG,
		String(scene.graph.stored.get(TORCH, "")))
	check("收进袋后卡片离场", not torch.visible)

	# 4b) 落点表完整性：id 一律来自 11 项白名单
	#     Web 的 nodeDropTargets() 是 10 项，推演桌布在松手处单独判一遍（11 个元素）；
	#     Godot 合并成同一条表，悬停高亮与松手分派共用 —— 不会"亮了却不生效"。
	var ids: Array = scene.dbg_drop_target_ids()
	var whitelist := ["chat-win", "bag-win", "clue-win", "bag-dock", "clue-icon",
		"tec-dock", "infer-icon", "goto-icon", "tec-avatar", "tec-chip", "mx-board"]
	var stray: Array = []
	for did in ids:
		if not whitelist.has(String(did)):
			stray.append(did)
	check("落点 id 全部在 11 项白名单内", stray.is_empty(), str(stray))
	var icons_all := true
	for need in ["bag-dock", "clue-icon", "tec-dock", "infer-icon", "goto-icon"]:
		if not ids.has(need):
			icons_all = false
	check("五个桌面图标落点都在表里", icons_all, str(ids))

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

	# 7) 滚轮 = 以光标为锚缩放（0.35~1.8）
	var k0: float = scene._view_k
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
	var dw: DetailWin = scene.get_node_or_null("desk/detail_win") as DetailWin
	check("详情窗跟随选中", dw != null and dw.visible)
	if dw != null:
		var body_txt: String = dw._compose(scene.graph.node(vis_card.card_key))
		check("详情窗有简介段", body_txt.contains("D:"))
		check("详情窗不剧透关系", not body_txt.contains("装着") and not body_txt.contains("指向它"))

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

	# ── P0 交互（批 2）：拖动幽灵线 · 桌布 chip 带坐标取回 ──
	var mw: MatrixWin = scene.dbg_open_matrix()
	await process_frame
	check("桌布窗能打开", mw != null)
	# 挑一个不压在任何可见卡 / 开着的窗 / 桌布上的松手点（四角 + 四边各试一次）
	var blank_pt := stage3.get_global_rect().get_center()
	for off in [Vector2(0, 190), Vector2(-190, 0), Vector2(190, 0), Vector2(0, -190),
		Vector2(-140, 150), Vector2(140, 150), Vector2(-140, -150), Vector2(140, -150)]:
		var cand: Vector2 = stage3.get_global_rect().get_center() + off
		var occupied := false
		for key in _cards().keys():
			var c3: NodeCard = _cards()[key]
			if c3.visible and c3.get_global_rect().has_point(cand):
				occupied = true
				break
		if not occupied and scene._bag_win != null and scene._bag_win.get_global_rect().has_point(cand):
			occupied = true
		if not occupied and scene._ledger_win != null and scene._ledger_win.get_global_rect().has_point(cand):
			occupied = true
		if not occupied and mw != null and mw._board.get_global_rect().has_point(cand):
			occupied = true
		if not occupied:
			blank_pt = cand
			break
	check("测试前提：落点在空画布、桌布外、开着的窗外",
		not mw._board.get_global_rect().has_point(blank_pt)
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
	check("测试前提：松手点在桌布外", not mw._board.get_global_rect().has_point(blank_pt))
	scene.dbg_matrix_assign(clue_key)
	await process_frame
	var chip_panel: Control = mw._chips.get("CLUES_nm", null) as Control
	check("归位后桌布上有芯片", chip_panel != null)
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

	# 14) V5 warn 药丸：mdhm 是 a001 里唯一「无文本入口」的未探索场景
	# （零 [loc:] 入边 · 零命令产出 · 自己也没有出口）
	check("谓词：mdhm 未探索前提", not (scene.dbg_state()["explored"] as Array).has("SCENES_mdhm"))
	check("谓词：枢纽花园（5 条入边）不算", not scene.graph.is_no_entry("loc:SCENES_garden"))
	check("谓词：命令产出的 choutiyi 不算", not scene.graph.is_no_entry("loc:SCENES_choutiyi"))
	var md_key: String = scene.dbg_ensure("loc", "SCENES_mdhm")
	await process_frame
	check("谓词：mdhm 无文本入口", scene.graph.is_no_entry(md_key))
	var md_card: NodeCard = _cards().get(md_key, null)
	check("mdhm 上卡", md_card != null)
	check("无文本入口药丸挂上了", md_card != null and md_card._warn and md_card._warn_badge.visible,
		str(md_card != null and md_card._warn))
	check("已探索的花园不挂药丸", (_cards()["loc:SCENES_garden"] as NodeCard)._warn == false)

	# 15) V4 pop：fresh 节点初生 0.4→1.12→1（0.45s）；fresh 一次性消费、「新」角标保留
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
	var m_blank: Vector2 = stage4.get_global_rect().get_center()
	for off in [Vector2(0, 190), Vector2(-190, 0), Vector2(190, 0), Vector2(0, -190),
		Vector2(-140, 150), Vector2(140, 150), Vector2(-140, -150), Vector2(140, -150)]:
		var cand4: Vector2 = stage4.get_global_rect().get_center() + off
		var occupied4 := false
		for key in _cards().keys():
			var c4: NodeCard = _cards()[key]
			if c4 != torch4 and c4.visible and c4.get_global_rect().has_point(cand4):
				occupied4 = true
				break
		if not occupied4 and scene._bag_win != null and scene._bag_win.get_global_rect().has_point(cand4):
			occupied4 = true
		if not occupied4 and scene._ledger_win != null and scene._ledger_win.get_global_rect().has_point(cand4):
			occupied4 = true
		if not occupied4 and mw != null and mw._board.get_global_rect().has_point(cand4):
			occupied4 = true
		if not occupied4:
			m_blank = cand4
			break
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
	_release(torch4, m_blank)
	await process_frame
	check("松手：镜像退场", scene._card_mirror == null)
	check("松手：原卡复位可见", torch4.visible)
	check("松手：坐标写回数据（同第 12-18 节口径）",
		absf(float(scene.graph.node(TORCH)["x"]) - torch4.position.x) < 0.5,
		str(scene.graph.node(TORCH)["x"]) + " / " + str(torch4.position.x))
	# 收掉推演窗与两扇收纳窗（S6/S7 起开着）：后面的交互章节要用整块画布，
	# 别让 mx-board / bag-win / clue-win 拦走 _drop_targets 里的落点
	scene._toggle_matrix()
	scene._toggle_storage(GraphState.BAG)
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
	lut.text = "REACTION-PROBE 反应表注入：[clue:CLUES_qsan]"
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
	check("正文 [clue:] 照旧建线索（回归）", scene.graph.has("clue", "CLUES_qsan"))

	# 22) z 序（Web 静态 z-index 表）：rank 高的窗永远盖低的，无论谁后开；
	# icons(24) 在普通窗(25)之下、详情(22)之上；toast(30) 在 TEC(28) 之上；镜像(40) 在 toast 之上
	var desk22: Control = scene.get_node("desk")
	scene._toggle_case_map()
	await process_frame
	scene._toggle_log()
	await process_frame
	var e_log: Control = scene._log_win
	var e_map: Control = scene._map_win
	var e_icons: Control = desk22.get_node("icons")
	check("z：后开的日志(21) 仍压不过先开的地图(25)", e_log.get_index() < e_map.get_index(),
		str(e_log.get_index()) + " / " + str(e_map.get_index()))
	check("z：icons(24) 在普通窗之下", e_icons.get_index() < e_map.get_index())
	check("z：icons(24) 在日志(21) 之上", e_log.get_index() < e_icons.get_index())
	scene._ensure_detail()
	await process_frame
	var e_detail: Control = scene._detail_win
	check("z：详情(22) 在 icons(24) 之下", e_detail.get_index() < e_icons.get_index())
	check("z：详情(22) 在日志(21) 之上", e_log.get_index() < e_detail.get_index())
	scene._open_tec()
	await process_frame
	check("z：TEC(28) 盖住先开的地图(25)", scene._map_win.get_index() < scene._tec.get_index())
	check("z：toast(30) 在 TEC(28) 之上", scene._tec.get_index() < desk22.get_node("toast").get_index())
	scene._hide_tec()
	await process_frame

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
	# 窗口点击提层走 rank：日志窗按下提层后仍在 icons / 详情之下（不越 rank 盖上）
	# 先把日志窗关到已知态（S22 里开着），再开一份新的
	if scene._log_win != null and is_instance_valid(scene._log_win):
		scene._toggle_log()   # open → close
		await process_frame
	scene._toggle_log()   # close → open
	await process_frame
	var e_icons23: Control = scene.get_node("desk/icons")
	var d23b: Vector2 = (scene._log_win as Control).get_global_rect().get_center() - Vector2(0, 80)
	var ev23 := InputEventMouseButton.new()
	ev23.button_index = MOUSE_BUTTON_LEFT
	ev23.pressed = true
	ev23.global_position = d23b
	(scene._log_win as Control)._on_bar_input(ev23)
	await process_frame
	check("窗提层后仍在 icons 之下", scene._log_win.get_index() < e_icons23.get_index(),
		str(scene._log_win.get_index()) + " / " + str(e_icons23.get_index()))
	check("窗提层 rank 未变", int(scene._log_win.get_meta("zrank", -1)) == 21)
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
	var k24 := "loc:SCENES_garden"
	var c24: NodeCard = _cards().get(k24, null)
	check("前提：目标卡在画布上", c24 != null and c24.visible)
	if c24 != null:
		var r24: Vector2 = c24.get_global_rect().get_center()
		# 适应窗口后卡片很小、会互相压住；真实事件命中的是最上面那张，先把目标提到最前
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
		_vpush_btn(Vector2(420, 640), true)
		await process_frame
		_vpush_mov(Vector2(470, 680))
		await process_frame
		check("残留会话：新按下先收尾、不平移画布",
			scene._drag_key == "" and scene._card_layer.position.is_equal_approx(world24),
			"drag_key=" + scene._drag_key + " world=" + str(scene._card_layer.position - world24))
		_vpush_btn(Vector2(470, 680), false)
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

	print("=== %d 项，失败 %d ===" % [total, fails])
	quit(0 if fails == 0 else 1)


func _cards() -> Dictionary:
	var out := {}
	var layer: Node = scene.get_node("desk/case_win/body/stage/cards")
	for c in layer.get_children():
		if c is NodeCard:
			out[(c as NodeCard).card_key] = c
	return out


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
		for k in scene._cards.keys():
			var c: NodeCard = scene._cards[k]
			if c == card or not c.visible:
				continue
			if c.get_global_rect().has_point(p):
				clear = false
				break
		if clear:
			return p
	return base + Vector2(-40, 30)


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
