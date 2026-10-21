class_name ComboSystem
extends RefCounted
## 拖放组合 + 物品命令（P0 只实现切片用到的两条链路）
##
## 与 Web 版 `05-combine.js` / `09-commands.js` 对齐的规则（防漂移，见计划 §四）：
##   1) 发光工具门：`needsLitToUse` 的工具没点亮 → 拦下，**不记「已试过」、不进撤销栈**
##   2) 命中规则：目标物品的 commands 里 `type == "useItem"` 且 `requiredItem == 工具的 id`
##   3) 成功三件套：提示语 + `onSuccess.scene` 揭示 + 消耗规则（P0 暂不消耗）

var case_def: CaseLoader
var graph: GraphState
var cmd_sys: CommandSystem


func _init(p_case: CaseLoader, p_graph: GraphState) -> void:
	case_def = p_case
	graph = p_graph
	cmd_sys = CommandSystem.new(p_case, p_graph)


## 工具是否「要发光才能用」
func needs_lit(tool_key: String) -> bool:
	var n := graph.node(tool_key)
	if n.is_empty() or n["kind"] != "item":
		return false
	var it := case_def.item_of(String(n["id"]))
	return it != null and it.needs_lit_to_use


## 开关灯（手电筒这类 toggleLight 物品）。返回 {changed, lit, message} 或空字典。
func toggle_light(node_key: String) -> Dictionary:
	var n := graph.node(node_key)
	if n.is_empty() or n["kind"] != "item":
		return {}
	var it := case_def.item_of(String(n["id"]))
	if it == null or not it.toggle_light:
		return {}
	n["lit"] = not bool(n.get("lit", false))
	var msg := it.lit_on_message if n["lit"] else it.lit_off_message
	return {"changed": true, "lit": n["lit"], "message": case_def.strip_tags(msg)}


## 是不是「场景类」节点（loc / time / 旧版 scene）。场景⇄场景的判定只认这个。
func _is_scene(n: Dictionary) -> bool:
	return not n.is_empty() and GraphState.is_scene_kind(String(n["kind"]))


## 把一个节点拖到另一个节点上。返回：
##   {ok, blocked, message, reveal:Array, next_scene:String, tried:String}
## blocked = 被规则拦下（不执行、不记 tried）
##
## 顺序照抄 Web `attemptCombo`：
##   ① 目标自己的反应表 → ② 反向（工具是反应表主人）→ ③ 目标的 useItem 命令
##   → ④ 容器扫描（它收着的东西对工具有反应）→ ⑤ 都不中：记 tried + 说原因
## `tried` 只进字典、不写进 `graph.edges` —— 连线层单独读 `graph.tried` 画虚线，
## 若混进 edges 会污染力导向的弹簧与枢纽度数。
func use_item(tool_key: String, target_key: String) -> Dictionary:
	var tool := graph.node(tool_key)
	var target := graph.node(target_key)
	if tool.is_empty() or target.is_empty() or tool_key == target_key:
		return {"ok": false, "message": ""}
	var tool_id := String(tool["id"])
	var target_id := String(target["id"])

	# ⓪ 场景通路（Web `05-combine.js:15`）：把容器拖到场景上，只要**容器正文里 `[loc:对方]`**
	#    列着对方，就等于「前往」。书桌 / 垃圾桶不是场景，但它们 content 里的
	#    `[loc:…]`（如书桌的「返回花园」）照样是一条通路 —— 这也是 Web 那句
	#    `isSceneKind(tool.kind) || isContainerNode(tool)` 的用意。
	if _is_scene(target) and (_is_scene(tool) or graph.is_container_node(tool_key)):
		if graph.scene_locs(tool_id).has(target_id) or graph.scene_locs(target_id).has(tool_id):
			return {"ok": true, "travel": target_id, "message": ""}
	# 两个场景之间没有通路 = 「走不过去」：明确说清楚再停，不往下淌到反应表
	# （否则玩家会得到「场景 A 对场景 B 没有反应」这种答非所问的话）。
	# ⚠ 与其余失败**不同**：Web 这条分支只记失败原因、不记「已试过」，也不画 tried 虚线。
	if _is_scene(tool) and _is_scene(target):
		return {"ok": false, "no_tried": true,
			"message": "这两个场景之间没有直接通路"}

	# ① 目标自己有反应表（人物对「你手上的东西」说一句话）
	var hit := lookup_reaction(String(target["kind"]), target_id, tool_id)
	var owner_key := target_key
	# ② 反向：工具自己是反应表的所有者（把人拖到东西上）
	if hit.is_empty():
		var rev := lookup_reaction(String(tool["kind"]), tool_id, target_id)
		if not rev.is_empty():
			hit = rev
			owner_key = tool_key
	if not hit.is_empty():
		return _apply_reaction(hit, owner_key)

	# ③ 目标的 useItem 命令正好需要这个工具（发光门 / 零件门 / 装零件都在 CommandSystem 里）
	var target_it := case_def.item_of(target_id)
	if target_it != null:
		for cmd in target_it.commands:
			if not (cmd is UseItemCommandDef):
				continue
			var uc := cmd as UseItemCommandDef
			if uc.required_item == null or uc.required_item.id != tool_id:
				continue
			var res := cmd_sys.execute(target_key, uc)
			res["matched"] = true
			return res

	# ④ 容器扫描：它收着的东西对工具有反应（也反过来扫一次工具）
	var scan := _scan_container_reaction(target_key, tool_id)
	var scan_owner := target_key
	if scan.is_empty():
		scan = _scan_container_reaction(tool_key, target_id)
		scan_owner = tool_key
	if not scan.is_empty():
		return _apply_reaction(scan, scan_owner)

	# ⑤ 都不中：记一笔「试过」（画布上画一条淡虚线），并说明原因
	var tried := tool_key + ">" + target_key
	graph.tried[tried] = true
	return {
		"ok": false,
		"tried": tried,
		"message": "「%s」对「%s」没有反应" % [target["label"], tool["label"]],
	}


## 反应表查询（Web `lookupReaction`）：先 item_reactions、再 clue_reactions。
## A-001 共 27 条，全是人物带的：物品触发 14 条（朱穗 6 / 陆珩松 4 / TEC 4）、
## 线索触发 13 条（朱穗 4 / 陆珩松 6 / 槿杉 3）。全部是纯文本，没有 `results` / `onSuccess`，
## 所以 reactions 的产出通道目前数据上不为空（`_apply_reaction` 的结果公式已在运行时打开，
## 小盘上用注入的带 results 的反应来验）。
func lookup_reaction(kind: String, owner_id: String, tool_id: String) -> Dictionary:
	if kind != "char":
		return {}
	var ch := case_def.char_of(owner_id)
	if ch == null:
		return {}
	for r in ch.item_reactions:
		if r != null and r.trigger_id == tool_id:
			return {"text": r.text, "results": r.results, "field": "itemReactions"}
	for r in ch.clue_reactions:
		if r != null and r.trigger_id == tool_id:
			return {"text": r.text, "results": r.results, "field": "reactions"}
	return {}


## 容器扫描：读**带标签的原文**（`raw_text_of`），逐个内容物查反应表
func _scan_container_reaction(container_key: String, other_id: String) -> Dictionary:
	var n := graph.node(container_key)
	if n.is_empty() or not graph.is_container_node(container_key):
		return {}
	for tag in case_def.tags_of(case_def.raw_text_of(String(n["kind"]), String(n["id"]))):
		var h := lookup_reaction(String(tag["kind"]), String(tag["id"]), other_id)
		if not h.is_empty():
			h["via"] = container_key
			return h
	return {}


## 命中后的统一落地：正文 → 提示语；正文里的 [clue:x] → 建线索节点并连给反应表主人；
## 所有出现的线索同时计入「已捕获」（与 runCommand 的 gotClues 同口径）。
##
## 三条产出来源（Web `05-combine.js:112-123`，A-001 的 27 条反应全是纯文本，
## 通道在运行时直接按 Web 的同一公式走，小盘上用注入反应表来验）：
##   `react.results.scene`              → 新场景节点（fresh=「新」）+ `cond` 边
##   `react.results.items` + `onSuccess.items`（同一批合并）→ spawnItems：
##     新物品 洒在主人右下 (from + 60 + i*26)，已上画的旧物品不 fresh/不挪位；
##   `results.scene` 若是时刻 id → 走档案开口径（Web announceTimeCollected） here handled by DESKTOP toast.
func _apply_reaction(hit: Dictionary, owner_key: String) -> Dictionary:
	var raw := String(hit.get("text", ""))
	var captured := graph.capture_clues(raw)
	var reveal: Array = []
	for tag in case_def.tags_of(raw):
		if String(tag["kind"]) != "clue":
			continue
		var id := String(tag["id"])
		if graph.has("clue", id):
			continue
		graph.add_node("clue", id)
		var ck := graph.key_of("clue", id)
		graph.link(owner_key, ck, "entity")
		reveal.append(ck)

	# results.scene：新场景 + `cond` 边（Web：ensureSceneNode + markFresh + isNew 才连边）
	var results: Dictionary = hit.get("results", {})
	var scene_id := String(results.get("scene", ""))
	if scene_id != "" and case_def.scene_of(scene_id) != null:
		var scene_existed := graph.has("loc", scene_id)   # normalize 会把时刻 id 归到 time
		var sn := graph.add_node("loc", scene_id)
		graph.mark_fresh(String(sn["key"]))
		if not scene_existed:
			graph.link(owner_key, String(sn["key"]), "cond")
		reveal.append(String(sn["key"]))

	# results.items + onSuccess.items 合并 → spawnItems（Web 04-graph.js:127 同一公式）
	var new_items: Array = []
	new_items.append_array(results.get("items", []))
	if hit.has("on_success_items"):
		new_items.append_array(hit["on_success_items"])
	if not new_items.is_empty():
		var src := graph.node(owner_key)
		var sx := 900.0 if float(src.get("x", -1.0)) < 0.0 else float(src["x"])
		var sy := 600.0 if float(src.get("x", -1.0)) < 0.0 else float(src["y"])
		var home := String(src.get("home_scene", ""))
		for i in new_items.size():
			var iid := String(new_items[i])
			var existed_item := graph.has("item", iid)
			var iv := graph.add_node("item", iid)
			if String(iv.get("home_scene", "")) == "":
				iv["home_scene"] = home
			if existed_item:
				iv["fresh"] = false        # 本来就在画布上：不抢镜头、不重挂「新」
			else:
				graph.mark_fresh(String(iv["key"]))
				iv["x"] = sx + 60.0 + float(i) * 26.0
				iv["y"] = sy + 60.0 + float(i) * 26.0
				reveal.append(String(iv["key"]))

	return {
		"ok": true,
		"matched": true,
		"message": case_def.strip_tags(raw),
		"captured": captured,
		"reveal": reveal,
	}


## 双击节点的默认命令（第一条）。没有命令就返回空，由调用方决定「展开」还是别的。
## Web 双击语义对条（08-interact.js）：场景（loc）也吃 SCENES[id].commands[0]，
## 只是 a001 数据里 0/11 个场景真带命令 —— 支路通路在小盘上同样打开。
func activate(node_key: String) -> Dictionary:
	var n := graph.node(node_key)
	if n.is_empty():
		return {}
	var cmds: Array = []
	match String(n["kind"]):
		"item":
			var it := case_def.item_of(String(n["id"]))
			if it != null:
				cmds = it.commands
		"loc":
			var sc := case_def.scene_of(String(n["id"]))
			if sc != null:
				cmds = sc.commands
	if cmds.is_empty():
		return {}
	return cmd_sys.execute(node_key, cmds[0])


## 从一次成功的组合里抽出「新获得的线索」（P0：正文里出现的 [clue:] 直接记为已捕获）
func capture_clues(text: String) -> Array:
	return graph.capture_clues(text)
