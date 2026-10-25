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

var path: String
var case_def: CaseDef = null
var memory_scenes: Array[SceneDef] = []
var scenes: Dictionary = {}      # id -> SceneDef
var items: Dictionary = {}       # id -> ItemDef
var chars: Dictionary = {}       # id -> CharDef
var clues: Dictionary = {}       # id -> ClueDef
var memories: Array[MemoryDef] = []
var dialogues: Array[DialogueDef] = []
var endings: Array[EndingDef] = []
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
	return unknown_nodes


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
	scenes.clear(); items.clear(); chars.clear(); clues.clear()
	for s in case_def.scenes:
		scenes[s.id] = s
	for it in case_def.items:
		items[it.id] = it
	for c in case_def.chars:
		chars[c.id] = c
	for cl in case_def.clues:
		clues[cl.id] = cl
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
	if p.begins_with("CLUES_") or p.begins_with("CLUE_") or p.begins_with("DATA_"):
		return "clue"
	return "data"


func scene_of(id: String) -> SceneDef:
	return scenes.get(id, null)


func item_of(id: String) -> ItemDef:
	return items.get(id, null)


func char_of(id: String) -> CharDef:
	return chars.get(id, null)


func clue_of(id: String) -> ClueDef:
	return clues.get(id, null)


## 按 kind 取实体（画布 kind = loc/item/char/clue）
func def_of(kind: String, id: String) -> Resource:
	match kind:
		"loc", "scene", "time":
			return scene_of(id)
		"item":
			return item_of(id)
		"char":
			return char_of(id)
		"clue", "data":
			return clue_of(id)
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
		"clue", "data":
			var cl := clue_of(id)
			return cl.label if cl != null else id
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
	_collect_ids(out, "clue", clues_s, clues, host_id)
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
