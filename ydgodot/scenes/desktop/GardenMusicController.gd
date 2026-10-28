class_name GardenMusicController
extends Node
## 由 Desktop 挂载的子系统控制器。
## 过渡期直接通过注入的 `desk` 访问宿主成员；搬出的函数名保持不变。

var desk: Desktop


func setup_ending() -> void:
	desk.add_child(desk._ending)
	desk._ending.setup_overlay()
	if not desk._ending.finished.is_connected(_on_ending_finished):
		desk._ending.finished.connect(_on_ending_finished)


func _music_unlocked() -> bool:
	if desk.graph == null:
		return false
	for n in desk.graph.nodes.values():
		var ins = n.get("installed", {})
		if ins is Dictionary and bool(ins.get("ITEMS_cz", false)):
			return true
	return false


func _open_music() -> void:
	if not _music_unlocked():
		return
	if desk._music_win == null or not is_instance_valid(desk._music_win):
		desk._music_win = MusicWin.new()
		desk._music_win.name = "music_win"
		desk._music_win.setup_music()
		desk._music_win.closed.connect(_on_music_closed)
		desk._music_win.minimized.connect(_minimize_music)
		desk._music_win.progress_changed.connect(_on_music_progress)
		desk._desk.add_child(desk._music_win)
		_place_music_windows()
	desk.windows._place_z(desk._music_win, Desktop.ZR_WIN)
	desk._music_win.visible = true
	if desk._music_dock != null:
		desk._music_dock.visible = false


func _ensure_music_dock() -> MusicDock:
	if desk._music_dock != null and is_instance_valid(desk._music_dock):
		return desk._music_dock
	desk._music_dock = MusicDock.new()
	desk._music_dock.name = "music_dock"
	desk._music_dock.setup_dock()
	desk._music_dock.restore_requested.connect(_restore_music)
	desk._music_dock.toggle_requested.connect(_toggle_music)
	desk._music_dock.stop_requested.connect(_stop_music)
	desk._music_dock.moved.connect(desk._place_toast_anchor)
	desk._desk.add_child(desk._music_dock)
	desk._music_dock.visible = false
	_place_music_windows()
	return desk._music_dock


func _place_music_windows() -> void:
	var desk_h := desk._desk.size.y if desk._desk != null and is_instance_valid(desk._desk) else desk._vh() - Desktop.HEADER_H
	if desk._music_win != null and is_instance_valid(desk._music_win):
		desk._music_win.position = Vector2(
			minf(906.0, desk._vw() - 14.0 - desk._music_win.size.x),
			minf(414.0, desk_h - 12.0 - desk._music_win.size.y))
	if desk._music_dock != null and is_instance_valid(desk._music_dock):
		if desk._music_dock.user_placed():
			desk._music_dock.clamp_into_parent()
		else:
			desk._music_dock.position = Vector2(
				minf(1026.0, desk._vw() - 16.0 - desk._music_dock.size.x),
				minf(532.0, desk_h - 16.0 - desk._music_dock.size.y))


func _minimize_music() -> void:
	if desk._music_win == null:
		return
	desk._music_win.visible = false
	var dock := _ensure_music_dock()
	dock.update_state(desk._music_win.state())
	dock.visible = true
	desk.windows._place_z(dock, Desktop.ZR_DOCK)


func _restore_music() -> void:
	if desk._music_win == null or not is_instance_valid(desk._music_win):
		_open_music()
		if desk._music_dock != null:
			desk._music_dock.visible = false
		return
	desk._music_win.visible = true
	desk.windows._place_z(desk._music_win, Desktop.ZR_WIN)
	if desk._music_dock != null:
		desk._music_dock.visible = false


func _on_music_closed() -> void:
	if desk._music_win != null:
		desk._music_win.visible = false
	if desk._music_dock != null:
		desk._music_dock.visible = false
	if desk._music_win != null and desk._music_win.is_playing():
		desk._show_toast("播放器已收起，音乐继续")


func _on_music_progress(_cur: float, _dur: float) -> void:
	if desk._music_dock != null and desk._music_dock.visible and desk._music_win != null:
		desk._music_dock.update_state(desk._music_win.state())


func _toggle_music() -> void:
	if desk._music_win == null:
		return
	desk._music_win.toggle_current()
	if desk._music_dock != null and desk._music_dock.visible:
		desk._music_dock.update_state(desk._music_win.state())


func _stop_music() -> void:
	if desk._music_win == null:
		return
	desk._music_win.stop()
	if desk._music_dock != null:
		desk._music_dock.visible = false


func _open_garden() -> void:
	if not GardenSystem.has_garden(desk.graph):
		return
	if desk._garden_win != null and is_instance_valid(desk._garden_win):
		desk._garden_win.refresh()
		desk.windows._raise_to_front(desk._garden_win)
		return
	GardenSystem.normalize(desk.graph, desk.case_def)
	desk._garden_win = GardenWin.new()
	desk._garden_win.name = "garden_win"
	desk._garden_win.setup_garden(desk.graph, desk.case_def)
	desk._garden_win.writes_enabled = desk._case_open
	desk._garden_win.closed.connect(func(): desk._garden_win = null)
	desk._garden_win.plant_moved.connect(func(_idx): desk.session._autosave())
	desk._garden_win.garden_changed.connect(_on_garden_changed)
	desk._garden_win.plot_bloomed.connect(_on_garden_bloomed)
	desk._desk.add_child(desk._garden_win)
	desk.windows._place_z(desk._garden_win, Desktop.ZR_WIN)
	desk.windows._place_floating_windows()


func _on_garden_changed() -> void:
	desk.session._autosave()
	desk.launcher._refresh_app_icons()


func _on_garden_bloomed(_idx: int, fresh: bool) -> void:
	if fresh:
		desk._show_toast("花园里的种子开花了")


## 种子从桌布拖到花园窗 / 花园图标；成功返回 true，MatrixWin 据此决定是否弹回。
func _drop_seed(at_global: Vector2) -> bool:
	if desk.graph == null or not GardenSystem.has_garden(desk.graph):
		return false
	if not bool(desk.graph.garden.get("seed", false)):
		return false
	var spot := {}
	var over_win := desk._garden_win != null and is_instance_valid(desk._garden_win) \
		and desk._garden_win.get_global_rect().has_point(at_global)
	var over_icon := desk._garden_btn != null and desk._garden_btn.visible \
		and desk._garden_btn.get_global_rect().has_point(at_global)
	if over_win:
		spot = desk._garden_win.spot_of_global(at_global)
	elif over_icon:
		spot = GardenSystem.spot_of(GardenSystem.DEFAULT_X, GardenSystem.DEFAULT_Y)
	else:
		return false
	var before := desk._save.snapshot() if desk._save != null else {}
	if not GardenSystem.plant(desk.graph, float(spot["x"]), float(spot["y"])):
		return false
	GardenSystem.normalize(desk.graph, desk.case_def)
	desk.session._commit(before)
	if desk._matrix_win != null and is_instance_valid(desk._matrix_win):
		desk._matrix_win.refresh_seed()
	if desk._garden_win != null and is_instance_valid(desk._garden_win):
		desk._garden_win.refresh()
		if over_icon:
			desk.windows._place_z(desk._garden_win, Desktop.ZR_WIN)
	else:
		_open_garden()
	desk.launcher._refresh_app_icons()
	desk._show_toast("种下了「真名」")
	return true


func _on_seed_dropped(at_global: Vector2) -> void:
	_drop_seed(at_global)


func _on_ending_finished() -> void:
	if desk._last_ending_id == "":
		return
	var e := desk.case_def.ending_by_id(desk._last_ending_id)
	if e == null:
		return
	## G6：普通结局也要给接续提示，不能演完就静场。
	if not e.is_true_capture:
		desk.session._autosave()
		desk.chrome._refresh_crumbs()
		var got := desk.graph.endings.size()
		var total := desk.case_def.endings.size()
		var name := e.name if e.name != "" else e.id
		var msg := "已记录「%s」结局（%d/%d）· 可以继续调查，寻找「真名」" % [name, got, total]
		desk._log(msg, "sys")
		desk._show_toast(msg)
		return
	## S5：正常路径的种子在 `_run_inference()` 已经发好；这里只做收幕后的展示。
	## 保留 normalize / grant_seed 兜底（截图与调试钩子会直接播遮罩、不经过推演）。
	var garden := GardenSystem.normalize(desk.graph, desk.case_def)
	if not bool(garden.get("seed", false)) and not GardenSystem.grant_seed(desk.graph, e.message, desk.case_def):
		return
	desk.session._autosave()
	desk.chrome._refresh_crumbs()
	if desk._matrix_win != null and is_instance_valid(desk._matrix_win):
		desk._matrix_win.refresh_seed()
	desk.launcher._refresh_app_icons()
	desk._show_toast("结局留下了一枚种子。把桌布上的种子拖到左侧「花园」图标。")
