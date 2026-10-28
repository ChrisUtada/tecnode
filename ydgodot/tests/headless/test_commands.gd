extends SceneTree
## P1.2 / P1.3 回归：容器展开链 + 六型命令的完整行为（对齐 Web 版 09-commands.js）
## 运行：godot --headless --path ydgodot --script res://tests/headless/test_commands.gd

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
	print("=== P1.2 / P1.3 容器与六型命令 ===")
	c = CaseLoader.new()
	check("装载案件", c.load_case(), c.load_error)
	g = GraphState.new(c)
	cs = CommandSystem.new(c, g)

	_test_container_chain()
	_test_choice()
	_test_reveal_light_gate()
	_test_conditional()
	_test_password()
	_test_installs_requires()
	_test_collapse_store()
	_test_use_item_via_combo()

	print("=== %d 项，失败 %d ===" % [total, fails])
	quit(0 if fails == 0 else 1)


# ── 1. 容器链：花园 → 书桌 → 抽屉（容器物品也能展开）────────────────────
func _test_container_chain() -> void:
	var fresh := g.reveal_container("loc", "SCENES_garden")
	check("场景展开：长出实体", fresh.size() >= 6, str(fresh.size()))
	check("书桌是容器（content 带标签）", g.is_container("item", "ITEM_shuzhuo"))

	var n2 := g.reveal_container("item", "ITEM_shuzhuo")
	check("书桌展开：长出抽屉 / 笔记 / 台灯",
		g.has("item", "ITEM_chouti") and g.has("item", "ITEM_sxbj") and g.has("item", "ITEM_taideng"),
		"%d 个新节点" % n2.size())
	check("书桌展开：连 entity 边", g.has_edge("item:ITEM_shuzhuo", "item:ITEM_chouti", "entity"))
	check("书桌标记已探索", g.explored.has("ITEM_shuzhuo"))
	check("重复展开不重复建节点", g.reveal_container("item", "ITEM_shuzhuo").size() == 0)


# ── 2. choice：两个抽屉同时摆上画布（连 cond 边）───────────────────────
func _test_choice() -> void:
	var it := c.item_of("ITEM_chouti")
	var cmd: ChoiceCommandDef = null
	for x in it.commands:
		if x is ChoiceCommandDef:
			cmd = x
	check("抽屉配的是 choice 命令", cmd != null and cmd.options.size() == 2)
	var res := cs.execute(g.key_of("item", "ITEM_chouti"), cmd)
	check("choice 执行成功", bool(res.get("ok", false)))
	check("两个抽屉场景都上了画布",
		g.has("loc", "SCENES_choutiyi") and g.has("loc", "SCENES_choutier"))
	check("选项连的是 cond 边",
		g.has_edge("item:ITEM_chouti", "loc:SCENES_choutiyi", "cond")
		and g.has_edge("item:ITEM_chouti", "loc:SCENES_choutier", "cond"))
	g.reveal_scene("SCENES_choutiyi")
	check("左侧抽屉里有手电筒", g.has("item", "ITEM_shoudiantong"))


# ── 3. reveal：光照门（手写笔记要台灯或手电筒亮着）──────────────────────
func _test_reveal_light_gate() -> void:
	var it := c.item_of("ITEM_sxbj")
	var cmd: RevealCommandDef = null
	for x in it.commands:
		if x is RevealCommandDef:
			cmd = x
	check("手写笔记配的是 reveal 命令", cmd != null)
	check("reveal 挂了光照门（台灯 / 手电筒）", cmd.requires_lit.size() == 2)
	var dark := cs.execute(g.key_of("item", "ITEM_sxbj"), cmd)
	check("没点灯：reveal 被拦下", bool(dark.get("blocked", false)) and String(dark.get("message", "")) != "")
	check("被拦下时没有摊出笔记内容", not g.has("item", "ITEMS_dlh"))

	g.add_node("item", "ITEM_taideng")
	g.node("item:ITEM_taideng")["lit"] = true
	var lit := cs.execute(g.key_of("item", "ITEM_sxbj"), cmd)
	check("点亮台灯后：reveal 成功", bool(lit.get("ok", false)))
	check("摊出笔记里的 5 件东西", (lit.get("spawn", []) as Array).size() == 5, str(lit.get("spawn")))
	check("摊出的东西连到笔记（entity 边）", g.has_edge("item:ITEM_sxbj", "item:ITEMS_dlh", "entity"))


# ── 4. conditional：证不齐就不放行（植物 → 铁门）─────────────────────
func _test_conditional() -> void:
	var it := c.item_of("ITEMS_zhiwu")
	var cmd: ConditionalCommandDef = null
	for x in it.commands:
		if x is ConditionalCommandDef:
			cmd = x
	check("植物配的是 conditional 命令", cmd != null and cmd.conditions.size() >= 5)
	var bad := cs.execute(g.key_of("item", "ITEMS_zhiwu"), cmd)
	check("证不齐：被拦下且给出 failMessage",
		bool(bad.get("blocked", false)) and String(bad.get("message", "")).length() > 0)
	check("拦下时没有长出铁门说明", not String(bad.get("message", "")).contains("铁门"))

	for cond in cmd.conditions:
		g.captured[cond.clue.id] = true
	var good := cs.execute(g.key_of("item", "ITEMS_zhiwu"), cmd)
	check("证齐了：放行并说出铁门", bool(good.get("ok", false)) and String(good.get("message", "")).contains("铁门"))
	check("证齐了：产出「门的后面」场景",
		(good.get("reveal", []) as Array).has("loc:SCENES_mdhm") or g.has("loc", "SCENES_mdhm"))
	check("证齐了：成功文案提示双击进入", String(good.get("message", "")).contains("双击"))


# ── 5. password：木盒 0321（错的不推进、对的开箱给东西）────────────────
func _test_password() -> void:
	var it := c.item_of("ITEMS_jzmh")
	var cmd: PasswordCommandDef = null
	for x in it.commands:
		if x is PasswordCommandDef:
			cmd = x
	check("木盒配的是 password 命令", cmd != null and cmd.value == "0321")
	check("未开箱时画布上没有钥匙", not g.has("item", "ITEMS_htys"))

	var wrong := cs.submit_password(g.key_of("item", "ITEMS_jzmh"), cmd, "1111")
	check("密码错：只回一句、不推进", bool(wrong.get("wrong_password", false)) and not g.has("item", "ITEMS_htys"))
	check("密码错的提示里带输入的密码", String(wrong.get("message", "")).contains("1111"))

	var right := cs.submit_password(g.key_of("item", "ITEMS_jzmh"), cmd, "0321")
	check("密码对：开箱成功", bool(right.get("ok", false)))
	check("开箱后钥匙与美工刀都出来了",
		g.has("item", "ITEMS_htys") and g.has("item", "ITEMS_rxbs"))


# ── 6. useItem：装零件（唱针）→ 才放得出黑胶 ──────────────────────────
func _test_installs_requires() -> void:
	var it := c.item_of("ITEMS_changji")
	var install_cmd: UseItemCommandDef = null
	var play_cmd: UseItemCommandDef = null
	for x in it.commands:
		if not (x is UseItemCommandDef):
			continue
		var uc := x as UseItemCommandDef
		if uc.installs:
			install_cmd = uc
		elif uc.requires.size() > 0:
			play_cmd = uc
	check("唱机有「装唱针」与「放黑胶」两条命令", install_cmd != null and play_cmd != null)

	g.add_node("item", "ITEMS_changji")
	g.add_node("item", "ITEMS_cz")
	g.add_node("item", "ITEMS_wmhj")
	var early := cs.execute(g.key_of("item", "ITEMS_changji"), play_cmd)
	check("没装唱针就放黑胶：被拦下", bool(early.get("blocked", false)))
	check("拦下时不推进到唱机场景", not g.explored.has("SCENES_cjag"))

	var put := cs.execute(g.key_of("item", "ITEMS_changji"), install_cmd)
	check("装上唱针", bool(put.get("ok", false)))
	check("零件记账落在节点上",
		(g.node("item:ITEMS_changji").get("installed", {}) as Dictionary).has("ITEMS_cz"))

	var play := cs.execute(g.key_of("item", "ITEMS_changji"), play_cmd)
	check("装了唱针后放黑胶：成功", bool(play.get("ok", false)))

	# 第三条命令（用钥匙）才带 onSuccess.scene —— 顺带验「payload 揭示场景」这条支路
	var key_cmd: UseItemCommandDef = null
	for x in c.item_of("ITEMS_changji").commands:
		if x is UseItemCommandDef and (x as UseItemCommandDef).required_item != null \
			and (x as UseItemCommandDef).required_item.id == "ITEMS_htys":
			key_cmd = x
	g.add_node("item", "ITEMS_htys")
	check("唱机有「用钥匙」的命令", key_cmd != null)
	if key_cmd != null:
		check("onSuccess.payload 揭示场景（唱机）", not g.explored.has("SCENES_cjag"))
		var opened := cs.execute(g.key_of("item", "ITEMS_changji"), key_cmd)
		check("用钥匙后揭示唱机场景",
			bool(opened.get("ok", false)) and g.explored.has("SCENES_cjag"))


# ── 7. 折叠 / 收纳 ──────────────────────────────────────────────────────
func _test_collapse_store() -> void:
	var key := g.key_of("item", "ITEM_shuzhuo")
	check("未折叠时 is_collapsed = false", not g.is_collapsed("ITEM_shuzhuo"))
	g.collapse("ITEM_shuzhuo")
	check("折叠后 is_collapsed = true", g.is_collapsed("ITEM_shuzhuo"))
	check("折叠不删节点（只是收起）", g.has("item", "ITEM_shuzhuo"))

	var child := g.key_of("item", "ITEM_chouti")
	g.set_hidden(child, true)
	check("隐藏的节点 is_visible = false", not g.is_visible(child))
	g.set_hidden(child, false)
	check("取消隐藏后可见", g.is_visible(child))

	g.store("item:ITEM_taideng", "BAG")
	check("收进物品：不可见", not g.is_visible("item:ITEM_taideng"))
	check("收进去向记账", String(g.take("item:ITEM_taideng")) == "BAG")
	check("取回后可见", g.is_visible("item:ITEM_taideng"))


# ── 8. 拖放组合仍然走同一套执行器 ───────────────────────────────────────
func _test_use_item_via_combo() -> void:
	var comb := ComboSystem.new(c, g)
	g.add_node("item", "ITEM_something")
	g.add_node("item", "ITEM_shoudiantong")
	var blocked := comb.use_item("item:ITEM_shoudiantong", "item:ITEM_something")
	check("没点亮的手电筒拖到黑影：发光门拦下", bool(blocked.get("blocked", false)))
	g.node("item:ITEM_shoudiantong")["lit"] = true
	var ok := comb.use_item("item:ITEM_shoudiantong", "item:ITEM_something")
	check("点亮后拖过去：成功并带出尸体场景",
		bool(ok.get("ok", false)) and String(ok.get("next_scene", "")) == "SCENES_body")
	check("组合结果里带 matched 标记（组合链路认出命中）", bool(ok.get("matched", false)))
