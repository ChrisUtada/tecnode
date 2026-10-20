extends SceneTree
## 一次性迁移：data/case-a001.json → cases/a001/**/*.tres（P1.1）
##
## 运行：
##   godot --headless --path ydgodot --script res://tools/json_to_tres.gd
##
## 两趟走：
##   ① 给每个实体建「壳」并**先写好 resource_path** —— 之后互相引用才会落成 ExtResource，
##      而不是把对方整份内联进来（items ↔ chars 有环：人物的 itemReactions 指物品，
##      物品的命令又指人物会说的话）。
##   ② 再逐字段填值、按 id 解析引用；解析不到就记进报告（不静默降级）。
##
## ⚠ 所有 `Array[Type]` 属性必须用**元素类型已声明**的数组赋值，普通 Array 会报
##    "Invalid assignment ... with value of type 'Array'"。所以下面有一组 _xx_refs() 小工具。
##
## 产出：`docs/migration_report.md`（实体数 / 引用数 / 悬空引用 / 文本指纹）。

const JSON_PATH := "res://data/case-a001.json"
const OUT_ROOT := "res://cases/a001"
const REPORT := "res://docs/migration_report.md"

var data: Dictionary = {}
var idx: Dictionary = {}          # id -> Resource
var refs_ok := 0
var refs_missing: Array = []
var type_counts: Dictionary = {}  # 类名 -> 数量
var text_blobs: Dictionary = {}   # 类名 -> 拼接文本（用于指纹）
var saved_count := 0
var save_errors: Array = []
var data_issues: Array = []      # 数据自身的问题（不是迁移错误）：指向不存在的实体


func _initialize() -> void:
	if not _load_json():
		quit(1)
		return
	_clean_old()
	_make_shells()
	_fill_all()
	_write_all()
	_write_report()
	print("迁移完成：写出 %d 个 .tres，引用解析 %d 条，悬空 %d 条" % [saved_count, refs_ok, refs_missing.size()])
	quit(0 if refs_missing.is_empty() and save_errors.is_empty() else 2)


# ── 读入 ────────────────────────────────────────────────────────────────

func _load_json() -> bool:
	var f := FileAccess.open(JSON_PATH, FileAccess.READ)
	if f == null:
		push_error("打不开 " + JSON_PATH)
		return false
	var j := JSON.new()
	var err := j.parse(f.get_as_text())
	f.close()
	if err != OK:
		push_error("JSON 解析失败：%s" % j.get_error_message())
		return false
	data = j.data
	return true


func _clean_old() -> void:
	for sub in ["scenes", "items", "chars", "clues", "memories", "dialogues", "endings"]:
		var dir_path: String = OUT_ROOT + "/" + sub
		DirAccess.make_dir_recursive_absolute(dir_path)
		var d: DirAccess = DirAccess.open(dir_path)
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(".tres"):
				d.remove(f)


# ── ① 壳 ────────────────────────────────────────────────────────────────

func _shell(script_path: String, id: String, subdir: String) -> void:
	var s: GDScript = load(script_path)
	var r: Resource = s.new()
	r.set("id", id)
	r.resource_path = "%s/%s/%s.tres" % [OUT_ROOT, subdir, id]
	idx[id] = r


func _make_shells() -> void:
	for id in data["scenes"].keys():
		_shell("res://core/defs/SceneDef.gd", id, "scenes")
	for id in data["items"].keys():
		_shell("res://core/defs/ItemDef.gd", id, "items")
	for id in data["chars"].keys():
		_shell("res://core/defs/CharDef.gd", id, "chars")
	for id in data["clues"].keys():
		_shell("res://core/defs/ClueDef.gd", id, "clues")
	for m in data["memories"]:
		_shell("res://core/defs/MemoryDef.gd", String(m["id"]), "memories")
	for d in data["dialogues"]:
		_shell("res://core/defs/DialogueDef.gd", String(d["id"]), "dialogues")
	for e in data["endings"]:
		_shell("res://core/defs/EndingDef.gd", String(e["id"]), "endings")


# ── ② 引用解析 ──────────────────────────────────────────────────────────

func _ref(id: String, expect := "") -> Resource:
	if id == "":
		return null
	var r: Resource = idx.get(id, null)
	if r == null:
		refs_missing.append("%s（期望 %s）" % [id, expect])
		return null
	if expect != "" and not _is_type(r, expect):
		refs_missing.append("%s 期望 %s，实际 %s" % [id, expect, r.get_script().get_global_name()])
		return null
	refs_ok += 1
	return r


func _dict(v) -> Dictionary:
	return v if v is Dictionary else {}


func _is_type(r: Resource, script_name: String) -> bool:
	var s: Script = r.get_script()
	return s != null and String(s.get_global_name()) == script_name


func _clue_refs(ids) -> Array[ClueDef]:
	var out: Array[ClueDef] = []
	for id in (ids if ids != null else []):
		var r := _ref(String(id), "ClueDef")
		if r != null:
			out.append(r)
	return out


func _item_refs(ids) -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	for id in (ids if ids != null else []):
		var r := _ref(String(id), "ItemDef")
		if r != null:
			out.append(r)
	return out


func _char_refs(ids) -> Array[CharDef]:
	var out: Array[CharDef] = []
	for id in (ids if ids != null else []):
		var r := _ref(String(id), "CharDef")
		if r != null:
			out.append(r)
	return out


func _str_list(rows) -> Array[String]:
	var out: Array[String] = []
	for row in (rows if rows != null else []):
		if row is Dictionary:
			out.append(String(row.get("text", "")))
		else:
			out.append(String(row))
	return out


# ── ② 填值 ──────────────────────────────────────────────────────────────

func _fill_all() -> void:
	for id in data["scenes"].keys():
		_fill_scene(idx[id], data["scenes"][id])
	for id in data["items"].keys():
		_fill_item(idx[id], data["items"][id])
	for id in data["chars"].keys():
		_fill_char(idx[id], data["chars"][id])
	for id in data["clues"].keys():
		_fill_clue(idx[id], data["clues"][id])
	for m in data["memories"]:
		_fill_memory(idx[String(m["id"])], m)
	for d in data["dialogues"]:
		_fill_dialogue(idx[String(d["id"])], d)
	for e in data["endings"]:
		_fill_ending(idx[String(e["id"])], e)


func _fill_scene(r: Resource, d: Dictionary) -> void:
	r.set("title", String(d.get("title", "")))
	r.set("content", String(d.get("content", "")))
	r.set("desc", String(d.get("desc", "")))
	r.set("image", String(d.get("image", "")))
	r.set("can_be_picked", bool(d.get("canBePicked", false)))
	r.set("hidden_clue", _hidden(d.get("hiddenClue", null)))


func _fill_item(r: Resource, d: Dictionary) -> void:
	r.set("label", String(d.get("label", "")))
	r.set("desc", String(d.get("desc", "")))
	r.set("content", String(d.get("content", "")))
	r.set("can_be_picked", bool(d.get("canBePicked", false)))
	r.set("toggle_light", bool(d.get("toggleLight", false)))
	r.set("needs_lit_to_use", bool(d.get("needsLitToUse", false)))
	r.set("lit_on_message", String(d.get("litOnMessage", "")))
	r.set("lit_off_message", String(d.get("litOffMessage", "")))
	r.set("lit_fail_message", String(d.get("litFailMessage", "")))
	r.set("hidden_clue", _hidden(d.get("hiddenClue", null)))

	var cmds: Array[CommandDef] = []
	for c in d.get("commands", []):
		var cmd := _command(c)
		if cmd != null:
			cmds.append(cmd)
	r.set("commands", cmds)

	var exs: Array[ExcerptDef] = []
	for e in d.get("excerpts", []):
		var ex := ExcerptDef.new()
		ex.text = String(e.get("text", ""))
		var to := String(e.get("to", ""))
		if to.begins_with("loc:"):
			ex.target_scene = _ref(to.substr(4), "SceneDef") as SceneDef
		elif to.begins_with("char:"):
			ex.target_char = _ref(to.substr(5), "CharDef") as CharDef
		else:
			refs_missing.append("摘录目标写法看不懂：" + to)
		exs.append(ex)
	r.set("excerpts", exs)


func _fill_char(r: Resource, d: Dictionary) -> void:
	r.set("name", String(d.get("name", "")))
	r.set("desc", String(d.get("desc", "")))
	r.set("avatar", String(d.get("avatar", "")))
	if d.get("debut", null) != null:
		r.set("debut", _ref(String(d["debut"]), "SceneDef") as SceneDef)
	r.set("talk_queue", _str_list(d.get("talkQueue", [])))

	var talks: Array[SceneTalkDef] = []
	var raw_talks: Dictionary = _dict(d.get("sceneTalks"))
	for sid in raw_talks.keys():
		var st := SceneTalkDef.new()
		st.scene = _ref(String(sid), "SceneDef") as SceneDef
		st.lines = _str_list(raw_talks[sid])
		talks.append(st)
	r.set("scene_talks", talks)
	r.set("clue_reactions", _reactions(_dict(d.get("reactions")), "clue"))
	r.set("item_reactions", _reactions(_dict(d.get("itemReactions")), "item"))
	r.set("hidden_clue", _hidden(d.get("hiddenClue", null)))


func _reactions(map: Dictionary, kind: String) -> Array[ReactionDef]:
	var out: Array[ReactionDef] = []
	for key in map.keys():
		var rec := ReactionDef.new()
		rec.trigger_id = String(key)
		var target: Resource = idx.get(String(key), null)
		if target == null:
			data_issues.append("%s 反应表指向不存在的实体 `%s`（Web 版同样永不触发；已保留 trigger_id）" % [kind, key])
		else:
			refs_ok += 1
			if kind == "clue" and _is_type(target, "ClueDef"):
				rec.clue = target as ClueDef
			elif kind == "item" and _is_type(target, "ItemDef"):
				rec.item = target as ItemDef
			else:
				refs_missing.append("%s 类型不符（%s 反应表）" % [key, kind])
		rec.text = String((map[key] as Dictionary).get("text", ""))
		out.append(rec)
	return out


func _fill_clue(r: Resource, d: Dictionary) -> void:
	r.set("label", String(d.get("label", "")))
	r.set("sense", String(d.get("type", "vision")))
	r.set("desc", String(d.get("desc", "")))


func _fill_memory(r: Resource, d: Dictionary) -> void:
	r.set("when", _ref(String(d.get("when", "")), "SceneDef") as SceneDef)
	r.set("where", _ref(String(d.get("where", "")), "SceneDef") as SceneDef)
	r.set("who", _ref(String(d.get("who", "")), "CharDef") as CharDef)
	r.set("title", String(d.get("title", "")))
	r.set("script_lines", _script(d.get("script", [])))


func _fill_dialogue(r: Resource, d: Dictionary) -> void:
	r.set("participants", _char_refs(d.get("participants", [])))
	if d.get("when", null) != null:
		r.set("context_when", _ref(String(d["when"]), "SceneDef") as SceneDef)
	if d.get("where", null) != null:
		r.set("context_where", _ref(String(d["where"]), "SceneDef") as SceneDef)
	r.set("script_lines", _script(d.get("script", [])))


func _fill_ending(r: Resource, d: Dictionary) -> void:
	r.set("name", String(d.get("name", "")))
	r.set("truename", String(d.get("truename", "")))
	r.set("recipe", _clue_refs(d.get("recipe", [])))
	r.set("is_true_capture", bool(d.get("isTrueCapture", false)))
	r.set("message", String(d.get("message", "")))
	var lines: Array[EndingLineDef] = []
	for l in d.get("lines", []):
		var el := EndingLineDef.new()
		el.text = String(l.get("text", ""))
		el.delay_ms = int(l.get("delay", 500))
		lines.append(el)
	r.set("lines", lines)


func _script(rows) -> Array[DialogueLineDef]:
	var out: Array[DialogueLineDef] = []
	for row in (rows if rows != null else []):
		var line := DialogueLineDef.new()
		line.kind = String(row.get("t", "narr"))
		line.text = String(row.get("text", ""))
		if row.get("who", null) != null:
			line.who = _ref(String(row["who"]), "CharDef") as CharDef
		out.append(line)
	return out


func _hidden(h) -> HiddenClueDef:
	if h == null:
		return null
	var hc := HiddenClueDef.new()
	hc.text = String(h.get("text", ""))
	hc.clues = _clue_refs(h.get("ids", []))
	return hc


func _command(c: Dictionary) -> CommandDef:
	var t := String(c.get("type", ""))
	var cmd: CommandDef
	match t:
		"text":
			var tc := TextCommandDef.new()
			tc.value = String(c.get("value", ""))
			cmd = tc
		"choice":
			var cc := ChoiceCommandDef.new()
			cc.title = String(c.get("title", ""))
			cc.prompt = String(c.get("prompt", ""))
			var opts: Array[ChoiceOptionDef] = []
			for o in c.get("options", []):
				var opt := ChoiceOptionDef.new()
				opt.label = String(o.get("label", ""))
				opt.message = String(o.get("message", ""))
				opt.payload = _payload(o.get("results", null), String(o.get("message", "")))
				opts.append(opt)
			cc.options = opts
			cmd = cc
		"conditional":
			var cond_cmd := ConditionalCommandDef.new()
			var conds: Array[ConditionDef] = []
			for cond in c.get("conditions", []):
				var cd := ConditionDef.new()
				cd.clue = _ref(String(cond.get("clue", "")), "ClueDef") as ClueDef
				cd.fail_message = String(cond.get("failMessage", ""))
				conds.append(cd)
			cond_cmd.conditions = conds
			cond_cmd.success_message = String(c.get("successMessage", ""))
			cond_cmd.on_success = _payload(c.get("onSuccess", null))
			cmd = cond_cmd
		"useItem":
			var uc := UseItemCommandDef.new()
			uc.required_item = _ref(String(c.get("requiredItem", "")), "ItemDef") as ItemDef
			uc.requires = _item_refs(c.get("requires", []))
			uc.installs = bool(c.get("installs", false))
			uc.success_message = String(c.get("successMessage", ""))
			uc.on_success = _payload(c.get("onSuccess", null))
			cmd = uc
		"password":
			var pc := PasswordCommandDef.new()
			pc.value = String(c.get("value", ""))
			pc.on_success = _payload(c.get("onSuccess", null))
			cmd = pc
		"reveal":
			var rc := RevealCommandDef.new()
			rc.value = String(c.get("value", ""))
			rc.items = _item_refs(c.get("items", []))
			cmd = rc
		_:
			refs_missing.append("未知命令类型：" + t)
			return null
	cmd.label = String(c.get("label", ""))
	cmd.fail_message = String(c.get("failMessage", ""))
	cmd.requires_lit = _item_refs(c.get("requiresLit", []))
	return cmd


func _payload(p, fallback_message := "") -> PayloadDef:
	if p == null or (p is Dictionary and (p as Dictionary).is_empty()):
		return null
	var pay := PayloadDef.new()
	pay.message = String(p.get("message", String(p.get("text", fallback_message))))
	if p.get("scene", null) != null:
		pay.scene = _ref(String(p["scene"]), "SceneDef") as SceneDef
	pay.items = _item_refs(p.get("items", []))
	return pay


# ── 写盘 ────────────────────────────────────────────────────────────────

func _write_all() -> void:
	var case_def := CaseDef.new()
	case_def.id = "a001"
	case_def.title = "植物学家的花园"
	var cfg: Dictionary = _dict(data.get("config"))
	case_def.now_label = String(cfg.get("nowLabel", ""))
	case_def.start_scene = _ref(String(cfg.get("startScene", "")), "SceneDef") as SceneDef
	case_def.reusable_tools = _item_refs(cfg.get("reusableTools", []))

	# 先按类名分组（同时算文本指纹）
	var by_class := {}
	for id in idx.keys():
		var r: Resource = idx[id]
		var cn := String(r.get_script().get_global_name())
		if not by_class.has(cn):
			by_class[cn] = []
		(by_class[cn] as Array).append(r)
		text_blobs[cn] = String(text_blobs.get(cn, "")) + _blob_of(r, cn)

	var scenes: Array[SceneDef] = []
	var items: Array[ItemDef] = []
	var chars: Array[CharDef] = []
	var clues: Array[ClueDef] = []
	var mems: Array[MemoryDef] = []
	var dlgs: Array[DialogueDef] = []
	var ends: Array[EndingDef] = []
	_fill_typed(scenes, by_class.get("SceneDef", []))
	_fill_typed(items, by_class.get("ItemDef", []))
	_fill_typed(chars, by_class.get("CharDef", []))
	_fill_typed(clues, by_class.get("ClueDef", []))
	_fill_typed(mems, by_class.get("MemoryDef", []))
	_fill_typed(dlgs, by_class.get("DialogueDef", []))
	_fill_typed(ends, by_class.get("EndingDef", []))
	case_def.scenes = scenes
	case_def.items = items
	case_def.chars = chars
	case_def.clues = clues
	case_def.memories = mems
	case_def.dialogues = dlgs
	case_def.endings = ends
	var memory_ids = cfg.get("memoryScenes", ["SCENES_0602", "SCENES_0704"])
	var memory_refs: Array[SceneDef] = []
	for mid in (memory_ids if memory_ids != null else []):
		var ms := _ref(String(mid), "SceneDef") as SceneDef
		if ms != null:
			memory_refs.append(ms)
	case_def.memory_scenes = memory_refs
	type_counts = {
		"SceneDef": scenes.size(), "ItemDef": items.size(), "CharDef": chars.size(),
		"ClueDef": clues.size(), "MemoryDef": mems.size(), "DialogueDef": dlgs.size(),
		"EndingDef": ends.size(),
	}

	for id in idx.keys():
		var r: Resource = idx[id]
		var err := ResourceSaver.save(r, r.resource_path)
		if err != OK:
			save_errors.append("%s（错误 %d）" % [r.resource_path, err])
		else:
			saved_count += 1

	case_def.resource_path = OUT_ROOT + "/case.tres"
	var e2 := ResourceSaver.save(case_def, case_def.resource_path)
	if e2 != OK:
		save_errors.append("%s（错误 %d）" % [case_def.resource_path, e2])
	else:
		saved_count += 1


## 往「元素类型已声明」的数组里填（普通 Array 不能直接赋给 Array[X]）
func _fill_typed(dst: Array, src: Array) -> void:
	var sorted_list: Array = src.duplicate()
	sorted_list.sort_custom(func(a, b): return String(a.get("id")) < String(b.get("id")))
	for r in sorted_list:
		dst.append(r)


## 指纹用的文本块：每类挑「正文类」字段拼起来（改一个字指纹就变）
func _blob_of(r: Resource, cls: String) -> String:
	match cls:
		"SceneDef":
			return "%s\u0001%s\u0001%s" % [r.get("title"), r.get("content"), r.get("desc")]
		"ItemDef":
			return "%s\u0001%s\u0001%s" % [r.get("label"), r.get("desc"), r.get("content")]
		"CharDef":
			return "%s\u0001%s" % [r.get("name"), r.get("desc")]
		"ClueDef":
			return "%s\u0001%s" % [r.get("label"), r.get("desc")]
		"MemoryDef":
			return String(r.get("title"))
		"EndingDef":
			return "%s\u0001%s" % [r.get("name"), r.get("message")]
	return String(r.get("id"))


# ── 报告 ────────────────────────────────────────────────────────────────

func _write_report() -> void:
	var lines: Array = []
	lines.append("# 迁移对照报告（JSON → Resource）\n")
	lines.append("> 由 `tools/json_to_tres.gd` 生成，勿手改。\n")
	lines.append("## 实体数量\n")
	lines.append("| 类型 | 数量 |")
	lines.append("|---|---|")
	var tks: Array = type_counts.keys()
	tks.sort()
	for k in tks:
		lines.append("| %s | %d |" % [k, type_counts[k]])
	lines.append("")
	lines.append("## 写盘\n")
	lines.append("- 成功写出 `.tres`：**%d** 个（含 `cases/a001/case.tres` 索引）" % saved_count)
	lines.append("- 写盘失败：**%d** 个" % save_errors.size())
	for e in save_errors:
		lines.append("  - ❌ " + String(e))
	lines.append("")
	lines.append("## 引用解析\n")
	lines.append("- 成功解析：**%d** 条" % refs_ok)
	lines.append("- 悬空 / 类型不符：**%d** 条" % refs_missing.size())
	for m in refs_missing:
		lines.append("  - ❌ " + String(m))
	lines.append("")
	lines.append("## 数据自身的问题（非迁移错误）\n")
	if data_issues.is_empty():
		lines.append("无。")
	else:
		for d in data_issues:
			lines.append("- ⚠ " + String(d))
	lines.append("")
	lines.append("## 文本指纹（逐类拼接后 sha256，迁移前后应一致）\n")
	var keys: Array = text_blobs.keys()
	keys.sort()
	for k in keys:
		lines.append("- `%s`：`%s`" % [k, String(text_blobs[k]).sha256_text()])
	lines.append("")
	var f := FileAccess.open(REPORT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines))
		f.close()
	print("报告写入 ", REPORT)
