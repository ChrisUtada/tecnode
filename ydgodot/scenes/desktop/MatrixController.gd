class_name MatrixController
extends Node
## 由 Desktop 挂载的子系统控制器。
## 过渡期直接通过注入的 `desk` 访问宿主成员；搬出的函数名保持不变。

var desk: Desktop


func _toggle_matrix() -> void:
	if not desk.session._require_case():
		return
	if desk._matrix_win != null and is_instance_valid(desk._matrix_win):
		_restore_matrix_occlusion()
		desk._matrix_win.queue_free()
		desk._matrix_win = null
		desk.windows._place_floating_windows()
		return
	desk._matrix_win = MatrixWin.new()
	desk._matrix_win.name = "matrix_win"
	desk._matrix_win.setup_matrix(desk.graph, desk.case_def)
	desk._matrix_win.position = Vector2(336, 40)
	desk._matrix_win.clue_taken.connect(_on_matrix_took)
	desk._matrix_win.clue_shown.connect(_on_matrix_chip_shown)
	desk._matrix_win.clue_dropped.connect(_on_matrix_dropped)
	desk._matrix_win.inference_requested.connect(_run_inference)
	desk._matrix_win.seed_dropped.connect(desk.garden_music._on_seed_dropped)
	## A7：用户点窗内 × 关闭时也要恢复被淡出的卡片；不能只覆盖图标开关那条路径。
	desk._matrix_win.closed.connect(_on_matrix_closed)
	# 线索卡拖动的镜像挂在桌面上（桌布自己 clip_contents，镜像挂里面拖到边缘会被裁掉）
	desk._matrix_win.drag_host = desk._desk
	desk._matrix_win.item_rect_changed.connect(_sync_matrix_occlusion)
	desk._desk.add_child(desk._matrix_win)
	desk.windows._place_z(desk._matrix_win, Desktop.ZR_WIN)
	## 打开推演就算离开「整理桌面」的提醒步骤；收纳不是硬门槛。
	if desk._tutorial_active and desk._tutorial_step == Desktop.TutorialStep.STORE_SUPPLIES:
		desk.tutorial._tutorial_begin_infer()
	desk.windows._place_floating_windows()
	_sync_matrix_occlusion.call_deferred()
	if desk._tutorial_active and desk._tutorial_step == Desktop.TutorialStep.INFER:
		desk.tutorial._tutorial_on_matrix_changed()


## A7：矩阵窗会把正下方的卡片遮得只剩一条白边，看起来像窗口漏了一块。
## 只对「大部分面积都被窗盖住」的卡片淡出；拖窗时实时重算，关窗恢复。
## 用 modulate 而非 visible：_layout_force 只排可见卡片，隐藏会让别的卡重排。
func _sync_matrix_occlusion() -> void:
	_restore_matrix_occlusion()
	if desk._matrix_win == null or not is_instance_valid(desk._matrix_win) or not desk._matrix_win.visible:
		return
	var win := Rect2(desk._matrix_win.global_position, desk._matrix_win.size)
	for key in desk._cards.keys():
		var c: NodeCard = desk._cards[key]
		if c == null or not is_instance_valid(c) or not c.visible or c.modulate.a <= 0.0:
			continue
		var box := Rect2(c.global_position, c.size)
		var hit := win.intersection(box)
		var area := box.size.x * box.size.y
		if area <= 0.0:
			continue
		if hit.size.x * hit.size.y < area * 0.6:
			continue
		c.modulate.a = 0.0
		c.process_mode = Node.PROCESS_MODE_DISABLED
		desk._matrix_faded.append(key)


func _restore_matrix_occlusion() -> void:
	for key in desk._matrix_faded:
		var c: NodeCard = desk._cards.get(String(key), null)
		if c != null and is_instance_valid(c):
			c.modulate.a = 1.0
			c.process_mode = Node.PROCESS_MODE_INHERIT
	desk._matrix_faded.clear()


func _on_matrix_closed() -> void:
	_restore_matrix_occlusion()
	desk._matrix_win = null
	desk.windows._place_floating_windows()


## 画布 / 证据 → 桌布。感官自动取证自身的 sense。
func _assign_to_matrix(key: String) -> bool:
	var n := desk.graph.node(key)
	if n.is_empty():
		return false
	if not desk.drag._is_zheng_node(n):
		var why := "推演桌布只收带五感的证；词先和物合成。" if n.kind == "evidence" \
			else "推演桌布只收证；物是原料。"
		if desk._tutorial_active and desk._tutorial_step == Desktop.TutorialStep.INFER:
			desk.tutorial._tutorial_say(why)
		else:
			desk.drag._reject_drop(why)
		return false
	var ev := desk.case_def.evidence_of(n.id)
	if ev == null:
		return false
	## 收纳是可选的：直接拖证上桌布也视为进入推演。
	if desk._tutorial_active and desk._tutorial_step == Desktop.TutorialStep.STORE_SUPPLIES:
		desk.tutorial._tutorial_begin_infer()
	var before := desk._save.snapshot()
	if not desk.graph.matrix_assign(key):
		desk.drag._reject_drop("「%s」的感官类型是%s，无法放到推演桌布。" % [n.label, MatrixState.SENSE_NAMES.get(ev.sense, ev.sense)])
		return false
	desk.card_ui._apply_hidden()
	desk.canvas._refresh_or_spawn_card(key)
	_refresh_matrix_views()
	desk.tutorial._tutorial_on_matrix_changed()
	desk.session._commit(before)
	return true


## K2：桌布线索引单击 = 看详情，和画布节点同一套语义（取回只走按钮 / 拖出）。
func _on_matrix_chip_shown(key: String) -> void:
	if desk.graph == null or not desk.graph.nodes.has(key):
		return
	desk.card_ui._on_card_selected(key)


func _on_matrix_took(key: String, at_global: Vector2 = Vector2(-1.0, -1.0)) -> void:
	var before := desk._save.snapshot()
	# 带坐标取回（Web `boardTake(cid, sense, cx, cy)`）：落在松手那一点。换算与 `_finish_sdrag` 同一条公式。
	var world := Vector2(-1.0, -1.0)
	if at_global.x >= 0.0:
		world = (at_global - desk._stage.get_global_position() - desk._view_pos) / maxf(desk._view_k, 0.01)
		world.x = maxf(0.0, world.x)
		world.y = maxf(0.0, world.y)
	if not desk.graph.matrix_take(key, world.x, world.y):
		return
	desk.card_ui._apply_hidden()
	desk.canvas._refresh_or_spawn_card(key)
	if world.x >= 0.0:
		var card := desk._cards.get(key, null) as NodeCard
		if card != null:
			card.position = world
			card.set_home(world)
	desk.canvas._repaint_edges()
	_refresh_matrix_views()
	desk.tutorial._tutorial_on_matrix_changed()
	desk.session._commit(before)


## 桌布上的证拖到「证据」（窗**或图标**）= 改归证据；
## 拖出桌布落到别处 = **带坐标**取回画布。
func _on_matrix_dropped(key: String, at_global: Vector2) -> void:
	var target: Dictionary = desk.drag._drop_target_at(at_global)
	var tid := String(target.get("id", "")) if not target.is_empty() else ""
	if tid != "":
		desk.drag._dispatch_drop(key, tid, at_global, "matrix")
		return
	var blocked: String = desk.drag._drop_blocker_at(at_global)
	if blocked != "":
		desk.drag._reject_drop(blocked)
		return
	## 桌布线索引拖到别的窗体 / 人物档案卡时留在桌布上，不要穿透掉落。
	if desk.canvas._floating_window_at(at_global) != null or desk.people._person_card_blocks(at_global):
		return
	## K4：拖到画布之外（顶栏 / 桌面空白）不写回负坐标，留在桌布原处。
	if not desk._stage.get_global_rect().has_point(at_global):
		desk._show_toast("这里放不下，已留在桌布上。", true)
		return
	_on_matrix_took(key, at_global)


func _on_ledger_to_matrix(key: String) -> void:
	## C6：证据行内按钮必须和拖到「推演」图标走同一条教学守卫。
	if desk._tutorial_active and desk._tutorial_step == Desktop.TutorialStep.STORE_SUPPLIES:
		desk.tutorial._tutorial_begin_infer()
	var before := desk._save.snapshot()
	if desk.graph.matrix_assign(key):
		desk.card_ui._apply_hidden()
		_refresh_matrix_views()
		desk.tutorial._tutorial_on_matrix_changed()
		desk.session._commit(before)
	else:
		if not desk.tutorial._tutorial_correct("这条证没有可用的感官槽位。"):
			desk.drag._reject_drop("这条证没有可用的感官槽位。")


func _refresh_matrix_views() -> void:
	if desk._matrix_win != null and is_instance_valid(desk._matrix_win):
		desk._matrix_win.refresh_matrix()
		desk._matrix_win.refresh_seed()
	if desk._bag_win != null and is_instance_valid(desk._bag_win):
		desk._bag_win.refresh_store()
	if desk._ledger_win != null and is_instance_valid(desk._ledger_win):
		desk._ledger_win.refresh_store()
	if desk._ledger_win != null and is_instance_valid(desk._ledger_win):
		desk._ledger_win.refresh_store()


## 长按蓄力完成 → 配方判定：恰好命中才算，多余的证也失败
func _run_inference() -> void:
	var hit := desk.graph.match_ending()
	if desk._tutorial_active:
		if desk._tutorial_step == Desktop.TutorialStep.INFER:
			if hit == null or hit.id != Desktop.TUT_ENDING_ID:
				if desk._matrix_win != null and is_instance_valid(desk._matrix_win):
					desk._matrix_win.show_heartbroken()
					desk._matrix_win.set_hint("TEC：配方不对——只需要「调查员证」一条证。")
				return
			desk.tutorial._tutorial_on_inference_success(hit)
			return
		## 领证 / 选案阶段重开推演：教学已经结束，不能落入正式结局幕。
		if desk._matrix_win != null and is_instance_valid(desk._matrix_win):
			desk._matrix_win.show_heartbroken()
			desk._matrix_win.set_hint("TEC：取证流程已经走完了。")
		return
	if hit == null:
		## 失败要指向下一步：空桌布 vs 有证但配方/数量不对。
		var why := "推演桌布上还没有证。先把证放到推演桌布。"
		if desk.graph.matrix_count() > 0:
			why = "当前证据组合没有对应结局。检查配方与证的数量，取回多余的证再试。"
		if desk._matrix_win != null and is_instance_valid(desk._matrix_win):
			desk._matrix_win.show_heartbroken()
			desk._matrix_win.set_hint("TEC：" + why)
		desk._log("推演失败：" + why, "warn")
		desk._show_toast("推演失败：" + why, true)
		return
	var before := desk._save.snapshot()
	desk.graph.mark_ending(hit.id)
	desk._last_ending_id = hit.id
	## S5：真名种子在「结局触发」这一刻就落进图与存档，收幕只是演出。
	## 玩家在遮罩亮着时直接退出，下次读档也不会丢种子。
	if hit.is_true_capture:
		GardenSystem.normalize(desk.graph, desk.case_def)
	if hit.is_true_capture and not desk._progress_read_only:
		desk._catalog.mark_completed(desk._active_case)
		if desk._catalog.unlock_next(desk._active_case):
			desk._log("新案件地址已解锁：%s" % desk.session._next_case_code(desk._active_case), "cap")
		desk.session._update_case_park_ui()
	if desk._matrix_win != null and is_instance_valid(desk._matrix_win):
		desk._matrix_win.play_shock()
	desk._log("结局达成：%s" % hit.name, "cap")
	desk._ending.play(hit)
	desk.session._commit(before)
	if hit.is_true_capture:
		## 不等 180ms 合并窗：结局触发即落盘，遮罩期间退出也不丢种子。
		desk.session._autosave()
