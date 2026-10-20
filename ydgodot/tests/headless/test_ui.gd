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


func _drag(from: NodeCard, to: NodeCard) -> void:
	var a := from.get_global_rect().get_center()
	var b := to.get_global_rect().get_center()
	_press(from, a)
	_motion(from, a + Vector2(12, 8))
	_motion(from, b)
	_release(from, b)


func _double_click(card: NodeCard) -> void:
	var p := card.get_global_rect().get_center()
	_press(card, p)
	_release(card, p)
