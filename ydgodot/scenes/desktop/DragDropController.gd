class_name DragDropController
extends Node
## 由 Desktop 挂载的子系统控制器。
## 过渡期直接通过注入的 `desk` 访问宿主成员；搬出的函数名保持不变。

var desk: Desktop


func _take_from_store(key: String, _unused: String) -> void:
	if key == "":
		return
	var win := _storage_win_of(key)
	if win != null:
		(win as StorageWin)._take(key)


func _storage_win_of(key: String) -> Control:
	if desk._bag_win != null and is_instance_valid(desk._bag_win) and (desk._bag_win as StorageWin).items().has(key):
		return desk._bag_win
	if desk._ledger_win != null and is_instance_valid(desk._ledger_win) and (desk._ledger_win as StorageWin).items().has(key):
		return desk._ledger_win
	return null


## 收纳窗里按住一行（StorageWin.row_pressed）→ 开启拖拽会话
func _on_row_pressed(key: String, from_kind: String, at_global: Vector2) -> void:
	## 行拖拽开始前先结束任何残留的画布平移 / 卡片镜像，
	## 否则行拖时可能同时看到「小幽灵在光标」和「整张卡片镜像在旧位」。
	desk._panning = false
	if desk._stage != null:
		desk._stage.mouse_default_cursor_shape = Control.CURSOR_ARROW
	if desk._drag_key != "":
		_abort_card_drag()
	else:
		_drop_card_mirror(null)
	_drop_sdrag_card_mirror()
	desk._sdrag_key = key
	## 起点直接用行事件的坐标——事件流与点击命中同流，任何窗口模式下都不会错位
	desk._sdrag_from = from_kind
	desk._sdrag_origin = at_global
	desk._sdrag_started = false
	desk._sdrag_label = String(desk.graph.node(key).get("label", key))
	var rc := desk._cards.get(key, null) as NodeCard
	## 行在袋里时，真实卡片必须不可见；若历史补间/刷新把它留在了旧位置，这里强制收掉，
	## 避免拖拽时看到「幽灵在光标处、节点却在旧坐标」。
	if rc != null:
		rc.visible = false


func _make_drag_ghost(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "drag_ghost"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := TecTheme.flat(TecTheme.LINE, TecTheme.R_SM, TecTheme.LINE, 1)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	var l := TecTheme.label(text, TecTheme.FS_BODY, TecTheme.CARD)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	if desk._sdrag_layer == null or not is_instance_valid(desk._sdrag_layer):
		desk._sdrag_layer = CanvasLayer.new()
		desk._sdrag_layer.layer = 100
		add_child(desk._sdrag_layer)
	desk._sdrag_layer.add_child(p)
	p.z_index = 40
	p.position = _sdrag_ghost_position(desk._sdrag_origin)
	return p


## 收纳清单拖拽幽灵挂在 `_desk` 下，位置必须用 desk 局部坐标；
## 指针是屏幕/全局坐标，直接赋值会整整偏一个顶栏高度。
func _sdrag_ghost_position(at_global: Vector2) -> Vector2:
	## 幽灵在 CanvasLayer 上，坐标直接就是视口坐标；不再做 desk 局部换算。
	return at_global


func _sdrag_cancel() -> void:
	desk._sdrag_key = ""
	desk._sdrag_from = ""
	desk._sdrag_started = false
	desk._sdrag_label = ""
	if desk._sdrag_ghost != null and is_instance_valid(desk._sdrag_ghost):
		desk._sdrag_ghost.queue_free()
	desk._sdrag_ghost = null
	_clear_drop_over()


## 行拖拽时用整张卡片的镜像跟着光标走：玩家看到的是「节点」而不是一个小标签。
## （当前已改回小标签；保留函数便于以后切换视觉，不再参与主路径。）
func _make_sdrag_card_mirror(at: Vector2) -> void:
	var src := desk._cards.get(desk._sdrag_key, null) as NodeCard
	if src == null or desk._desk == null:
		return
	var mirror := src.build_mirror()
	if mirror == null:
		return
	desk._desk.add_child(mirror)
	desk.windows._place_z(mirror, Desktop.ZR_MIRROR)
	_sync_sdrag_card_mirror(at)


func _sync_sdrag_card_mirror(_at: Vector2) -> void:
	pass


func _drop_sdrag_card_mirror() -> void:
	pass


## 松手结算：另一个收纳窗 → 推演桌布 / 推演图标 → 画布（落在松手那一点）→ 都不中：回去
func _finish_sdrag(at: Vector2) -> void:
	var key := desk._sdrag_key
	var card0 := desk._cards.get(key, null) as NodeCard
	_sdrag_cancel()
	if key == "" or desk.graph == null or not desk.graph.stored.has(key):
		return
	var n := desk.graph.node(key)
	var before := desk._save.snapshot()
	var target := _drop_target_at(at)
	var tid := String(target.get("id", "")) if not target.is_empty() else ""
	if tid != "":
		_dispatch_drop(key, tid, at, "store")
		return
	var blocked := _drop_blocker_at(at)
	if blocked != "":
		_reject_drop(blocked)
		return
	## 落在任何窗体 / 人物档案卡上（含 TEC / 对话 / 推演标题栏）都留在原处，不穿透。
	if desk.canvas._floating_window_at(at) != null or desk.people._person_card_blocks(at):
		return
	if not desk._stage.get_global_rect().has_point(at):
		# 落在画布之外：东西留在原处，并给一句反馈（W23）。
		desk._show_toast("这里放不下，已留在原处。", true)
		return
	var world := (at - desk._stage.get_global_position() - desk._view_pos) / maxf(desk._view_k, 0.01)
	world.x = maxf(0.0, world.x)
	world.y = maxf(0.0, world.y)
	## 行拖拽的视觉预览是小标签，左上角贴光标；落位也用左上角对齐，保证视觉连续。
	var place := world
	if card0 != null:
		place.x = clampf(place.x, 0.0, maxf(0.0, Desktop.WORLD_W - card0.size.x))
		place.y = clampf(place.y, 0.0, maxf(0.0, Desktop.WORLD_H - card0.size.y))
	desk.graph.take_back(key, place.x, place.y)
	desk.card_ui._apply_hidden()
	_refresh_storage_wins()
	var card := desk._cards.get(key, null) as NodeCard
	if card != null:
		card.position = place
		card.set_home(place)
	desk._selected = key
	desk.graph.selected = key
	desk.chrome._apply_focus()
	desk.card_ui._refresh_detail()
	desk.canvas._repaint_edges()
	desk.session._commit(before)


## 拖动会话没收尾就遇到新的按下：把卡按当前坐标落地并清掉镜像。
## （正常路径由 NodeCard 的松手处理；这里只兜「松手事件丢了」的那条）
func _abort_card_drag() -> void:
	var key := desk._drag_key
	var card: NodeCard = desk._cards.get(key, null)
	desk._drag_key = ""
	desk._panning = false
	if card != null and is_instance_valid(card):
		card.cancel_drag()
	else:
		_drop_card_mirror(null)
		_clear_drop_over()
		if desk._edge_layer != null:
			desk._edge_layer.clear_ghost()
		if desk._drag_line != null and is_instance_valid(desk._drag_line):
			desk._drag_line.clear_ghost()


func _on_card_dragged(key: String) -> void:
	desk.canvas._cancel_layout_job()
	desk.canvas._kill_move(key)
	# Web 的拖动不改选中；但这里选中一下能让「聚焦选中」不把正在拖的卡淡化掉，
	# 属于报告 §3.1 ② 里点名的有意偏离。
	desk._selected = key
	desk.graph.selected = key
	desk.chrome._apply_focus()
	# Web 拖起即把整卡搬进 #drag-layer（浮在所有窗子之上）+ 原件 `visibility:hidden`。
	# Godot 里用镜像卡承载「浮层」那份视觉，原件隐藏（连线仍然用它的 world 坐标）。
	desk._drag_key = key
	var card: NodeCard = desk._cards.get(key, null)
	if desk._drag_line != null:
		desk._drag_line.clear_ghost()
	if card != null:
		_mount_card_mirror(card)


## 拖动中：落点悬停高亮（Web 的 `.over`）+ 幽灵线，每帧按指针重算一次。
## 幽灵线画在连线层（world 空间），所以要把指针的屏幕坐标换算回 world。
func _on_card_drag_moved(key: String, at_global: Vector2) -> void:
	var card: NodeCard = desk._cards.get(key, null)
	if card != null and desk._edge_layer != null and desk._card_layer != null:
		var world_at: Vector2 = desk._card_layer.get_global_transform().affine_inverse() * at_global
		desk._edge_layer.set_ghost(card.visual_center(), world_at)
		if desk._drag_line != null and is_instance_valid(desk._drag_line):
			## 同一根幽灵线在桌布根再画一次：拖动时线要压在窗口/图标上，而不是被窗框盖住。
			var inv := desk._drag_line.get_global_transform().affine_inverse()
			var from_global: Vector2 = desk._card_layer.get_global_transform() * card.visual_center()
			desk._drag_line.set_ghost(inv * from_global, inv * at_global)
	_sync_card_mirror(card)
	_update_drop_over(at_global)
	desk._edges_dirty = true


func _mount_card_mirror(card: NodeCard) -> void:
	if card == null or desk._desk == null:
		return
	if desk._card_mirror != null and is_instance_valid(desk._card_mirror):
		desk._card_mirror.queue_free()
	# ⚠ 原件不能让 `visible = false`。Godot 的 GUI 命中判定会跳过「树里不可见」的控件：
	# 拖动第一帧把原件隐藏之后，鼠标移动就不再投递给它（mouse_focus 失效），
	# motion 断流 ⇒ 卡片停在原地、镜像不跟手、松手也没人处理（`_drag_key` 一直挂着）。
	# 之后任何一次按下都落到画布手势层 ⇒ 整块画布跟着鼠标平移 ——「桌布在动，节点不动」。
	# 改成全透明但仍在树里（NodeCard.set_ghost）：事件照收，画面交给镜像。
	card.set_ghost(true)
	var mirror := card.build_mirror()
	if mirror == null:
		return
	desk._desk.add_child(mirror)
	desk.windows._place_z(mirror, Desktop.ZR_MIRROR)
	mirror.scale = card.get_global_transform().get_scale()
	mirror.global_position = card.get_global_position()
	desk._card_mirror = mirror


func _sync_card_mirror(card: NodeCard) -> void:
	if desk._card_mirror == null or not is_instance_valid(desk._card_mirror):
		return
	if card == null and desk._drag_key != "":
		card = desk._cards.get(desk._drag_key, null) as NodeCard
	if card == null or not is_instance_valid(card):
		return
	## W14：缩放 / 平移中拖卡，镜像的 scale 与 LOD 必须跟原件一起走，
	## 否则 0.95 以下原件只剩符号，镜像还挂着完整标题，读作两张不同的卡。
	desk._card_mirror.scale = card.get_global_transform().get_scale()
	desk._card_mirror.set_lod(desk._view_k)
	desk._card_mirror.global_position = card.get_global_position()


## 松手换身回来：镜像销毁、原卡按数据可见性复位（后续的弹回 / 收纳 / 消费各走各路）
func _drop_card_mirror(card: NodeCard) -> void:
	if desk._card_mirror != null and is_instance_valid(desk._card_mirror):
		desk._card_mirror.queue_free()
	desk._card_mirror = null
	if card != null and is_instance_valid(card):
		card.set_ghost(false)
		card.visible = desk.graph.visible_node(desk.graph.node(card.card_key))


## 松手：落点由 `_handle_card_drop` 分派；没命中就停在松手处并把坐标写回数据
func _on_card_drag_finished(key: String, pos: Vector2, handled: bool) -> void:
	## 松手后的 spring_back 会走 0.3s；这段期间连线必须跟着卡片走，不能停在落点。
	desk.canvas._follow_frames = maxi(desk.canvas._follow_frames, 40)
	var finished_card: NodeCard = desk._cards.get(key, null)
	_drop_card_mirror(finished_card)
	desk._drag_key = ""
	_clear_drop_over()
	if desk._edge_layer != null:
		desk._edge_layer.clear_ghost()
	if desk._drag_line != null and is_instance_valid(desk._drag_line):
		desk._drag_line.clear_ghost()
	desk.canvas._repaint_edges()
	var n := desk.graph.node(key)
	if n.is_empty():
		return
	if handled:
		return
	var before := desk._save.snapshot()
	n["x"] = pos.x
	n["y"] = pos.y
	desk.chrome._refresh_crumbs()
	desk.session._commit(before)


## 兼容旧入口（无头测试与 dbg 钩子还在调）：等价于「卡片松手落在 at_global」的完整分派。
## 真实交互走 NodeCard → drop_sink → `_handle_card_drop`，这里只是给测试用的一次性封装。
func _on_card_drag_released(key: String, at_global: Vector2) -> void:
	if _handle_card_drop(key, at_global):
		if desk._cards.has(key):
			(desk._cards[key] as NodeCard).spring_back()
		return
	var target: String = desk.canvas._card_key_at(at_global)
	if target != "" and target != key:
		if desk._cards.has(key):
			(desk._cards[key] as NodeCard).spring_back()
		desk.card_ui._on_card_combo(key, target)


## 单一的落点表。**禁止**在别处再堆 `if 命中某某图标` —— 加落点只改这里。
## 顺序：对话窗 → 两扇收纳窗 → 五个桌面图标 → TEC 头像 / 收起卡 → 推演桌布。
## 窗口排在图标之前：窗开着时通常盖在图标列上，此时归属窗口。
func _drop_targets() -> Array:
	var out: Array = []
	if desk._chat_win != null and is_instance_valid(desk._chat_win) and desk._chat_win.is_visible_in_tree():
		out.append({"id": "chat-win", "rect": desk._chat_win.get_global_rect(), "inset": 10.0,
			"depth": _target_depth(desk._chat_win)})
	if desk._bag_win != null and is_instance_valid(desk._bag_win) and desk._bag_win.is_visible_in_tree():
		out.append({"id": "bag-win", "rect": desk._bag_win.get_global_rect(), "inset": 10.0,
			"depth": _target_depth(desk._bag_win)})
	if desk._ledger_win != null and is_instance_valid(desk._ledger_win) and desk._ledger_win.is_visible_in_tree():
		out.append({"id": "clue-win", "rect": desk._ledger_win.get_global_rect(), "inset": 10.0,
			"depth": _target_depth(desk._ledger_win)})
	## K5：「拖场景到档案图标 = 前往」是已废弃的场景前往，不再作为落点。
	## 档案图标仍由 `_drop_blocker_at()` 拦截并给出说明，避免卡片穿透到画布。
	for pair in [["bag-dock", "icon_bag"], ["clue-icon", "icon_clue"], ["tec-dock", "icon_tec"],
			["infer-icon", "icon_infer"]]:
		var ic: Control = desk._desk.get_node_or_null("icons/" + String(pair[1])) as Control
		if ic != null and ic.is_visible_in_tree():
			out.append({"id": String(pair[0]), "rect": ic.get_global_rect(), "inset": 0.0,
				"depth": _target_depth(ic)})
	if desk._tec != null and is_instance_valid(desk._tec) and desk._tec.visible:
		## 整个 TEC 窗体都是分析落点：拖到标题栏、正文、头像任意位置都能交给 TEC。
		out.append({"id": "tec-dock", "rect": desk._tec.get_global_rect(), "inset": 10.0,
			"depth": _target_depth(desk._tec)})
	if desk._tec_chip != null and is_instance_valid(desk._tec_chip) and desk._tec_chip.visible:
		out.append({"id": "tec-chip", "rect": desk._tec_chip.get_global_rect(), "inset": 2.0,
			"depth": _target_depth(desk._tec_chip)})
	if desk._matrix_win != null and is_instance_valid(desk._matrix_win) and desk._matrix_win.visible:
		## 整扇推演窗都是线索落点：拖到标题栏 / 板边也算交给当前窗口，
		## 不再让卡片从窗体缝隙漏到下面的画布节点。
		out.append({"id": "mx-board", "rect": desk._matrix_win.get_global_rect(), "inset": 10.0,
			"depth": _target_depth(desk._matrix_win)})
	if desk._people_card != null and is_instance_valid(desk._people_card) and desk._people_card.visible:
		for ft in desk._people_card.evidence_drop_targets():
			out.append({
				"id": "person-field:%s:%s" % [String(desk._people_card.person_id), String(ft["id"])],
				"rect": ft["rect"], "inset": 0.0,
				"depth": _target_depth(desk._people_card),
			})
	## 落点优先级跟随真实层序：后提上来的窗（含推演窗）先命中。
	## 固定顺序会让下面的 TEC 抢走上面推演窗的拖放，看起来就是「功能穿透」。
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("depth", -1)) > int(b.get("depth", -1)))
	return out


func _target_depth(ctrl: Control) -> int:
	if ctrl == null or not is_instance_valid(ctrl):
		return -1
	var n: Node = ctrl
	while n != null and n.get_parent() != desk._desk:
		n = n.get_parent()
	return n.get_index() if n != null else -1


func _drop_target_at(at_global: Vector2) -> Dictionary:
	for t in _drop_targets():
		if (t["rect"] as Rect2).has_point(at_global):
			return t
	return {}


## W8/K4：收纳行拖拽时，只高亮松手真的会生效的落点。
## 高亮 ≠ 命中会让玩家以为「拖到 TEC 也能分析收纳里的东西」，实际却只能先取回。
func _drop_hover_allowed(target_id: String) -> bool:
	if desk._sdrag_key == "" or desk.graph == null:
		return true
	var n := desk.graph.node(desk._sdrag_key)
	if n.is_empty():
		return true
	var kind := String(n["kind"])
	var zheng := _is_zheng_node(n)
	var word := _is_word_node(n)
	if target_id.begins_with("person-field:"):
		return zheng
	match target_id:
		"tec-dock", "tec-avatar", "tec-chip", "chat-win":
			return false
		"bag-win", "bag-dock":
			return kind == "item" or word
		"clue-win", "clue-icon", "infer-icon", "mx-board":
			return zheng
	return true


## 拖动中用：命中的窗口 / 图标 / 卡片统一画一层虚线框
func _update_drop_over(at_global: Vector2) -> void:
	if desk.people._person_card_blocks(at_global):
		_clear_drop_over()
		return
	var hit_id := ""
	var hit_rect := Rect2()
	var hit_inset := 0.0
	for t in _drop_targets():
		if not _drop_hover_allowed(String(t["id"])):
			continue
		if (t["rect"] as Rect2).has_point(at_global):
			hit_id = String(t["id"])
			hit_rect = t["rect"]
			hit_inset = float(t.get("inset", 0.0))
			break
	# 目标节点（组合）：只在没有图标 / 窗口命中时描边，效果与窗口、图标完全一致。
	var under := ""
	if hit_id == "":
		under = desk.canvas._card_key_at(at_global)
	desk._drag_over_card = under
	if under != "":
		_show_drop_outline((desk._cards[under] as NodeCard).get_global_rect(), 0.0)
	elif hit_id != "":
		_show_drop_outline(hit_rect, hit_inset)
	elif desk._drop_outline != null and is_instance_valid(desk._drop_outline):
		desk._drop_outline.clear_outline()


## 所有落点共用同一层虚线框：窗口在可见边框外 4px（PAD-4），图标 / 卡片贴外框，桌布贴板边。
func _show_drop_outline(rect_global: Rect2, inset: float) -> void:
	if desk._drop_outline == null or not is_instance_valid(desk._drop_outline):
		return
	var inv := desk._desk.get_global_transform().affine_inverse()
	var origin := inv * rect_global.position
	desk._drop_outline.show_rect(Rect2(origin, rect_global.size).grow(-inset))


func _clear_drop_over() -> void:
	if desk._drop_outline != null and is_instance_valid(desk._drop_outline):
		desk._drop_outline.clear_outline()
	desk._drag_over_card = ""


func _on_card_spring_finished(_key: String) -> void:
	desk.canvas._repaint_edges()


## 松手分派：命中落点即消费（卡片回原位）。返回 true 表示已被落点接管。
func _handle_card_drop(key: String, at_global: Vector2) -> bool:
	var target := _drop_target_at(at_global)
	if not target.is_empty():
		_dispatch_drop(key, String(target["id"]), at_global, "canvas")
		return true
	var blocked := _drop_blocker_at(at_global)
	if blocked != "":
		_reject_drop(blocked)
		return true
	## 任何浮动窗 / 人物档案卡都拦截卡片，哪怕它不是落点：松手弹回，不穿透到下面。
	if desk.canvas._floating_window_at(at_global) != null or desk.people._person_card_blocks(at_global):
		desk._show_toast("这里不能放节点，已弹回。", true)
		return true
	return false


## K5：已退役的落点不再「生效」，但仍要挡住卡片并说清原因（不能穿透到画布）。
func _drop_blocker_at(at_global: Vector2) -> String:
	var goto_icon := desk._desk.get_node_or_null("icons/icon_goto") as Control \
		if desk._desk != null and is_instance_valid(desk._desk) else null
	if goto_icon != null and goto_icon.is_visible_in_tree() \
			and goto_icon.get_global_rect().has_point(at_global):
		return "档案只收时间点：场景请双击展开；时间点请从档案窗前往。"
	return ""


## K6：所有拒收统一「warning toast + 日志」，话术由调用方按目标分派。
func _reject_drop(text: String) -> void:
	if text == "":
		return
	desk._log(text, "warn")
	desk._show_toast(text, true)


func _is_word_node(n: Dictionary) -> bool:
	return String(n.get("kind", "")) == "evidence" and String(n.get("tier", "")) == "ci"


func _is_zheng_node(n: Dictionary) -> bool:
	return String(n.get("kind", "")) == "evidence" and String(n.get("tier", "")) == "zheng"


func _source_name(source: String) -> String:
	match source:
		"store":
			return "收纳"
		"matrix":
			return "推演桌布"
	return "画布"


## K4：三条拖放路径（画布卡片 / 收纳行 / 桌布线索引）共用的唯一分派器。
## 返回 true = 已处理（包括明确拒收）；false = 未命中，交给来源自己的默认回弹。
func _dispatch_drop(key: String, target_id: String, _at_global: Vector2, source: String) -> bool:
	if target_id == "":
		return false
	if desk.graph == null:
		return true
	var n := desk.graph.node(key)
	if n.is_empty():
		return true
	var kind := String(n["kind"])
	var label := String(n.get("label", key))
	if target_id.begins_with("person-field:"):
		var parts := target_id.split(":")
		if parts.size() >= 3:
			desk.people._assign_evidence_to_field(String(parts[1]), String(parts[2]), key, source)
		return true
	var tier := String(n.get("tier", ""))
	match target_id:
		"bag-win", "bag-dock":
			if source == "canvas":
				_store_into(GraphState.BAG, key)
			else:
				_restash_to(key, GraphState.BAG, label)
		"clue-win", "clue-icon":
			if source == "canvas":
				_store_into(GraphState.LEDGER, key)
			else:
				_restash_to(key, GraphState.LEDGER, label)
		"tec-dock", "tec-avatar", "tec-chip":
			if kind == "evidence":
				_reject_drop(desk.people._evidence_tec_message(tier))
			elif source == "canvas":
				desk.tec._start_tec_analysis(key)
			else:
				_reject_drop("先从%s把「%s」取回画布，再拖给 TEC 分析。" % [_source_name(source), label])
		"infer-icon", "mx-board":
			if not _is_zheng_node(n):
				if kind == "evidence":
					_reject_drop("推演桌布只接带五感的「证」；词是证言，先和物合成。")
				elif not desk.tutorial._tutorial_correct("推演桌布只收证。"):
					_reject_drop("只有「证」能放到推演桌布。")
			elif source != "matrix":
				desk.matrix._assign_to_matrix(key)
		"chat-win":
			if kind == "evidence":
				_reject_drop("证据不是人物，不能加入这段对话。")
			elif source == "canvas":
				desk.narrative._chat_drop(key)
			else:
				_reject_drop("对话窗只接画布上的节点；先从%s取回。" % _source_name(source))
		_:
			return false
	return true


## 兼容旧调用 / 测试：等价于「画布卡片落在某落点」。
func _apply_drop(id: String, key: String) -> void:
	_dispatch_drop(key, id, Vector2.ZERO, "canvas")


## 收纳之间搬运（袋 ↔ 册 / 桌布 → 册）：类型不合就按目标回绝。
func _restash_to(key: String, to: String, label: String) -> void:
	if desk.graph == null or not desk.graph.stored.has(key):
		return
	var from := String(desk.graph.stored.get(key, ""))
	if from == to:
		return
	var nd := desk.graph.node(key)
	var kind := String(nd.get("kind", ""))
	var tier := String(nd.get("tier", ""))
	if to == GraphState.BAG and not (kind == "item" or (kind == "evidence" and tier == "ci")):
		_reject_drop("「物品」收物与词；证是知识，进「证据」。")
		return
	if to == GraphState.LEDGER and not (kind == "evidence" and tier == "zheng"):
		_reject_drop("「证据」只收证；词进「物品」，物是原料。")
		return
	var before := desk._save.snapshot()
	if not desk.graph.restash(key, from, to):
		return
	desk.card_ui._apply_hidden()
	desk.matrix._refresh_matrix_views()
	desk._show_toast("「%s」搬到「%s」" % [label,
		"物品" if to == GraphState.BAG else "证据"])
	desk.session._commit(before)


## 收进物品 / 证据（拒收时给一句人话，别让玩家以为是坏了）
func _store_into(where: String, key: String) -> void:
	var n := desk.graph.node(key)
	if n.is_empty():
		return
	var target_name := "物品" if where == GraphState.BAG else "证据"
	if desk.graph.stored.has(key):
		var already := "「%s」已经在「%s」里了。" % [String(n.get("label", key)), target_name]
		if not desk.tutorial._tutorial_correct(already):
			_reject_drop(already)
		return
	var kind := String(n.get("kind", ""))
	var tier := String(n.get("tier", ""))
	if where == GraphState.BAG:
		if kind != "item" and not (kind == "evidence" and tier == "ci"):
			var bag_msg := "「物品」收物与词；「%s」是证，请进「证据」。" % String(n.get("label", key)) \
				if kind == "evidence" else "「物品」收物与词；「%s」不能放进「物品」。" % String(n.get("label", key))
			if not desk.tutorial._tutorial_correct(bag_msg):
				_reject_drop(bag_msg)
			return
		if not desk.graph.can_bag(key):
			var bag_msg2 := "「%s」不能放进「物品」。" % String(n.get("label", key))
			if desk.graph.is_container_node(key):
				bag_msg2 = "「%s」是现场的一部分，收不走；它装着的东西可以单独收。" \
					% String(n.get("label", key))
			if not desk.tutorial._tutorial_correct(bag_msg2):
				_reject_drop(bag_msg2)
			return
	if where == GraphState.LEDGER and not (kind == "evidence" and tier == "zheng"):
		var book_msg := "「证据」只收证；词是证言，进「物品」。" if kind == "evidence" \
			else "「证据」只收证；物是原料。"
		if not desk.tutorial._tutorial_correct(book_msg):
			_reject_drop(book_msg)
		return
	var before := desk._save.snapshot()
	var ok := desk.graph.bag_store(key) if where == GraphState.BAG else desk.graph.ledger_store(key)
	if not ok:
		return
	desk.card_ui._apply_hidden()
	_refresh_storage_wins()
	desk._show_toast("「%s」收进「%s」" % [String(n.get("label", "")), target_name])
	desk.session._commit(before)


func _refresh_storage_wins() -> void:
	if desk._bag_win != null and is_instance_valid(desk._bag_win):
		desk._bag_win.refresh_store()
	if desk._ledger_win != null and is_instance_valid(desk._ledger_win):
		desk._ledger_win.refresh_store()


func _toggle_storage(kind: String) -> void:
	if not desk.session._require_case():
		return
	if kind == GraphState.BAG:
		if desk._bag_win != null and is_instance_valid(desk._bag_win):
			desk._bag_win.queue_free()
			desk._bag_win = null
			return
		desk._bag_win = StorageWin.new()
		desk._bag_win.name = "bag_win"
		desk._bag_win.setup_store("物品", GraphState.BAG, desk.graph, desk.case_def)
		desk._bag_win.writes_enabled = desk._case_open
		desk._bag_win.position = Vector2(150, 300)
		desk._bag_win.will_take.connect(_on_storage_will_take)
		desk._bag_win.took.connect(_on_storage_took)
		desk._bag_win.row_pressed.connect(_on_row_pressed)
		desk._bag_win.closed.connect(func(): desk._bag_win = null)
		desk._desk.add_child(desk._bag_win)
		desk.windows._place_z(desk._bag_win, Desktop.ZR_WIN)
		return
	if desk._ledger_win != null and is_instance_valid(desk._ledger_win):
		desk._ledger_win.queue_free()
		desk._ledger_win = null
		return
	desk._ledger_win = StorageWin.new()
	desk._ledger_win.name = "clue_win"
	desk._ledger_win.setup_store("证据", GraphState.LEDGER, desk.graph, desk.case_def)
	desk._ledger_win.writes_enabled = desk._case_open
	desk._ledger_win.position = Vector2(410, 300)
	desk._ledger_win.will_take.connect(_on_storage_will_take)
	desk._ledger_win.took.connect(_on_storage_took)
	desk._ledger_win.to_matrix.connect(desk.matrix._on_ledger_to_matrix)
	desk._ledger_win.row_pressed.connect(_on_row_pressed)
	desk._ledger_win.closed.connect(func(): desk._ledger_win = null)
	desk._desk.add_child(desk._ledger_win)
	desk.windows._place_z(desk._ledger_win, Desktop.ZR_WIN)


## 收纳窗取出前先拍快照（StorageWin 自己改图，Desktop 只能从信号里抢在它前面）
func _on_storage_will_take(_key: String) -> void:
	desk._storage_before = desk._save.snapshot()


## 从收纳窗取回：节点回到画布，并刷新两个清单窗
func _on_storage_took(key: String) -> void:
	if desk._cards.has(key):
		(desk._cards[key] as NodeCard).visible = desk.graph.visible_node(desk.graph.node(key))
	desk.canvas._relayout()
	if desk._bag_win != null and is_instance_valid(desk._bag_win):
		desk._bag_win.refresh_store()
	if desk._ledger_win != null and is_instance_valid(desk._ledger_win):
		desk._ledger_win.refresh_store()
	desk.session._commit(desk._storage_before)
	desk._storage_before = {}
