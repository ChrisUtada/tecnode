class_name CaseLoader
extends RefCounted
## 案件装载（Resource 版，P1）
##
## P0 曾直读 `data/case-a001.json`；P1.1 起数据落在 `cases/a001/**/*.tres`，
## 本类只认 `.tres` —— **JSON 已冻结为只读档案**（对照基准由 test_migration.gd 守着）。
##
## 对外仍保留 P0 的字符串型便利方法（`label_of` / `text_of` / `tags_of` / `strip_tags`），
## 因为它们是「文本协议」的入口，与数据形态无关；其余一律直接用 Resource。

const CASE_PATH := "res://cases/a001/case.tres"
const DEFAULT_MEMORY_SCENES := ["SCENES_0602", "SCENES_0704"]
## TEC / 执行者不是普通角色卡，素材固定放在 raw 下；其余角色一律读 CharDef.avatar。
const AVATAR_SPECIAL := {
	"CHARS_TEC": "res://assets/raw/tec-avatar.png",
	"CHARS_EXEC": "res://assets/raw/executor-avatar.png",
}

var path: String
var case_def: CaseDef = null
var memory_scenes: Array[SceneDef] = []
var scenes: Dictionary = {}      # id -> SceneDef
var items: Dictionary = {}       # id -> ItemDef
var chars: Dictionary = {}       # id -> CharDef
var clues: Dictionary = {}       # id -> EvidenceDef（旧名兼容别名）
var evidences: Dictionary = {}   # id -> EvidenceDef
var evidence_recipes: Array[EvidenceRecipeDef] = []
var memories: Array[MemoryDef] = []
var dialogues: Array[DialogueDef] = []
var endings: Array[EndingDef] = []
var evidence_issues: Array = []
var load_error: String = ""


func _init(p_path: String = CASE_PATH) -> void:
	path = p_path


func load_case() -> bool:
	if not ResourceLoader.exists(path):
		load_error = ("找不到 %s —— 先跑一次迁移："
			+ "godot --headless --path ydgodot --script res://tools/json_to_tres.gd") % path
		push_error(load_error)
		return false
	var r = load(path)
	if not (r is CaseDef):
		load_error = "%s 不是 CaseDef" % path
		push_error(load_error)
		return false
	case_def = r
	_index()
	validate_nodes()
	evidence_issues = validate_evidence()
	if not evidence_issues.is_empty():
		push_warning("证据链有 %d 处不可达 / 配置问题：%s" % [
			evidence_issues.size(), str(evidence_issues.slice(0, 5))])
	## §7-3：标签退役后的防回灌校验。正文里只要再出现 `[xxx:` 就拒绝装载，
	## 逼数据走结构化字段（hidden_clue / clues / node_*），而不是让解析器悄悄复活。
	var dirty := validate_text_clean()
	if not dirty.is_empty():
		load_error = "正文仍含退役标签：%s" % str(dirty.slice(0, 5))
		push_error(load_error)
		return false
	return true


## 把所有场景 / 容器物品的节点清单过一遍：写错的 id 直接打到输出面板，
## 不让它在画布上静默消失（资源被删 / 改名后 id 失配是最常见的一种）。
func validate_nodes() -> Array:
	unknown_nodes.clear()
	for s in case_def.scenes:
		nodes_of_scene(s)
	for it in case_def.items:
		nodes_of_item(it)
	if not unknown_nodes.is_empty():
		push_warning("画布节点清单有 %d 个 id 解析不到：%s" % [unknown_nodes.size(), str(unknown_nodes)])
	var cycles := containment_cycles()
	if not cycles.is_empty():
		push_warning("画布节点清单有 %d 组包含环（折叠时会互相隐藏）：%s" % [
			cycles.size(), str(cycles.slice(0, 3))])
	return unknown_nodes


## 容器包含环：A 的 node_items 里有 B，B 的 node_items 里又有 A。
## 这类数据在折叠时会让两个容器互相判定「该藏」，最终整组节点消失。
## 场景 / 物品都纳入；返回 [[key, key, ...], ...]。
func containment_cycles() -> Array:
	var adj := {}
	for s in case_def.scenes:
		var children: Array[String] = []
		for id in s.node_items:
			if items.has(id):
				children.append("item:" + String(id))
			elif scenes.has(id):
				children.append(scene_kind(String(id)) + ":" + String(id))
		adj[scene_kind(String(s.id)) + ":" + String(s.id)] = children
	for it in case_def.items:
		var children: Array[String] = []
		for id in it.node_items:
			if items.has(id):
				children.append("item:" + String(id))
			elif scenes.has(id):
				children.append(scene_kind(String(id)) + ":" + String(id))
		adj["item:" + String(it.id)] = children
	var color := {}
	var stack: Array[String] = []
	var out: Array = []
	var seen := {}
	for v in adj.keys():
		if int(color.get(v, 0)) == 0:
			_cycle_dfs(String(v), adj, color, stack, out, seen)
	return out


func _cycle_dfs(v: String, adj: Dictionary, color: Dictionary, stack: Array[String],
		out: Array, seen: Dictionary) -> void:
	color[v] = 1
	stack.append(v)
	for raw in adj.get(v, []):
		var w := String(raw)
		if not adj.has(w):
			continue
		var c := int(color.get(w, 0))
		if c == 0:
			_cycle_dfs(w, adj, color, stack, out, seen)
		elif c == 1:
			var at := stack.find(w)
			if at < 0:
				continue
			var cycle: Array[String] = stack.slice(at)
			cycle.append(w)
			var sig := "|".join(cycle)
			if not seen.has(sig):
				seen[sig] = true
				out.append(cycle)
	stack.pop_back()
	color[v] = 2


## 证据链可达性：每个原料证据必须有来源（TEC / 对话 / 回忆 / 配方），
## 每条配方的两端与产物都必须可达，每个关键字段至少有一条可拿到证据的支撑。
## 返回问题列表；空 = 通过。运行时只警告，迁移测试会判死。
func validate_evidence() -> Array:
	var out: Array = []
	_validate_evidence_defs(out)
	var available := _collect_available_evidence()
	_validate_recipes(out, available)
	_validate_endings(out, available)
	_validate_evidence_fields(out, available)
	return out


func _validate_evidence_defs(out: Array) -> void:
	var valid_tiers := ["wu", "ci", "zheng"]
	var valid_origins := ["tec", "synth", "deduce"]
	for ev in evidences.values():
		if ev == null or ev.id == "":
			out.append("证据定义缺 id")
			continue
		if not valid_tiers.has(String(ev.tier)):
			out.append("%s 的 tier 非法：%s" % [ev.id, ev.tier])
		if not valid_origins.has(String(ev.origin)):
			out.append("%s 的 origin 非法：%s" % [ev.id, ev.origin])
		if String(ev.tier) == "zheng" and not MatrixState.SENSES.has(String(ev.sense)):
			out.append("%s 的 sense 非法：%s" % [ev.id, ev.sense])
		if ev.label.strip_edges() == "":
			out.append("%s 缺 label" % ev.id)


## 收集所有可达证据：TEC 产出、对话 / 回忆掉落、命令 / 反应产出，
## 再让配方产物迭代到稳定（产物可继续作为下一层原料）。
func _collect_available_evidence() -> Dictionary:
	var available := {}
	# TEC 产出：物品 / 场景 / 人物的 hidden_clue（字段名沿用）里列出的证。
	for it in case_def.items:
		if it.hidden_clue != null:
			for ev in it.hidden_clue.clues:
				if ev != null:
					available[ev.id] = true
	for s in case_def.scenes:
		if s.hidden_clue != null:
			for ev in s.hidden_clue.clues:
				if ev != null:
					available[ev.id] = true
	for ch in case_def.chars:
		if ch.hidden_clue != null:
			for ev in ch.hidden_clue.clues:
				if ev != null:
					available[ev.id] = true
	for d in case_def.dialogues:
		for ev in d.drops_evidence:
			if ev != null:
				available[ev.id] = true
	for m in case_def.memories:
		for ev in m.drops_evidence:
			if ev != null:
				available[ev.id] = true
	# 命令 / 反应也能产证：纳入可达性。
	for it in case_def.items:
		for cmd in it.commands:
			for ev in cmd.clues:
				if ev != null: available[ev.id] = true
			var pay = cmd.get("on_success")
			if pay is PayloadDef:
				for ev in (pay as PayloadDef).clues:
					if ev != null: available[ev.id] = true
			if cmd is ChoiceCommandDef:
				for opt in (cmd as ChoiceCommandDef).options:
					if opt != null and opt.payload != null:
						for ev in opt.payload.clues:
							if ev != null: available[ev.id] = true
	for ch in case_def.chars:
		for row in ch.clue_reactions:
			for ev in row.clues:
				if ev != null: available[ev.id] = true
		for row in ch.item_reactions:
			for ev in row.clues:
				if ev != null: available[ev.id] = true
	# 物品本体天然算「物」原料。
	var changed := true
	while changed:
		changed = false
		for r in case_def.evidence_recipes:
			if r == null or r.a == null or r.b == null or r.evidence == null:
				continue
			if _recipe_side_available(r.a, available) and _recipe_side_available(r.b, available) \
					and not available.has(r.evidence.id):
				available[r.evidence.id] = true
				changed = true
	return available


func _validate_recipes(out: Array, available: Dictionary) -> void:
	for r in case_def.evidence_recipes:
		if r == null or r.a == null or r.b == null or r.evidence == null:
			out.append("配方缺 a / b / evidence")
			continue
		if r.a == r.b:
			out.append("配方 %s 的两端是同一张原料" % r.id)
		if String(r.evidence.tier) != "zheng":
			out.append("配方 %s 的产物不是「证」：%s" % [r.id, r.evidence.tier])
		if not MatrixState.SENSES.has(String(r.sense)):
			out.append("配方 %s 的 sense 非法：%s" % [r.id, r.sense])
		for raw in [r.a, r.b]:
			if not _recipe_side_available(raw, available):
				out.append("配方 %s 的「%s」没有可达来源" % [r.id, _raw_id(raw)])
		if not available.has(r.evidence.id):
			out.append("配方 %s 的产物「%s」不可达" % [r.id, r.evidence.id])


## 结局配方必须覆盖它需要的五感：每个 sense 至少要有一张可达的证。
func _validate_endings(out: Array, available: Dictionary) -> void:
	var sense_ok := {}
	for eid in available.keys():
		var ev := evidence_of(String(eid))
		if ev != null and String(ev.tier) == "zheng":
			sense_ok[String(ev.sense)] = true
	for end in case_def.endings:
		for ev in end.recipe:
			if ev == null or not available.has(ev.id):
				out.append("结局 %s 的「%s」不可达" % [end.id, _raw_id(ev)])
			elif not sense_ok.has(String(ev.sense)):
				out.append("结局 %s 的「%s」缺少同感官可达证据" % [end.id, ev.id])


func _validate_evidence_fields(out: Array, available: Dictionary) -> void:
	for ch in case_def.chars:
		for f in ch.evidence_fields:
			if f == null:
				out.append("%s 有空的证据字段" % ch.id)
				continue
			if f.options.is_empty() or not f.options.has(f.correct):
				out.append("%s / %s 的词库不含正确答案" % [ch.id, f.id])
			if f.support.is_empty():
				out.append("%s / %s 没有支撑证据" % [ch.id, f.id])
			for ev in f.support:
				if ev == null or not available.has(ev.id) or String(ev.tier) != "zheng":
					out.append("%s / %s 的支撑证据不可达或不是证" % [ch.id, f.id])
			if f.drop_clue == null:
				out.append("%s / %s 没有完成掉落证据" % [ch.id, f.id])


func _recipe_side_available(raw: Resource, available: Dictionary) -> bool:
	if raw is ItemDef:
		return items.has(String((raw as ItemDef).id))
	if raw is EvidenceDef:
		return available.has(String((raw as EvidenceDef).id))
	return false


func _raw_id(raw: Resource) -> String:
	if raw == null:
		return ""
	if raw is ItemDef:
		return String((raw as ItemDef).id)
	if raw is EvidenceDef:
		return String((raw as EvidenceDef).id)
	return ""


## 扫描所有数据资源里的字符串，找 `[item:` / `[clue:` 这类退役标签。
## 跳过脚本 / 贴图 / 路径字段；用实例 id 防环（CaseDef ↔ SceneDef 互相引用）。
func validate_text_clean() -> Array:
	var out: Array = []
	var seen := {}
	var re := RegEx.new()
	re.compile("\\[[A-Za-z_]+:")
	_scan_text(case_def, "case", re, out, seen)
	return out


func _scan_text(value, path: String, re: RegEx, out: Array, seen: Dictionary) -> void:
	if value == null:
		return
	if value is String:
		if re.search(String(value)) != null:
			out.append(path)
		return
	if value is Script or value is Texture2D or value is AudioStream:
		return
	if value is Resource:
		var rid: int = value.get_instance_id()
		if seen.has(rid):
			return
		seen[rid] = true
		for p in value.get_property_list():
			var pname := String(p.get("name", ""))
			if pname in ["script", "resource_path", "resource_name", "image", "avatar"]:
				continue
			_scan_text(value.get(pname), path + "." + pname, re, out, seen)
		return
	if value is Array or value is PackedStringArray:
		for i in value.size():
			_scan_text(value[i], path + "[%d]" % i, re, out, seen)
		return
	if value is Dictionary:
		for k in value.keys():
			_scan_text(value[k], path + "." + String(k), re, out, seen)


func _index() -> void:
	scenes.clear(); items.clear(); chars.clear(); clues.clear(); evidences.clear()
	for s in case_def.scenes:
		scenes[s.id] = s
	for it in case_def.items:
		items[it.id] = it
	for c in case_def.chars:
		chars[c.id] = c
	## 旧 `clues` 数组也并入 evidences：迁移期兼容，新数据不再写 clues。
	for ev in case_def.clues:
		evidences[ev.id] = ev
	for ev in case_def.evidences:
		evidences[ev.id] = ev
	## 旧调用方仍可用 `clue_of` / `clues`；底层已经是证。
	clues = evidences
	evidence_recipes = case_def.evidence_recipes
	memories = case_def.memories
	dialogues = case_def.dialogues
	endings = case_def.endings
	memory_scenes = case_def.memory_scenes
	if memory_scenes.is_empty():
		for id in DEFAULT_MEMORY_SCENES:
			if scenes.has(id):
				memory_scenes.append(scenes[id])


# ── 查询 ────────────────────────────────────────────────────────────────

## 引用前缀 → 画布节点 kind
## ⚠ 数据里前缀单复数混用（SCENES_garden 与 SCENE_x、ITEM_something 与 ITEMS_bd 都有）；
##    DATA_* 是线索类的伪实体（五感配方里会出现）。
static func kind_of_ref(ref_id: String) -> String:
	var p := ref_id.to_upper()
	if p.begins_with("SCENES_") or p.begins_with("SCENE_"):
		return "loc"
	if p.begins_with("ITEMS_") or p.begins_with("ITEM_"):
		return "item"
	if p.begins_with("CHARS_") or p.begins_with("CHAR_"):
		return "char"
	if p.begins_with("CLUES_") or p.begins_with("CLUE_") or p.begins_with("DATA_") \
			or p.begins_with("EVID_") or p.begins_with("EVIDENCE_"):
		return "evidence"
	return "data"


func scene_of(id: String) -> SceneDef:
	return scenes.get(id, null)


func item_of(id: String) -> ItemDef:
	return items.get(id, null)


func char_of(id: String) -> CharDef:
	return chars.get(id, null)


## 统一头像解析入口：名册 / 档案卡 / 对话窗 / 记忆放映卡都走这里。
func avatar_path_of(id: String) -> String:
	if AVATAR_SPECIAL.has(id):
		return String(AVATAR_SPECIAL[id])
	return avatar_path_of_def(char_of(id))


## 头像字段兼容两种写法：`res://...` 直接加载；旧的 Web 相对路径只取文件名，
## 依次在 raw / images / 旧 images 下找。找不到返回空串，让 UI 落回首字占位。
static func avatar_path_of_def(ch: CharDef) -> String:
	if ch == null:
		return ""
	var raw := String(ch.avatar).strip_edges()
	if raw == "":
		return ""
	if raw.begins_with("res://") and ResourceLoader.exists(raw):
		return raw
	var base := raw.get_file()
	for root in ["res://assets/raw/", "res://assets/images/", "res://images/"]:
		if ResourceLoader.exists(root + base):
			return root + base
	return ""


## 兼容旧调用名：旧“线索”现在就是证。
func clue_of(id: String) -> EvidenceDef:
	return evidences.get(id, null)


func evidence_of(id: String) -> EvidenceDef:
	return evidences.get(id, null)


## 无序对配方：`a × b` 与 `b × a` 都能命中。原料可以是物品（物）或证据（词/证），
## 因此必须同时比较 kind，避免同名 id / 类型串线。
func evidence_recipe_for(a_kind: String, a_id: String, b_kind: String, b_id: String) -> EvidenceRecipeDef:
	for r in evidence_recipes:
		if r == null or r.a == null or r.b == null:
			continue
		if _recipe_side_matches(r.a, a_kind, a_id) and _recipe_side_matches(r.b, b_kind, b_id):
			return r
		if _recipe_side_matches(r.a, b_kind, b_id) and _recipe_side_matches(r.b, a_kind, a_id):
			return r
	return null


func _recipe_side_matches(raw: Resource, kind: String, id: String) -> bool:
	if raw is ItemDef:
		return kind == "item" and String((raw as ItemDef).id) == id
	if raw is EvidenceDef:
		return kind == "evidence" and String((raw as EvidenceDef).id) == id
	return false


## 物品是否被任何证据配方引用：详情窗据此显示「可用作证据原料」。
func item_used_in_recipe(id: String) -> bool:
	for r in evidence_recipes:
		if r == null:
			continue
		for raw in [r.a, r.b]:
			if raw is ItemDef and String((raw as ItemDef).id) == id:
				return true
	return false


func evidence_tier_of(id: String) -> String:
	var ev := evidence_of(id)
	return ev.tier if ev != null else ""


## 按 kind 取实体（画布 kind = loc/item/char/clue）
func def_of(kind: String, id: String) -> Resource:
	match kind:
		"loc", "scene", "time":
			return scene_of(id)
		"item":
			return item_of(id)
		"char":
			return char_of(id)
		"clue", "data", "evidence":
			return evidence_of(id)
	return null


func label_of(kind: String, id: String) -> String:
	match kind:
		"loc", "scene", "time":
			var s := scene_of(id)
			return s.title if s != null else id
		"item":
			var it := item_of(id)
			return it.label if it != null else id
		"char":
			var ch := char_of(id)
			return ch.name if ch != null else id
		"clue", "data", "evidence":
			var ev := evidence_of(id)
			return ev.label if ev != null else id
	return id


func scene_title(id: String) -> String:
	var s := scene_of(id)
	return s.title if s != null else id


# ── 画布节点清单（显式数据）──────────────────────────────────────────────
## 场景 / 容器物品展开时长出哪些节点，**只读资源上的四栏 id**，不再从正文标签推。
## 正文与画布从此互不影响：正文改写、标签删净，画布该有的东西一个不少。
## 顺序固定 item → char → loc → clue（回忆时刻按这个序算入场偏移）。
## 写错的 id 不会静默当空气：收进 `unknown_nodes`，测试与装载日志都会报。

var unknown_nodes: Array = []     # ["SCENES_garden → item:ITEM_xxx"]

func nodes_of_scene(s: SceneDef) -> Array:
	if s == null:
		return []
	return _merge_nodes(s.node_items, s.node_chars, s.node_locs, s.node_clues, s.id)


func nodes_of_item(it: ItemDef) -> Array:
	if it == null:
		return []
	return _merge_nodes(it.node_items, it.node_chars, it.node_locs, it.node_clues, it.id)


## 按容器 id 取节点清单（场景 / 时刻在前，其次容器物品）
func container_nodes(kind: String, id: String) -> Array:
	var k := String(kind)
	if k == "loc" or k == "time" or k == "scene":
		return nodes_of_scene(scene_of(id))
	return nodes_of_item(item_of(id))


func _merge_nodes(items_s: PackedStringArray, chars_s: PackedStringArray,
		locs_s: PackedStringArray, clues_s: PackedStringArray, host_id: String) -> Array:
	var out: Array = []
	_collect_ids(out, "item", items_s, items, host_id)
	_collect_ids(out, "char", chars_s, chars, host_id)
	_collect_ids(out, "loc", locs_s, scenes, host_id)
	_collect_ids(out, "evidence", clues_s, evidences, host_id)
	return out


func _collect_ids(out: Array, kind: String, ids: PackedStringArray,
		table: Dictionary, host_id: String) -> void:
	for id in ids:
		if table.has(id):
			out.append({"kind": kind, "id": String(id)})
		else:
			unknown_nodes.append("%s → %s:%s" % [host_id, kind, id])


func is_time_id(id: String) -> bool:
	for s in memory_scenes:
		if s != null and s.id == id:
			return true
	return false


## 场景引用在画布上的 kind：时刻场景是 "time"，其余是 "loc"。
func scene_kind(id: String) -> String:
	return "time" if is_time_id(id) else "loc"


func memory_scene_ids() -> Array:
	var out: Array = []
	for s in memory_scenes:
		if s != null:
			out.append(s.id)
	return out


func memories_for(when_id: String) -> Array[MemoryDef]:
	var out: Array[MemoryDef] = []
	for m in memories:
		if m != null and m.when != null and m.when.id == when_id:
			out.append(m)
	return out


## 回忆小剧场匹配器：when × who × where 三者全中才算命中。
func memory_for(when_id: String, who_id: String, where_id: String) -> MemoryDef:
	for m in memories:
		if m == null:
			continue
		if m.when != null and m.when.id == when_id \
			and m.who != null and m.who.id == who_id \
			and m.where != null and m.where.id == where_id:
			return m
	return null


## 某时刻回忆发生的地点（取该时刻第一条回忆的 where）。
func mem_place_of(when_id: String) -> SceneDef:
	for m in memories_for(when_id):
		return m.where
	return null


func time_label_of(t: String) -> String:
	if t == "present":
		return now_label()
	return scene_title(t)


## 档案窗简介：发生地点 · 在场人物 + 一句开场旁白。
func time_brief_of(t: String) -> Dictionary:
	var mems := memories_for(t)
	var where := ""
	var who_names: Array = []
	for m in mems:
		if where == "" and m.where != null:
			where = m.where.title
		if m.who != null and not who_names.has(m.who.name):
			who_names.append(m.who.name)
	var summary := ""
	for m in mems:
		for line in m.script_lines:
			if line != null and line.kind == "narr" and line.text != "":
				summary = String(line.text)
				break
		if summary != "":
			break
	return {"where": where, "who": " · ".join(who_names), "sum": summary}


func start_scene() -> String:
	return case_def.start_scene.id if case_def.start_scene != null else ""


func now_label() -> String:
	return case_def.now_label


func ending_by_id(id: String) -> EndingDef:
	for e in endings:
		if e.id == id:
			return e
	return null


# ── 文本协议 ────────────────────────────────────────────────────────────

func text_of(kind: String, id: String) -> String:
	if kind == "loc" or kind == "scene" or kind == "time":
		var s := scene_of(id)
		return s.content if s != null else ""
	var it := item_of(id)
	return it.desc if it != null else ""


## §7-3：正文标签已退役，raw_text_of 与 text_of 同源保留，避免旧调用方立刻断掉。
func raw_text_of(kind: String, id: String) -> String:
	return text_of(kind, id)
