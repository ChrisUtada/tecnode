class_name CanvasController
extends Node
## 由 Desktop 挂载的子系统控制器。
## 过渡期直接通过注入的 `desk` 访问宿主成员；搬出的函数名保持不变。

var desk: Desktop

## 卡片落位补间与连线跟随帧：纯画布状态，跟随本控制器。
var _move_twens: Dictionary = {}      # key -> 卡片落位补间（下一次重排前先杀）
var _follow_frames := 0               # >0 时每帧重画连线（过渡期间连线跟着节点走）
var _layout_job = null                # 分帧力导向任务
## 当前「可见节点集合」的签名。力导向只认它：集合没变 = 结构没变 = 一个坐标都不该动。
var _layout_sig := ""
## 本次重排新上画的 card_key。常规展开只给这些新卡找位置，不推动已有卡片、不自动缩镜头。
var _fresh_spawns: Array = []
## F3 基准：最近一次 reconcile 的复用 / 新建 / 移除数量。
var _last_rebuild_stats := {"reused": 0, "spawned": 0, "despawned": 0}
## F1：分帧力导向作业。用 preload 而不是依赖全局 class_name，避免缓存未生成时无头装载失败。
const ForceLayoutScript = preload("res://core/ForceLayout.gd")


## 按当前图状态重建所有卡片（撤销 / 续档共用）
func _rebuild_from_graph(fit_camera := false) -> void:
	_cancel_layout_job()
	desk.card_ui._close_card_context()
	var was_analyzing := desk._tec != null and desk._tec.is_analyzing()
	var fresh_before := {}
	for raw_key in desk.graph.nodes.keys():
		if bool((desk.graph.nodes[raw_key] as Dictionary).get("fresh", false)):
			fresh_before[String(raw_key)] = true
	## F3：按 card_key 增量 reconcile。读档 / 撤销时大多数节点还是同一张卡，
	## 不销毁重建 500+ 子控件；只更新数据、显隐与坐标，缺的才 spawn，多的才 despawn。
	desk._selected = ""
	desk.graph.selected = ""
	desk._storage_before = {}
	if desk._edge_layer != null:
		desk._edge_layer.clear_ghost()
	GardenSystem.normalize(desk.graph, desk.case_def)
	desk.people._refresh_people_win()
	desk.people._refresh_person_card_fields()
	desk._refresh_log_win()
	## S4：撤销 / 读档只重建画布，不碰音乐播放器。正在播的歌属于「玩家现场」，
	## 不该因为撤销一个无关操作（点亮手电、收纳一件物品）被掐断。
	## 真换案仍走 `_new_runtime()`，那里会正常释放播放器。
	if desk._garden_win != null and is_instance_valid(desk._garden_win):
		desk._garden_win.queue_free()
	desk._garden_win = null
	if desk._pw_pop != null and is_instance_valid(desk._pw_pop):
		desk._pw_pop.queue_free()
	desk._pw_pop = null
	desk._pw_ctx = {}
	if desk._narr != null and is_instance_valid(desk._narr):
		desk._narr.queue_free()
	desk._narr = null
	desk.narrative._close_mem_card()
	desk.narrative._close_chat()
	if desk._archive_win != null and is_instance_valid(desk._archive_win):
		desk._archive_win.queue_free()
	desk._archive_win = null
	desk._ending.visible = false
	if desk._tec != null:
		desk._tec.cancel_analysis()
		desk.tec._sync_tec_chip()
	if was_analyzing:
		desk._log("撤销 / 读档取消了进行中的 TEC 分析", "warn")
		desk._show_toast("已取消进行中的 TEC 分析", true)
	desk._suppress_archive_new = true
	var alive := {}
	_last_rebuild_stats = {"reused": 0, "spawned": 0, "despawned": 0}
	for raw_key in desk.graph.nodes.keys():
		var key := String(raw_key)
		var n: Dictionary = desk.graph.nodes[raw_key]
		alive[key] = true
		var card: NodeCard = desk._cards.get(key, null)
		if card != null and is_instance_valid(card):
			card.node_data = n
			card.visible = desk.graph.visible_node(n)
			card.position = Vector2(float(n.get("x", 0.0)), float(n.get("y", 0.0)))
			card.set_home_silent(card.position)
			card.set_lod(desk._view_k)
			_sync_card_shell(card)
			_last_rebuild_stats["reused"] += 1
		else:
			_spawn_card(key)
			_last_rebuild_stats["spawned"] += 1
	for key in desk._cards.keys():
		if not alive.has(String(key)):
			_despawn_card(String(key))
			_last_rebuild_stats["despawned"] += 1
	desk._suppress_archive_new = false
	desk.card_ui._apply_hidden()
	## S9：撤销 / 读档后按当前图重新补档案「新」角标，而不是一律清掉。
	_refresh_archive_new_from_graph()
	## S16：读档后 fresh 已被消费；未读节点用 unread 再补一次入场 pop。
	_replay_unread_pops(fresh_before)
	## S10：卡片全部重建后，推演桌布的遮挡淡出必须重算。
	if desk._matrix_win != null and is_instance_valid(desk._matrix_win) and desk._matrix_win.visible:
		## F3 之后卡片是复用的：先把旧遮罩恢复，再让 sync 重新淡出。
		## 只 clear 不 restore 会把 process_mode=DISABLED 永久留在卡上。
		desk.matrix._sync_matrix_occlusion.call_deferred()
	# 读档 / 撤销后摆位是存档里那一份，不能被下一次互动的重排顺手推走 —— 签名就地认下来。
	_fresh_spawns.clear()
	_layout_sig = _layout_signature()
	desk.matrix._refresh_matrix_views()
	desk._last_ending_id = String(desk.graph.endings.keys()[0]) if not desk.graph.endings.is_empty() else ""
	var sid := desk.graph.last_scene
	desk.session._set_crumb(desk.session._case_label() + " // " + desk.case_def.scene_title(sid) if sid != "" else desk.session._case_label())
	if fit_camera:
		## S2：读档后镜头回到「适应窗口」，而不是停在上一局的 (0,0)@1.0。
		_reset_camera()
		_fit_cards()
	desk.session._update_case_chrome()
	desk.launcher._refresh_app_icons()


func _refresh_archive_new_from_graph() -> void:
	desk.narrative._clear_archive_new()
	for raw_key in desk.graph.nodes.keys():
		var n: Dictionary = desk.graph.nodes[raw_key]
		if String(n.get("kind", "")) == "time" and desk.graph.has_unread(String(raw_key)):
			desk.narrative._mark_archive_new()
			return


func _replay_unread_pops(skip: Dictionary) -> void:
	if desk._shot_mode() or desk._tutorial_active:
		return
	for raw_key in desk.graph.nodes.keys():
		var k := String(raw_key)
		if skip.has(k) or not desk.graph.has_unread(k):
			continue
		var card := desk._cards.get(k, null) as NodeCard
		if card == null:
			continue
		card.pivot_offset = card.size * 0.5
		card.play_pop()


func _on_stage_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if not mb.pressed:
				return
			var mp := mb.position
			var step := Desktop.ZOOM_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / Desktop.ZOOM_STEP
			var k2 := clampf(desk._view_k * step, Desktop.ZOOM_MIN, Desktop.ZOOM_MAX)
			## 近 100% 吸附：1.0 是点阵字唯一落在原生格上的倍率，别让玩家「差一点点」
			if absf(k2 - 1.0) < Desktop.ZOOM_SNAP:
				k2 = 1.0
			if absf(k2 - desk._view_k) > 0.0001:
				desk._view_pos = mp - (mp - desk._view_pos) * (k2 / desk._view_k)
				desk._view_k = k2
				desk._view_pos = _clamp_view_pos(desk._view_pos)
				desk._view_user = true
				_apply_view()
			desk._stage.accept_event()
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			# 上一轮拖动如果没收到松手（切窗 / 失焦 / 事件丢失），这里先收尾。
			# 否则画布会带着一张「悬空的卡」继续平移，看着就是「桌布在动、节点不动」。
			if desk._drag_key != "":
				desk.drag._abort_card_drag()
				return
			desk._panning = true
			desk._wake_process()
			desk._pan_from = mb.position
			desk._pan_origin = desk._view_pos
			if desk._stage != null:
				desk._stage.mouse_default_cursor_shape = Control.CURSOR_DRAG
			_clear_selection()
		else:
			desk._panning = false
			if desk._stage != null:
				desk._stage.mouse_default_cursor_shape = Control.CURSOR_ARROW
		return
	if event is InputEventMouseMotion and desk._panning:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			## 松手事件被窗口吃掉时 _panning 会卡住，之后移动鼠标会像「镜头自己在飘」。
			desk._panning = false
			if desk._stage != null:
				desk._stage.mouse_default_cursor_shape = Control.CURSOR_ARROW
			return
		desk._view_pos = _clamp_view_pos(desk._pan_origin
			+ ((event as InputEventMouseMotion).position - desk._pan_from))
		desk._view_user = true
		_apply_view()


## W12：平移 / 缩放后世界不能被整个推出视口。四边各留 80px 世界可见。
func _clamp_view_pos(p: Vector2) -> Vector2:
	if desk._stage == null or not is_instance_valid(desk._stage):
		return p
	var keep := 80.0
	var world := Vector2(Desktop.WORLD_W, Desktop.WORLD_H) * maxf(desk._view_k, 0.01)
	var stage := desk._stage.size
	return Vector2(
		clampf(p.x, keep - world.x, maxf(keep - world.x, stage.x - keep)),
		clampf(p.y, keep - world.y, maxf(keep - world.y, stage.y - keep)))


func _reset_camera() -> void:
	desk._view_k = 1.0
	desk._view_pos = Vector2.ZERO
	desk._view_user = false
	_apply_view()


func _apply_view() -> void:
	if desk._card_layer == null:
		return
	desk._card_layer.position = desk._view_pos
	desk._card_layer.scale = Vector2(desk._view_k, desk._view_k)
	## 低倍率下连线按 1/k 反向加粗：不补偿的话 1.3px 的实体线到 0.62x 只剩 0.8px，
	## 会被纸纹底吃成「虚线」。补偿后屏幕上仍是 1.3px（见 EdgeLayer.set_zoom）。
	if desk._edge_layer != null and is_instance_valid(desk._edge_layer):
		desk._edge_layer.set_zoom(desk._view_k)
	_apply_lod()
	_reanchor_mem_card()
	desk.drag._sync_card_mirror(null)


## 把当前倍率分发给每张卡（NodeCard.set_lod 自己判档并早退，重复调用不吃性能）
func _apply_lod() -> void:
	if desk._cards.is_empty():
		return
	for key in desk._cards.keys():
		var c: NodeCard = desk._cards.get(key, null)
		if c != null and is_instance_valid(c):
			c.set_lod(desk._view_k)


## 缩放 / 平移 / 重排都会让锚点节点在屏幕上换位置，而放映卡是**屏幕坐标**摆的 ——
## 不重锚它就会留在原地，看起来像压在节点上（实测 448×328 的卡盖住花园卡）。
func _reanchor_mem_card() -> void:
	if desk._mem_card != null and is_instance_valid(desk._mem_card) and desk.narrative._mem_anchor_key != "":
		desk.narrative._anchor_card_to(desk._mem_card, desk.narrative._mem_anchor_key)


func _clear_selection() -> void:
	desk.launcher._clear_icon_selection()
	if desk._selected == "":
		return
	desk._selected = ""
	if desk.graph != null:
		desk.graph.selected = ""
	desk.chrome._apply_focus()
	desk.card_ui._refresh_detail()


## 组合 / 命令消耗掉的数据节点也要收尸：卡片、选中、拖动、连线痕迹全部一起清。
func _despawn_card(key: String) -> void:
	if key == "":
		return
	_kill_move(key)
	if desk._drag_key == key:
		desk.drag._drop_card_mirror(null)
		desk._drag_key = ""
	if desk._matrix_faded.has(key):
		desk._matrix_faded.erase(key)
	var card: NodeCard = desk._cards.get(key, null)
	if card != null and is_instance_valid(card):
		card.queue_free()
	desk._cards.erase(key)
	_fresh_spawns.erase(key)
	if desk._selected == key:
		desk._selected = ""
		if desk.graph != null:
			desk.graph.selected = ""
		desk.chrome._apply_focus()
		desk.card_ui._refresh_detail()


## 任何改图路径的兜底：数据层已不存在的卡片必须从 _cards 清掉，避免僵尸卡继续画线 / 参与布局。
func _sync_canvas() -> void:
	if desk.graph == null or desk._cards.is_empty():
		return
	var removed := false
	for key in desk._cards.keys():
		var card: NodeCard = desk._cards.get(key, null)
		if card == null or not is_instance_valid(card) or not desk.graph.nodes.has(String(key)):
			_despawn_card(String(key))
			removed = true
	if removed:
		desk.card_ui._apply_hidden()
		_repaint_edges()


func _spawn_card(key: String) -> NodeCard:
	if desk._cards.has(key):
		return desk._cards[key]
	var n := desk.graph.node(key)
	if n.is_empty():
		return null
	if String(n["kind"]) == "time":
		if not desk._suppress_archive_new and desk.graph.has_unread(key):
			desk.narrative._mark_archive_new()
		return null                       # 时间节点不上画布（入口在档案窗）
	var w := GraphState.SCENE_W if GraphState.is_scene_kind(String(n["kind"])) else GraphState.ENT_W
	var h := GraphState.SCENE_H if GraphState.is_scene_kind(String(n["kind"])) else GraphState.ENT_H
	var card := NodeCard.new()
	card.name = "card_" + key.replace(":", "_")
	card.setup(key, String(n["kind"]), n, w, h)
	_sync_card_shell(card)
	_seed_one(key)
	card.position = Vector2(float(n.get("x", 0.0)), float(n.get("y", 0.0)))
	card.drop_sink = Callable(desk.drag, "_handle_card_drop")
	card.world_rect = Rect2(Vector2.ZERO, Vector2(Desktop.WORLD_W, Desktop.WORLD_H))
	card.selected.connect(desk.card_ui._on_card_selected)
	card.pressed.connect(desk.card_ui._on_card_pressed)
	card.activated.connect(desk.card_ui._on_card_activated)
	card.dragged.connect(desk.drag._on_card_dragged)
	card.drag_moved.connect(desk.drag._on_card_drag_moved)
	card.drag_finished.connect(desk.drag._on_card_drag_finished)
	card.combo_requested.connect(desk.card_ui._on_card_combo)
	card.pin_toggled.connect(desk.card_ui._on_card_pin_toggled)
	card.context_requested.connect(desk.card_ui._open_card_context)
	card.spring_finished.connect(desk.drag._on_card_spring_finished)
	desk._card_layer.add_child(card)
	desk._cards[key] = card
	_fresh_spawns.append(key)
	## 新卡上画布时立刻对齐当前倍率，否则缩小状态下新出现的卡会带着「完整两行」出现
	card.set_lod(desk._view_k)
	# Web 的入场 pop：fresh 的节点初次上画布闪一下（`n.fresh` 渲染一次即被摘掉；
	# `unread`「新」角标继续保留，直到玩家点过卡片）。截图模式里不弹（像素对拍要稳），
	# 但 fresh 照样消费掉（两次截图的 fresh 状态必须收敛）。
	if bool(n.get("fresh", false)):
		desk.graph.consume_fresh(key)
		## 教学期新节点不做 0.2s 的 pop 淡入：卡片和连线要同帧出现，避免「线慢一拍」。
		## 首次铺场（`_layout_sig` 仍为空）也不弹：花园卡会先 pop 再被布局推一下，
		## 视觉上就是上下偏移；初始画面应当直接静止在最终位置。
		if not desk._shot_mode() and not desk._tutorial_active and _layout_sig != "":
			card.pivot_offset = card.size * 0.5
			card.play_pop()
			## pop 期间连线不能停在旧端点；接下来半秒逐帧重画。
			_follow_frames = maxi(_follow_frames, 30)
			desk._edges_dirty = true
			desk._wake_process()
	## 新卡一上画布就重画连线；否则同帧刚建立的边要等下一次布局/交互才出现。
	_repaint_edges()
	return card


## 播种：**只给还没落过位的节点**（x/y < 0）一个初始坐标，已落位的原样保留。
## 容器（场景 / 书桌）按 5 列网格，实体围在画布中央 —— 与 Web `layout()` 的 seed 同口径。
func _seed_one(key: String) -> void:
	var n := desk.graph.node(key)
	if n.is_empty() or (float(n.get("x", -1.0)) >= 0.0 and float(n.get("y", -1.0)) >= 0.0):
		return
	var cidx := 0
	for k in desk.graph.nodes.keys():
		var kk := String(k)
		if not desk.graph.is_container_node(kk):
			continue
		var m := desk.graph.node(kk)
		if kk == key or float(m.get("x", -1.0)) < 0.0:
			cidx += 1
	if desk.graph.is_container_node(key):
		var i := maxi(cidx - 1, 0)
		n["x"] = 200.0 + float(i % 5) * 380.0
		n["y"] = 160.0 + float(i / 5) * 300.0
	else:
		# 实体：按 key 哈希撒在中央（确定性 —— 同一份存档每次开都落在同一处）
		var h := float(abs(key.hash()) % 1000) / 1000.0
		var h2 := float(abs(key.hash() * 31) % 1000) / 1000.0
		n["x"] = 700.0 + (h - 0.5) * 420.0
		n["y"] = 560.0 + (h2 - 0.5) * 420.0


## 重画连线（Web `paintEdges()`）：端点取 `visual_center()`，四种边各自配色 / 线宽 / 虚线。
## 聚焦选中开着时，与选中节点无关的边降到 12% 不透明（Web 的 `opacity .12`）。
## 连线端点是否真的可见：卡被矩阵窗用 modulate.a=0 暂时遮掉时，不能继续画线。
func _edge_card_shown(card: NodeCard, key: String) -> bool:
	if card == null or not is_instance_valid(card):
		return false
	if String(key) == desk._drag_key:
		return true
	## 入场 pop 的前 0.2s alpha 从 0 开始；不能把它误判成矩阵遮挡而跳过连线，
	## 否则新节点出现的第一时间线是断的。
	var shown := card.visible and desk.graph != null and desk.graph.visible_node(desk.graph.node(String(key)))
	return shown and (card.modulate.a > 0.0 or card.is_popping())


## 边的可见度跟随端点卡片的 pop alpha；普通卡恒为 1。
func _edge_card_alpha(card: NodeCard) -> float:
	if card == null or not is_instance_valid(card):
		return 0.0
	if card.is_popping():
		return clampf(card.modulate.a, 0.0, 1.0)
	return 1.0


func _repaint_edges() -> void:
	desk._edges_dirty = false
	if desk._edge_layer == null or desk.graph == null:
		return
	var focus_sel := desk._selected if (desk._opt_focus and desk._selected != "" and desk.graph.nodes.has(desk._selected)) else ""
	var segs: Array = []
	for e in desk.graph.edges:
		var a := String(e.get("a", ""))
		var b := String(e.get("b", ""))
		var ca: NodeCard = desk._cards.get(a, null)
		var cb: NodeCard = desk._cards.get(b, null)
		if ca == null or cb == null:
			continue
		# 拖动中本卡被镜像隐藏（Web 也 `visibility:hidden` 原件）—— 边照常画
		if not _edge_card_shown(ca, a) or not _edge_card_shown(cb, b):
			continue
		segs.append({
			"id": "e:" + a + ">" + b + "|" + String(e.get("rel", "entity")),
			"a": ca.visual_center(), "b": cb.visual_center(),
			"kind": String(e.get("rel", "entity")),
			"dim": focus_sel != "" and a != focus_sel and b != focus_sel,
			"alpha": minf(_edge_card_alpha(ca), _edge_card_alpha(cb)),
		})
	# 「试过但没成」的边：Web 把它们当 kind=tried 的边画（`graph.tried` 里是 a>b 的字符串键）
	for raw in desk.graph.tried.keys():
		var pair := String(raw).split(">", false, 1)
		if pair.size() != 2:
			continue
		var ca: NodeCard = desk._cards.get(pair[0], null)
		var cb: NodeCard = desk._cards.get(pair[1], null)
		if ca == null or cb == null:
			continue
		if not _edge_card_shown(ca, pair[0]) or not _edge_card_shown(cb, pair[1]):
			continue
		segs.append({
			"id": "t:" + raw,
			"a": ca.visual_center(), "b": cb.visual_center(), "kind": "tried",
			"dim": focus_sel != "" and pair[0] != focus_sel and pair[1] != focus_sel,
			"alpha": minf(_edge_card_alpha(ca), _edge_card_alpha(cb)),
		})
	desk._edge_layer.set_segments(segs)


## 「前往」（Web gotoScene）：确保场景卡在画布上，镜头平移居中并选中它
func _goto_scene(id: String) -> void:
	if desk.case_def == null or desk.case_def.scene_of(id) == null:
		return
	var key := desk.graph.scene_key(id)
	var before := desk._save.snapshot()
	var was_explored := desk.graph.explored.has(id)
	if not desk.graph.nodes.has(key):
		desk.graph.add_node("loc", id)
		_spawn_card(key)
		desk.card_ui._apply_hidden()
		_relayout()
	var card: NodeCard = desk._cards.get(key, null)
	if card == null:
		return
	desk._selected = key
	desk.graph.selected = key
	_center_on(card)
	desk.chrome._apply_focus()
	desk.chrome._refresh_crumbs()
	desk._log("前往「%s」" % desk.case_def.scene_title(id), "act")
	desk._show_toast("前往「%s」" % desk.case_def.scene_title(id))
	desk.tec._on_first_expand("loc", id, was_explored)
	desk.session._commit(before)


## 把镜头平移到某张卡（只平移，不替玩家改缩放 —— 与 Web 的 focusOn 同口径）
func _center_on(card: NodeCard) -> void:
	if desk._stage == null or desk._card_layer == null:
		return
	var c := card.visual_center()
	desk._view_pos = desk._stage.size * 0.5 - c * desk._view_k
	desk._card_layer.position = desk._view_pos
	desk._view_user = true


## 指针下面是哪张卡（world 顺序里最上面那张：从后往前找）
## 指针下最上层的浮动窗（排除永远铺底的案件主窗）。卡片命中 / 落点都先过这一层，
## 保证窗体不吃穿透：作用对象只能是当前窗口。
func _floating_window_at(at_global: Vector2) -> SysWindow:
	if desk._desk == null or not is_instance_valid(desk._desk):
		return null
	for i in range(desk._desk.get_child_count() - 1, -1, -1):
		var w := desk._desk.get_child(i) as SysWindow
		if w == null or not is_instance_valid(w) or not w.visible or w == desk._case_win:
			continue
		if w.get_global_rect().has_point(at_global):
			return w
	return null


func _card_key_at(at_global: Vector2) -> String:
	## 指针落在任何浮动窗 / 人物档案卡上时，下面的卡片不可被选中 / 当作组合目标。
	if _floating_window_at(at_global) != null or desk.people._person_card_blocks(at_global):
		return ""
	for i in range(desk._card_layer.get_child_count() - 1, -1, -1):
		var card := desk._card_layer.get_child(i) as NodeCard
		if card == null or not card.visible:
			continue
		# 正在拖的卡忽略自己：它现在跟着指针走，命中自己会被误判成「拖到别的节点上」
		if card.card_key == desk._drag_key:
			continue
		if card.get_global_rect().grow(-NodeCard.PAD * 0.5).has_point(at_global):
			return card.card_key
	return ""


## 把人物叫到画面中央（Web `gotoChar`）：没节点就补一个、在袋里就取回，然后居中 + 选中。
func _goto_char(id: String) -> bool:
	if desk.case_def == null:
		return false
	var key := desk.graph.key_of("char", id)
	var ch := desk.case_def.char_of(id)
	var label := ch.name if ch != null and ch.name != "" else id
	var before := desk._save.snapshot() if desk._save != null else {}
	var spawn := false
	if not desk.graph.nodes.has(key):
		var n := desk.graph.add_node("char", id)
		if String(n.get("home_scene", "")) == "":
			n["home_scene"] = desk.graph.last_scene
		spawn = true
	if desk.graph.stored.has(key):
		desk.graph.take_back(key)
		spawn = true
	if spawn or not desk._cards.has(key):
		_refresh_or_spawn_card(key)
		_relayout()
	else:
		var card0: NodeCard = desk._cards[key]
		card0.visible = desk.graph.visible_node(desk.graph.node(key))
	_repaint_edges()
	var card: NodeCard = desk._cards.get(key, null)
	if card != null:
		_center_on(card)
	desk.card_ui._on_card_selected(key)
	## S12：对话窗开着时不再误报「暂无对话文本」——把现有对话提层，等玩家看完。
	if desk._chat_win != null and is_instance_valid(desk._chat_win):
		desk.windows._raise_to_front(desk._chat_win)
		desk.session._commit(before)
		return true
	if desk.card_ui._say_next_line(id):
		return true
	desk._show_toast("「%s」\n（暂无对话文本）" % label, true)
	desk.session._commit(before)
	return true


func _refresh_or_spawn_card(key: String) -> void:
	var card: NodeCard = desk._cards.get(key, null)
	if card == null:
		card = _spawn_card(key)
	if card != null:
		card.visible = desk.graph.visible_node(desk.graph.node(key))
		card.refresh()
		_sync_card_shell(card)


func _sync_card_shell(card: NodeCard) -> void:
	if card == null or desk.graph == null:
		return
	var n := desk.graph.node(card.card_key)
	var id := String(n.get("id", ""))
	card.set_shell_state(desk.graph.is_container_node(card.card_key),
		desk.graph.explored.has(id), desk.graph.is_collapsed(id), bool(n.get("unread", false)),
		desk.graph.is_hub(String(n.get("kind", "")), id))
	## 教学是线性引导，不挂「无文本入口」警告；TEC办公室尤其不该因为不需要叙事而被标红。
	card.set_warn(not desk._tutorial_active and desk.graph.is_no_entry(card.card_key))


func _layout_signature() -> String:
	var keys: Array = []
	for key in desk._cards.keys():
		if (desk._cards[key] as NodeCard).visible:
			keys.append(String(key))
	keys.sort()
	return "|".join(PackedStringArray(keys))


## 布局（对齐 Web `layout()`）：**松弛一次**，不是重新排版。
##   - 只给「从没落过位」的节点播种（x/y < 0）；已落位的保留；
##   - 右键钉住的节点在松弛中完全不动（这是「把摆位留住」的唯一手段）；
##   - 纯状态变化（点亮 / 捕获 / 选中）不跑力导向 —— 那些只需要 `_apply_hidden()` / `refresh()`。
##
## 为什么用「可见集合签名」而不是在几十个调用点上加 `if`：260 轮松弛**并不收敛**
## （实测同一批节点连跑 8 次，单次最大位移 194 → 72 → 38 → 21 → 12 → 6.9 → 3.9 → 2.3 → 1.3px），
## 所以每多跑一次，全画布就整体漂一次。旧版无条件跑，双击点亮手电筒都会把 8 张卡一起推走。
## 收敛靠调用次数而不是靠这里多跑几轮：Web 也只在新节点出现时 `layout()`。
## `force` = 用户显式要求「现在就按当前结构重排」（页眉开关）；测试伪造数据位时也用它。
func _relayout(animated := false, force := false) -> void:
	var sig := _layout_signature()
	var new_keys: Array = _fresh_spawns.duplicate()
	_fresh_spawns.clear()
	if force or sig != _layout_sig:
		var initial: bool = _layout_sig == ""
		# 这次从隐藏变可见的旧卡（折叠容器重新展开）：它们也要按新卡处理，
		# 否则 sig 变了但 new_keys 为空，会退回全量力导向把整屏推走。
		var prev_visible := {}
		for k in _layout_sig.split("|", false):
			prev_visible[String(k)] = true
		var shown_keys: Array = []
		for key in desk._cards.keys():
			var c: NodeCard = desk._cards[key]
			if c != null and is_instance_valid(c) and c.visible and not prev_visible.has(String(key)):
				shown_keys.append(String(key))
		_layout_sig = sig
		if desk._tutorial_active:
			desk.tutorial._layout_tutorial()
		elif not force and not initial:
			## 常规展开 / 折叠：现有卡片一张都不动，只把新出现 / 新上画的节点摆在触发卡周围。
			## 不跑力导向、不 fit 镜头，标题保持 LOD 文字档。
			var moving: Array = new_keys.duplicate()
			for k in shown_keys:
				if not moving.has(k):
					moving.append(k)
			_place_new_cards(moving)
		else:
			## 首次铺场 / 重置：一次算完并落位，不要分帧「飘过去」。
			## 否则花园卡会先被 pop 缩放、再被力导向逐帧推几像素，看起来像上下抖。
			_layout_force(animated, force or initial)
			## 自动档才重框；玩家自己调过镜头（滚轮 / 拖空白 / 定位某张卡）就别动他的视野，
			## 否则每加一个节点、镜头就被拉开一次 —— 刚放大到某张卡细看时会像「被抢走」。
			if desk._opt_reveal and not desk._view_user:
				_fit_cards()
	desk.chrome._refresh_crumbs()
	desk.chrome._sync_header_sizes()
	_repaint_edges()
	_reanchor_mem_card()
	desk.matrix._sync_matrix_occlusion()


## 常规展开的稳定落位：以触发卡为锚，把新卡摆在外圈，避开已经可见的卡片。
## 不移动旧卡、不跑力导向、不自动 fit —— 点开容器时玩家先看到完整标题。
func _place_new_cards(keys: Array) -> void:
	if keys.is_empty() or desk._cards.is_empty():
		return
	var fresh := {}
	for k in keys:
		fresh[String(k)] = true
	var anchor_key := ""
	for key in fresh.keys():
		for e in desk.graph.edges:
			var other := ""
			if String(e.get("a", "")) == String(key):
				other = String(e.get("b", ""))
			elif String(e.get("b", "")) == String(key):
				other = String(e.get("a", ""))
			if other == "" or fresh.has(other):
				continue
			var c: NodeCard = desk._cards.get(other, null)
			if c != null and is_instance_valid(c) and c.visible:
				anchor_key = other
				break
		if anchor_key != "":
			break
	if anchor_key == "" and fresh.has(desk._selected):
		anchor_key = desk._selected
	var anchor_center := Vector2.ZERO
	if anchor_key != "" and desk._cards.has(anchor_key):
		anchor_center = (desk._cards[anchor_key] as NodeCard).visual_center()
	else:
		anchor_center = (desk._stage.size * 0.5 - desk._view_pos) / maxf(desk._view_k, 0.01)
	var occupied: Array[Rect2] = []
	for k in desk._cards.keys():
		var c: NodeCard = desk._cards[k]
		if c == null or not is_instance_valid(c) or not c.visible or fresh.has(String(k)):
			continue
		occupied.append(c.visual_rect())
	var slots: Array[Vector2] = []
	for ring in 3:
		var radius := 230.0 + float(ring) * 150.0
		for i in 8:
			var ang := TAU * float(i) / 8.0 + float(ring) * 0.35
			slots.append(Vector2(cos(ang), sin(ang)) * radius)
	var slot_i := 0
	for key in fresh.keys():
		var card: NodeCard = desk._cards.get(String(key), null)
		if card == null or not is_instance_valid(card):
			continue
		var n := desk.graph.node(String(key))
		if n.is_empty():
			continue
		var placed := false
		for _try in slots.size():
			var p: Vector2 = anchor_center + slots[slot_i % slots.size()]
			slot_i += 1
			p -= card.size * 0.5
			p = Vector2(clampf(p.x, 64.0, Desktop.WORLD_W - 224.0),
				clampf(p.y, 56.0, Desktop.WORLD_H - 120.0))
			p = p.snapped(Vector2(8, 8))
			var box := Rect2(p + Vector2(NodeCard.PAD, NodeCard.PAD),
				card.size - Vector2(NodeCard.PAD * 2.0, NodeCard.PAD * 2.0))
			var clash := false
			for r in occupied:
				if r.grow(10.0).intersects(box):
					clash = true
					break
			if clash:
				continue
			_kill_move(String(key))
			n["x"] = p.x
			n["y"] = p.y
			card.set_home_silent(p)
			card.position = p
			card.set_lod(desk._view_k)
			occupied.append(card.visual_rect())
			placed = true
			break
		if not placed:
			# 极端拥挤：仍然落在锚点旁边，但不改旧卡位置。
			var p: Vector2 = anchor_center + Vector2(230.0, 230.0) - card.size * 0.5
			p = Vector2(clampf(p.x, 64.0, Desktop.WORLD_W - 224.0),
				clampf(p.y, 56.0, Desktop.WORLD_H - 120.0)).snapped(Vector2(8, 8))
			_kill_move(String(key))
			n["x"] = p.x
			n["y"] = p.y
			card.set_home_silent(p)
			card.position = p
			card.set_lod(desk._view_k)
	_repaint_edges()
	## 只平移、不缩放：把新节点纳入当前视口，文字仍是 1x/0.95x 档。
	_pan_to_include(fresh.keys())


## 最小平移让这批卡片完整进入 stage（四周留 40px）。不动倍率，所以不会把标题缩成符号。
func _pan_to_include(keys: Array) -> void:
	if keys.is_empty() or desk._stage == null or not is_instance_valid(desk._stage):
		return
	var box := Rect2()
	var has := false
	for raw in keys:
		var c: NodeCard = desk._cards.get(String(raw), null)
		if c == null or not is_instance_valid(c) or not c.visible:
			continue
		var s := Rect2(desk._view_pos + c.position * desk._view_k, c.size * desk._view_k)
		box = s if not has else box.merge(s)
		has = true
	if not has:
		return
	var stage := desk._stage.size
	var margin := 40.0
	var p := desk._view_pos
	if box.end.x > stage.x - margin:
		p.x -= box.end.x - (stage.x - margin)
	if box.position.x < margin:
		p.x += margin - box.position.x
	if box.end.y > stage.y - margin:
		p.y -= box.end.y - (stage.y - margin)
	if box.position.y < margin:
		p.y += margin - box.position.y
	if p != desk._view_pos:
		desk._view_pos = _clamp_view_pos(p)
		_apply_view()


## 力导向：斥力 30000/d²、最小间距 R_a+R_b+14、弹簧 rest 185/300/150、向心 0.0022，260 轮。
## 参数照抄 `src/js/07-render.js`；R 用视觉半径（半对角线），与 Web 的 80 / 68 同口径。
func _layout_force(animated: bool = false, force := false) -> void:
	var list: Array = []
	for key in desk._cards.keys():
		if (desk._cards[key] as NodeCard).visible:
			list.append(String(key))
	if list.is_empty():
		return
	_layout_job = ForceLayoutScript.new()
	_layout_job.prepare(desk.graph, list)
	desk._wake_process()
	## 无头 / 截图 / 页眉「立即重排」：一次跑完，坐标语义不变。
	## 常规展开：先跑 40 轮把大致形状铺开，剩余 220 轮交给 _process 每帧 8 轮，
	## 避免 60 节点时 46 万次对迭代把一帧卡死（F1）。
	var sync := force or desk._shot_mode() or DisplayServer.get_name() == "headless"
	_layout_job.step(ForceLayoutScript.TOTAL_ROUNDS if sync else Desktop.LAYOUT_QUICK_ROUNDS)
	_apply_layout_job(animated, not sync)
	if sync:
		_layout_job = null


func _cancel_layout_job() -> void:
	_layout_job = null


## 把求解器当前坐标写回图与卡片。progressive=true 时逐帧直落（物理收敛观感），
## 不启动 0.34s 补间，否则每帧都会重新起一条 tween。
func _apply_layout_job(animated: bool, progressive: bool) -> void:
	if _layout_job == null:
		return
	for key in _layout_job.keys:
		var n := desk.graph.node(String(key))
		if n.is_empty():
			continue
		var card: NodeCard = desk._cards.get(String(key), null)
		var p: Vector2 = _layout_job.pos[key]
		if not bool(_layout_job.free[key]):
			n["x"] = p.x
			n["y"] = p.y
			continue
		## P2：自动摆卡落 8px 网格。边界也取 8 的倍数，保证靠边时仍对齐；
		## 手动拖动的落点由 `NodeCard._clamp_pos()` 同样吸到 8px 网格（C3）。
		p = Vector2(clampf(p.x, 64.0, Desktop.WORLD_W - 224.0),
			clampf(p.y, 56.0, Desktop.WORLD_H - 120.0))
		p = p.snapped(Vector2(8, 8))
		n["x"] = p.x
		n["y"] = p.y
		if card == null or not is_instance_valid(card):
			continue
		var before_pos: Vector2 = card.position
		card.set_home_silent(p)
		var fp: bool = bool(_layout_job.first_place.get(String(key), false))
		if progressive or fp or not animated or desk._shot_mode() or before_pos.distance_to(p) < 2.0:
			card.position = p
		else:
			_start_move_tween(String(key), card, p)

func _start_move_tween(key: String, card: NodeCard, p: Vector2) -> void:
	_kill_move(key)
	var tw := card.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(card, "position", p, 0.34)
	tw.finished.connect(func() -> void:
		_move_twens.erase(key)
		card.position = p
		# 锚在它身上的浮层（回忆放映卡 / 叙事卡）跟着落地重锚，否则卡片停在节点半路的位置上
		if desk.narrative._mem_anchor_key == key and desk._mem_card != null and is_instance_valid(desk._mem_card):
			desk.narrative._anchor_card_to(desk._mem_card, key)
		_repaint_edges(), CONNECT_ONE_SHOT)
	_move_twens[key] = tw
	_follow_frames = maxi(_follow_frames, 21)   # ≈420ms @ 60fps（Web paintEdgesFor(420)）
	desk._wake_process()


func _kill_move(key: String) -> void:
	if _move_twens.has(key):
		(_move_twens[key] as Tween).kill()
		_move_twens.erase(key)


func _fit_cards(keep_titles := true) -> void:
	if desk._card_layer == null:
		return
	var bounds := Rect2()
	var has_card := false
	for c in desk._card_layer.get_children():
		var card := c as NodeCard
		if card == null or not card.visible:
			continue
		# 用数据里的最终位（过渡动画期间 card.position 还在路上，镜头该框的是终点）
		var n := desk.graph.node(card.card_key)
		var at := Vector2(float(n.get("x", card.position.x)), float(n.get("y", card.position.y)))
		var r := Rect2(at + Vector2(NodeCard.PAD, NodeCard.PAD),
			card.size - Vector2(NodeCard.PAD * 2.0, NodeCard.PAD * 2.0))
		if has_card:
			bounds = bounds.merge(r)
		else:
			bounds = r
			has_card = true
	if not has_card or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		desk._view_k = 1.0
		desk._view_pos = Vector2.ZERO
		desk._card_layer.position = Vector2.ZERO
		desk._card_layer.scale = Vector2.ONE
		desk._view_user = false
		return
	## 按包围盒缩放（0.45~1.3）：节点多到一屏装不下时缩出去，才是「适应窗口」的本义。
	## 缩出来的非整数倍由 LOD 兜住 —— 读不清的倍率下副标与角标已经退场，不会留下糊字。
	var pad := 60.0
	var k := minf((desk._stage.size.x - pad * 2.0) / bounds.size.x,
		(desk._stage.size.y - pad * 2.0) / bounds.size.y)
	var floor_k := Desktop.FIT_TEXT_MIN if keep_titles else Desktop.ZOOM_MIN
	desk._view_k = clampf(k, floor_k, Desktop.FIT_MAX)
	## U1：fit 结果也过一遍 1.0 吸附带，别让「适应窗口」停在 0.97 这种非原生倍率。
	if absf(desk._view_k - 1.0) < Desktop.ZOOM_SNAP:
		desk._view_k = 1.0
	var z := desk._zoom_override()
	if z > 0.0:
		desk._view_k = z
	desk._view_pos = (desk._stage.size - bounds.size * desk._view_k) * 0.5 - bounds.position * desk._view_k
	desk._view_user = false
	_apply_view()
