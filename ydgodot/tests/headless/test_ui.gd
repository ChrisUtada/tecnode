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

	check("桌面建起来了", scene != null and scene.dbg_state()["cards"] >= 2, str(scene.dbg_state()))

	scene.dbg_expand("SCENES_garden")
	await process_frame
	var cards: Dictionary = _cards()
	check("展开后卡片数增加", cards.size() >= 6, str(cards.size()))
	check("手电筒与黑影都在画布上", cards.has(TORCH) and cards.has(SHADOW))

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

	# 再双击书桌 = 收起：它的孩子被藏起来
	scene.dbg_activate("item:ITEM_shuzhuo")
	await process_frame
	var st2: Dictionary = scene.dbg_state()
	check("再次双击书桌：折叠记账", (st2["collapsed"] as Array).has("ITEM_shuzhuo"))
	# 抽屉有 cond 边连到场外的抽屉场景 → 按 Web 的 recomputeHidden 口径「跟场外有连线的留下」
	check("折叠后：有场外连线的节点留在画布上", (_cards()["item:ITEM_chouti"] as NodeCard).visible == true)
	check("折叠后：没有场外连线的节点被藏起来", (_cards()["item:ITEM_taideng"] as NodeCard).visible == false)

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
		and brand.get_theme_font_size("font_size") == 14)
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
	var drop_blank := torch.get_global_rect().get_center() + Vector2(-40, 30)
	_press(torch, torch.get_global_rect().get_center())
	_motion(torch, drop_blank)
	_release(torch, drop_blank)
	await process_frame
	check("拖到空白：坐标写回数据",
		absf(float(scene.graph.node(TORCH)["x"]) - torch.position.x) < 0.5
		and absf(float(scene.graph.node(TORCH)["y"]) - torch.position.y) < 0.5,
		str(torch.position) + " / " + str(scene.graph.node(TORCH).get("x")))

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

	print("=== %d 项，失败 %d ===" % [total, fails])
	quit(0 if fails == 0 else 1)


func _cards() -> Dictionary:
	var out := {}
	var layer: Node = scene.get_node("desk/case_win/body/stage/cards")
	for c in layer.get_children():
		if c is NodeCard:
			out[(c as NodeCard).card_key] = c
	return out


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


## 拖动：`to` 可以是另一张卡（组合），也可以是桌面图标 / 窗口（落点）
func _drag(from: NodeCard, to: Control) -> void:
	var a := from.get_global_rect().get_center()
	var b := to.get_global_rect().get_center()
	_press(from, a)
	_motion(from, a + Vector2(12, 8))
	_motion(from, b)
	_release(from, b)


## 单击 = 选中（不激活）；双击 = 两下（280ms 窗口内）才激活 —— 与 Web 的 pointerup + dblclick 同口径
func _single_click(card: NodeCard) -> void:
	var p := card.get_global_rect().get_center()
	_press(card, p)
	_release(card, p)


func _double_click(card: NodeCard) -> void:
	_single_click(card)
	_single_click(card)
