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


## 把一个节点拖到另一个节点上。返回：
##   {ok, blocked, message, reveal:Array, next_scene:String}
## blocked = 被规则拦下（不执行、不记 tried）
func use_item(tool_key: String, target_key: String) -> Dictionary:
	var tool := graph.node(tool_key)
	var target := graph.node(target_key)
	if tool.is_empty() or target.is_empty() or tool_key == target_key:
		return {"ok": false, "message": ""}

	var target_it := case_def.item_of(String(target["id"]))
	if target_it != null:
		for cmd in target_it.commands:
			if not (cmd is UseItemCommandDef):
				continue
			var uc := cmd as UseItemCommandDef
			if uc.required_item == null or uc.required_item.id != String(tool["id"]):
				continue
			# 发光门 / 零件门 / 装零件 / onSuccess，全在 CommandSystem 里一处实现
			var res := cmd_sys.execute(target_key, uc)
			res["matched"] = true
			return res
	return {
		"ok": false,
		"message": "「%s」与「%s」之间没有发生任何事。" % [tool["label"], target["label"]],
	}


## 双击节点的默认命令（第一条）。没有命令就返回空，由调用方决定「展开」还是别的。
func activate(node_key: String) -> Dictionary:
	var n := graph.node(node_key)
	if n.is_empty() or n["kind"] != "item":
		return {}
	var it := case_def.item_of(String(n["id"]))
	if it == null or it.commands.is_empty():
		return {}
	return cmd_sys.execute(node_key, it.commands[0])


## 从一次成功的组合里抽出「新获得的线索」（P0：正文里出现的 [clue:] 直接记为已捕获）
func capture_clues(text: String) -> Array:
	var got: Array = []
	for tag in case_def.tags_of(text):
		if tag["kind"] != "clue":
			continue
		if graph.captured.has(tag["id"]):
			continue
		graph.captured[tag["id"]] = true
		var n := graph.add_node("clue", tag["id"])
		got.append(n["key"])
	return got
