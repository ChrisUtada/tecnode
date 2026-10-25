class_name CommandSystem
extends RefCounted
## 物品命令执行器：六型命令统一入口（对齐 `src/js/09-commands.js`）
##
## 规则（防漂移，见计划 §四）：
##   1) **光照门**（通用）：`requires_lit` 非空时，列出的灯至少亮一盏才执行
##   2) **conditional**：列出的线索**全部**已捕获，缺一条就只给那条的 failMessage
##   3) **useItem**：工具必须在画布上、发光工具必须已点亮、`requires` 的零件必须已装上；
##      带 `installs` 的成功时把工具记进目标节点的 `installed`
##   4) **password**：不在 execute 里判，交给弹窗；`submit_password` 才校验
##   5) **reveal**：文字 + 把 `items` 摊到节点旁边（连 entity 边）
##   6) **choice**：不是弹窗——把所有选项的结果**同时**摆上画布（连 cond 边）
##
## 返回结构（UI 只认这个）：
##   {ok, blocked, message, messages:Array, spawn:Array, reveal:Array,
##    needs_password:bool, lit_changed:bool, installed:bool}

var case_def: CaseLoader
var graph: GraphState

## 「合成消耗」开关（Web 版工具栏的 tg-consume，默认开）：
## 开了 = 用完非可复用工具就把工具节点删掉；关掉 = 工具留着，方便反复试。
var consume_tools: bool = true


func _init(p_case: CaseLoader, p_graph: GraphState) -> void:
	case_def = p_case
	graph = p_graph


func execute(node_key: String, cmd: CommandDef) -> Dictionary:
	var n := graph.node(node_key)
	if n.is_empty() or cmd == null:
		return _fail("")

	if not cmd.requires_lit.is_empty() and not _light_on(cmd.requires_lit):
		return _blocked(cmd.fail_message if cmd.fail_message != "" else "光线太暗，什么也看不清。")

	if cmd is TextCommandDef:
		return _run_text(node_key, n, cmd as TextCommandDef)
	if cmd is ChoiceCommandDef:
		return _run_choice(node_key, cmd as ChoiceCommandDef)
	if cmd is ConditionalCommandDef:
		return _run_conditional(node_key, cmd as ConditionalCommandDef)
	if cmd is UseItemCommandDef:
		return _run_use_item(node_key, n, cmd as UseItemCommandDef)
	if cmd is PasswordCommandDef:
		return {"ok": false, "needs_password": true, "message": ""}   # 交给弹窗
	if cmd is RevealCommandDef:
		return _run_reveal(node_key, n, cmd as RevealCommandDef)
	return _fail("未知命令类型")


# ── 六型 ────────────────────────────────────────────────────────────────

func _run_text(node_key: String, n: Dictionary, cmd: TextCommandDef) -> Dictionary:
	var out := _ok(cmd.value)
	if cmd.requires_lit.is_empty():
		# 纯文本也可能顺手开关灯（手电筒 / 台灯）
		var it := case_def.item_of(String(n["id"]))
		if it != null and it.toggle_light:
			n["lit"] = not bool(n.get("lit", false))
			out["lit_changed"] = true
			out["lit"] = bool(n["lit"])
			var flavor := it.lit_on_message if n["lit"] else it.lit_off_message
			out["flavor"] = flavor
	out["captured"] = graph.capture_clue_refs(cmd.clues, node_key)
	return out


func _run_choice(node_key: String, cmd: ChoiceCommandDef) -> Dictionary:
	var messages: Array = []
	var spawn: Array = []
	var captured: Array = []
	for i in cmd.options.size():
		var o: ChoiceOptionDef = cmd.options[i]
		if o.message != "":
			messages.append(o.message)
		if o.payload != null:
			if o.payload.scene != null:
				# 选项 = 场景：**只把选项节点摆上画布**（Web `spawnChoiceNodes` 走的是
				# `ensureSceneNode` + `link(cond)`，不 reveal）。内容要玩家自己双击那个抽屉才展开。
				# 旧版在这里调 `reveal_scene`，等于双击一下抽屉就把两个抽屉里的东西全倒出来，
				# 抽屉还一出生就记成「已探索」—— 手电筒也因此不劳而获。
				var sid := o.payload.scene.id
				var skey := graph.scene_key(sid)
				var exists := graph.nodes.has(skey)
				graph.add_node("loc", sid)
				if not exists:
					graph.mark_fresh(skey)
					spawn.append(skey)
				else:
					messages.append("「%s」已经在画布上了" % o.payload.scene.title)
				graph.link(node_key, skey, "cond")
			else:
				var r := _apply_payload(o.payload, node_key)
				spawn.append_array(r.get("spawn", []))
				spawn.append_array(r.get("reveal", []))
				captured.append_array(r.get("captured", []))
	return {
		"ok": true, "message": "", "messages": messages, "spawn": spawn,
		"captured": captured, "blocked": false, "needs_password": false,
	}


func _run_conditional(node_key: String, cmd: ConditionalCommandDef) -> Dictionary:
	for cond in cmd.conditions:
		if cond.clue == null:
			continue
		if not graph.captured.has(cond.clue.id):
			var why := cond.fail_message if cond.fail_message != "" else "条件不足。"
			return _blocked(why)
	var r := _apply_payload(cmd.on_success, node_key)
	var text := cmd.success_message
	if text == "":
		text = String(r.get("message", ""))
	var out := _ok(text)
	out["spawn"] = r.get("spawn", [])
	out["reveal"] = r.get("reveal", [])
	out["next_scene"] = r.get("next_scene", "")
	out["first_scene"] = r.get("first_scene", "")
	out["captured"] = _merge_captured(cmd.clues, r, node_key)
	return out


func _run_use_item(node_key: String, n: Dictionary, cmd: UseItemCommandDef) -> Dictionary:
	var need := cmd.required_item
	if need == null:
		return _fail("这条命令没有配工具")
	var have_key := graph.key_of("item", need.id)
	var have := graph.node(have_key)
	if have.is_empty():
		return _blocked(cmd.fail_message if cmd.fail_message != "" else "需要「%s」，但画布上还没有它" % need.label)
	# 判定顺序对齐 Web 版 09-commands.js：**先查零件，再查工具本身发不发光**
	for req in cmd.requires:
		if req == null:
			continue
		var installed: Dictionary = n.get("installed", {})
		if not installed.has(req.id):
			var why2 := cmd.fail_message if cmd.fail_message != "" else "还缺「%s」没装上，现在做不了这件事。" % req.label
			return _blocked(why2)
	if need.needs_lit_to_use and not bool(have.get("lit", false)):
		var why := need.lit_fail_message if need.lit_fail_message != "" else "还没有点亮，照不出任何东西。"
		return _blocked("「%s」%s" % [need.label, why])

	if cmd.installs:
		var ins: Dictionary = n.get("installed", {})
		ins[need.id] = true
		n["installed"] = ins

	var out := _ok(cmd.success_message)
	out["installed"] = cmd.installs
	var r := _apply_payload(cmd.on_success, node_key)
	out["spawn"] = r.get("spawn", [])
	out["reveal"] = r.get("reveal", [])
	out["next_scene"] = r.get("next_scene", "")
	out["first_scene"] = r.get("first_scene", "")
	out["captured"] = _merge_captured(cmd.clues, r, node_key)

	# 消耗：非可复用工具用完就没了（Web 版 tg-consume 开关，默认开）
	if consume_tools and not graph.is_reusable_tool(need.id) and have_key != node_key:
		graph.delete_node(have_key)
		out["consumed"] = [have_key]
	return out


func _run_reveal(node_key: String, n: Dictionary, cmd: RevealCommandDef) -> Dictionary:
	var text: String = cmd.value          # RevealCommandDef 只有 value（数据侧同款）
	var out := _ok(text)
	var spawn: Array = []
	for it in cmd.items:
		if it == null:
			continue
		var key: String = String(graph.add_node("item", it.id)["key"])
		graph.link(node_key, key, "entity")
		spawn.append(key)
	out["spawn"] = spawn
	out["captured"] = graph.capture_clue_refs(cmd.clues, node_key)
	return out


## 密码命令：输对了才执行（错的只回一句话，不推进任何状态）
func submit_password(node_key: String, cmd: PasswordCommandDef, input: String) -> Dictionary:
	var v := input.strip_edges()
	if v != cmd.value:
		return {"ok": false, "blocked": true, "wrong_password": true,
			"message": "「%s」密码 %s 不正确" % [graph.node(node_key).get("label", ""), ("(空)" if v == "" else v)]}
	var out := _ok("打开了。")
	var r := _apply_payload(cmd.on_success, node_key)
	out["spawn"] = r.get("spawn", [])
	out["reveal"] = r.get("reveal", [])
	out["next_scene"] = r.get("next_scene", "")
	out["first_scene"] = r.get("first_scene", "")
	out["captured"] = r.get("captured", [])
	out["message"] = String(r.get("message", ""))
	return out


# ── 公共部件 ────────────────────────────────────────────────────────────

## 「有没有光」：列表为空 = 任意一盏亮着即可（对应 Web 的 LIGHT_SOURCES）
func _light_on(lamps: Array[ItemDef]) -> bool:
	if lamps.is_empty():
		for key in graph.nodes.keys():
			var n: Dictionary = graph.nodes[key]
			if n["kind"] == "item" and bool(n.get("lit", false)):
				return true
		return false
	for lamp in lamps:
		if lamp == null:
			continue
		var n := graph.node(graph.key_of("item", lamp.id))
		if not n.is_empty() and bool(n.get("lit", false)):
			return true
	return false


func _apply_payload(payload: PayloadDef, node_key: String) -> Dictionary:
	var out := {"message": "", "spawn": [], "reveal": [], "next_scene": "", "first_scene": ""}
	if payload == null:
		return out
	out["message"] = payload.message
	out["captured"] = graph.capture_clue_refs(payload.clues, node_key)
	for it in payload.items:
		if it == null:
			continue
		var key: String = String(graph.add_node("item", it.id)["key"])
		graph.link(node_key, key, "entity")
		(out["spawn"] as Array).append(key)
	if payload.scene != null:
		var was_explored := graph.explored.has(payload.scene.id)
		var fresh := graph.reveal_scene(payload.scene.id)
		(out["reveal"] as Array).append_array(fresh)
		out["next_scene"] = payload.scene.id
		if not was_explored:
			out["first_scene"] = payload.scene.id
	return out


func _merge_captured(cmd_clues: Array, payload_result: Dictionary, node_key: String) -> Array:
	var got := graph.capture_clue_refs(cmd_clues, node_key)
	got.append_array(payload_result.get("captured", []))
	return got


func _ok(message: String) -> Dictionary:
	return {"ok": true, "blocked": false, "needs_password": false, "message": message,
		"messages": [], "spawn": [], "reveal": [], "captured": []}


func _blocked(message: String) -> Dictionary:
	return {"ok": false, "blocked": true, "needs_password": false, "message": message,
		"messages": [], "spawn": [], "reveal": [], "captured": []}


func _fail(message: String) -> Dictionary:
	return {"ok": false, "blocked": false, "needs_password": false, "message": message,
		"messages": [], "spawn": [], "reveal": [], "captured": []}
