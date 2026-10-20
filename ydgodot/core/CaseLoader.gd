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
	return true


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
				summary = strip_tags(line.text)
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
		return strip_tags(s.content if s != null else "")
	var it := item_of(id)
	return strip_tags(it.desc if it != null else "")


func strip_tags(raw: String) -> String:
	var s := raw.replace("<br>", "\n").replace("<br/>", "\n").replace("<br />", "\n")
	var re := RegEx.new()
	re.compile("\\[(item|loc|char|clue|data):([^\\]]+)\\]")
	var out := ""
	var last := 0
	for m in re.search_all(s):
		out += s.substr(last, m.get_start() - last)
		out += label_of(_tag_kind(m.get_string(1)), m.get_string(2))
		last = m.get_end()
	out += s.substr(last)
	return out


## 提取正文标签（去重、保序）—— 揭示场景时用它决定长出哪些节点
func tags_of(raw: String) -> Array:
	var re := RegEx.new()
	re.compile("\\[(item|loc|char|clue|data):([^\\]]+)\\]")
	var seen := {}
	var out: Array = []
	for m in re.search_all(raw):
		var id := m.get_string(2)
		if not seen.has(id):
			seen[id] = true
			out.append({"kind": _tag_kind(m.get_string(1)), "id": id})
	return out


## 正文标签的前缀就是权威 kind（NPC_FB 这类 id 不带 CHARS_ 前缀，不能靠 id 猜）。
static func _tag_kind(prefix: String) -> String:
	if prefix == "scene":
		return "loc"
	return prefix
