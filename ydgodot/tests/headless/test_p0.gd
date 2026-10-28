extends "res://tests/headless/_test_base.gd"
## P0 无头回归：只要逻辑链断了就红。
## 运行：godot --headless --path ydgodot --script res://tests/headless/test_p0.gd

func _initialize() -> void:
	print("=== P0 垂直切片回归 ===")
	var c := CaseLoader.new()
	check("装载案件数据", c.load_case(), c.load_error)
	check("案件有 11 个场景 / 35 件物品 / 28 条证据",
		c.scenes.size() == 11 and c.items.size() == 35 and c.evidences.size() == 28,
		"%d/%d/%d" % [c.scenes.size(), c.items.size(), c.evidences.size()])
	var dirty := c.validate_text_clean()
	check("§7-3 正文无退役标签（装载校验可用）", dirty.is_empty(), str(dirty.slice(0, 5)))
	check("§7-3 退役标签会拒绝装载", c.validate_text_clean().is_empty())

	var g := GraphState.new(c)
	var fresh := g.reveal_scene("SCENES_garden")
	check("花园展开：长出实体节点", fresh.size() >= 6, str(fresh.size()))
	check("花园展开：黑影上画布", g.has("item", "ITEM_something"))
	check("花园展开：场景节点已探索", g.explored.has("SCENES_garden"))
	check("重复展开不重复建节点", g.reveal_scene("SCENES_garden").size() == 0)

	# ── 正文与画布解耦 ──
	# 节点清单只认资源上的 node_items / node_chars / node_locs / node_clues。
	# 正文写什么（甚至写成空的）都不该改变画布上出现的东西 —— 这正是原先的病灶：
	# 在检查器里润色正文时把 `[item:x]` 删掉，花园就一个节点都不长了。
	var s_garden := c.scene_of("SCENES_garden")
	var keep_content := s_garden.content
	s_garden.content = keep_content + "<br>[item:ITEMS_bd][char:CHARS_js]"
	var g_extra := GraphState.new(c)
	var n_extra: int = g_extra.reveal_scene("SCENES_garden").size()
	check("正文多写标签：不多长节点", n_extra == 7, str(n_extra))
	check("正文多写的标签没被建成节点", not g_extra.has("item", "ITEMS_bd") and not g_extra.has("char", "CHARS_js"))
	s_garden.content = ""
	var g_blank := GraphState.new(c)
	var n_blank: int = g_blank.reveal_scene("SCENES_garden").size()
	check("正文清空：节点照旧长出 7 个", n_blank == 7, str(n_blank))
	s_garden.content = keep_content

	var comb := ComboSystem.new(c, g)
	g.add_node("item", "ITEM_shoudiantong")

	var blocked := comb.use_item("item:ITEM_shoudiantong", "item:ITEM_something")
	check("没点亮：组合被发光门拦下", bool(blocked.get("blocked", false)))
	check("被拦下时没有推进到尸体场景", not g.explored.has("SCENES_body"))

	var lit := comb.toggle_light("item:ITEM_shoudiantong")
	check("双击手电筒：点亮", bool(lit.get("lit", false)))
	check("点亮时给一句提示", String(lit.get("message", "")).length() > 0)

	var ok := comb.use_item("item:ITEM_shoudiantong", "item:ITEM_something")
	check("点亮后：组合成功", bool(ok.get("ok", false)), str(ok))
	check("成功语与数据一致", String(ok.get("message", "")).begins_with("黑影被照亮了"))
	check("onSuccess 带出尸体场景", String(ok.get("next_scene", "")) == "SCENES_body")
	check("尸体场景已探索", g.explored.has("SCENES_body"))
	check("尸体场景节点已建", g.has("loc", "SCENES_body"))
	check("尸体场景的实体已长出（绷带）", g.has("item", "ITEMS_bd"))

	var again := comb.use_item("item:ITEM_shoudiantong", "item:ITEM_something")
	check("重复照亮仍返回成功（幂等，不重复建节点）", bool(again.get("ok", false)))
	check("尸体场景没有被建两遍", g.nodes.keys().count("loc:SCENES_body") == 1)

	_finish()
