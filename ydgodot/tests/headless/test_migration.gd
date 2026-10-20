extends SceneTree
## P1.1 迁移回归：`.tres` 与 JSON **逐字段**对照（不是抽查几项，是把每个字段都归一化后整包比）。
## 运行：godot --headless --path ydgodot --script res://tests/headless/test_migration.gd

var fails := 0
var total := 0
var jd: Dictionary = {}
var c: CaseDef


func check(name: String, cond: bool, detail: String = "") -> void:
	total += 1
	if cond:
		print("  PASS  ", name)
	else:
		fails += 1
		print("  FAIL  ", name, ("  [" + detail + "]") if detail != "" else "")


func _initialize() -> void:
	print("=== P1.1 迁移回归（JSON ↔ Resource）===")
	var f := FileAccess.open("res://data/case-a001.json", FileAccess.READ)
	var j := JSON.new()
	j.parse(f.get_as_text())
	f.close()
	jd = j.data

	c = load("res://cases/a001/case.tres") as CaseDef
	check("case.tres 可加载", c != null)
	if c == null:
		quit(1)
		return

	check("实体数量一致（场景/物品/人物/线索/回忆/对话/结局）",
		c.scenes.size() == jd["scenes"].size() and c.items.size() == jd["items"].size()
		and c.chars.size() == jd["chars"].size() and c.clues.size() == jd["clues"].size()
		and c.memories.size() == jd["memories"].size() and c.dialogues.size() == jd["dialogues"].size()
		and c.endings.size() == jd["endings"].size(),
		"%d/%d/%d/%d/%d/%d/%d" % [c.scenes.size(), c.items.size(), c.chars.size(), c.clues.size(),
			c.memories.size(), c.dialogues.size(), c.endings.size()])

	var scenes := _by_id(c.scenes)
	var items := _by_id(c.items)
	var chars := _by_id(c.chars)
	var clues := _by_id(c.clues)
	var mems := _by_id(c.memories)
	var dlgs := _by_id(c.dialogues)
	var ends := _by_id(c.endings)

	# ── 配置 ──
	check("config.startScene 指向 SCENE_START", c.start_scene != null and c.start_scene.id == jd["config"]["startScene"])
	check("config.nowLabel 一致", c.now_label == jd["config"]["nowLabel"])
	check("config.reusableTools 一致",
		_ids(c.reusable_tools) == jd["config"]["reusableTools"], str(_ids(c.reusable_tools)))
	var want_mem = jd["config"].get("memoryScenes", ["SCENES_0602", "SCENES_0704"])
	check("config.memoryScenes 一致（缺省回退两天）",
		_ids(c.memory_scenes) == want_mem, str(_ids(c.memory_scenes)))

	# ── 逐类整包比对 ──
	var bad := 0
	for id in jd["scenes"]:
		var r: SceneDef = scenes.get(id)
		if r == null or not _eq(_norm_scene(r), _norm_scene_json(jd["scenes"][id])):
			bad += 1
			print("     ✗ scene ", id)
	check("场景 %d 个逐字段一致（含 hiddenClue）" % jd["scenes"].size(), bad == 0, "%d 个不一致" % bad)

	bad = 0
	for id in jd["items"]:
		var r: ItemDef = items.get(id)
		if r == null or not _eq(_norm_item(r), _norm_item_json(jd["items"][id])):
			bad += 1
			print("     ✗ item ", id)
	check("物品 %d 个逐字段一致（含六型命令 / 摘录 / 光照）" % jd["items"].size(), bad == 0, "%d 个不一致" % bad)

	bad = 0
	for id in jd["chars"]:
		var r: CharDef = chars.get(id)
		if r == null or not _eq(_norm_char(r), _norm_char_json(jd["chars"][id])):
			bad += 1
			print("     ✗ char ", id)
	check("人物 %d 个逐字段一致（含 talkQueue / sceneTalks / 反应表）" % jd["chars"].size(), bad == 0, "%d 个不一致" % bad)

	bad = 0
	for id in jd["clues"]:
		var r: ClueDef = clues.get(id)
		if r == null or r.label != jd["clues"][id]["label"] or r.sense != jd["clues"][id]["type"] \
			or r.desc != jd["clues"][id]["desc"]:
			bad += 1
			print("     ✗ clue ", id)
	check("线索 %d 个逐字段一致（含五感枚举）" % jd["clues"].size(), bad == 0, "%d 个不一致" % bad)

	bad = 0
	for m in jd["memories"]:
		var r: MemoryDef = mems.get(String(m["id"]))
		if r == null or not _eq(_norm_memory(r), _norm_memory_json(m)):
			bad += 1
			print("     ✗ memory ", m["id"])
	check("回忆 %d 段逐字段一致（when × where × who + 剧本）" % jd["memories"].size(), bad == 0, "%d 个不一致" % bad)

	bad = 0
	for d in jd["dialogues"]:
		var r: DialogueDef = dlgs.get(String(d["id"]))
		if r == null or not _eq(_norm_dialogue(r), _norm_dialogue_json(d)):
			bad += 1
			print("     ✗ dialogue ", d["id"])
	check("多人对话 %d 段逐字段一致（含参与人 / 上下文）" % jd["dialogues"].size(), bad == 0, "%d 个不一致" % bad)

	bad = 0
	for e in jd["endings"]:
		var r: EndingDef = ends.get(String(e["id"]))
		if r == null or not _eq(_norm_ending(r), _norm_ending_json(e)):
			bad += 1
			print("     ✗ ending ", e["id"])
	check("结局 %d 个逐字段一致（含五感配方 / 分幕）" % jd["endings"].size(), bad == 0, "%d 个不一致" % bad)

	# ── 引用完整性（Resource 化的核心收益）──
	var broken := []
	for it in c.items:
		for cmd in it.commands:
			if cmd is UseItemCommandDef:
				if cmd.required_item == null:
					broken.append("%s 的 useItem 缺 required_item" % it.id)
				for req in (cmd as UseItemCommandDef).requires:
					if req == null:
						broken.append("%s 的 requires 有 null" % it.id)
			elif cmd is ConditionalCommandDef:
				for cond in (cmd as ConditionalCommandDef).conditions:
					if cond.clue == null:
						broken.append("%s 的条件缺 clue" % it.id)
			elif cmd is RevealCommandDef:
				for x in (cmd as RevealCommandDef).items:
					if x == null:
						broken.append("%s 的 reveal items 有 null" % it.id)
	for e in c.endings:
		for r in e.recipe:
			if r == null:
				broken.append("%s 的配方有 null" % e.id)
	check("类型化引用无 null（配方 / 条件 / 零件 / 揭示）", broken.is_empty(), str(broken.slice(0, 3)))

	# ── 循环引用没被内联成副本 ──
	var chrono: ItemDef = items.get("ITEMS_changji")
	var same := false
	for cmd in chrono.commands:
		if cmd is UseItemCommandDef and (cmd as UseItemCommandDef).required_item != null \
			and (cmd as UseItemCommandDef).required_item.id == "ITEMS_wmhj":
			same = true
	check("跨实体引用指向同一资源（不是内联副本）", same)

	print("=== %d 项，失败 %d ===" % [total, fails])
	quit(0 if fails == 0 else 1)


# ── 归一化（两边用同一套形状，才能整包比）──────────────────────────────

func _by_id(list) -> Dictionary:
	var out := {}
	for r in list:
		out[String(r.get("id"))] = r
	return out


func _ids(list) -> Array:
	var out := []
	for r in list:
		out.append(String(r.get("id")))
	return out


func _eq(a, b) -> bool:
	return a == b          # Dictionary / Array 的 == 是深比较（不是比引用）


func _clue_ids(h) -> Array:
	var out := []
	if h != null:
		for r in h.clues:
			out.append(String(r.id))
	return out


func _norm_scene(r: SceneDef) -> Dictionary:
	return {"title": r.title, "content": r.content, "desc": r.desc, "canBePicked": r.can_be_picked,
		"hiddenText": (r.hidden_clue.text if r.hidden_clue != null else null),
		"hiddenIds": _clue_ids(r.hidden_clue)}


func _norm_scene_json(d: Dictionary) -> Dictionary:
	var h = d.get("hiddenClue", null)
	return {"title": String(d.get("title", "")), "content": String(d.get("content", "")),
		"desc": String(d.get("desc", "")), "canBePicked": bool(d.get("canBePicked", false)),
		"hiddenText": (String(h.get("text", "")) if h != null else null),
		"hiddenIds": (h.get("ids", []) if h != null else [])}


func _norm_item(r: ItemDef) -> Dictionary:
	var cmds := []
	for cmd in r.commands:
		cmds.append(_norm_cmd(cmd))
	var exs := []
	for e in r.excerpts:
		exs.append({"text": e.text,
			"to": ("loc:" + e.target_scene.id) if e.target_scene != null else ("char:" + e.target_char.id)})
	return {"label": r.label, "desc": r.desc, "content": r.content, "canBePicked": r.can_be_picked,
		"toggleLight": r.toggle_light, "needsLitToUse": r.needs_lit_to_use,
		"litOn": r.lit_on_message, "litOff": r.lit_off_message, "litFail": r.lit_fail_message,
		"commands": cmds, "excerpts": exs,
		"hiddenText": (r.hidden_clue.text if r.hidden_clue != null else null),
		"hiddenIds": _clue_ids(r.hidden_clue)}


func _norm_item_json(d: Dictionary) -> Dictionary:
	var cmds := []
	for cmd in d.get("commands", []):
		cmds.append(_norm_cmd_json(cmd))
	var exs := []
	for e in d.get("excerpts", []):
		exs.append({"text": String(e.get("text", "")), "to": String(e.get("to", ""))})
	var h = d.get("hiddenClue", null)
	return {"label": String(d.get("label", "")), "desc": String(d.get("desc", "")),
		"content": String(d.get("content", "")), "canBePicked": bool(d.get("canBePicked", false)),
		"toggleLight": bool(d.get("toggleLight", false)), "needsLitToUse": bool(d.get("needsLitToUse", false)),
		"litOn": String(d.get("litOnMessage", "")), "litOff": String(d.get("litOffMessage", "")),
		"litFail": String(d.get("litFailMessage", "")),
		"commands": cmds, "excerpts": exs,
		"hiddenText": (String(h.get("text", "")) if h != null else null),
		"hiddenIds": (h.get("ids", []) if h != null else [])}


func _norm_cmd(cmd: CommandDef) -> Dictionary:
	var base := {"label": cmd.label, "fail": cmd.fail_message, "lit": _ids(cmd.requires_lit)}
	if cmd is TextCommandDef:
		base["type"] = "text"
		base["value"] = (cmd as TextCommandDef).value
	elif cmd is ChoiceCommandDef:
		var cc := cmd as ChoiceCommandDef
		base["type"] = "choice"
		base["title"] = cc.title
		base["prompt"] = cc.prompt
		var opts := []
		for o in cc.options:
			opts.append({"label": o.label, "message": o.message, "results": _norm_payload(o.payload)})
		base["options"] = opts
	elif cmd is ConditionalCommandDef:
		var kc := cmd as ConditionalCommandDef
		base["type"] = "conditional"
		var conds := []
		for cnd in kc.conditions:
			conds.append({"clue": String(cnd.clue.id) if cnd.clue != null else "", "failMessage": cnd.fail_message})
		base["conditions"] = conds
		base["successMessage"] = kc.success_message
		base["onSuccess"] = _norm_payload(kc.on_success)
	elif cmd is UseItemCommandDef:
		var uc := cmd as UseItemCommandDef
		base["type"] = "useItem"
		base["requiredItem"] = String(uc.required_item.id) if uc.required_item != null else ""
		base["requires"] = _ids(uc.requires)
		base["installs"] = uc.installs
		base["successMessage"] = uc.success_message
		base["onSuccess"] = _norm_payload(uc.on_success)
	elif cmd is PasswordCommandDef:
		var pc := cmd as PasswordCommandDef
		base["type"] = "password"
		base["value"] = pc.value
		base["onSuccess"] = _norm_payload(pc.on_success)
	elif cmd is RevealCommandDef:
		var rc := cmd as RevealCommandDef
		base["type"] = "reveal"
		base["value"] = rc.value
		base["items"] = _ids(rc.items)
	return base


func _norm_cmd_json(d: Dictionary) -> Dictionary:
	var base := {"label": String(d.get("label", "")), "fail": String(d.get("failMessage", "")),
		"lit": d.get("requiresLit", []), "type": String(d.get("type", ""))}
	match String(d.get("type", "")):
		"text":
			base["value"] = String(d.get("value", ""))
		"choice":
			base["title"] = String(d.get("title", ""))
			base["prompt"] = String(d.get("prompt", ""))
			var opts := []
			for o in d.get("options", []):
				opts.append({"label": String(o.get("label", "")), "message": String(o.get("message", "")),
					"results": _norm_payload_json(o.get("results", null))})
			base["options"] = opts
		"conditional":
			var conds := []
			for cnd in d.get("conditions", []):
				conds.append({"clue": String(cnd.get("clue", "")), "failMessage": String(cnd.get("failMessage", ""))})
			base["conditions"] = conds
			base["successMessage"] = String(d.get("successMessage", ""))
			base["onSuccess"] = _norm_payload_json(d.get("onSuccess", null))
		"useItem":
			base["requiredItem"] = String(d.get("requiredItem", ""))
			base["requires"] = d.get("requires", [])
			base["installs"] = bool(d.get("installs", false))
			base["successMessage"] = String(d.get("successMessage", ""))
			base["onSuccess"] = _norm_payload_json(d.get("onSuccess", null))
		"password":
			base["value"] = String(d.get("value", ""))
			base["onSuccess"] = _norm_payload_json(d.get("onSuccess", null))
		"reveal":
			base["value"] = String(d.get("value", ""))
			base["items"] = d.get("items", [])
	return base


func _norm_payload(p) -> Variant:
	if p == null:
		return null
	return {"message": p.message, "scene": (String(p.scene.id) if p.scene != null else ""), "items": _ids(p.items)}


func _norm_payload_json(p) -> Variant:
	if p == null:
		return null
	return {"message": String(p.get("message", p.get("text", ""))),
		"scene": String(p.get("scene", "")), "items": p.get("items", [])}


func _norm_char(r: CharDef) -> Dictionary:
	var talks := {}
	for st in r.scene_talks:
		if st.scene != null:
			talks[st.scene.id] = st.lines
	var clue_re := {}
	for rec in r.clue_reactions:
		clue_re[rec.trigger_id] = rec.text
	var item_re := {}
	for rec in r.item_reactions:
		item_re[rec.trigger_id] = rec.text
	return {"name": r.name, "desc": r.desc, "avatar": r.avatar,
		"debut": (r.debut.id if r.debut != null else ""),
		"talkQueue": r.talk_queue, "sceneTalks": talks,
		"reactions": clue_re, "itemReactions": item_re}


func _d(v) -> Dictionary:
	return v if v is Dictionary else {}


func _norm_char_json(d: Dictionary) -> Dictionary:
	var talks := {}
	for sid in _d(d.get("sceneTalks")).keys():
		var lines := []
		for l in d["sceneTalks"][sid]:
			lines.append(String(l.get("text", "")))
		talks[sid] = lines
	var clue_re := {}
	for k in _d(d.get("reactions")).keys():
		clue_re[k] = String(d["reactions"][k].get("text", ""))
	var item_re := {}
	for k in _d(d.get("itemReactions")).keys():
		item_re[k] = String(d["itemReactions"][k].get("text", ""))
	var queue := []
	for l in d.get("talkQueue", []):
		queue.append(String(l.get("text", "")))
	return {"name": String(d.get("name", "")), "desc": String(d.get("desc", "")),
		"avatar": String(d.get("avatar", "")), "debut": String(d.get("debut", "")),
		"talkQueue": queue, "sceneTalks": talks, "reactions": clue_re, "itemReactions": item_re}


func _norm_memory(r: MemoryDef) -> Dictionary:
	var lines := []
	for l in r.script_lines:
		lines.append({"t": l.kind, "who": (l.who.id if l.who != null else ""), "text": l.text})
	return {"id": r.id, "when": (r.when.id if r.when != null else ""), "where": (r.where.id if r.where != null else ""),
		"who": (r.who.id if r.who != null else ""), "title": r.title, "script": lines}


func _norm_memory_json(d: Dictionary) -> Dictionary:
	var lines := []
	for l in d.get("script", []):
		lines.append({"t": String(l.get("t", "")), "who": String(l.get("who", "")), "text": String(l.get("text", ""))})
	return {"id": String(d.get("id", "")), "when": String(d.get("when", "")), "where": String(d.get("where", "")),
		"who": String(d.get("who", "")), "title": String(d.get("title", "")), "script": lines}


func _norm_dialogue(r: DialogueDef) -> Dictionary:
	var lines := []
	for l in r.script_lines:
		lines.append({"t": l.kind, "who": (l.who.id if l.who != null else ""), "text": l.text})
	return {"id": r.id, "participants": _ids(r.participants),
		"when": (r.context_when.id if r.context_when != null else ""),
		"where": (r.context_where.id if r.context_where != null else ""), "script": lines}


func _norm_dialogue_json(d: Dictionary) -> Dictionary:
	var lines := []
	for l in d.get("script", []):
		lines.append({"t": String(l.get("t", "")), "who": String(l.get("who", "")), "text": String(l.get("text", ""))})
	return {"id": String(d.get("id", "")), "participants": d.get("participants", []),
		"when": String(d.get("when", "")), "where": String(d.get("where", "")), "script": lines}


func _norm_ending(r: EndingDef) -> Dictionary:
	var lines := []
	for l in r.lines:
		lines.append({"text": l.text, "delay": l.delay_ms})
	return {"id": r.id, "name": r.name, "truename": r.truename, "recipe": _ids(r.recipe),
		"isTrueCapture": r.is_true_capture, "message": r.message, "lines": lines}


func _norm_ending_json(d: Dictionary) -> Dictionary:
	var lines := []
	for l in d.get("lines", []):
		lines.append({"text": String(l.get("text", "")), "delay": int(l.get("delay", 0))})
	return {"id": String(d.get("id", "")), "name": String(d.get("name", "")),
		"truename": String(d.get("truename", "")), "recipe": d.get("recipe", []),
		"isTrueCapture": bool(d.get("isTrueCapture", false)), "message": String(d.get("message", "")),
		"lines": lines}
