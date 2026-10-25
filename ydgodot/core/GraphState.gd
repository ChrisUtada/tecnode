class_name GraphState
extends RefCounted
## 画布图状态（纯逻辑，不依赖场景树 —— 无头测试可直接 new）
##
## 与 Web 版 `02-state.js` 的最小同构子集：节点表 / 边表 / 已探索 / 已捕获 / 点亮 / 分析进度。
## P0 只保留切片需要的字段；P1 补齐快照、撤销栈、收纳、时间档等。

## P2：卡片尺寸收进 8px 网格。场景 160×56、实体 128×48 ——
## 视觉框（NodeCard 的 position + 8px PAD）落在网格上时，卡片本身也正好对齐。
const SCENE_W := 160.0
const SCENE_H := 56.0
const ENT_W := 128.0
const ENT_H := 48.0

const PRESENT_TIME := "present"
const MEM_CAST_DX := 60.0
const MEM_CAST_DY := 150.0
const MEM_CAST_STEP := 96.0

var case_def: CaseLoader
var nodes: Dictionary = {}        # key -> {key, kind, id, label, x, y, lit, home_scene, pinned, bag_from}
var edges: Array = []             # {a: key, b: key, rel: "entity"|"move"|"cond"}
var explored: Dictionary = {}     # 容器 id -> true（场景与容器物品共用）
var captured: Dictionary = {}     # clue id -> true
var tec_prog: Dictionary = {}     # scene id -> 已分析条数
var collapsed: Dictionary = {}    # 容器 id -> true（展开过又收起）
var stored: Dictionary = {}       # node key -> 收纳去向（"BAG" / "LEDGER" / "MATRIX" / 场景 id）
var hidden: Dictionary = {}       # node key -> true（被更高层级的动作隐藏）
var matrix: Dictionary = {}       # 五感槽位：sense -> Array[clue id]（推演桌布）
var endings: Dictionary = {}      # 已达成结局 id -> true
var tried: Dictionary = {}        # "tool>target" -> true（失败组合的痕迹，Web 的 tried）
var talk_prog: Dictionary = {}    # 人物 id -> 对话进度（P2 对话系统用，快照先接住）
var card_seen: Dictionary = {}    # 时刻 -> true（玩家知识：读过就不再自动重放）
var debuted: Dictionary = {}      # 人物 id -> true（登场置位）
var time: String = PRESENT_TIME    # 当前时刻；初始是「现在」
var garden: Dictionary = {"seed": false, "plots": []}   # 真名结局后的花园
var selected: String = ""
var last_scene: String = ""
## 因果追踪（SYS_LOGS）的条目：{text, kind}，kind ∈ "" / "sys" / "warn" / "err" / "cap" / "act"。
## **不进快照**、不随撤销回滚 —— 对齐 Web：日志是 DOM 节点，重来 / 换案才清（17-boot.js:20）。
var logs: Array = []
## F6：日志历史上限。超出后从最旧开始丢，避免长局把 ScrollContainer 撑成无限 DOM。
const LOG_MAX := 200
## 人物档案卡备注：id -> 文本（玩家知识，按案件存档；撤销不回滚，读档按存档恢复）。
var notes: Dictionary = {}
## 证据主张（待核对）：person_id -> field_id -> {value, evidence_id}。进快照，撤销会回滚。
var claims: Dictionary = {}
## 已核准字段：person_id -> field_id -> {value, evidence_id}。
## 玩家知识：撤销不回滚，读档按存档恢复。
var confirmed_fields: Dictionary = {}

## 名册常驻成员（Web `ROSTER_PINNED`）：一进游戏就在册，不靠「已结识」判定；
## 两者都没有画布节点，点一行 = 打开人物档案卡。
const ROSTER_PINNED := ["CHARS_TEC", "CHARS_EXEC"]
## 调查员（玩家自己）不是 CharDef，名册与档案卡共用这个 id 作 notes key。
const INVESTIGATOR_ID := "INVESTIGATOR"
const ROSTER_PINNED_TAG := {"CHARS_TEC": "助手窗", "CHARS_EXEC": "推演器"}
const ROSTER_PINNED_NAME := {"CHARS_EXEC": "执行者"}
const ROSTER_PINNED_DESC := {"CHARS_EXEC": "推演桌布中央的执行者，长按 2.5 秒执行推演。"}

## 三个收纳落点（与 Web 版 06-storage.js / 12-panels.js / 13-matrix.js 同名）
const BAG := "BAG"                # 证物袋：什么都收
const LEDGER := "LEDGER"          # 线索册：只有线索能进
const MATRIX := "MATRIX"          # 推演桌布：归位的线索

## 五感顺序与显示名（Web 版 SENSES 的键序 —— 排序、遍历都按它来）
const SENSES := ["vision", "hearing", "touch", "smell", "taste"]
const SENSE_NAMES := {
	"vision": "视觉", "hearing": "听觉", "touch": "触觉",
	"smell": "嗅觉", "taste": "味觉",
}


func _init(p_case: CaseLoader) -> void:
	case_def = p_case
	_blank_matrix()


func _blank_matrix() -> void:
	matrix = {}
	for sense in SENSES:
		matrix[sense] = []


## 数据侧的 [loc:SCENES_0602] 与画布侧的 time:SCENES_0602 必须收敛到同一个键。
## 这是 GraphState 的「nodeKeyOfRef」边界：凡是从引用推节点键的地方都走这里。
func normalize_kind(kind: String, id: String) -> String:
	if kind == "scene":
		kind = "loc"
	if kind == "clue" or kind == "data":
		kind = "evidence"
	if kind == "loc" and case_def != null and case_def.is_time_id(id):
		return "time"
	return kind


static func is_scene_kind(kind: String) -> bool:
	return kind == "loc" or kind == "time" or kind == "scene"


func key_of(kind: String, id: String) -> String:
	return "%s:%s" % [normalize_kind(kind, id), id]


func scene_key(id: String) -> String:
	return key_of("loc", id)


func has(kind: String, id: String) -> bool:
	return nodes.has(key_of(kind, id))


func node(key: String) -> Dictionary:
	return nodes.get(key, {})


func add_node(kind: String, id: String) -> Dictionary:
	kind = normalize_kind(kind, id)
	var key := key_of(kind, id)
	if nodes.has(key):
		return nodes[key]
	var n := {
		"key": key,
		"kind": kind,
		"id": id,
		"label": case_def.label_of(kind, id),
		# -1 = **还没落过位**。布局只给「未落位」的节点播种，已落位的一律保留
		# （Web 用 `x == null` 判同一件事；Godot 的 Dictionary 没法存 null 语义的 float）
		"x": -1.0,
		"y": -1.0,
		"lit": false,
		"home_scene": "",
		"pinned": false,     # 钉住：折叠容器时不跟着藏（Web 版右键钉住）
		"bag_from": "",      # 进袋前的来源容器 id（袋清单标注「来自 ×××」）
		"installed": {},      # 装在本节点上的零件（item id -> true）
		"captured": kind == "evidence" and captured.has(id),
		"fresh": false,       # 本次新出现（档案 / 卡片的「新」角标）
		"unread": false,      # 玩家还没点过它
	}
	if kind == "evidence":
		var ev := case_def.evidence_of(id) if case_def != null else null
		n["tier"] = ev.tier if ev != null else "zheng"
		n["sense"] = ev.sense if ev != null else "vision"
		n["origin"] = ev.origin if ev != null else "tec"
		n["captured"] = String(n["tier"]) == "zheng" and captured.has(id)
		## 证据是玩家已经拿到的知识，不随时刻 / 折叠容器消失。
		n["always_visible"] = true
	nodes[key] = n
	return n


func link(a: String, b: String, rel: String) -> void:
	if a == b:
		return
	for e in edges:
		if e["rel"] == rel and ((e["a"] == a and e["b"] == b) or (e["a"] == b and e["b"] == a)):
			return
	edges.append({"a": a, "b": b, "rel": rel})


func has_edge(a: String, b: String, rel: String = "") -> bool:
	for e in edges:
		if rel != "" and e["rel"] != rel:
			continue
		if (e["a"] == a and e["b"] == b) or (e["a"] == b and e["b"] == a):
			return true
	return false


## 删节点（连同它的边）—— 对齐 Web 的 deleteNode
func delete_node(key: String) -> bool:
	if not nodes.has(key):
		return false
	nodes.erase(key)
	hidden.erase(key)
	stored.erase(key)
	var kept: Array = []
	for e in edges:
		if e["a"] != key and e["b"] != key:
			kept.append(e)
	edges = kept
	## 删掉节点后，「试过」虚线键也要一起清；否则节点日后再出现会带着旧虚线还魂。
	for raw in tried.keys():
		var pair := String(raw).split(">", false, 1)
		if pair.size() == 2 and (pair[0] == key or pair[1] == key):
			tried.erase(raw)
	return true


## 工具是不是「可复用」（config.reusableTools）—— 可复用的工具用完不消失
func is_reusable_tool(id: String) -> bool:
	if case_def == null or case_def.case_def == null:
		return false
	for it in case_def.case_def.reusable_tools:
		if it != null and it.id == id:
			return true
	return false


func neighbors(key: String) -> Array:
	var out: Array = []
	for e in edges:
		if e["a"] == key:
			out.append(e["b"])
		elif e["b"] == key:
			out.append(e["a"])
	return out


## 展开一个场景：建容器节点 + 正文里点名的实体（item / char / clue / 互通的 loc）。
## 幂等；返回本次新建的 key 列表。
## 展开一个场景：建容器节点 + 把**资源里那四栏节点**摆上桌面。
## 幂等；返回本次新建的 key 列表。
##
## ⚠ 节点清单**只读** `SceneDef.node_items / node_chars / node_locs / node_clues`，
## 绝不解析 `content`。正文随便改、标签删干净，画布上该有的东西一个不少；
## 要让某个东西出现在场景里，就去 Godot 检查器里加进那四栏。
func reveal_scene(sid: String) -> Array:
	var s := case_def.scene_of(sid)
	if s == null:
		return []
	var fresh: Array = []
	var sn := add_node("loc", sid)
	if not explored.has(sid):
		fresh.append(sn["key"])
		mark_fresh(String(sn["key"]))
	explored[sid] = true
	last_scene = sid

	for tag in case_def.nodes_of_scene(s):
		var kind: String = tag["kind"]
		var id: String = tag["id"]
		var existed := has(kind, id)
		var n := add_node(kind, id)
		## 场景 / 时间点通过 `node_locs` 连过来是「通路」，不是「被场景装下」。
		## 若把目的地场景的 home_scene 写成当前场景，会和反向通路组成环，
		## 两边都折叠时会互相隐藏，最后整张画布清空。
		if not is_scene_kind(kind) and String(n.get("home_scene", "")) == "":
			n["home_scene"] = sid
		if not existed:
			fresh.append(n["key"])
			mark_fresh(String(n["key"]))
		if kind == "char":
			meet_char_at(id, sid)         # 这个场景正是 debut 点的，此刻置位
		link(sn["key"], n["key"], "move" if is_scene_kind(String(n["kind"])) else "entity")
	return fresh


# ── 容器（场景 / 书桌这类能倒出东西的物品）──────────────────────────────

## 是不是「容器」：场景，或**节点清单非空**的物品（书桌 / 抽屉 / 垃圾桶）。
## 早先按「content 里有没有标签」判，结果正文一改写，书桌就不是容器了 ——
## 现在只看显式清单。
func is_container(kind: String, id: String) -> bool:
	var k := normalize_kind(kind, id)
	if k == "loc" or k == "time":
		return case_def.scene_of(id) != null
	if k != "item":
		return false
	var it := case_def.item_of(id)
	return it != null and case_def.nodes_of_item(it).size() > 0


func container_content(kind: String, id: String) -> String:
	var k := normalize_kind(kind, id)
	if k == "loc" or k == "time":
		var s := case_def.scene_of(id)
		return s.content if s != null else ""
	var it := case_def.item_of(id)
	return it.content if it != null else ""


## 展开任意容器（场景或容器物品）：长出它 content 里点名的实体，连 entity 边。
## 与 reveal_scene 的唯一区别：容器本身不一定是 loc。幂等，返回新 key 列表。
func reveal_container(kind: String, id: String) -> Array:
	if not is_container(kind, id):
		return []
	var fresh: Array = []
	var host_key := key_of(kind, id)
	var host := add_node(kind, id)
	if not explored.has(id):
		fresh.append(host["key"])
		mark_fresh(String(host["key"]))
	explored[id] = true
	collapsed.erase(id)

	for tag in case_def.container_nodes(kind, id):
		var k: String = tag["kind"]
		var cid: String = tag["id"]
		var existed := has(k, cid)
		var n := add_node(k, cid)
		## 同 reveal_scene：`node_locs` 是通路，不是归属。书桌的 node_locs 里
		## 回指花园，不能把花园的 home_scene 改成书桌，否则折叠会成环。
		if not is_scene_kind(k) and String(n.get("home_scene", "")) == "":
			n["home_scene"] = id
		if not existed:
			fresh.append(n["key"])
			mark_fresh(String(n["key"]))
		if k == "char":
			meet_char_at(cid, id)
		link(host_key, n["key"], "move" if is_scene_kind(String(n["kind"])) else "entity")
	return fresh


## 折叠：把容器自己标记为「已收起」（画面上保留节点，内容不再展开）
func collapse(id: String) -> void:
	collapsed[id] = true
	recompute_hidden()


func uncollapse(id: String) -> void:
	collapsed.erase(id)
	recompute_hidden()


func is_collapsed(id: String) -> bool:
	return collapsed.has(id)


# ── 收纳 / 隐藏 ────────────────────────────────────────────────────────

func store(key: String, where: String) -> void:
	stored[key] = where


func take(key: String) -> String:
	var where := String(stored.get(key, ""))
	if where == MATRIX:
		_remove_from_matrix(String(node(key).get("id", "")))
	stored.erase(key)
	hidden.erase(key)
	return where


func set_hidden(key: String, on: bool) -> void:
	if on:
		hidden[key] = true
	else:
		hidden.erase(key)


func is_visible(key: String) -> bool:
	return not hidden.has(key) and not stored.has(key) and nodes.has(key)


func mark_fresh(key: String) -> void:
	var n := node(key)
	if n.is_empty():
		return
	n["fresh"] = true
	n["unread"] = true


## 玩家点过这个节点 ⇒ 摘掉「新」角标（Web 的 clearFresh）
func clear_fresh(key: String) -> void:
	var n := node(key)
	if n.is_empty():
		return
	n["fresh"] = false
	n["unread"] = false


## 入场动画的一次性消费：只摘 fresh（pop 的来源），unread 还在
##（「新」角标要等玩家点过节点才摘，与 Web 的 n.unread / n.fresh 双轨一致）
func consume_fresh(key: String) -> void:
	var n := node(key)
	if n.is_empty():
		return
	n["fresh"] = false


func has_unread(key: String) -> bool:
	return bool(node(key).get("unread", false))


# ── 时间轴 / 时刻图层 / 登场门控（对齐 Web 03-utils.js）─────────────────

## 某时刻的节点集由回忆数据派生：该 when 下所有 where 地点 + who 人物。
## present 返回 null = 全显，不做时间过滤。
func time_stage_keys(t: String):
	if t == PRESENT_TIME:
		return null
	var keys: Array = []
	for m in case_def.memories_for(t):
		if m.where != null and not keys.has(scene_key(m.where.id)):
			keys.append(scene_key(m.where.id))
		if m.who != null and not keys.has(key_of("char", m.who.id)):
			keys.append(key_of("char", m.who.id))
	return keys


## 时间轴各档：present 在首位，其余按 config.memoryScenes 顺序。
func timeline_stages() -> Array:
	var out: Array = [
		{"id": PRESENT_TIME, "label": case_def.now_label(), "keys": null},
	]
	for sid in case_def.memory_scene_ids():
		out.append({
			"id": sid,
			"label": case_def.scene_title(String(sid)),
			"keys": time_stage_keys(String(sid)),
		})
	return out


func current_stage() -> Dictionary:
	var stages := timeline_stages()
	for s in stages:
		if String(s["id"]) == time:
			return s
	return stages[0]


## 已经获得的时刻：画布上已有该时刻节点，或已探索过它。
func timeline_known() -> Array:
	var out: Array = []
	for sid in case_def.memory_scene_ids():
		var id := String(sid)
		if nodes.has(scene_key(id)) or explored.has(id):
			out.append(id)
	return out


func time_label_of(t: String = "") -> String:
	return case_def.time_label_of(t if t != "" else time)


func mem_place_of(t: String) -> SceneDef:
	return case_def.mem_place_of(t)


## 时间可见性：当前时刻的节点集里没有它 ⇒ 不可见；present 档全通过。
func visible_now(n: Dictionary) -> bool:
	if n.is_empty():
		return false
	var st := current_stage()
	var keys = st.get("keys", null)
	return keys == null or (keys as Array).has(String(n["key"]))


func char_debut(id: String) -> String:
	var c := case_def.char_of(id)
	return c.debut.id if c != null and c.debut != null else ""


func char_debuted(id: String) -> bool:
	if char_debut(id) == "":
		return true
	return debuted.has(id)


## 到达 debut（幂等）：展开场景 / 进入回忆时刻时调用。
func meet_char_at(id: String, sid: String) -> void:
	if char_debut(id) != sid:
		return
	debuted[id] = true


## 人物对话队列（对齐 Web `charTalkQueue`）：基础 talkQueue + 他 **当前所在场景** 的 sceneTalks。
## 队列里的空行会被剔掉 —— 与 Web 的 `filter(Boolean)` 同口径。
func char_talk_queue(id: String) -> Array:
	var out: Array = []
	var c := case_def.char_of(id)
	if c == null:
		return out
	for line in c.talk_queue:
		if String(line) != "":
			out.append(String(line))
	var home := ""
	var n := node(key_of("char", id))
	if not n.is_empty():
		home = String(n.get("home_scene", ""))
	if home == "":
		return out
	for st in c.scene_talks:
		if st == null or st.scene == null or st.scene.id != home:
			continue
		for line in st.lines:
			if String(line) != "":
				out.append(String(line))
	return out


## 名册进度：{prog, total}。有节点按真实结算，没有节点时 prog = 0。
## talk_prog 的键是**节点 key**（`char:ID`），不是裸 id —— 取错就会永远读到 0。
func char_progress(id: String) -> Dictionary:
	var key := key_of("char", id)
	var prog := int(talk_prog.get(key, 0)) if nodes.has(key) else 0
	return {"prog": prog, "total": char_talk_queue(id).size()}


## 名册收录（对齐 Web `metChars`）：常驻成员在前 + 已结识的角色。
## 「已结识」= 画布上有已登场的人物节点 ∪ 到过某个时刻（放过放映卡）∪ 探索过 sceneTalks 覆盖的场景。
## **纸面提及不算** —— 只读过名字不进名册（节点也还没登场）。
func met_char_ids() -> Array:
	var out: Array = []
	for id in ROSTER_PINNED:
		out.append(id)
	var met: Dictionary = {}
	for key in nodes.keys():
		var k := String(key)
		if not k.begins_with("char:"):
			continue
		var cid := k.substr(5)
		if char_debuted(cid):
			met[cid] = true
	# 「到过」的场景集合 = 读过放映卡的时刻 ∪ 已探索的场景
	var reached: Dictionary = card_seen.duplicate()
	for sid in explored.keys():
		if bool(explored[sid]):
			reached[String(sid)] = true
	for cid in case_def.chars.keys():
		var c := case_def.char_of(String(cid))
		if c == null or String(cid) == "CHARS_TEC":
			continue
		if met.has(String(cid)):
			continue
		for st in c.scene_talks:
			if st == null or st.scene == null:
				continue
			if reached.has(st.scene.id):
				met[String(cid)] = true
				break
	var rest: Array = []
	for cid in met.keys():
		rest.append(String(cid))
	rest.sort()
	out.append_array(rest)
	return out


## 人物在「现在」档的登场点：sceneTalks 里第一个非回忆场景；没有 = 现在档不登场。
func char_now_scene(id: String) -> String:
	var c := case_def.char_of(id)
	if c == null:
		return ""
	for st in c.scene_talks:
		if st == null or st.scene == null:
			continue
		if not case_def.is_time_id(st.scene.id):
			return st.scene.id
	return ""


func char_now_met(id: String) -> bool:
	if id == "CHARS_TEC":
		return true
	var sid := char_now_scene(id)
	return sid != "" and explored.has(sid)


## 综合可见（时间 × 空间 × 登场）：渲染 / 交互 / 聚焦一律认这一个。
func visible_node(n: Dictionary) -> bool:
	if n.is_empty() or hidden.has(String(n["key"])) or stored.has(String(n["key"])):
		return false
	## 没有场景上下文的常驻节点（例如教学期由 TEC 直接调出的「调查员」人物）：
	## 显式豁免「必须在已探索场景里」的判定，避免拖拽收尾 / 收纳重算把它藏掉。
	if bool(n.get("always_visible", false)):
		return true
	if String(n["kind"]) == "char":
		var id := String(n["id"])
		if not char_debuted(id):
			return false
		if not visible_now(n):
			return false
		var keys = current_stage().get("keys", null)
		if keys == null and not char_now_met(id):
			return false
		return true
	return visible_now(n)


## 进入回忆时刻：把那一刻 `node_chars` 里列着、且 debut 正是这一刻的人物带出画布。
## 已存在的节点不动（不重复提示、不挪坐标）；返回新增数量。
func spawn_mem_cast(t: String) -> int:
	var s := case_def.scene_of(t)
	if s == null or not case_def.is_time_id(t):
		return 0
	var place := case_def.mem_place_of(t)
	var pn: Dictionary = nodes.get(scene_key(place.id), {}) if place != null else {}
	var hx := float(pn.get("x", 0.0)) if not pn.is_empty() else -1.0
	var hy := float(pn.get("y", 0.0)) if not pn.is_empty() else -1.0
	var added := 0
	var i := 0
	for tag in case_def.nodes_of_scene(s):
		var tag_i := i
		i += 1
		if String(tag["kind"]) != "char":
			continue
		var cid := String(tag["id"])
		if char_debut(cid) != t:
			continue                      # 登场点不在这一刻：文本提及 ≠ 遇到
		var existed := has("char", cid)
		var n := add_node("char", cid)
		if String(n.get("home_scene", "")) == "":
			n["home_scene"] = t
		meet_char_at(cid, t)
		if not existed:
			added += 1
			if hx >= 0.0:
				n["x"] = hx + MEM_CAST_DX + float(tag_i % 3) * MEM_CAST_STEP
				n["y"] = hy + MEM_CAST_DY + float(int(tag_i / 3)) * MEM_CAST_STEP
			mark_fresh(String(n["key"]))
			if not pn.is_empty():
				link(String(pn["key"]), String(n["key"]), "entity")
	return added


## 节点是不是「容器」—— 容器（场景 / 书桌 / 抽屉 / 垃圾桶）是不可收纳的落脚点
## （对齐 Web 的 isContainerNode：容器进不了袋，也进不了册）
func is_container_node(key: String) -> bool:
	var n := node(key)
	if n.is_empty():
		return false
	return is_container(String(n["kind"]), String(n["id"]))


## 证物袋准入：物品必须显式允许（ItemDef.baggable）。
## 容器是否可收也走同一属性，不再靠「有没有子节点」隐式决定。
func can_bag(key: String) -> bool:
	var n := node(key)
	if n.is_empty() or stored.has(key):
		return false
	var kind := String(n.get("kind", ""))
	if kind == "evidence":
		## 袋 = 物与言；证是知识，进证据册，不进证物袋。
		return String(n.get("tier", "")) == "ci"
	if kind != "item":
		return false
	var it := case_def.item_of(String(n.get("id", "")))
	return it != null and it.baggable


## 收进证物袋：记下来源，供袋清单标注「来自 ×××」。
func bag_store(key: String) -> bool:
	if not can_bag(key):
		return false
	var n := node(key)
	n["bag_from"] = String(n.get("home_scene", ""))
	n["pinned"] = false
	stored[key] = BAG
	recompute_hidden()
	return true


## 收进证据册：只有「证」能进（词进证物袋，物不进册）。
func ledger_store(key: String) -> bool:
	var n := node(key)
	if n.is_empty() or stored.has(key):
		return false
	if String(n["kind"]) != "evidence" or String(n.get("tier", "")) != "zheng":
		return false
	n["pinned"] = false
	stored[key] = LEDGER
	recompute_hidden()
	return true


## 取回画布：从任一收纳处取回。落点可选（拖出来时给落点）。
func take_back(key: String, x: float = -1.0, y: float = -1.0) -> bool:
	if not stored.has(key):
		return false
	var n := node(key)
	if String(stored[key]) == MATRIX:
		_remove_from_matrix(String(n.get("id", "")))
	stored.erase(key)
	hidden.erase(key)
	n["pinned"] = false
	if x >= 0.0 and y >= 0.0:
		n["x"] = x
		n["y"] = y
	recompute_hidden()
	return true


## 两扇收纳窗之间搬运（证物袋 ↔ 线索册）：只改去向，不重排
func restash(key: String, from: String, to: String) -> bool:
	if not stored.has(key) or String(stored[key]) != from or from == to:
		return false
	if to != BAG and to != LEDGER:
		return false
	var n := node(key)
	## 袋收物与词，册收证：两边不互通。
	var kind := String(n.get("kind", ""))
	var tier := String(n.get("tier", ""))
	if to == BAG and not (kind == "item" or (kind == "evidence" and tier == "ci")):
		return false
	if to == LEDGER and not (kind == "evidence" and tier == "zheng"):
		return false
	if from == MATRIX:
		_remove_from_matrix(String(n.get("id", "")))
	n["pinned"] = false
	if to == BAG:
		n["bag_from"] = String(n.get("home_scene", ""))
	else:
		n["bag_from"] = ""
	stored[key] = to
	return true


# ── 推演桌布（五感槽位）────────────────────────────────────────────────

## 归位到推演桌布（线索 → 某感官槽位）。`sense` 省略时按线索自身的感官归位。
## 与 Web 的 assignClue 同口径：不管线索现在在画布 / 袋 / 册，都能直接改写去向；
## 同一槽位重复归位返回 false；感官不符也返回 false。
## 归位到推演桌布（证 → 某感官槽位）。词 / 物没有五感，不收。
func matrix_assign(key: String, sense: String = "") -> bool:
	var n := node(key)
	if n.is_empty() or String(n["kind"]) != "evidence" or String(n.get("tier", "")) != "zheng":
		return false
	var ev := case_def.evidence_of(String(n["id"]))
	if ev == null:
		return false
	if sense == "":
		sense = ev.sense
	if not matrix.has(sense) or ev.sense != sense:
		return false
	var list: Array = matrix[sense]
	if list.has(ev.id):
		return false
	_remove_from_matrix(ev.id)
	list.append(ev.id)
	stored[key] = MATRIX
	hidden.erase(key)
	n["pinned"] = false
	return true


## 从推演桌布取回画布（桌布 → 线索册是 restash，那条走上面）
func matrix_take(key: String, x: float = -1.0, y: float = -1.0) -> bool:
	if String(stored.get(key, "")) != MATRIX:
		return false
	return take_back(key, x, y)


## 桌布上的线索 id（按五感顺序摊平）
func matrix_ids() -> Array:
	var out: Array = []
	for sense in SENSES:
		out.append_array(matrix.get(sense, []))
	return out


## 桌布上的节点 key（对齐 Web 的 matrixItems）
func matrix_items() -> Array:
	var out: Array = []
	for key in stored.keys():
		if String(stored[key]) == MATRIX:
			out.append(key)
	return out


func matrix_count() -> int:
	return matrix_ids().size()


## 清空桌布上的线索（教学推演完成后用；线索仍保留在 stored=MATRIX，不会重新上桌）。
func clear_matrix() -> void:
	for sense in SENSES:
		matrix[sense] = []


func matrix_has(id: String) -> bool:
	return matrix_ids().has(id)


func matrix_slot_of(id: String) -> String:
	for sense in SENSES:
		if (matrix.get(sense, []) as Array).has(id):
			return sense
	return ""


func _remove_from_matrix(id: String) -> void:
	for sense in SENSES:
		(matrix[sense] as Array).erase(id)


## 推演判定：当前槽位里的线索**恰好**等于某条结局的配方（Web 版 executeInference 同口径）。
## 数据顺序优先（ENDINGS.find 的等价实现），返回第一个命中的 EndingDef，否则 null。
func match_ending() -> EndingDef:
	var ids := {}
	for sense in SENSES:
		for id in matrix[sense]:
			ids[String(id)] = true
	for ending in case_def.endings:
		if ending == null or ending.recipe.size() != ids.size():
			continue
		var all := true
		for clue in ending.recipe:
			if clue == null or not ids.has(clue.id):
				all = false
				break
		if all:
			return ending
	return null


## 记录结局达成（供 P1.5 快照 / 结局图鉴使用）
func mark_ending(id: String) -> void:
	endings[id] = true


## 只从显式结构化证据引用落地，不再解析正文标签。
func capture_evidence_refs(refs: Array, from_key: String = "", origin: String = "synth") -> Array:
	var got: Array = []
	for ref in refs:
		var eid := String((ref as EvidenceDef).id) if ref is EvidenceDef else String(ref)
		if eid == "":
			continue
		if captured.has(eid) and nodes.has(key_of("evidence", eid)):
			continue
		got.append(capture_evidence(eid, from_key, -1.0, -1.0, origin))
	return got


## 兼容旧调用名：旧“线索”现在就是证。
func capture_clue_refs(refs: Array, from_key: String = "") -> Array:
	return capture_evidence_refs(refs, from_key, "tec")


func capture_clue(cid: String, from_key: String = "") -> String:
	return capture_evidence(cid, from_key, -1.0, -1.0, "tec")


## 证据落地（TEC / 对话 / 回忆 / 配方共用）：已存在则返回同一个 key，不重复掉落。
## `origin` 记来源（tec/synth/deduce）；`词`不设 captured，`证`落地即已捕获。
func capture_evidence(eid: String, from_key: String = "", x: float = -1.0, y: float = -1.0,
		origin: String = "synth") -> String:
	var existing := key_of("evidence", eid)
	if nodes.has(existing):
		var old := nodes[existing] as Dictionary
		if String(old.get("tier", "")) == "zheng":
			captured[eid] = true
			old["captured"] = true
		return existing
	var n := add_node("evidence", eid)
	n["origin"] = origin
	if String(n.get("tier", "")) == "zheng":
		captured[eid] = true
		n["captured"] = true
	if from_key != "":
		link(from_key, String(n["key"]), "entity")
		var src := node(from_key)
		if String(n.get("home_scene", "")) == "":
			n["home_scene"] = String(src.get("home_scene", ""))
	if x >= 0.0 and y >= 0.0:
		n["x"] = x
		n["y"] = y
	mark_fresh(String(n["key"]))
	return String(n["key"])


# ── 档案字段：主张 / 核准 ───────────────────────────────────────────────

func claim_of(person_id: String, field_id: String) -> Dictionary:
	var row = claims.get(person_id, null)
	if row is Dictionary:
		return (row as Dictionary).get(field_id, {})
	return {}


func set_claim(person_id: String, field_id: String, value: String = "", evidence_id: String = "") -> void:
	if not claims.has(person_id):
		claims[person_id] = {}
	var row: Dictionary = claims[person_id]
	var old: Dictionary = row.get(field_id, {})
	row[field_id] = {
		"value": value if value != "" else String(old.get("value", "")),
		"evidence_id": evidence_id if evidence_id != "" else String(old.get("evidence_id", "")),
	}


func clear_claim(person_id: String, field_id: String) -> void:
	if not claims.has(person_id):
		return
	(claims[person_id] as Dictionary).erase(field_id)
	if (claims[person_id] as Dictionary).is_empty():
		claims.erase(person_id)


func pending_claims(person_id: String) -> Dictionary:
	var out := {}
	var row = claims.get(person_id, null)
	if row is Dictionary:
		for fid in (row as Dictionary).keys():
			var claim = (row as Dictionary)[fid]
			if claim is Dictionary and String((claim as Dictionary).get("evidence_id", "")) != "":
				out[String(fid)] = (claim as Dictionary).duplicate(true)
	return out


func pending_claim_count(person_id: String) -> int:
	return pending_claims(person_id).size()


func confirmed_field_of(person_id: String, field_id: String) -> Dictionary:
	var row = confirmed_fields.get(person_id, null)
	if row is Dictionary:
		return (row as Dictionary).get(field_id, {})
	return {}


func is_field_confirmed(person_id: String, field_id: String) -> bool:
	return not confirmed_field_of(person_id, field_id).is_empty()


func confirm_field(person_id: String, field_id: String, value: String, evidence_id: String) -> void:
	if not confirmed_fields.has(person_id):
		confirmed_fields[person_id] = {}
	(confirmed_fields[person_id] as Dictionary)[field_id] = {
		"value": value, "evidence_id": evidence_id,
	}
	clear_claim(person_id, field_id)


func all_fields_confirmed(person_id: String) -> bool:
	var ch := case_def.char_of(person_id) if case_def != null else null
	if ch == null or ch.evidence_fields.is_empty():
		return false
	for f in ch.evidence_fields:
		if f == null or not is_field_confirmed(person_id, f.id):
			return false
	return true


## 折叠后的隐藏重算（对齐 Web 的 recomputeHidden）：
##   折叠的容器住着的节点默认藏起来，但
##   · 钉住的（pinned）不藏；
##   · 与场外还有连线的（被用到别处）不藏。
## 反复迭代到稳定（Web 版同款 while(changed) 写法）。
func recompute_hidden() -> void:
	for key in nodes.keys():
		hidden.erase(key)
	## F5：先把边表折叠成邻接表、把 home_scene 折叠成索引，避免「每个折叠容器 × 每个节点
	## × 整张边表」的三重扫描。判定语义与旧版逐边扫描完全一致。
	var adj := {}
	for e in edges:
		var a := String(e.get("a", ""))
		var b := String(e.get("b", ""))
		if not nodes.has(a) or not nodes.has(b):
			continue
		if not adj.has(a):
			adj[a] = []
		if not adj.has(b):
			adj[b] = []
		(adj[a] as Array).append(b)
		(adj[b] as Array).append(a)
	var by_scene := {}
	for key in nodes.keys():
		var node_kind := String((nodes[key] as Dictionary).get("kind", ""))
		## 场景 / 时间点永远是根：即使旧存档把 home_scene 写成了某个物品（历史成环数据），
		## 也不能因为那个容器折叠而把整张场景卡藏掉。
		if is_scene_kind(node_kind):
			continue
		var home := String((nodes[key] as Dictionary).get("home_scene", ""))
		if home == "":
			continue
		if not by_scene.has(home):
			by_scene[home] = []
		(by_scene[home] as Array).append(String(key))
	var changed := true
	while changed:
		changed = false
		for cid in collapsed.keys():
			var scene_id := String(cid)
			var container_key := key_of("loc", scene_id)
			if not nodes.has(container_key):
				container_key = key_of("item", scene_id)
			for key in by_scene.get(scene_id, []):
				var n: Dictionary = nodes[key]
				if stored.has(key) or hidden.has(key) or bool(n.get("pinned", false)):
					continue
				if bool(n.get("always_visible", false)):
					continue
				if key == container_key:
					continue
				# 与「保持可见」的节点还有边 → 不藏
				var exported := false
				for other_key in adj.get(key, []):
					if other_key == container_key:
						continue
					if not nodes.has(other_key):
						continue
					if hidden.has(other_key) or stored.has(other_key):
						continue
					if String((nodes[other_key] as Dictionary).get("home_scene", "")) == scene_id:
						continue
					exported = true
					break
				if not exported:
					hidden[key] = true
					changed = true


## 枢纽场景：入边 + 出边 >= 5（对齐 Web `isHub`）。
## 容器物品正文里的 [loc:X] 也算一条入边 —— 否则把书桌改成物品后，花园会因为
## 「承载通路的东西换了身份」平白丢掉枢纽身份，画布上的双线框也会跟着消失。
var _hub_degree: Dictionary = {}
## [loc:X] 文本入边计数（Web 03-utils.js `inbound`）：场景内容 + 容器物品内容里的
## loc 标签都指向目标场景。is_no_entry（warn 药丸谓词）的第一条排除项。
var _loc_in: Dictionary = {}
## 命令产出的场景通路（Web `condRoutes`）：物品命令的结果中所指向的场景
##（choice options 的 results.scene / use-item 与 conditional 的 onSuccess.scene）。
var _route_scene: Dictionary = {}


func is_hub(kind: String, id: String) -> bool:
	if kind != "loc":
		return false
	if _hub_degree.is_empty():
		_build_hub_degree()
	return int(_hub_degree.get(id, 0)) >= 5


## 「无文本入口」谓词（Web 07-render.js:134-135 的 `badge warn`）：
## kind=loc + 未探索 + 没有任何 [loc:X] 文本通路指向 + 没有任何命令能产出 +
## 自己也没有出口。四个条件都成立才挂药丸 —— 这是「永远走不进来的瞎掰地点」
## 的第一道提醒（若在推演 / 档案里确实有别的到达法，药丸会在数据里替它背书）。
func is_no_entry(key: String) -> bool:
	var n := node(key)
	if n.is_empty() or String(n["kind"]) != "loc":
		return false
	var id := String(n["id"])
	if explored.has(id):
		return false
	if _loc_in.is_empty():
		_build_hub_degree()
	return int(_loc_in.get(id, 0)) == 0 and not _route_scene.has(id) \
		and scene_locs(id).is_empty()


func _build_hub_degree() -> void:
	_hub_degree.clear()
	_loc_in.clear()
	_route_scene.clear()
	if case_def == null:
		return
	for sid in case_def.scenes.keys():
		var sid_s := String(sid)
		_hub_degree[sid_s] = int(_hub_degree.get(sid_s, 0))
		for loc in scene_locs(sid_s):
			_hub_degree[sid_s] = int(_hub_degree[sid_s]) + 1
			_hub_degree[String(loc)] = int(_hub_degree.get(String(loc), 0)) + 1
			_loc_in[String(loc)] = int(_loc_in.get(String(loc), 0)) + 1
	for iid in case_def.items.keys():
		for loc in scene_locs(String(iid)):
			_hub_degree[String(loc)] = int(_hub_degree.get(String(loc), 0)) + 1
			_loc_in[String(loc)] = int(_loc_in.get(String(loc), 0)) + 1
	for iid2 in case_def.items.keys():
		var it2 := case_def.item_of(String(iid2))
		if it2 == null:
			continue
		for cmd in it2.commands:
			_collect_cmd_scenes(cmd)


## 命令树里所有「指向场景」的结果（Web 是对 ITEMS 原始 JSON 全嵌套遍历键名
## `scene`；这里的资源是强类型，枚举三处拥有的 PayloadDef 就是全集）
func _collect_cmd_scenes(cmd: CommandDef) -> void:
	var p := payload_of_command(cmd)
	if p != null and p.scene != null and p.scene.id != "":
		_route_scene[p.scene.id] = true
	if cmd is ChoiceCommandDef:
		for opt in (cmd as ChoiceCommandDef).options:
			if opt != null and opt.payload != null and opt.payload.scene != null \
					and opt.payload.scene.id != "":
				_route_scene[opt.payload.scene.id] = true


func payload_of_command(cmd: CommandDef) -> PayloadDef:
	if cmd is UseItemCommandDef:
		return (cmd as UseItemCommandDef).on_success
	if cmd is ConditionalCommandDef:
		return (cmd as ConditionalCommandDef).on_success
	return null


## 容器节点清单里列出的其他地点（`node_locs`）—— 拖容器到场景 = 前往的通路。
## 覆盖两类宿主：场景，以及能展开的容器物品（书桌 / 垃圾桶）。
## 清单来自资源上的 `node_locs`，与正文写了什么无关。
func scene_locs(sid: String) -> Array:
	var out: Array = []
	var s := case_def.scene_of(sid)
	var list: Array = case_def.nodes_of_scene(s) if s != null else case_def.nodes_of_item(case_def.item_of(sid))
	for tag in list:
		if String(tag["kind"]) == "loc":
			out.append(String(tag["id"]))
	return out


## ── 因果追踪（SYS_LOGS）────────────────────────────────────────────────
## 口径照抄 Web `03-utils.js:250-262`：日志是**案卷**，只记「结果」，不记操作流水。
## ✅ 记：捕获线索 / 结局 / 案件解锁、组合结果与失败、使用物品的结果、前往、
##        一切失败与拦截（缺线索 / 缺工具 / 密码错 / 推演不匹配）、开局与换案标记。
## ❌ 不记：展开与收起容器、收入与取出、卡片放映、撤销 / 重置等桌面操作、
##        可达性统计、**对话台词本身**（台词里给出线索才是结果）。
func add_log(text: String, kind: String = "") -> void:
	if text == "":
		return
	logs.append({"text": text, "kind": kind})
	while logs.size() > LOG_MAX:
		logs.pop_front()


func clear_logs() -> void:
	logs.clear()


func log_count() -> int:
	return logs.size()
