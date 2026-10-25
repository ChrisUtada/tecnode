extends SceneTree
## 一次性迁移：把「正文标签」冻结成资源上的节点清单（node_items / node_chars /
## node_locs / node_clues，全部是 id 字符串）。
##
## 为什么要有这趟：节点原先从 `content` 里的 `[item:X]` 现推，正文一改写（哪怕只是润色、
## 把标签删干净）画布上就什么都不长了。迁移之后**正文只负责文字**，节点归属只在
## Godot 检查器里维护。
##
## 源：`res://data/case-a001.json` —— 冻结档案，标签还完整（包括后来被改写掉的正文）。
## 目标：`cases/a001/scenes/*.tres`、`cases/a001/items/*.tres`
##
## 运行：
##   godot --headless --path ydgodot --script res://tools/migrate_node_lists.gd
##
## ⚠ 只会覆盖那四栏，正文与其它字段原样保留（load → 改四栏 → save）。
## ⚠ 存 id 而不是资源引用：地点之间本来就互通，`node_locs` 必然双向；实测 `.tres`
##    与 `.res` 冷启动都不支持环（"referenced non-existent resource"）。但检查器里不用
##    手打 id —— `addons/case_nodes/` 把四栏渲染成资源选择列表。

const JSON_PATH := "res://data/case-a001.json"
const CASE_PATH := "res://cases/a001/case.tres"

var data: Dictionary = {}
var case_def: CaseDef = null
var tag_re: RegEx
var missing: Array = []
var report: Array = []


func _initialize() -> void:
	if not _load_json():
		quit(1)
		return
	tag_re = RegEx.new()
	tag_re.compile("\\[(item|loc|char|clue|data):([^\\]]+)\\]")
	case_def = load(CASE_PATH) as CaseDef
	if case_def == null:
		push_error("加载不了 " + CASE_PATH)
		quit(1)
		return

	for s in case_def.scenes:
		var d: Dictionary = data.get("scenes", {}).get(s.id, {})
		if d.is_empty():
			continue
		_fill(s, String(d.get("content", "")), "scene", s.id)
	for it in case_def.items:
		var d: Dictionary = data.get("items", {}).get(it.id, {})
		if d.is_empty():
			continue
		var raw := String(d.get("content", ""))
		if raw == "":
			continue
		_fill(it, raw, "item", it.id)

	print("\n=== 迁移报告 ===")
	for line in report:
		print("  ", line)
	print("  悬空标签：" + ("无" if missing.is_empty() else str(missing)))
	print("=== 完成：%d 个容器写了节点清单 ===" % report.size())
	quit(0)


func _load_json() -> bool:
	var f := FileAccess.open(JSON_PATH, FileAccess.READ)
	if f == null:
		push_error("打不开 " + JSON_PATH)
		return false
	var j: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (j is Dictionary):
		push_error("JSON 解析失败")
		return false
	data = j
	return true


func _fill(res: Resource, raw: String, host_kind: String, id: String) -> void:
	var items := PackedStringArray()
	var chars := PackedStringArray()
	var locs := PackedStringArray()
	var clues := PackedStringArray()
	for m in tag_re.search_all(raw):
		var k := String(m.get_string(1))
		if k == "scene":
			k = "loc"
		var tid := String(m.get_string(2))
		if k == "char" and tid == "CHARS_TEC":
			continue                      # TEC 是常驻对话方，不上画布（与旧行为一致）
		match k:
			"item":
				if _has_item(tid):
					items.append(tid)
				else:
					missing.append("%s → item:%s" % [id, tid])
			"char":
				if _has_char(tid):
					chars.append(tid)
				else:
					missing.append("%s → char:%s" % [id, tid])
			"loc":
				if _has_scene(tid):
					locs.append(tid)
				else:
					missing.append("%s → loc:%s" % [id, tid])
			"clue", "data":
				if _has_clue(tid):
					clues.append(tid)
				else:
					missing.append("%s → clue:%s" % [id, tid])

	res.node_items = items
	res.node_chars = chars
	res.node_locs = locs
	res.node_clues = clues
	var save_path: String = res.resource_path
	if save_path == "":
		missing.append("%s 没有 resource_path，跳过保存" % id)
		return
	var err := ResourceSaver.save(res, save_path)
	report.append("%-22s %-6s item×%d char×%d loc×%d clue×%d%s" % [
		id, host_kind, items.size(), chars.size(), locs.size(), clues.size(),
		"" if err == OK else "  ⚠ 保存失败 %d" % err])


func _has_item(id: String) -> bool:
	for it in case_def.items:
		if it.id == id:
			return true
	return false


func _has_char(id: String) -> bool:
	for c in case_def.chars:
		if c.id == id:
			return true
	return false


func _has_scene(id: String) -> bool:
	for s in case_def.scenes:
		if s.id == id:
			return true
	return false


func _has_clue(id: String) -> bool:
	for c in case_def.clues:
		if c.id == id:
			return true
	return false
