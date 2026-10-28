class_name SaveSystem
extends RefCounted
## 快照 / 撤销栈 / 案件存档（对齐 Web `02-state.js` + `16-cases.js`）
##
## 快照只装「玩家玩出来的运行时态」：节点（含位置 / 点亮 / 钉住 / 零件 / 收纳去向）、
## 边、已探索 / 已捕获 / 已试、TEC 进度、折叠、五感阵列、已达成结局、时刻与花园。
## 人物档案备注属于「玩家知识」，但需要跨读档保留，故单独存 notes；撤销时不回滚。
## 可重算的 hidden 不存。
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
## F4：最近一次已入账 / 已写盘的快照 JSON。提交判脏不再序列化 before 与 current 两份，
## 只序列化 current 一次并与它比较；自动写盘可直接复用这份字符串。
var last_json := ""
var pending_json := ""
## F4 基准：快照 / JSON 序列化次数（测试用）。
var dbg_snapshot_calls := 0
var dbg_json_calls := 0


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
	dbg_snapshot_calls += 1
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
		"notes": graph.notes.duplicate(true),
		"claims": graph.claims.duplicate(true),
		"confirmedFields": graph.confirmed_fields.duplicate(true),
	}


func snapshot_json() -> String:
	dbg_json_calls += 1
	return JSON.stringify(snapshot())


## 把快照写回当前 GraphState（原地恢复，外部持有的 graph 引用继续有效）。
## `keep_knowledge` 只给撤销用：玩家知识（unread / cardSeen / debuted）以**当前值**为准，
## 不让撤销把「已经看过 / 已经认识」退回旧档（S8）。普通读档仍按存档里的知识恢复。
func restore(s: Dictionary, keep_knowledge := false) -> bool:
	last_error = ""
	if s.is_empty() or not (s.get("nodes") is Dictionary):
		last_error = "快照缺少 nodes"
		return false
	## S15：格式号只写不校验会导致未来旧档被按新格式静默解析。
	## 缺省 / 老档按当前格式读；比当前新的版本明确拒绝。
	var fmt := int(s.get("format", FORMAT))
	if fmt > FORMAT:
		last_error = "存档格式过新：%d（当前支持 %d）" % [fmt, FORMAT]
		return false
	var now_card_seen := graph.card_seen.duplicate(true) if keep_knowledge else {}
	var now_debuted := graph.debuted.duplicate(true) if keep_knowledge else {}
	var now_unread := {}
	var now_confirmed := graph.confirmed_fields.duplicate(true) if keep_knowledge else {}
	if keep_knowledge:
		for raw_key in graph.nodes.keys():
			var k := String(raw_key)
			now_unread[k] = bool((graph.nodes[raw_key] as Dictionary).get("unread", false))
	graph.nodes.clear()
	graph.edges.clear()
	graph.explored.clear()
	graph.captured.clear()
	graph.tec_prog.clear()
	graph.collapsed.clear()
	graph.stored.clear()
	graph.endings.clear()
	graph.tried.clear()
	graph.claims.clear()
	graph.confirmed_fields.clear()
	graph.talk_prog.clear()
	graph.card_seen.clear()
	graph.debuted.clear()
	graph.time = String(s.get("time", "present"))
	graph.garden = {"seed": false, "plots": []}
	graph.selected = ""
	graph.last_scene = String(s.get("lastScene", s.get("last_scene", "")))
	graph.matrix_state.reset()

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
		graph.garden_state.from_dict(garden_in)
	elif _as_array(s.get("endings", [])).has("TRUE_E"):
		# P2.5 老档迁移：走完真名但存档还没有 garden 字段 → 补一枚种子
		graph.garden_state.reset()
		graph.garden_state.set_seed(true)

	## 人物档案卡备注：读档按存档恢复；撤销（keep_knowledge）保持当前值不覆盖。
	if not keep_knowledge:
		graph.notes.clear()
		var notes_in = s.get("notes", {})
		if notes_in is Dictionary:
			for key in (notes_in as Dictionary).keys():
				graph.notes[String(key)] = String((notes_in as Dictionary)[key])

	var matrix_in = s.get("matrix", {})
	if matrix_in is Dictionary:
		graph.matrix_state.from_dict(matrix_in)
	for id in _as_array(s.get("endings", [])):
		graph.endings[String(id)] = true
	for pid in (s.get("claims", {}) as Dictionary).keys():
		var row = (s.get("claims", {}) as Dictionary)[pid]
		if row is Dictionary:
			graph.claims[String(pid)] = (row as Dictionary).duplicate(true)
	for pid2 in (s.get("confirmedFields", {}) as Dictionary).keys():
		var row2 = (s.get("confirmedFields", {}) as Dictionary)[pid2]
		if row2 is Dictionary:
			graph.confirmed_fields[String(pid2)] = (row2 as Dictionary).duplicate(true)

	## S8：撤销时用**当前值**合并知识，而不是让快照覆盖；
	## 当前值里显式 false 的条目也照样覆盖（与 Web 的 Object.assign 同口径）。
	if keep_knowledge:
		for key in now_card_seen.keys():
			graph.card_seen[String(key)] = bool(now_card_seen[key])
		for key in now_debuted.keys():
			graph.debuted[String(key)] = bool(now_debuted[key])
		for key in now_unread.keys():
			if graph.nodes.has(key):
				graph.nodes[key]["unread"] = bool(now_unread[key])
		## 已盖章字段是玩家知识：撤销能把主张与节点倒回去，但不能把章倒掉。
		graph.confirmed_fields = now_confirmed
	## 已盖章字段不应该再留一条待核对主张（旧档 / 撤销交叉时可能出现）。
	for pid in graph.confirmed_fields.keys():
		for fid in (graph.confirmed_fields[pid] as Dictionary).keys():
			graph.clear_claim(String(pid), String(fid))

	graph.recompute_hidden()
	## 图已被替换：下一次提交必须重新建立基准，不能拿旧 JSON 判「没变」。
	last_json = ""
	return true


func restore_json(text: String) -> bool:
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		last_error = "存档不是 JSON 对象"
		return false
	return restore(parsed as Dictionary)


func _matrix_copy() -> Dictionary:
	return graph.matrix_state.to_dict()


func _as_array(value) -> Array:
	return value if value is Array else []


# ── 撤销栈 ──────────────────────────────────────────────────────────────

func push_history(snap: Dictionary = {}) -> void:
	var s := snap if not snap.is_empty() else snapshot()
	history.append(s.duplicate(true))
	while history.size() > HISTORY_MAX:
		history.pop_front()


func push_history_snapshot(snap: Dictionary) -> void:
	if snap.is_empty():
		return
	history.append(snap)
	while history.size() > HISTORY_MAX:
		history.pop_front()


func can_undo() -> bool:
	return not history.is_empty()


func undo() -> bool:
	if history.is_empty():
		return false
	return restore(history.pop_back() as Dictionary, true)


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
	var snap := snapshot()
	last_json = JSON.stringify(snap)
	var text := JSON.stringify(snap, "\t")
	f.store_string(text)
	f.close()
	pending_json = ""
	return true


## 自动写盘：复用 `_commit` 已经算好的 JSON，避免第三次 snapshot + stringify。
func flush_pending(p_path: String = "") -> bool:
	if pending_json == "":
		return save_to_disk(p_path)
	last_error = ""
	var target := p_path if p_path != "" else path
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		last_error = "无法写入 %s（错误 %d）" % [target, FileAccess.get_open_error()]
		return false
	f.store_string(pending_json)
	f.close()
	last_json = pending_json
	pending_json = ""
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
	last_json = ""
	pending_json = ""
	return true


func has_save(p_path: String = "") -> bool:
	return FileAccess.file_exists(p_path if p_path != "" else path)


func clear_save(p_path: String = "") -> void:
	var target := p_path if p_path != "" else path
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
