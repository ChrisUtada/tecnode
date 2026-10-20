class_name SaveSystem
extends RefCounted
## 快照 / 撤销栈 / 案件存档（对齐 Web `02-state.js` + `16-cases.js`）
##
## 快照只装「玩家玩出来的运行时态」：节点（含位置 / 点亮 / 钉住 / 零件 / 收纳去向）、
## 边、已探索 / 已捕获 / 已试、TEC 进度、折叠、五感阵列、已达成结局、时刻与花园。
## 玩家知识（Web 的 seenTexts / unread）与可重算的 hidden 不存。
##
## 存档路径固定为 `user://tec_case_<id>.save`；撤销栈最多 60 步。

const FORMAT := 1
const HISTORY_MAX := 60
const SAVE_PREFIX := "user://tec_case_"
const SAVE_SUFFIX := ".save"
const BAD_PATH_CHARS := ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]

var graph: GraphState
var case_id: String = ""
var path: String = ""
var history: Array = []
var last_error: String = ""


func _init(p_graph: GraphState, p_case_id: String = "", p_path: String = "") -> void:
	graph = p_graph
	case_id = p_case_id
	path = p_path if p_path != "" else save_path_for(case_id)


static func save_path_for(id: String) -> String:
	var safe := id.strip_edges()
	if safe == "":
		safe = "unknown"
	for ch in BAD_PATH_CHARS:
		safe = safe.replace(ch, "_")
	return SAVE_PREFIX + safe + SAVE_SUFFIX


# ── 快照 ────────────────────────────────────────────────────────────────

func snapshot() -> Dictionary:
	var nodes_out := {}
	for key in graph.nodes.keys():
		var n: Dictionary = graph.nodes[key]
		var item: Dictionary = n.duplicate(true)
		var where := String(graph.stored.get(key, ""))
		item["stored"] = where != ""
		item["storedIn"] = where
		nodes_out[key] = item
	return {
		"format": FORMAT,
		"caseId": case_id,
		"nodes": nodes_out,
		"edges": graph.edges.duplicate(true),
		"explored": graph.explored.keys(),
		"captured": graph.captured.keys(),
		"tried": graph.tried.keys(),
		"talkProg": graph.talk_prog.duplicate(true),
		"tecProg": graph.tec_prog.duplicate(true),
		"lastScene": graph.last_scene,
		"collapsed": graph.collapsed.keys(),
		"time": graph.time,
		"cardSeen": graph.card_seen.duplicate(true),
		"debuted": graph.debuted.duplicate(true),
		"matrix": _matrix_copy(),
		"endings": graph.endings.keys(),
		"garden": graph.garden.duplicate(true),
	}


func snapshot_json() -> String:
	return JSON.stringify(snapshot())


## 把快照写回当前 GraphState（原地恢复，外部持有的 graph 引用继续有效）
func restore(s: Dictionary) -> bool:
	last_error = ""
	if s.is_empty() or not (s.get("nodes") is Dictionary):
		last_error = "快照缺少 nodes"
		return false
	graph.nodes.clear()
	graph.edges.clear()
	graph.explored.clear()
	graph.captured.clear()
	graph.tec_prog.clear()
	graph.collapsed.clear()
	graph.stored.clear()
	graph.endings.clear()
	graph.tried.clear()
	graph.talk_prog.clear()
	graph.card_seen.clear()
	graph.debuted.clear()
	graph.time = String(s.get("time", "present"))
	graph.garden = {"seed": false, "plots": []}
	graph.selected = ""
	graph.last_scene = String(s.get("lastScene", s.get("last_scene", "")))
	for sense in GraphState.SENSES:
		graph.matrix[sense] = []

	for raw in (s["nodes"] as Dictionary).values():
		if not (raw is Dictionary):
			continue
		var n: Dictionary = (raw as Dictionary).duplicate(true)
		var key := String(n.get("key", ""))
		if key == "":
			key = graph.key_of(String(n.get("kind", "")), String(n.get("id", "")))
		if key == ":":
			continue
		n["key"] = key
		n["kind"] = String(n.get("kind", ""))
		n["id"] = String(n.get("id", ""))
		n["label"] = String(n.get("label", n["id"]))
		n["x"] = float(n.get("x", 0.0))
		n["y"] = float(n.get("y", 0.0))
		n["lit"] = bool(n.get("lit", false))
		n["pinned"] = bool(n.get("pinned", false))
		n["home_scene"] = String(n.get("home_scene", ""))
		n["bag_from"] = String(n.get("bag_from", ""))
		var installed = n.get("installed", {})
		n["installed"] = (installed as Dictionary).duplicate(true) if installed is Dictionary else {}
		n["captured"] = bool(n.get("captured", false))
		n["fresh"] = bool(n.get("fresh", false))
		n["unread"] = bool(n.get("unread", false))
		var where := String(n.get("storedIn", ""))
		if where != "":
			graph.stored[key] = where
		n["stored"] = where != ""
		n["storedIn"] = where
		if bool(n["captured"]):
			graph.captured[String(n["id"])] = true
		graph.nodes[key] = n

	for raw_edge in _as_array(s.get("edges", [])):
		if not (raw_edge is Dictionary):
			continue
		var e: Dictionary = raw_edge
		var a := String(e.get("a", ""))
		var b := String(e.get("b", ""))
		if a == "" or b == "" or not graph.nodes.has(a) or not graph.nodes.has(b):
			continue
		graph.edges.append({
			"a": a, "b": b,
			"rel": String(e.get("rel", e.get("kind", "entity"))),
		})

	for id in _as_array(s.get("explored", [])):
		graph.explored[String(id)] = true
	for id in _as_array(s.get("captured", [])):
		graph.captured[String(id)] = true
	for id in _as_array(s.get("tried", [])):
		graph.tried[String(id)] = true
	for key in (s.get("tecProg", s.get("tec_prog", {})) as Dictionary).keys():
		graph.tec_prog[String(key)] = int(s.get("tecProg", s.get("tec_prog", {}))[key])
	for key in (s.get("talkProg", {}) as Dictionary).keys():
		graph.talk_prog[String(key)] = int((s.get("talkProg", {}) as Dictionary)[key])
	for id in _as_array(s.get("collapsed", [])):
		graph.collapsed[String(id)] = true
	for key in (s.get("cardSeen", {}) as Dictionary).keys():
		graph.card_seen[String(key)] = bool((s.get("cardSeen", {}) as Dictionary)[key])
	for key in (s.get("debuted", {}) as Dictionary).keys():
		graph.debuted[String(key)] = bool((s.get("debuted", {}) as Dictionary)[key])
	var garden_in = s.get("garden", null)
	if garden_in is Dictionary:
		graph.garden = (garden_in as Dictionary).duplicate(true)
		if not (graph.garden.get("plots", []) is Array):
			graph.garden["plots"] = []
		graph.garden["seed"] = bool(graph.garden.get("seed", false))
	elif _as_array(s.get("endings", [])).has("TRUE_E"):
		# P2.5 老档迁移：走完真名但存档还没有 garden 字段 → 补一枚种子
		graph.garden = {"seed": true, "plots": []}

	var matrix_in = s.get("matrix", {})
	if matrix_in is Dictionary:
		for sense in GraphState.SENSES:
			var list = (matrix_in as Dictionary).get(sense, [])
			graph.matrix[sense] = _as_array(list).duplicate()
	for id in _as_array(s.get("endings", [])):
		graph.endings[String(id)] = true

	graph.recompute_hidden()
	return true


func restore_json(text: String) -> bool:
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		last_error = "存档不是 JSON 对象"
		return false
	return restore(parsed as Dictionary)


func _matrix_copy() -> Dictionary:
	var out := {}
	for sense in GraphState.SENSES:
		out[sense] = (graph.matrix.get(sense, []) as Array).duplicate()
	return out


func _as_array(value) -> Array:
	return value if value is Array else []


# ── 撤销栈 ──────────────────────────────────────────────────────────────

func push_history(snap: Dictionary = {}) -> void:
	var s := snap if not snap.is_empty() else snapshot()
	history.append(s.duplicate(true))
	while history.size() > HISTORY_MAX:
		history.pop_front()


func can_undo() -> bool:
	return not history.is_empty()


func undo() -> bool:
	if history.is_empty():
		return false
	return restore(history.pop_back() as Dictionary)


func clear_history() -> void:
	history.clear()


# ── 磁盘存档 ────────────────────────────────────────────────────────────

func save_to_disk(p_path: String = "") -> bool:
	last_error = ""
	var target := p_path if p_path != "" else path
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		last_error = "无法写入 %s（错误 %d）" % [target, FileAccess.get_open_error()]
		return false
	f.store_string(JSON.stringify(snapshot(), "\t"))
	f.close()
	return true


func load_from_disk(p_path: String = "") -> bool:
	last_error = ""
	var target := p_path if p_path != "" else path
	if not FileAccess.file_exists(target):
		last_error = "存档不存在：%s" % target
		return false
	var f := FileAccess.open(target, FileAccess.READ)
	if f == null:
		last_error = "无法读取 %s（错误 %d）" % [target, FileAccess.get_open_error()]
		return false
	var text := f.get_as_text()
	f.close()
	if not restore_json(text):
		return false
	history.clear()
	return true


func has_save(p_path: String = "") -> bool:
	return FileAccess.file_exists(p_path if p_path != "" else path)


func clear_save(p_path: String = "") -> void:
	var target := p_path if p_path != "" else path
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
