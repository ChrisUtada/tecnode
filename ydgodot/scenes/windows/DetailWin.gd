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
var _para_label: TypewriterLabel
var _fit_queued := false
## W6：× 关闭是「玩家收起」而不是销毁；后台 commit 不能把它重新弹出来。
var _user_closed := false
## U2：叙事播完后补显示详情时，简介整段出现，不再二次打字。
var _show_full_once := false


func setup_detail(p_graph: GraphState, p_case: CaseLoader) -> void:
	_graph = p_graph
	_case = p_case
	setup("节点详情", W, 260)
	enable_controls("", "关闭详情", false)
	place_right()
	closed.connect(_on_user_closed)
	_rows = VBoxContainer.new()
	_rows.name = "rows"
	_rows.add_theme_constant_override("separation", 6)
	_rows.custom_minimum_size = Vector2(W - 24.0 - 24.0, 0)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	## 内容最小尺寸每次变化（重排）都重贴窗高：一次性「等两帧再量」对字体度量
	## 晚落定的情况不可靠（实测真实渲染与无头行数不同），窗高必须跟随内容。
	_rows.sort_children.connect(_queue_fit)
	content.add_child(_rows)


## 贴右上角：右沿按当前视口现算（960 / 1280 / 1920 都贴边）。
## 传 `vw` 时用调用方给的宽度（Desktop 布局已算好，避免和视口更新错一拍）。
func place_right(vw: float = -1.0) -> void:
	var w := vw
	if w <= 0.0 and is_inside_tree():
		w = get_viewport_rect().size.x
	if w <= 0.0:
		w = 1280.0
	position = Vector2(w - PAD_R - W - SysWindow.PAD, TOP)


## 选中变化 / 图状态变化都调这里；内容逐字没变就不重建（免得滚动位置跳回顶部）
func show_node(key: String, force := false) -> void:
	if key != _key or force:
		_user_closed = false
	_key = key
	refresh()


func show_full_once() -> void:
	_show_full_once = true


func _on_user_closed() -> void:
	_user_closed = true
	hide()


func current_key() -> String:
	return _key


func refresh() -> void:
	if _graph == null or _rows == null:
		return
	var n := _graph.node(_key)
	if n.is_empty():
		hide()
		return
	if _user_closed:
		return
	show()
	var html := _compose(n)
	if html == _sig:
		if _show_full_once:
			_show_full_once = false
			if _para_label != null:
				_para_label.finish_typing()
		return
	_sig = html
	_rebuild(n)


## 先把内容拼成「带标记的一串行」，再一次性铺控件 —— 便于逐字比较是否变化
func _compose(n: NodeState) -> String:
	var out: Array = []
	var kind := n.kind
	# 简介
	out.append("D:" + _intro_text(n, kind))
	# 状态
	var st := _status_text(n, kind)
	if st != "":
		out.append("S:" + st)
	# 来源（场景不给：场景之间是叙事链接，不是「谁装下了谁」）
	if kind != "loc" and n.home_scene != "":
		out.append("F:" + _container_title(n.home_scene))
	# 动作按钮
	if _graph.is_container_node(_key) and _graph.explored.has(n.id):
		out.append("B:renarr")
	if kind == "char":
		var prog := int(_graph.talk_prog.get(_key, 0))
		if prog > 0:
			out.append("B:talk")
		if _has_monologue(n.id):
			out.append("B:monologue")
	if n.id == "ITEMS_changji" and _installed(n).has("ITEMS_cz"):
		out.append("B:music")
	return "\n".join(out)


func _rebuild(n: NodeState) -> void:
	for c in _rows.get_children():
		c.queue_free()
	var kind := n.kind
	_head = _line(n.label if n.label != "" else _key, TecTheme.FS_BODY, TecTheme.TEXT)
	_head.name = "dt_title"
	_rows.add_child(_head)
	_meta = _line(_kind_name(kind), TecTheme.FS_BODY, TecTheme.MUTED)
	_meta.name = "dt_meta"
	_rows.add_child(_meta)
	var para := _para(_intro_text(n, kind))
	_rows.add_child(para)
	_para_label = para
	if not para.typing_finished.is_connected(_queue_fit):
		para.typing_finished.connect(_queue_fit)
	if _show_full_once:
		_show_full_once = false
		para.finish_typing()
	else:
		para.start_typing()
	var st := _status_text(n, kind)
	if st != "":
		_rows.add_child(_line("状态：" + st, TecTheme.FS_BODY, TecTheme.MUTED))
	if kind != "loc" and n.home_scene != "":
		_rows.add_child(_line("来源：" + _container_title(n.home_scene), TecTheme.FS_BODY, TecTheme.MUTED))
	if _graph.is_container_node(_key) and _graph.explored.has(n.id):
		var b := _button("重看场景叙事" if GraphState.is_scene_kind(kind) else "重看叙事")
		b.pressed.connect(func(): renarr_scene.emit(n.id))
		_rows.add_child(b)
	if kind == "char":
		if int(_graph.talk_prog.get(_key, 0)) > 0:
			var t := _button("重看对话")
			t.pressed.connect(func(): renarr_talk.emit(_key))
			_rows.add_child(t)
		if _has_monologue(n.id):
			var m := _button("播放独白")
			m.pressed.connect(func(): play_monologue.emit(n.id))
			_rows.add_child(m)
	if n.id == "ITEMS_changji" and _installed(n).has("ITEMS_cz"):
		var mu := _button("播放音乐")
		mu.pressed.connect(func(): play_music.emit())
		_rows.add_child(mu)
	# 高度跟着内容走；视口不够高时整体上移，优先保证按钮不越出窗框。
	await get_tree().process_frame
	await get_tree().process_frame
	_fit_to_content()


## 内容重排时重贴窗高（去抖到帧末一次）。窗高变化本身会引发一次 sort，
## 但量出的目标高度相同就直接返回，循环一拍即停。
func _queue_fit() -> void:
	if _fit_queued:
		return
	_fit_queued = true
	await get_tree().process_frame
	_fit_queued = false
	_fit_to_content()


func _fit_to_content() -> void:
	if _rows == null:
		return
	var rows_h := _rows.get_combined_minimum_size().y
	var vh := FloatingPanel.viewport_height(self)
	var inner := rows_h + SysWindow.BAR_H + 20.0 + 8.0
	## 不设滚动条（用户口径）：窗高封顶在视口内，超高内容时窗口上移而不是出滚动条。
	inner = minf(inner, maxf(160.0, vh - TOP - 8.0 - SysWindow.PAD * 2.0))
	if absf(size.y - (inner + SysWindow.PAD * 2.0)) >= 1.0:
		set_inner_height(inner)
	## 窗口完整地留在视口内：先按 TOP 放，放不下就往上抬到 8px。
	position.y = _vh_pos(TOP, vh - 8.0 - size.y)


func _vh_pos(preferred: float, max_top: float) -> float:
	if max_top < 8.0:
		return 8.0
	return clampf(preferred, 8.0, max_top)


func _intro_text(n: NodeState, kind: String) -> String:
	if _graph.is_container_node(_key) or GraphState.is_scene_kind(kind):
		var mem := _mem_narr(n.id, kind)
		if mem != "":
			return mem + "\n（时刻：" + _case.time_label_of(_graph.time) + "）"
		return _case.text_of(kind, n.id) \
			if _case.text_of(kind, n.id) != "" else "（无描述）"
	if kind == "clue":
		var c := _case.clue_of(n.id)
		return _non_empty(c.desc if c != null else "", "（无描述）")
	if kind == "evidence":
		var ev := _case.evidence_of(n.id)
		if ev == null:
			return "（无描述）"
		var body := _non_empty(ev.desc, "（无描述）")
		if ev.source_text.strip_edges() != "":
			body += "\n来源：" + ev.source_text
		return body
	if kind == "char":
		var mem := _mem_narr(n.id, kind)
		if mem != "":
			return mem + "\n（时刻：" + _case.time_label_of(_graph.time) + "）"
		var ch := _case.char_of(n.id)
		return _non_empty(ch.desc if ch != null else "", "（无描述）")
	var it := _case.item_of(n.id)
	if it == null:
		return "（无描述）"
	# 容器物品的简介就是它的正文；普通物品是 desc
	var body := it.content if it.content != "" else it.desc
	return _non_empty(body, "（无描述）")


func _status_text(n: NodeState, kind: String) -> String:
	if kind == "loc" and _graph.is_no_entry(_key):
		return "暂未发现入口 · 先探索其他地点"
	if _graph.is_container_node(_key):
		## 折叠要单独报：卡面副标删掉之后，「收起来了」只剩画布上「白纸 + 虚线框」
		## 这一个很轻的形态线索（未探索是「纸色 + 虚线」），详情窗得把话说清楚。
		var base := "已折叠 · 双击可展开" if _graph.is_collapsed(n.id) \
			else ("已探索" if _graph.explored.has(n.id) else "未探索")
		if kind == "item" and _case.item_used_in_recipe(n.id):
			base += " · 可用作证据原料"
		return base
	if kind == "clue":
		var c := _case.clue_of(n.id)
		var sense := String(c.sense) if c != null else ""
		var cap := "已捕获" if n.captured else "未捕获"
		return cap + " · " + String(MatrixState.SENSE_NAMES.get(sense, sense))
	if kind == "char":
		var ch := _case.char_of(n.id)
		var total := ch.talk_queue.size() if ch != null else 0
		return "已聊完" if int(_graph.talk_prog.get(_key, 0)) >= total else "可对话"
	if kind == "evidence":
		var ev := _case.evidence_of(n.id)
		if ev == null:
			return ""
		if String(ev.tier) == "ci":
			return "词 · 证言（与物合成证）"
		var origin: String = String({"tec": "TEC 分析", "synth": "物 × 词合成", "deduce": "档案演绎"}.get(String(ev.origin), String(ev.origin)))
		return "证 · %s · %s" % [String(MatrixState.SENSE_NAMES.get(ev.sense, ev.sense)), origin]
	if kind != "item":
		return ""
	var it := _case.item_of(n.id)
	if it == null:
		return ""
	var st: Array = []
	if it.toggle_light:
		st.append("已点亮" if n.lit else "未点亮")
		if it.needs_lit_to_use:
			st.append("可照亮黑暗里的东西" if n.lit else "先点亮它，才能照亮黑暗里的东西")
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
	if _case.item_used_in_recipe(n.id):
		st.append("可用作证据原料")
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
				lines.append(String(line.text))
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


func _installed(n: NodeState) -> Dictionary:
	return n.installed


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
