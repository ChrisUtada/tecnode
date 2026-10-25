extends SceneTree
## 旧「线索」→「证」的一次性数据迁移（幂等）。
##
## 迁移内容：
##   1. `cases/<id>/clues/*.tres` → `cases/<id>/evidence/*.tres`
##      （脚本 ClueDef → EvidenceDef，补 tier=zheng / origin=tec）
##   2. 全案 `.tres` 里的 `res://cases/*/clues/`、`core/defs/ClueDef.gd` 引用改到新路径；
##      删除废弃的 v1 `hidden_evidence` 行
##   3. `case.tres` 顶层 `clues` 数组合并进 `evidences`
##   4. `data/case-a001.json` 顶层 `clues` 合并进 `evidences`，删 `hiddenEvidence`
##
## 幂等：没有可迁移内容时所有计数为 0，且不写任何文件。
## 运行：godot --headless --path ydgodot --script res://tools/migrate_clues_to_evidence.gd

const ROOT := "res://cases"
const JSON_PATH := "res://data/case-a001.json"

var moved := 0
var patched := 0
var json_patched := 0
var notes: Array[String] = []


func _initialize() -> void:
	for case_dir in DirAccess.get_directories_at(ROOT):
		if case_dir.begins_with("."):
			continue
		_migrate_case(ROOT.path_join(case_dir))
	_migrate_json()
	print("migrate_clues_to_evidence: moved=%d patched=%d json=%d" % [moved, patched, json_patched])
	for n in notes:
		print("  - ", n)
	quit(0)


func _migrate_case(case_dir: String) -> void:
	var old_dir := case_dir.path_join("clues")
	var ev_dir := case_dir.path_join("evidence")
	if DirAccess.dir_exists_absolute(old_dir):
		DirAccess.make_dir_recursive_absolute(ev_dir)
		for f in DirAccess.get_files_at(old_dir):
			if not f.ends_with(".tres"):
				continue
			var src := old_dir.path_join(f)
			var text := _read(src)
			var converted := _convert_clue_resource(text)
			_write(ev_dir.path_join(f), converted)
			DirAccess.remove_absolute(src)
			moved += 1
			notes.append("迁移 %s → %s" % [src, ev_dir.path_join(f)])
		DirAccess.remove_absolute(old_dir)
	for p in _all_tres(case_dir):
		var text := _read(p)
		var out := _patch_refs(text)
		if p.get_file() == "case.tres":
			out = _merge_case_clues(out)
		if out != text:
			_write(p, out)
			patched += 1
			notes.append("改写 " + p)


func _convert_clue_resource(text: String) -> String:
	var out := _patch_refs(text)
	## 旧 ClueDef 已带 sense；缺 tier / origin 时补默认值。
	if not RegEx.create_from_string("(?m)^tier = ").search(out):
		out = _insert_resource_prop(out, "tier = \"zheng\"")
	if not RegEx.create_from_string("(?m)^origin = ").search(out):
		out = _insert_resource_prop(out, "origin = \"tec\"")
	if not RegEx.create_from_string("(?m)^sense = ").search(out):
		out = _insert_resource_prop(out, "sense = \"vision\"")
	return out


func _insert_resource_prop(text: String, prop: String) -> String:
	var tag := "[resource]\n"
	var at := text.find(tag)
	return text if at < 0 else text.insert(at + tag.length(), prop + "\n")


func _patch_refs(text: String) -> String:
	var out := text.replace("script_class=\"ClueDef\"", "script_class=\"EvidenceDef\"")
	out = out.replace("res://core/defs/ClueDef.gd", "res://core/defs/EvidenceDef.gd")
	out = out.replace("/clues/", "/evidence/")
	## v1 的物证卡通道已废除：物品 / 场景上的 hidden_evidence 不再存在。
	var keep: Array[String] = []
	for line in out.split("\n"):
		if line.begins_with("hidden_evidence = "):
			continue
		keep.append(line)
	return "\n".join(keep)


func _merge_case_clues(text: String) -> String:
	var clue_re := RegEx.create_from_string("(?m)^clues = Array\\[[^\\]]*\\]\\(\\[([^\\]]*)\\]\\)\\n?")
	var clue_m := clue_re.search(text)
	if clue_m == null:
		return text
	var clue_refs := _refs(clue_m.get_string(1))
	var ev_re := RegEx.create_from_string("(?m)^evidences = Array\\[[^\\]]*\\]\\(\\[([^\\]]*)\\]\\)")
	var ev_m := ev_re.search(text)
	if ev_m == null:
		## 只有旧数组：原地改名即可，类型 ExtResource 已由 _patch_refs 改成 EvidenceDef。
		return clue_re.sub(text, "evidences = Array[" + _array_type(clue_m.get_string(0)) + "](["
			+ ", ".join(clue_refs) + "])\n", true)
	var merged := _refs(ev_m.get_string(1))
	for r in clue_refs:
		if not merged.has(r):
			merged.append(r)
	var ev_line := "evidences = Array[" + _array_type(ev_m.get_string(0)) + "]([" \
		+ ", ".join(merged) + "])"
	var out := ev_re.sub(text, ev_line, true)
	## 删掉旧 clues 行；用同上正则再匹配一次，避免手算区间。
	return clue_re.sub(out, "", true)


func _array_type(line: String) -> String:
	var m := RegEx.create_from_string("Array\\[([^\\]]*)\\]").search(line)
	return m.get_string(1) if m != null else "ExtResource(\"evd_script\")"


func _refs(inner: String) -> Array[String]:
	var out: Array[String] = []
	for raw in inner.split(","):
		var t := raw.strip_edges()
		if t != "" and not out.has(t):
			out.append(t)
	return out


func _all_tres(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir_path):
		if f.ends_with(".tres"):
			out.append(dir_path.path_join(f))
	for d in DirAccess.get_directories_at(dir_path):
		if d.begins_with("."):
			continue
		out.append_array(_all_tres(dir_path.path_join(d)))
	return out


func _migrate_json() -> void:
	if not FileAccess.file_exists(JSON_PATH):
		return
	var f := FileAccess.open(JSON_PATH, FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		return
	var d: Dictionary = data
	var touched := false
	var evidences: Dictionary = d.get("evidences", {})
	var old_clues: Dictionary = d.get("clues", {})
	for cid in old_clues.keys():
		if not evidences.has(cid):
			var raw: Dictionary = old_clues[cid]
			evidences[cid] = {
				"label": String(raw.get("label", "")),
				"tier": "zheng",
				"sense": String(raw.get("type", "vision")),
				"origin": "tec",
				"desc": String(raw.get("desc", "")),
				"sourceText": "TEC 分析所得。",
			}
		touched = true
	if d.has("clues"):
		d.erase("clues")
		touched = true
	if not evidences.is_empty():
		d["evidences"] = evidences
	for it in (d.get("items", {}) as Dictionary).values():
		if it is Dictionary and (it as Dictionary).has("hiddenEvidence"):
			(it as Dictionary).erase("hiddenEvidence")
			touched = true
	if not touched:
		return
	var out := FileAccess.open(JSON_PATH, FileAccess.WRITE)
	out.store_string(JSON.stringify(d, "  ", false) + "\n")
	out.close()
	json_patched += 1
	notes.append("改写 " + JSON_PATH)


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	var s := f.get_as_text() if f != null else ""
	if f != null:
		f.close()
	return s


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("写不了 " + path)
		return
	f.store_string(text)
	f.close()
