extends SceneTree
## P0 无头回归：只要逻辑链断了就红。
## 运行：godot --headless --path ydgodot --script res://tests/headless/test_p0.gd

var fails := 0
var total := 0


func check(name: String, cond: bool, detail: String = "") -> void:
	total += 1
	if cond:
		print("  PASS  ", name)
	else:
		fails += 1
		print("  FAIL  ", name, ("  [" + detail + "]") if detail != "" else "")


func _initialize() -> void:
	print("=== P0 垂直切片回归 ===")
	var c := CaseLoader.new()
	check("装载 data/case-a001.json", c.load_case(), c.load_error)
	check("案件有 11 个场景 / 36 件物品 / 20 条线索",
		c.scenes.size() == 11 and c.items.size() == 36 and c.clues.size() == 20,
		"%d/%d/%d" % [c.scenes.size(), c.items.size(), c.clues.size()])
	check("文本协议：标签换成中文名", c.strip_tags("花园里有[item:ITEM_something]。") == "花园里有黑影。")
	check("<br> 变成换行", c.strip_tags("一<br>二").contains("\n"))

	var g := GraphState.new(c)
	var fresh := g.reveal_scene("SCENES_garden")
	check("花园展开：长出实体节点", fresh.size() >= 6, str(fresh.size()))
	check("花园展开：黑影上画布", g.has("item", "ITEM_something"))
	check("花园展开：场景节点已探索", g.explored.has("SCENES_garden"))
	check("重复展开不重复建节点", g.reveal_scene("SCENES_garden").size() == 0)

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

	print("=== %d 项，失败 %d ===" % [total, fails])
	quit(0 if fails == 0 else 1)
