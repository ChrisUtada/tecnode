class_name DetailWin
extends SysWindow
## 节点详情窗（Web `#detail-win` 的 Godot 版）。
##
## **只有三种内容：简介 / 状态 / 来源。** 刻意不列「容器里装着什么」「谁指向它」「它跟谁有反应」
## —— 那些正是玩家该自己动手（展开 / 组合 / 拖给 TEC）试出来的东西，写在这里等于直接递答案。
## 唯一例外是「状态」里的**使用条件**（要光 / 要零件 / 开关与否）：那是防瞎试的前馈。
##
## 位置与 Web 一致：右上角（right 14 / top 60），宽 300，正文 13px / 行高 1.7。

signal renarr_scene(id: String)
signal renarr_talk(key: String)
signal play_monologue(char_id: String)
signal play_music()

const W := 300.0
const PAD_R := 14.0
const TOP := 60.0

var _graph: GraphState
var _case: CaseLoader
var _key := ""
var _sig := ""
var _rows: VBoxContainer
var _head: Label
var _meta: Label


func setup_detail(p_graph: GraphState, p_case: CaseLoader) -> void:
	_graph = p_graph
	_case = p_case
	setup("节点详情", W, 260)
	position = Vector2(1280.0 - PAD_R - W - SysWindow.PAD, TOP)
	closed.connect(hide)
	_rows = VBoxContainer.new()
	_rows.name = "rows"
	_rows.add_theme_constant_override("separation", 6)
	_rows.custom_minimum_size = Vector2(W - 24.0 - 24.0, 0)
	content.add_child(_rows)


## 选中变化 / 图状态变化都调这里；内容逐字没变就不重建（免得滚动位置跳回顶部）
func show_node(key: String) -> void:
	_key = key
	refresh()


func current_key() -> String:
	return _key


func refresh() -> void:
	if _graph == null or _rows == null:
		return
	var n: Dictionary = _graph.node(_key)
	if n.is_empty():
		hide()
		return
	show()
	var html := _compose(n)
	if html == _sig:
		return
	_sig = html
	_rebuild(n)


## 先把内容拼成「带标记的一串行」，再一次性铺控件 —— 便于逐字比较是否变化
func _compose(n: Dictionary) -> String:
	var out: Array = []
	var kind := String(n.get("kind", ""))
	# 简介
	out.append("D:" + _intro_text(n, kind))
	# 状态
	var st := _status_text(n, kind)
	if st != "":
		out.append("S:" + st)
	# 来源（场景不给：场景之间是叙事链接，不是「谁装下了谁」）
	if kind != "loc" and String(n.get("home_scene", "")) != "":
		out.append("F:" + _container_title(String(n["home_scene"])))
	# 动作按钮
	if _graph.is_container_node(_key) and _graph.explored.has(String(n.get("id", ""))):
		out.append("B:renarr")
	if kind == "char":
		var prog := int(_graph.talk_prog.get(_key, 0))
		if prog > 0:
			out.append("B:talk")
		if _has_monologue(String(n["id"])):
			out.append("B:monologue")
	if String(n.get("id", "")) == "ITEMS_changji" and _installed(n).has("ITEMS_cz"):
		out.append("B:music")
	return "\n".join(out)


func _rebuild(n: Dictionary) -> void:
	for c in _rows.get_children():
		c.queue_free()
	var kind := String(n.get("kind", ""))
	_head = _line(String(n.get("label", _key)), TecTheme.FS_BODY, TecTheme.TEXT)
	_head.name = "dt_title"
	_rows.add_child(_head)
	_meta = _line(_kind_name(kind), TecTheme.FS_BODY, TecTheme.MUTED)
	_meta.name = "dt_meta"
	_rows.add_child(_meta)
	var para := _para(_intro_text(n, kind))
	_rows.add_child(para)
	para.start_typing()
	var st := _status_text(n, kind)
	if st != "":
		_rows.add_child(_line("状态：" + st, TecTheme.FS_BODY, TecTheme.MUTED))
	if kind != "loc" and String(n.get("home_scene", "")) != "":
		_rows.add_child(_line("来源：" + _container_title(String(n["home_scene"])), TecTheme.FS_BODY, TecTheme.MUTED))
	if _graph.is_container_node(_key) and _graph.explored.has(String(n.get("id", ""))):
		var b := _button("重看场景叙事" if GraphState.is_scene_kind(kind) else "重看叙事")
		b.pressed.connect(func(): renarr_scene.emit(String(n["id"])))
		_rows.add_child(b)
	if kind == "char":
		if int(_graph.talk_prog.get(_key, 0)) > 0:
			var t := _button("重看对话")
			t.pressed.connect(func(): renarr_talk.emit(_key))
			_rows.add_child(t)
		if _has_monologue(String(n["id"])):
			var m := _button("播放独白")
			m.pressed.connect(func(): play_monologue.emit(String(n["id"])))
			_rows.add_child(m)
	if String(n.get("id", "")) == "ITEMS_changji" and _installed(n).has("ITEMS_cz"):
		var mu := _button("播放音乐")
		mu.pressed.connect(func(): play_music.emit())
		_rows.add_child(mu)
	# 高度跟着内容走，不再截到 420
	await get_tree().process_frame
	var h := _rows.get_combined_minimum_size().y
	set_inner_height(h + SysWindow.BAR_H + 20.0)
	## 长简介同样不能把窗底顶出画面：贴到底就整体上移
	if position.y + size.y > 740.0:
		position.y = maxf(8.0, 740.0 - size.y)


func _intro_text(n: Dictionary, kind: String) -> String:
	if _graph.is_container_node(_key) or GraphState.is_scene_kind(kind):
		var mem := _mem_narr(String(n.get("id", "")), kind)
		if mem != "":
			return mem + "\n（时刻：" + _case.time_label_of(_graph.time) + "）"
		return _case.strip_tags(_case.text_of(kind, String(n.get("id", "")))) \
			if _case.text_of(kind, String(n.get("id", ""))) != "" else "（无描述）"
	if kind == "clue":
		var c := _case.clue_of(String(n["id"]))
		return _non_empty(_case.strip_tags(c.desc) if c != null else "", "（无描述）")
	if kind == "char":
		var mem := _mem_narr(String(n.get("id", "")), kind)
		if mem != "":
			return mem + "\n（时刻：" + _case.time_label_of(_graph.time) + "）"
		var ch := _case.char_of(String(n["id"]))
		return _non_empty(_case.strip_tags(ch.desc) if ch != null else "", "（无描述）")
	var it := _case.item_of(String(n["id"]))
	if it == null:
		return "（无描述）"
	# 容器物品的简介就是它的正文；普通物品是 desc
	var body := it.content if it.content != "" else it.desc
	return _non_empty(_case.strip_tags(body), "（无描述）")


func _status_text(n: Dictionary, kind: String) -> String:
	if _graph.is_container_node(_key):
		## 折叠要单独报：卡面副标删掉之后，「收起来了」只剩画布上「白纸 + 虚线框」
		## 这一个很轻的形态线索（未探索是「纸色 + 虚线」），详情窗得把话说清楚。
		if _graph.is_collapsed(String(n["id"])):
			return "已折叠 · 双击可展开"
		return "已探索" if _graph.explored.has(String(n["id"])) else "未探索"
	if kind == "clue":
		var c := _case.clue_of(String(n["id"]))
		var sense := String(c.sense) if c != null else ""
		var cap := "已捕获" if bool(n.get("captured", false)) else "未捕获"
		return cap + " · " + String(GraphState.SENSE_NAMES.get(sense, sense))
	if kind == "char":
		var ch := _case.char_of(String(n["id"]))
		var total := ch.talk_queue.size() if ch != null else 0
		return "已聊完" if int(_graph.talk_prog.get(_key, 0)) >= total else "可对话"
	if kind != "item":
		return ""
	var it := _case.item_of(String(n["id"]))
	if it == null:
		return ""
	var st: Array = []
	if it.toggle_light:
		st.append("已点亮" if bool(n.get("lit", false)) else "未点亮")
		if it.needs_lit_to_use:
			st.append("可照亮黑暗里的东西" if bool(n.get("lit", false)) else "先点亮它，才能照亮黑暗里的东西")
	var fitted: Array = []
	for k in _installed(n).keys():
		fitted.append(_case.label_of("item", String(k)))
	if not fitted.is_empty():
		st.append("已装上 " + "、".join(fitted))
	var need: Array = []
	for cmd in it.commands:
		if not (cmd is UseItemCommandDef):
			continue
		var uc := cmd as UseItemCommandDef
		if uc.requires.is_empty():
			continue
		for pid in uc.requires:
			var rid := String(pid.id) if pid != null else ""
			if rid != "" and not _installed(n).has(rid) and not need.has(rid):
				need.append(rid)
	if not need.is_empty():
		var names: Array = []
		for rid in need:
			names.append(_case.label_of("item", String(rid)))
		st.append("待装上 " + "、".join(names))
	return " · ".join(st)


func _mem_narr(id: String, kind: String) -> String:
	if _graph.time == GraphState.PRESENT_TIME or _case == null:
		return ""
	for mem in _case.memories_for(_graph.time):
		if mem == null:
			continue
		var hit := (kind == "char" and mem.who != null and mem.who.id == id) \
			or (GraphState.is_scene_kind(kind) and mem.where != null and mem.where.id == id)
		if not hit:
			continue
		var lines: Array = []
		for line in mem.script_lines:
			if line != null and String(line.text) != "":
				lines.append(_case.strip_tags(String(line.text)))
		if not lines.is_empty():
			return "\n".join(lines)
	return ""


func _has_monologue(char_id: String) -> bool:
	# 独白 = 参与者只有一个人（与 DialogueSystem.monologue_of 同判据）
	for d in _case.dialogues:
		if d == null or d.participants.size() != 1:
			continue
		if d.participants[0] != null and String(d.participants[0].id) == char_id:
			return true
	return false


func _installed(n: Dictionary) -> Dictionary:
	var m: Dictionary = n.get("installed", {})
	return m


func _container_title(scene_id: String) -> String:
	if _case.scene_of(scene_id) != null:
		return _case.scene_title(scene_id)
	if _case.item_of(scene_id) != null:
		return _case.label_of("item", scene_id)
	return scene_id


func _kind_name(kind: String) -> String:
	return String(NodeCard.KIND_NAME.get(kind, kind))


func _non_empty(s: String, fallback: String) -> String:
	var t := s.strip_edges()
	return t if t != "" else fallback


func _line(text: String, size_px: int, color: Color) -> Label:
	var l := TecTheme.label(text, size_px, color)
	l.custom_minimum_size = Vector2(W - 24.0 - 24.0, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _para(text: String) -> TypewriterLabel:
	var l := TecTheme.narrative_label(text, TecTheme.TEXT)
	l.name = "dt_desc"
	l.custom_minimum_size = Vector2(W - 24.0 - 24.0, 0)
	return l


## 详情窗的四个「重看」键走**全站同一套按钮语法**（P4.2）：白底 + 1px 纯黑键线。
## 原来是无框纯文字 + 悬停反白 —— 在满屏有框的界面里，它读作「一段可点的说明」；
## 文案里的 `[ ]` 方括号也是「没有框，只好用字符假装一个框」的补偿，有真键线后就一起去掉。
func _button(text: String) -> Button:
	return TecTheme.button(text)
