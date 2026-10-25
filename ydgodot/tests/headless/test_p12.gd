extends SceneTree
## P1.2 图状态全量 + P1.3 命令行为补充回归
##
## 覆盖这一轮补齐的四处口径（都与 Web 版 02-state.js / 06-storage.js / 09-commands.js 对齐）：
##   1) 收纳三态：BAG 什么都收 / LEDGER 只收线索 / MATRIX 归位
##   2) 折叠后的隐藏重算：钉住的、跟场外有连线的都不藏
##   3) useItem 的判定顺序：先查零件，再查工具发不发光
##   4) 工具消耗：非可复用工具用完消失，可复用的留着
##
## 运行：godot --headless --path ydgodot --script res://tests/headless/test_p12.gd

var fails := 0
var total := 0
var c: CaseLoader
var g: GraphState
var cs: CommandSystem


func check(name: String, cond: bool, detail: String = "") -> void:
	total += 1
	if cond:
		print("  PASS  ", name)
	else:
		fails += 1
		print("  FAIL  ", name, ("  [" + detail + "]") if detail != "" else "")


func _initialize() -> void:
	print("=== P1.2 图状态全量 + P1.3 命令行为 ===")
	c = CaseLoader.new()
	check("装载案件", c.load_case(), c.load_error)
	g = GraphState.new(c)
	cs = CommandSystem.new(c, g)

	_test_bag()
	_test_ledger()
	_test_matrix()
	_test_restash()
	_test_collapse_hidden()
	_test_use_item_order()
	_test_consume()
	_test_delete_node()

	print("=== %d 项，失败 %d ===" % [total, fails])
	quit(0 if fails == 0 else 1)


# ── 1. 证物袋：什么都收（容器除外），记来源 ────────────────────────────
func _test_bag() -> void:
	g.reveal_container("loc", "SCENES_garden")
	g.reveal_container("item", "ITEM_shuzhuo")
	var lamp := g.key_of("item", "ITEM_taideng")
	check("袋：普通物品属性允许", g.can_bag(lamp))
	check("袋：普通物品收得进", g.bag_store(lamp))
	check("袋：收进去后不可见", not g.is_visible(lamp))
	check("袋：记账去向 BAG", String(g.stored.get(lamp, "")) == GraphState.BAG)
	check("袋：记下来源容器", String(g.node(lamp).get("bag_from", "")) == "ITEM_shuzhuo")
	check("袋：容器收不进（书桌是落脚点）", not g.bag_store(g.key_of("item", "ITEM_shuzhuo")))
	var drawer := String(g.add_node("item", "ITEM_chouti")["key"])
	check("袋：抽屉也按 baggable=false 拒收", not g.bag_store(drawer))
	check("袋：can_bag 与物品属性同源", not g.can_bag(drawer))
	check("袋：已收纳的不重复收", not g.bag_store(lamp))
	check("袋：取回后重新可见", g.take_back(lamp) and g.is_visible(lamp))


# ── 2. 线索册：只有线索能进 ────────────────────────────────────────────
func _test_ledger() -> void:
	var clue: String = String(g.add_node("clue", "CLUES_nm")["key"])
	var item: String = String(g.add_node("item", "ITEMS_bd")["key"])
	check("册：证收得进", g.ledger_store(clue))
	check("册：普通物品收不进", not g.ledger_store(item))
	check("册：记账去向 LEDGER", String(g.stored.get(clue, "")) == GraphState.LEDGER)
	check("册：取回后可见", g.take_back(clue) and g.is_visible(clue))


# ── 3. 推演桌布：按感官归位，感官不对不收 ────────────────────────────
func _test_matrix() -> void:
	var clue: String = String(g.add_node("clue", "CLUES_nm")["key"])
	var sense := c.clue_of("CLUES_nm").sense
	check("桌布：感官对的证能归位", g.matrix_assign(clue, sense))
	check("桌布：记账去向 MATRIX", String(g.stored.get(clue, "")) == GraphState.MATRIX)
	check("桌布：感官不对不收", not g.matrix_assign(clue, "taste" if sense != "taste" else "vision"))
	check("桌布：能取回画布", g.matrix_take(clue) and g.is_visible(clue))


# ── 4. 跨窗搬运：袋（物/词）与册（证）不再互通 ──────────────────────────
func _test_restash() -> void:
	var word: String = String(g.add_node("evidence", "EVID_CI_lhs_word")["key"])
	check("词进证物袋", g.bag_store(word))
	check("词不能搬进证据册", not g.restash(word, GraphState.BAG, GraphState.LEDGER))
	var zheng: String = String(g.add_node("evidence", "CLUES_JS")["key"])
	check("证不进证物袋", not g.bag_store(zheng))
	check("证进证据册", g.ledger_store(zheng))
	check("证不能搬进证物袋", not g.restash(zheng, GraphState.LEDGER, GraphState.BAG))
	check("搬运：搬到同一个地方算无效", not g.restash(zheng, GraphState.LEDGER, GraphState.LEDGER))


# ── 5. 折叠后的隐藏重算 ────────────────────────────────────────────────
func _test_collapse_hidden() -> void:
	var g2 := GraphState.new(c)
	g2.reveal_container("loc", "SCENES_garden")
	g2.reveal_container("item", "ITEM_shuzhuo")
	var lamp := g2.key_of("item", "ITEM_taideng")
	var book := g2.key_of("item", "ITEM_sxbj")
	check("折叠前：书桌的孩子都可见", g2.is_visible(lamp) and g2.is_visible(book))

	g2.collapse("ITEM_shuzhuo")
	check("折叠后：书桌的孩子被藏起来", not g2.is_visible(lamp) and not g2.is_visible(book))
	check("折叠后：容器本身还在", g2.is_visible(g2.key_of("item", "ITEM_shuzhuo")))

	# 钉住 → 不跟着藏
	g2.node(lamp)["pinned"] = true
	g2.recompute_hidden()
	check("钉住的节点：折叠也不藏", g2.is_visible(lamp))

	# 与场外有连线 → 不藏
	var g3 := GraphState.new(c)
	# 花园里长出来的东西 home_scene 是 SCENES_garden —— 那是「场外」
	g3.reveal_scene("SCENES_garden")
	g3.reveal_container("item", "ITEM_shuzhuo")
	var t3 := g3.key_of("item", "ITEM_taideng")
	var outside := g3.key_of("item", "ITEM_something")     # 花园里的东西，home_scene = SCENES_garden
	g3.link(outside, t3, "entity")
	g3.collapse("ITEM_shuzhuo")
	check("与场外有连线的节点：折叠也不藏", g3.is_visible(t3), str(g3.hidden.keys()))

	g2.uncollapse("ITEM_shuzhuo")
	check("展开后：孩子重新可见", g2.is_visible(lamp) and g2.is_visible(book))

	# 场景通路不是归属：花园 ↔ 书桌的 node_locs 互相指，不能把场景挂到物品下。
	var g9 := GraphState.new(c)
	g9.reveal_scene("SCENES_garden")
	g9.reveal_container("item", "ITEM_shuzhuo")
	check("场景通路不反向改 home_scene",
		String(g9.node("loc:SCENES_garden").get("home_scene", "")) == "",
		str(g9.node("loc:SCENES_garden")))
	g9.collapse("SCENES_garden")
	g9.collapse("ITEM_shuzhuo")
	check("连续折叠花园与书桌：花园场景仍在", g9.is_visible("loc:SCENES_garden"),
		str(g9.hidden.keys()))
	check("连续折叠花园与书桌：书桌随花园收起", not g9.is_visible("item:ITEM_shuzhuo"))

	# 旧存档可能已经写成环：场景节点的 home_scene 被误记成物品。重算时场景仍必须当根。
	var g10 := GraphState.new(c)
	var old_garden := g10.add_node("loc", "SCENES_garden")
	old_garden["home_scene"] = "ITEM_shuzhuo"
	g10.add_node("item", "ITEM_shuzhuo")
	g10.add_node("item", "ITEM_taideng")["home_scene"] = "ITEM_shuzhuo"
	g10.collapse("SCENES_garden")
	g10.collapse("ITEM_shuzhuo")
	check("旧存档成环数据：场景卡仍不消失", g10.is_visible("loc:SCENES_garden"),
		str(g10.hidden.keys()))
	check("旧存档场景归属被顺手修正",
		String(g10.node("loc:SCENES_garden").get("home_scene", "")) == "",
		str(g10.node("loc:SCENES_garden")))

	check("数据层：容器 node_items 无包含环", c.containment_cycles().is_empty(),
		str(c.containment_cycles()))

	# 旧存档里的物品归属也可能成环：A→B→A。成环节点按根处理，不能互相藏光。
	var g11 := GraphState.new(c)
	var desk11 := g11.add_node("item", "ITEM_shuzhuo")
	var trash11 := g11.add_node("item", "ITEMS_ljt")
	desk11["home_scene"] = "ITEMS_ljt"
	trash11["home_scene"] = "ITEM_shuzhuo"
	g11.collapse("ITEM_shuzhuo")
	g11.collapse("ITEMS_ljt")
	check("物品 home 成环：两张卡都不会消失",
		g11.is_visible(String(desk11["key"])) and g11.is_visible(String(trash11["key"])),
		str(g11.hidden.keys()))
	check("物品 home 成环：旧数据被改成根",
		String(desk11.get("home_scene", "")) == "" and String(trash11.get("home_scene", "")) == "",
		"%s / %s" % [desk11.get("home_scene", ""), trash11.get("home_scene", "")])

	# 新写入归属时也要挡住环：书桌已经属于垃圾桶时，不能再把垃圾桶挂回书桌下。
	var g12 := GraphState.new(c)
	var desk12 := g12.add_node("item", "ITEM_shuzhuo")
	desk12["home_scene"] = "ITEMS_ljt"
	var trash12 := g12.add_node("item", "ITEMS_ljt")
	g12._assign_home(trash12, String(desk12["key"]))
	check("新归属不会写成环", String(trash12.get("home_scene", "")) == "",
		str(trash12.get("home_scene", "")))


# ── 6. useItem 判定顺序：先零件，后发光 ───────────────────────────────
func _test_use_item_order() -> void:
	var g4 := GraphState.new(c)
	var cs4 := CommandSystem.new(c, g4)
	var changji := g4.key_of("item", "ITEMS_changji")
	g4.add_node("item", "ITEMS_changji")
	g4.add_node("item", "ITEMS_cz")
	g4.add_node("item", "ITEMS_wmhj")
	var play: UseItemCommandDef = null
	for x in c.item_of("ITEMS_changji").commands:
		if x is UseItemCommandDef and (x as UseItemCommandDef).requires.size() > 0:
			play = x as UseItemCommandDef
	# 唱针本身要发光？—— 唱针不发光的道具，测试只验「缺零件」优先于其他门
	g4.node(g4.key_of("item", "ITEMS_cz"))["lit"] = true
	var res := cs4.execute(changji, play)
	check("缺零件时先报缺零件（不是别的原因）",
		bool(res.get("blocked", false)) and String(res.get("message", "")).contains("唱针"),
		String(res.get("message", "")))


# ── 7. 工具消耗：非可复用工具用完消失 ─────────────────────────────────
func _test_consume() -> void:
	var g5 := GraphState.new(c)
	var cs5 := CommandSystem.new(c, g5)
	g5.add_node("item", "ITEMS_choudiantong")
	g5.add_node("item", "ITEMS_bd")
	g5.add_node("item", "ITEMS_jd")
	var cmd: UseItemCommandDef = null
	for x in c.item_of("ITEMS_bd").commands:
		if x is UseItemCommandDef:
			cmd = x as UseItemCommandDef
	check("绷带配了 useItem 命令", cmd != null)
	if cmd != null:
		var res := cs5.execute(g5.key_of("item", "ITEMS_bd"), cmd)
		check("用完成功", bool(res.get("ok", false)))
		check("非可复用工具用完消失", not g5.has("item", "ITEMS_jd"))
		check("结果里报了消耗", (res.get("consumed", []) as Array).has(g5.key_of("item", "ITEMS_jd")))

	# 可复用工具（手电筒在 config.reusableTools 里）不该消失
	var g6 := GraphState.new(c)
	var cs6 := CommandSystem.new(c, g6)
	g6.add_node("item", "ITEM_something")
	g6.add_node("item", "ITEM_shoudiantong")
	var c2: UseItemCommandDef = null
	for x in c.item_of("ITEM_something").commands:
		if x is UseItemCommandDef:
			c2 = x as UseItemCommandDef
	g6.node(g6.key_of("item", "ITEM_shoudiantong"))["lit"] = true
	cs6.execute(g6.key_of("item", "ITEM_something"), c2)
	check("可复用工具用完还在", g6.has("item", "ITEM_shoudiantong"))

	# 关掉消耗开关 → 工具留着
	var g7 := GraphState.new(c)
	var cs7 := CommandSystem.new(c, g7)
	cs7.consume_tools = false
	g7.add_node("item", "ITEMS_bd")
	g7.add_node("item", "ITEMS_jd")
	cs7.execute(g7.key_of("item", "ITEMS_bd"), cmd)
	check("关掉消耗开关：工具留着", g7.has("item", "ITEMS_jd"))


# ── 8. 删节点连边一起走 ────────────────────────────────────────────────
func _test_delete_node() -> void:
	var g8 := GraphState.new(c)
	g8.add_node("item", "ITEM_shoudiantong")
	g8.link("item:ITEM_shoudiantong", "loc:SCENES_garden", "entity")
	g8.tried["item:ITEM_shoudiantong>loc:SCENES_garden"] = true
	g8.tried["loc:SCENES_garden>char:NPC_FB"] = true
	check("删节点成功", g8.delete_node("item:ITEM_shoudiantong"))
	check("删掉后节点没了", not g8.has("item", "ITEM_shoudiantong"))
	check("连着的边也一起没了", not g8.has_edge("item:ITEM_shoudiantong", "loc:SCENES_garden"))
	check("U5 删节点清掉相关 tried",
		not g8.tried.has("item:ITEM_shoudiantong>loc:SCENES_garden"))
	check("U5 不误删无关 tried", g8.tried.has("loc:SCENES_garden>char:NPC_FB"))
	check("删不存在的节点返回 false", not g8.delete_node("item:ITEM_shoudiantong"))

	# 删除折叠中的容器：不能留下 collapsed 记账，否则后续重置 / 重建会被旧状态藏掉。
	var g13 := GraphState.new(c)
	g13.reveal_container("item", "ITEM_shuzhuo")
	g13.collapse("ITEM_shuzhuo")
	check("删除前：容器已折叠", g13.collapsed.has("ITEM_shuzhuo"))
	g13.delete_node("item:ITEM_shuzhuo")
	check("删除容器：collapsed 记账一起清掉", not g13.collapsed.has("ITEM_shuzhuo"),
		str(g13.collapsed.keys()))
