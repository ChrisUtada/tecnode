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
	check("册：线索收得进", g.ledger_store(clue))
	check("册：普通物品收不进", not g.ledger_store(item))
	check("册：记账去向 LEDGER", String(g.stored.get(clue, "")) == GraphState.LEDGER)
	check("册：取回后可见", g.take_back(clue) and g.is_visible(clue))


# ── 3. 推演桌布：按感官归位，感官不对不收 ────────────────────────────
func _test_matrix() -> void:
	var clue: String = String(g.add_node("clue", "CLUES_nm")["key"])
	var sense := c.clue_of("CLUES_nm").sense
	check("桌布：感官对的线索能归位", g.matrix_assign(clue, sense))
	check("桌布：记账去向 MATRIX", String(g.stored.get(clue, "")) == GraphState.MATRIX)
	check("桌布：感官不对不收", not g.matrix_assign(clue, "taste" if sense != "taste" else "vision"))
	check("桌布：能取回画布", g.matrix_take(clue) and g.is_visible(clue))


# ── 4. 跨窗搬运（袋 ↔ 册）：只改去向 ──────────────────────────────────
func _test_restash() -> void:
	var clue: String = String(g.add_node("clue", "CLUES_JS")["key"])
	g.bag_store(clue)
	check("搬运：袋 → 册 成功", g.restash(clue, GraphState.BAG, GraphState.LEDGER))
	check("搬运：去向改成 LEDGER", String(g.stored.get(clue, "")) == GraphState.LEDGER)
	check("搬运：从错的地方搬不动", not g.restash(clue, GraphState.BAG, GraphState.LEDGER))
	check("搬运：搬到同一个地方算无效", not g.restash(clue, GraphState.LEDGER, GraphState.LEDGER))


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
