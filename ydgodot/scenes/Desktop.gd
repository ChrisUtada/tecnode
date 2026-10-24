extends Control
## 桌面外壳 + 画布 + P0 垂直切片链路
##
## 切片（计划 §三 P0）：花园展开 → 手电筒拖到黑影 → 尸体场景 → TEC 分析计时 → 结局演出。
## 数据直读 `data/case-a001.json`（P0 允许），逻辑全在 core/ 里，本文件只管「搭界面 + 接线」。

const HEADER_H := 52.0
## 设计基准分辨率：**16:9**。注意它现在只是「默认窗口尺寸 + Web 版对拍口径」，
## **不再是逻辑坐标系** —— `content_scale_mode = DISABLED` 之后，逻辑尺寸 = 窗口像素，
## 界面贴着窗口右下边的东西一律用 `_vw()` / `_vh()` 现算（见 `_layout_root()`）。
## 为什么放弃整体放大：点阵字体只在 12 的整数倍像素落得下原字格，1920×1080 的可用区
## 算出来是 1.444x，整屏字发胖发糊（docs/font_scale.png）。
const DESIGN_W := 1280.0
const DESIGN_H := 720.0
## 窗口最小尺寸：再小左栏（86）+ 画布就挤成一团，也给 `_vw()` 一个兜底。
const MIN_W := 960
const MIN_H := 560
const SLICE_SCENE := "SCENES_garden"
const CARD_PAD := 8.0
const MEM_CARD_MIN_X := 132.0
## 画布世界尺寸（对齐 Web `#world{width:2000px;height:1300px}`）。
## 卡片坐标存在 world 空间里；`_card_layer` 只做「平移 + 缩放」的视口变换。
const WORLD_W := 2000.0
const WORLD_H := 1300.0
const AUTOSAVE_DELAY_MSEC := 180
const StartScreenScript := preload("res://ui/StartScreen.gd")

## ── 开场教学（第 1–6 幕）───────────────────────────────────────────────────
## 第 2 幕只在教学迷你案件里跑，不碰 A-001 的存档与节点。数据在
## `cases/tutorial/case.tres`；正式案件在第 6 幕选择后再装载。
const TUTORIAL_CASE_PATH := "res://cases/tutorial/case.tres"
const TUT_ACTOR_ID := "CHARS_INVESTIGATOR"
const TUT_CLUE_ID := "CLUES_INVESTIGATOR"
const TUT_CERT_ITEM_ID := "ITEMS_investigator_cert"
const TUT_CERT_CLUE_ID := "CLUES_INVESTIGATOR_CERT"
const TUT_ACTOR_KEY := "char:" + TUT_ACTOR_ID
const TUT_CLUE_KEY := "clue:" + TUT_CLUE_ID
const TUT_CERT_ITEM_KEY := "item:" + TUT_CERT_ITEM_ID
const TUT_CERT_CLUE_KEY := "clue:" + TUT_CERT_CLUE_ID
const TUT_CARD_X := 40.0
const TUT_CARD_STEP_X := 60.0
const TUT_CARD_STEP_Y := 80.0

enum TutorialStep {
	DRAG_ACTOR,        # ① 把「调查员」拖给 TEC
	DOUBLE_CLICK_CLUE, # ② 双击「调查员」线索
	DRAG_CERT,         # ③ 把「调查员证」拖给 TEC
	DONE,
}

## 页眉几何 —— 逐项来自 Web 的计算布局（tools/pixeldiff/probe_web_rects.cjs 量的
## getBoundingClientRect），不是凭感觉的间距。改文案长度要同步改宽度，否则右侧按钮组会错位。
const HDR_SUB := "节点原型 v2 · 案件 A-001"
const HDR_X_BRAND := 14.0
const HDR_X_SUB := 110.0
const HDR_X_CHIP := 318.0
const HDR_W_CHIP := 190.0
const HDR_X_CRUMB := 522.0
const HDR_W_CRUMB := 134.0
const HDR_BTN_Y := 11.5
const HDR_BTN_H := 27.0
const HDR_TOG_Y := 12.5
const HDR_TOG_H := 25.0
## A1：右侧只留一个正式「撤销」和一个「调试」入口；其余 5 项进弹出面板。
const HDR_X_DEBUG := 1202.0
const HDR_W_DEBUG := 64.0
const HDR_X_UNDO := 1144.0
const HDR_W_UNDO := 50.0
const DEBUG_POP_W := 196.0

var case_def: CaseLoader
var graph: GraphState
var combos: ComboSystem

var _desk: Control
var _head: Panel
var _ui_built := false
var _stage: Control
var _card_layer: Control
var _edge_layer: EdgeLayer
var _view_k := 1.0
var _view_pos := Vector2.ZERO
## ── 相机倍率 ───────────────────────────────────────────────────────────────
## 连续缩放（不是 1x/2x 两档）：世界 2000×1300、画布只有约 1174×648，花园那 5 个
## 节点的包围盒实测 682×851 —— **不缩到 0.62x 根本装不进一屏**，所以「只能整数倍」
## 这条纪律在「看全貌」这件事上必须让路。代价（点阵字重采样）由 NodeCard 的 LOD
## 分级吸收：缩到读不清的倍率时，字本来就该退场（见 `NodeCard.set_lod`）。
const ZOOM_MIN := 0.45
const ZOOM_MAX := 2.0
const ZOOM_STEP := 1.12
## 「适应窗口」只放大到 1.3：再大就是单卡特写，不是「适应」了
const FIT_MAX := 1.3
## 吸附带：|k−1| < 6% 直接落到 1.0 —— 100% 是点阵字唯一绝对对齐原生格的倍率，
## 玩家从任意起点滚回来看上去「停在整」的位置，顺手就能拿到最锐利的那一档。
const ZOOM_SNAP := 0.06
## 玩家是否手动动过视图（滚轮 / 拖空白 / 定位某张卡）。false = 还在「适应窗口」的
## 自动档上，此时窗口尺寸变化就重新 fit，否则按中心补偿（别抢玩家的镜头）。
var _view_user := false
var _panning := false
var _pan_from := Vector2.ZERO
var _pan_origin := Vector2.ZERO
var _opt_focus := true          # 页眉「聚焦选中」
var _opt_reveal := true         # 页眉「新节点自动居中」
var _crumb: Label
var _brand_sub: Label
var _debug_btn: Button
var _debug_pop: PanelContainer
var _debug_shadow: ColorRect
var _debug_scrim: Control
var _hdr_sized: Array = []      # [Control, Vector2]：页眉控件的目标尺寸，见 _sync_header_sizes()
var _hdr_right: Array = []      # [Control, float]：贴右控件的「距右边缘」距离，见 _layout_header_right()
var _toast: PanelContainer
var _toast_label: Label
var _toast_timer: SceneTreeTimer
var _toast_queue: Array[Dictionary] = []
var _toast_active := false
var _toast_tween: Tween
var _case_win: SysWindow
var _tec: TecWindow
var _tec_chip: TecChip
var _tec_btn: Button
var _tec_min := false
var _tec_dot := false
var _tec_before: Dictionary = {}
var _narr: NarrCard
var _ending: EndingOverlay
var _cards: Dictionary = {}          # key -> NodeCard
var _selected: String = ""
## 拖动中的悬停落点（落点 id / 被高亮的控件 / 被高亮的目标卡）
var _drop_over_id := ""
var _drop_over_node: Node = null
var _drag_over_card := ""
## 拖动镜像（Web #drag-layer）：拖起时在桌布根上占一份"假身"，松手销毁。
var _card_mirror: NodeCard = null
## 正在拖的节点 key（原卡被隐藏期间，连线照常以它为端点）
var _drag_key := ""
var _edges_dirty := false
## 收纳行拖拽会话（见 _process）
var _sdrag_key := ""
var _sdrag_from := ""
var _sdrag_origin := Vector2.ZERO
var _sdrag_started := false
var _sdrag_ghost: PanelContainer = null
var _sdrag_label := ""
## 桌面图标的单击/双击（双击才开窗）
var _icon_sel: DeskIcon = null
var _icon_last_app := ""
var _icon_last_ms := -100000
var _icon_layout_h := -1.0
var _cmds: CommandSystem
var _pw_pop: PasswordPop = null
var _pw_ctx: Dictionary = {}
var _active_win: SysWindow = null     # A2：当前最上层的激活窗
var _bag_win: StorageWin = null
var _ledger_win: StorageWin = null
var _matrix_win: MatrixWin = null
var _matrix_pair_layout := false   # G3：桌布与花园并排过 → 花园关闭时复位
var _matrix_faded: Array = []      # A7：被矩阵窗盖住的卡片，关窗 / 拖动时恢复
var _archive_win: ArchiveWin = null
var _mem_card: MemCard = null
var _chat_win: ChatWindow = null
var _detail_win: DetailWin = null
var dialogues: DialogueSystem = null
var _archive_btn: Button = null
var _archive_badge: PanelContainer = null
var _archive_new := false
var _suppress_archive_new := false
var _last_ending_id := ""
var _flash_supply_note := false
var _save: SaveSystem = null
var _save_enabled := true
var _autosave_pending := false
var _autosave_due_msec := 0
var _storage_before: Dictionary = {}
var _investigator: Dictionary = {}
var _inv_path := Investigator.PATH
var _intro: IntroWin = null
var _start_screen: Control = null
var _tutorial_active := false
var _tutorial_step := TutorialStep.DRAG_ACTOR
var _tutorial_actor_key := ""
var _inv_chip: Button = null
var _cert_win: SysWindow = null
var _catalog: CaseCatalog = null
var _active_case := CaseCatalog.DEFAULT_ID
var _progress_path := CaseCatalog.PROGRESS_PATH
var _progress_read_only := false
var _case_open := true
var _case_held := false
var _case_docked := false
var _map_win: CaseMapWin = null
var _map_btn: Button = null
var _map_badge: PanelContainer = null
var _dock_card: Button = null
var _dock_code: Label = null
var _dock_title: Label = null
var _dock_sub: Label = null
var _music_btn: Button = null
var _music_win: MusicWin = null
var _music_dock: MusicDock = null
var _garden_btn: Button = null
var _garden_badge: PanelContainer = null
var _garden_win: GardenWin = null
var _garden_drop_before: Dictionary = {}
## 批 1（差距报告 I1 / I2 / I3）：日志窗 + 人物名册 + 四个计数角标
var _people_win: PeopleWin = null
var _log_win: LogWin = null
var _log_unread := 0
var _infer_btn: Button = null
var _bag_btn: Button = null
var _clue_btn: Button = null
var _log_btn: Button = null
var _people_btn: Button = null
var _infer_badge: PanelContainer = null
var _bag_badge: PanelContainer = null
var _clue_badge: PanelContainer = null
var _log_badge: PanelContainer = null


## 窗口物理尺寸按屏幕可用区算 —— **绝不能写死**。旧版 `window_*_override` 写死
## 1280×800，在 2560×1440 上只占 28% 面积，这就是「看着偏小」的根因。
##
## **不做整体缩放**：`content_scale_mode = DISABLED`，逻辑尺寸 = 窗口像素。
## 点阵字体只在 12 / 24 / 36px（12 的整数倍）落得下原字格，任何等比缩放都是重采样
## —— 1920×1080 的可用区算出来是 1.444x，整屏字发胖发糊。代价是界面元素不随屏幕
## 变大，所以改成「桌面铺满可用区 + 布局自适应」（`_layout_root()`）：
## 画布区跟着窗口长，左栏宽度与字号恒定。
func _setup_window_scale() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var win := get_window()
	if win == null:
		return
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	win.min_size = Vector2i(MIN_W, MIN_H)
	var forced := _win_override()
	if forced.x >= MIN_W and forced.y >= MIN_H:
		win.size = forced
		return
	if _shot_mode():
		## 对拍要 1:1 像素口径：截图窗口必须正好等于设计基准。
		win.size = Vector2i(int(DESIGN_W), int(DESIGN_H))
		return
	var usable := DisplayServer.screen_get_usable_rect()
	var avail: Vector2i = usable.size
	if avail.x < MIN_W or avail.y < MIN_H:
		win.size = Vector2i(int(DESIGN_W), int(DESIGN_H))
		return
	win.size = avail
	win.position = usable.position


# ── 自适应布局（不缩放的配套）────────────────────────────────────────────
## `content_scale_mode` 是 DISABLED，所以视口尺寸就是窗口像素。凡是「贴着窗口右/下边」
## 的东西都按这两个值现算，不再拿 DESIGN_W/H 当坐标系（那两个只是默认窗口尺寸）。

func _vw() -> float:
	var w := get_viewport_rect().size.x
	return w if w >= float(MIN_W) * 0.5 else DESIGN_W


func _vh() -> float:
	var h := get_viewport_rect().size.y
	return h if h >= float(MIN_H) * 0.5 else DESIGN_H


## 屏幕尺寸变了：页眉拉满、桌面区铺满、主窗跟长、贴右的浮层重新对边。
## 只改「容器与贴边位置」，画布内容靠 `_stage.size` 变化后的中心补偿保持视觉不动。
func _layout_root() -> void:
	if not _ui_built:
		return
	var vw := _vw()
	var vh := _vh()
	if _head != null and is_instance_valid(_head):
		_head.size = Vector2(vw, HEADER_H)
	_layout_header_left(vw)
	_layout_header_right(vw)
	_layout_debug_panel()
	if _desk != null and is_instance_valid(_desk):
		_desk.position = Vector2(0, HEADER_H)
		_desk.size = Vector2(vw, vh - HEADER_H)
	_resize_case_window(vw, vh)
	if _detail_win != null and is_instance_valid(_detail_win):
		_detail_win.place_right(vw)
	if _desk.size.y != _icon_layout_h:
		_icon_layout_h = _desk.size.y
		_reset_icon_positions()
	_place_toast_anchor()
	_place_music_windows()
	_place_floating_windows()
	_relayout_edge_windows(vw)


## 窄窗口先收左半边：工具组固定 596px（670..1266），窗口宽到 1150 以下时
## 证章会和工具组叠上。按右组左沿反推，逐级隐藏面包屑/副题，并把证章挪到品牌后。
func _layout_header_left(vw: float) -> void:
	if _brand_sub == null or _inv_chip == null or _crumb == null:
		return
	if not is_instance_valid(_brand_sub) or not is_instance_valid(_inv_chip) \
			or not is_instance_valid(_crumb):
		return
	var right_left := vw - (DESIGN_W - 670.0)
	var show_crumb := right_left >= HDR_X_CRUMB + HDR_W_CRUMB + 12.0
	var show_sub := right_left >= HDR_X_CHIP + HDR_W_CHIP + 12.0
	_crumb.visible = show_crumb
	_brand_sub.visible = show_sub
	_inv_chip.position.x = HDR_X_CHIP if show_sub else HDR_X_SUB


## 页眉工具组是 flex 的 `margin-left:auto`：贴右，不贴左。坐标表按 1280 量出来的，
## 存的是「距右边多少」，所以窗口变宽时整体右移即可。
func _layout_header_right(vw: float) -> void:
	for pair in _hdr_right:
		var c: Control = pair[0]
		if is_instance_valid(c):
			c.position.x = vw - float(pair[1])


## 主窗铺满「桌面 − 左侧图标列」。宽度/高度都用实际视口算，1280×720 下正好落在
## 原来的 1164(内宽) × 638(内高)、画布 1162 × 608，与 Web 版 P3 对拍口径一致
## （`test_ui` 有断言钉住这两个数）。
func _resize_case_window(vw: float, vh: float) -> void:
	if _case_win == null or not is_instance_valid(_case_win):
		return
	var inner_w := maxf(vw - 86.0 - SysWindow.PAD * 2.0 - 2.0, 640.0)
	var inner_h := maxf(vh - HEADER_H - 2.0 - SysWindow.PAD * 2.0, 360.0)
	_case_win.position = Vector2(86, 0)
	_case_win.resize_to(inner_w, inner_h)
	_case_win.body.position = Vector2(SysWindow.PAD + 1, SysWindow.PAD + 1 + SysWindow.BAR_H)
	_case_win.body.size = Vector2(inner_w - 2, inner_h - 2 - SysWindow.BAR_H)
	if _stage == null or not is_instance_valid(_stage):
		return
	var old := _stage.size
	if old == _case_win.body.size:
		return
	_stage.size = _case_win.body.size
	if _card_layer == null or not is_instance_valid(_card_layer):
		return
	if _view_user:
		## 玩家自己调过镜头：只补偿尺寸差的一半，保持画面中心不跑，缩放比不动。
		_view_pos += (_stage.size - old) * 0.5
		_apply_view()
	else:
		## 还在「适应窗口」自动档上：窗口变大就重新铺满，否则卡片会缩在中间一小块。
		_fit_cards()


## 贴右边的常驻浮窗（人物名册 / 日志）：只在它们开着的时候重算，关着的等下次打开。
## 日志窗是**右下角**（x、y 都贴边），名册只有 x 贴边、y 固定 60。
func _relayout_edge_windows(vw: float) -> void:
	if _people_win != null and is_instance_valid(_people_win):
		_people_win.position.x = vw - 328.0 - _people_win.size.x + SysWindow.PAD
	if _log_win != null and is_instance_valid(_log_win):
		_log_win.position = Vector2(vw - 14.0 - _log_win.size.x + SysWindow.PAD,
			_desk.size.y - 96.0 - _log_win.size.y + SysWindow.PAD)


func _ready() -> void:
	_setup_window_scale()
	theme = TecTheme.build()
	_progress_path = "user://shot_progress.json" if _shot_mode() else CaseCatalog.PROGRESS_PATH
	_progress_read_only = DisplayServer.get_name() == "headless" and not _shot_mode()
	_catalog = CaseCatalog.new(_progress_path)
	case_def = CaseLoader.new(CaseCatalog.path_of(_active_case))
	if not case_def.load_case():
		push_error("案件数据装载失败：" + case_def.load_error)
		return
	_save_enabled = not _shot_mode() and DisplayServer.get_name() != "headless"
	_investigator = Investigator.load_from(_inv_path)
	graph = GraphState.new(case_def)
	combos = ComboSystem.new(case_def, graph)
	_cmds = CommandSystem.new(case_def, graph)
	_build_ui()
	_update_case_chrome()
	_update_case_park_ui()
	_refresh_chip()
	if _start_screen_allowed():
		_open_start_screen()
	else:
		_boot_session()
	if _has_arg("--shot-p2"):
		_shot_p2_flow.call_deferred()
	elif _has_arg("--shot-p3"):
		_shot_p3_flow.call_deferred()
	elif _has_arg("--shot"):
		if _has_arg("--shot-intro"):
			_shot_intro_flow.call_deferred()
		else:
			_shot_flow.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_autosave()
		get_tree().quit()
	elif what == NOTIFICATION_RESIZED:
		## 不缩放之后，窗口尺寸变了就得自己重排（页眉拉满 / 主窗跟长 / 贴右浮层对边）。
		## `_ui_built` 挡住 _build_ui 期间的那几次重排：那时 _case_win 还没建出来。
		_layout_root()


## 收纳行拖拽会话（Web `06-storage.js` / `12-panels.js` 的行拖拽）：
## 行按下时开一个会话，桌面每帧跟手 + 刷新落点高亮，松左键时结算。
## 为什么不用 Control 的 drag&drop：那套只搬数据、画不了跟手的幽灵；
## 而画布拖动本来就是我们自己算的指针手势，两边口径要一致。
func _process(_dt: float) -> void:
	if _autosave_pending and Time.get_ticks_msec() >= _autosave_due_msec:
		_autosave()
	var edges_due := _edges_dirty
	if _follow_frames > 0:
		_follow_frames -= 1
		edges_due = true
	if edges_due:
		_repaint_edges()
	# 锚点节点还在重排补间里飞：浮层每帧重锚，跟着它一起走（Web 是每次 render 重算锚点）。
	# 只在补间期间做 —— 落地后重锚交给 `_start_move_tween` 的 finished，免得跟玩家拖窗口打架。
	if _mem_card != null and is_instance_valid(_mem_card) and _mem_anchor_key != "" \
		and _move_twens.has(_mem_anchor_key):
		_anchor_card_to(_mem_card, _mem_anchor_key)
	if _sdrag_key == "":
		return
	var at := _desk.get_global_mouse_position()
	if not _sdrag_started:
		if at.distance_to(_sdrag_origin) < 5.0:
			if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				var clicked := _sdrag_key
				_sdrag_cancel()
				# 没移动就松手 = 单击这一行 = 取回（Web 的行单击口径）
				_take_from_store(clicked, "")
			return
		_sdrag_started = true
		_sdrag_ghost = _make_drag_ghost(_sdrag_label)
	else:
		_sdrag_ghost.position = at + Vector2(12, 10)
	_update_drop_over(at)
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_sdrag(at)


func _take_from_store(key: String, _unused: String) -> void:
	if key == "":
		return
	var win := _storage_win_of(key)
	if win != null:
		(win as StorageWin)._take(key)


func _storage_win_of(key: String) -> Control:
	if _bag_win != null and is_instance_valid(_bag_win) and (_bag_win as StorageWin).items().has(key):
		return _bag_win
	if _ledger_win != null and is_instance_valid(_ledger_win) and (_ledger_win as StorageWin).items().has(key):
		return _ledger_win
	return null


## 收纳窗里按住一行（StorageWin.row_pressed）→ 开启拖拽会话
func _on_row_pressed(key: String, from_kind: String, at_global: Vector2) -> void:
	_sdrag_key = key
	_sdrag_from = from_kind
	_sdrag_origin = at_global
	_sdrag_started = false
	_sdrag_label = String(graph.node(key).get("label", key))


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
	_desk.add_child(p)
	p.z_index = 40
	p.position = _sdrag_origin + Vector2(12, 10)
	return p


func _sdrag_cancel() -> void:
	_sdrag_key = ""
	_sdrag_from = ""
	_sdrag_started = false
	_sdrag_label = ""
	if _sdrag_ghost != null and is_instance_valid(_sdrag_ghost):
		_sdrag_ghost.queue_free()
	_sdrag_ghost = null
	_clear_drop_over()


## 松手结算：另一个收纳窗 → 推演桌布 / 推演器图标 → 画布（落在松手那一点）→ 都不中：回去
func _finish_sdrag(at: Vector2) -> void:
	var key := _sdrag_key
	var from := _sdrag_from
	_sdrag_cancel()
	if key == "" or graph == null or not graph.stored.has(key):
		return
	var n := graph.node(key)
	var before := _save.snapshot()
	var to := ""
	if _bag_win != null and is_instance_valid(_bag_win) and _bag_win.is_visible_in_tree() \
		and _bag_win.get_global_rect().has_point(at):
		to = GraphState.BAG
	elif _ledger_win != null and is_instance_valid(_ledger_win) and _ledger_win.is_visible_in_tree() \
		and _ledger_win.get_global_rect().has_point(at):
		to = GraphState.LEDGER
	if to != "" and to != from:
		if to == GraphState.LEDGER and String(n["kind"]) != "clue":
			_show_toast("只有线索能进线索册", true)
			return
		if graph.restash(key, from, to):
			_refresh_storage_wins()
			_apply_hidden()
			_show_toast("「%s」搬到%s" % [String(n["label"]), "证物袋" if to == GraphState.BAG else "线索册"])
			_commit(before)
		return
	if _drop_on_matrix_icon(at) and String(n["kind"]) == "clue":
		_assign_to_matrix(key)
		return
	if _matrix_win != null and is_instance_valid(_matrix_win) \
		and _matrix_win.board_global_rect().has_point(at) and String(n["kind"]) == "clue":
		_assign_to_matrix(key)
		return
	if not _stage.get_global_rect().has_point(at):
		# 落在画布之外：什么都不做，东西留在原处（不吞节点）
		return
	var world := (at - _stage.get_global_position() - _view_pos) / maxf(_view_k, 0.01)
	graph.take_back(key, world.x, world.y)
	_apply_hidden()
	_refresh_storage_wins()
	var card := _cards.get(key, null) as NodeCard
	if card != null:
		card.position = world
		card.set_home(world)
	_selected = key
	graph.selected = key
	_apply_focus()
	_refresh_detail()
	_repaint_edges()
	_commit(before)


func _drop_on_matrix_icon(at: Vector2) -> bool:
	var ic: Control = _desk.get_node_or_null("icons/icon_infer") as Control
	return ic != null and ic.is_visible_in_tree() and ic.get_global_rect().has_point(at)


## 命令行参数（`--` 之后的用户参数）
func _has_arg(flag: String) -> bool:
	return OS.get_cmdline_user_args().has(flag) or OS.get_cmdline_args().has(flag)


## 调试用：`--win=1600x900` 直接钉窗口尺寸。因为 `content_scale_mode` 是 DISABLED，
## 这个值就等于逻辑尺寸 —— 排查「某个尺寸下布局崩了」和换截图口径全靠它。
## 不传则按屏幕可用区铺满（见 `_setup_window_scale`）。
func _win_override() -> Vector2i:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if not a.begins_with("--win="):
			continue
		var parts := a.substr(6).split("x")
		if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i.ZERO


func _shot_mode() -> bool:
	return _has_arg("--shot") or _has_arg("--shot-p2") or _has_arg("--shot-p3")


## 调试用：`--zoom=0.62` 钉死相机倍率（截图取证 / 排查某个倍率下的 LOD 与字重）。
## 不传返回 -1（照常 fit）。**只影响镜头，不写存档**。
func _zoom_override() -> float:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if not a.begins_with("--zoom="):
			continue
		var v := a.substr(7)
		if v.is_valid_float():
			return clampf(float(v), ZOOM_MIN, ZOOM_MAX)
	return -1.0


# ── 界面搭建 ────────────────────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	## 外壳底板：**平涂**。原来是竖向三段渐变（BG_HI → BG → BG_LO），
	## 那是「纸面浮雕」的遗产 —— 换到灰阶后，上亮下暗只会被读成脏，不是立体。
	## Mac 的桌面本来就是一块平色，层次全靠黑框和窗口的白面撑。
	var bg := ColorRect.new()
	bg.name = "desk_bg"
	## 外壳底色与画布**同一个灰**（P4.1）：图标区原来是纯白，白底板压在灰画布边上会显形；
	## 两处同色之后，图标「没有底板」才真的没有。
	bg.color = TecTheme.DESK_GRAY
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_build_header()

	_desk = Control.new()
	_desk.name = "desk"
	_desk.position = Vector2(0, HEADER_H)
	_desk.size = Vector2(DESIGN_W, DESIGN_H - HEADER_H)
	_desk.mouse_filter = Control.MOUSE_FILTER_PASS
	## 对齐 Web `#desktop{overflow:hidden}`：窗框的九切片会往外撑 32px 画投影，
	## 桌面必须裁掉溢到页眉上的那一段，否则页眉底下会多一圈影。
	_desk.clip_contents = true
	add_child(_desk)

	_build_case_window()
	_build_icons()
	_build_case_park()
	_build_tec_chip()

	_tec = TecWindow.new()
	_tec.name = "tec_win"
	_tec.setup_tec()
	_tec.position = Vector2(906, 264)
	_tec.visible = false
	_tec.closed.connect(_close_tec)
	_tec.minimized.connect(_minimize_tec)
	_tec.analysis_started.connect(_on_tec_analysis_started)
	_tec.analysis_progress.connect(_on_tec_analysis_progress)
	_tec.analysis_done.connect(_on_tec_analysis_done)
	_tec.talk_requested.connect(_tec_talk)
	_desk.add_child(_tec)
	_place_z(_tec, ZR_TEC)

	_narr = NarrCard.new()
	_narr.name = "narr_card"
	_narr.visible = false
	_desk.add_child(_narr)
	_place_z(_narr, ZR_NARR)

	_ending = EndingOverlay.new()
	_ending.name = "ending"
	setup_ending()

	_build_toast()
	_build_debug_panel()

	## 界面建完才开自适应：_build_ui 期间主窗/浮层还没影，重排会空转。
	_ui_built = true
	_layout_root()


func setup_ending() -> void:
	add_child(_ending)
	_ending.setup_overlay()
	if not _ending.finished.is_connected(_on_ending_finished):
		_ending.finished.connect(_on_ending_finished)


func _build_header() -> void:
	var head := Panel.new()
	head.name = "header"
	head.position = Vector2.ZERO
	head.size = Vector2(DESIGN_W, HEADER_H)
	_head = head
	var sb := StyleBoxFlat.new()
	sb.bg_color = TecTheme.LINE
	sb.border_width_bottom = 2
	sb.border_color = TecTheme.LINE
	head.add_theme_stylebox_override("panel", sb)
	add_child(head)

	# 品牌：`.brand` 14px + 字距 2；副题是它的 `<small>`（11px，间距 6px）
	var brand := TecTheme.brand_label("T.E.C-OS", TecTheme.FS_TITLE, TecTheme.CARD)
	brand.name = "brand"
	brand.position = Vector2(HDR_X_BRAND, -1.0)
	brand.size = Vector2(92.0, HEADER_H + 2.0)
	brand.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(brand)

	var sub := TecTheme.label(HDR_SUB, TecTheme.FS_BODY, TecTheme.LINE2)
	sub.name = "brand_sub"
	sub.position = Vector2(HDR_X_SUB, 0.0)
	sub.size = Vector2(206.0, HEADER_H)
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_brand_sub = sub
	head.add_child(sub)

	# 调查员证章（`#inv-chip`）：11px、奶油 1px 描边、**无圆角**、内边距 4/8
	_inv_chip = TecTheme.button("")
	_inv_chip.name = "inv_chip"
	_inv_chip.position = Vector2(HDR_X_CHIP, 13.5)
	_inv_chip.size = Vector2(HDR_W_CHIP, 23.0)
	_inv_chip.clip_text = true
	_inv_chip.add_theme_font_size_override("font_size", TecTheme.FS_BODY)
	_inv_chip.add_theme_color_override("font_color", TecTheme.CARD)
	_inv_chip.add_theme_color_override("font_hover_color", TecTheme.TEXT)
	_inv_chip.add_theme_color_override("font_pressed_color", TecTheme.TEXT)
	var chip_normal := TecTheme.flat(TecTheme.NONE, TecTheme.R_SM, TecTheme.CARD)
	var chip_hover := TecTheme.flat(TecTheme.CARD, TecTheme.R_SM, TecTheme.CARD)
	for csb in [chip_normal, chip_hover]:
		csb.content_margin_left = 8
		csb.content_margin_right = 8
		csb.content_margin_top = 4
		csb.content_margin_bottom = 4
	_inv_chip.add_theme_stylebox_override("normal", chip_normal)
	_inv_chip.add_theme_stylebox_override("hover", chip_hover)
	_inv_chip.add_theme_stylebox_override("pressed", chip_hover)
	_inv_chip.visible = false
	_inv_chip.pressed.connect(_open_cert_review)
	head.add_child(_inv_chip)

	# 面包屑：12px、超宽截断（Web 是 `overflow:hidden; text-overflow:ellipsis`）
	_crumb = TecTheme.label("", TecTheme.FS_BODY, TecTheme.LINE2)
	_crumb.name = "crumb"
	_crumb.position = Vector2(HDR_X_CRUMB, 0.0)
	_crumb.size = Vector2(HDR_W_CRUMB, HEADER_H)
	_crumb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_crumb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_crumb.clip_text = true
	head.add_child(_crumb)

	# A1：右侧只留正式操作。三个调试开关 + 适应窗口 / 重置 / 检查可达性
	# 全部收进「调试」弹出面板，避免系统界面第一眼像开发工具条。
	var undo := TecTheme.header_button("撤销", true)
	undo.name = "btn_撤销"
	head.add_child(undo)
	_place_hdr(undo, Vector2(HDR_X_UNDO, HDR_BTN_Y), Vector2(HDR_W_UNDO, HDR_BTN_H), true)
	undo.pressed.connect(_undo)

	_debug_btn = TecTheme.header_button("调试")
	_debug_btn.name = "btn_调试"
	_debug_btn.toggle_mode = true
	head.add_child(_debug_btn)
	_place_hdr(_debug_btn, Vector2(HDR_X_DEBUG, HDR_BTN_Y),
		Vector2(HDR_W_DEBUG, HDR_BTN_H), true)
	_debug_btn.toggled.connect(_on_debug_toggled)
	_refresh_crumbs()
	call_deferred("_sync_header_sizes")


## 页眉开关：奶油描边的胶囊 + 13×13 勾选框 + 文案，与 Web 的 `.tog` 同尺寸（25 高）。
## 位置 / 尺寸由调用方经 `_place_hdr()` 摆（Button 的 size 要等入树后再赋一遍才压得住）。
func _make_toggle(text: String) -> Button:
	var b := TecTheme.header_button(text)
	b.name = "tog_" + text
	b.toggle_mode = true
	b.button_pressed = true
	b.add_theme_constant_override("h_separation", 4)
	b.icon = _check_tex(true)
	# 开关的「按下」就是常态：底保持透明，字必须一直是奶油色
	b.add_theme_color_override("font_pressed_color", TecTheme.CARD)
	b.add_theme_color_override("font_hover_pressed_color", TecTheme.CARD)
	var sb := TecTheme.flat(TecTheme.NONE, TecTheme.R_BTN, TecTheme.CARD)
	# 左 10 / 右 9 / 上下 6.5：左内边距对上 Web `.tog` 的 `padding-left:10px`
	# （勾选框左边线正好落在 680）；上下 6.5 让最小高度 = 12 + 13 = 25，不会顶开 25 的目标高度。
	sb.content_margin_left = 10
	sb.content_margin_right = 9
	sb.content_margin_top = 6.5
	sb.content_margin_bottom = 6.5
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.toggled.connect(func(on: bool): b.icon = _check_tex(on); _on_header_toggle(text, on))
	return b


## 摆页眉控件并记下目标尺寸。
## ⚠ Button 的 `size` 会被「最小尺寸」反顶：控件还没进场景树时，`get_theme_font_size()`
## 取不到我们的 12px 覆盖、退回主题默认 16px，算出来的最小高度是 31 ——
## 于是 `size = 25` 当场被抬成 31，而等入树后最小尺寸掉回 24/20，控件也不会自己缩回去。
## 症状是页眉所有按钮都比 Web 高 6px、文字整体下沉 3px（P3 对拍里 tools 区 17.7% 差异的主因）。
## 解法：目标尺寸记在这里，入树之后再赋一遍（`_sync_header_sizes`）。
## `anchor_right`：坐标表是按 1280 宽量的，贴右的那组存「距右边缘多少」而不是绝对 x，
## 窗口变宽时由 `_layout_header_right()` 整体右移。
func _place_hdr(c: Control, pos: Vector2, sz: Vector2, anchor_right: bool = false) -> void:
	c.position = pos
	c.size = sz
	_hdr_sized.append([c, sz])
	if anchor_right:
		_hdr_right.append([c, DESIGN_W - pos.x])


func _sync_header_sizes() -> void:
	for pair in _hdr_sized:
		var c: Control = pair[0]
		if is_instance_valid(c) and c.size != pair[1]:
			c.size = pair[1]


## 「调试」弹出面板：黑底 + 奶油字，跟页眉同一套 header_button 语法。
## 点击面板外任意位置由全屏 scrim 关闭；开关留在面板里连续调，动作按钮点完收起。
func _build_debug_panel() -> void:
	_debug_scrim = Control.new()
	_debug_scrim.name = "debug_scrim"
	_debug_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_debug_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_debug_scrim.z_index = 90
	_debug_scrim.gui_input.connect(_on_debug_scrim_input)
	_debug_scrim.visible = false
	add_child(_debug_scrim)

	_debug_shadow = ColorRect.new()
	_debug_shadow.name = "debug_shadow"
	_debug_shadow.color = TecTheme.shadow(1.0)
	_debug_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_shadow.z_index = 91
	_debug_shadow.visible = false
	add_child(_debug_shadow)

	_debug_pop = PanelContainer.new()
	_debug_pop.name = "debug_pop"
	_debug_pop.custom_minimum_size = Vector2(DEBUG_POP_W, 0)
	_debug_pop.mouse_filter = Control.MOUSE_FILTER_STOP
	_debug_pop.z_index = 91
	var sb := TecTheme.flat(TecTheme.LINE, TecTheme.R_SM, TecTheme.CARD, 1)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_debug_pop.add_theme_stylebox_override("panel", sb)
	_debug_pop.visible = false
	add_child(_debug_pop)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_debug_pop.add_child(col)

	var cap := TecTheme.label("调试 / DEBUG", TecTheme.FS_BODY, TecTheme.white(0.62))
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(cap)

	for text in ["合成消耗", "聚焦选中", "新节点自动居中"]:
		var t := _make_toggle(text)
		t.custom_minimum_size = Vector2(0, HDR_TOG_H)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.alignment = HORIZONTAL_ALIGNMENT_LEFT
		col.add_child(t)

	var rule := ColorRect.new()
	rule.color = TecTheme.white(0.16)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)

	var actions := [["适应窗口", _fit_view], ["重置", _reset_case], ["检查可达性", _check_reachability]]
	for item in actions:
		var b := TecTheme.header_button(String(item[0]))
		b.name = "dbg_btn_" + String(item[0])
		b.custom_minimum_size = Vector2(0, HDR_BTN_H)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(item[1])
		b.pressed.connect(_close_debug_panel)
		col.add_child(b)


func _on_debug_toggled(on: bool) -> void:
	if on:
		_open_debug_panel()
	else:
		_close_debug_panel()


func _open_debug_panel() -> void:
	if _debug_pop == null or _debug_scrim == null:
		return
	_debug_scrim.visible = true
	_debug_pop.visible = true
	if _debug_shadow != null:
		_debug_shadow.visible = true
	_debug_pop.reset_size()
	_layout_debug_panel()
	if _debug_btn != null and not _debug_btn.button_pressed:
		_debug_btn.set_pressed_no_signal(true)


func _close_debug_panel() -> void:
	if _debug_pop != null:
		_debug_pop.visible = false
	if _debug_shadow != null:
		_debug_shadow.visible = false
	if _debug_scrim != null:
		_debug_scrim.visible = false
	if _debug_btn != null and _debug_btn.button_pressed:
		_debug_btn.set_pressed_no_signal(false)


func _on_debug_scrim_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		_close_debug_panel()


func _layout_debug_panel() -> void:
	if _debug_pop == null or not _debug_pop.visible:
		return
	var sz := _debug_pop.get_combined_minimum_size()
	_debug_pop.size = Vector2(DEBUG_POP_W, sz.y)
	_debug_pop.position = Vector2(_vw() - 14.0 - DEBUG_POP_W, HEADER_H + 6.0)
	if _debug_shadow != null:
		_debug_shadow.size = _debug_pop.size
		_debug_shadow.position = _debug_pop.position + SysWindow.OFFSET_SHADOW


## 13×13 勾选框：奶油底 + 墨色勾（Web 的 `accent-color:#e6e3d2` 渲染出来就是这个样子）。
## 现画而不是切图：勾是 2px 阶梯，缩放后比切图更稳。
func _check_tex(on: bool) -> ImageTexture:
	var img := Image.create(13, 13, false, Image.FORMAT_RGBA8)
	img.fill(TecTheme.NONE)
	var radius := 2
	var inside := PackedByteArray()
	inside.resize(13 * 13)
	for y in range(13):
		for x in range(13):
			var cx := clampi(x, radius, 12 - radius)
			var cy := clampi(y, radius, 12 - radius)
			var dx := x - cx
			var dy := y - cy
			inside[y * 13 + x] = 1 if dx * dx + dy * dy <= radius * radius else 0
	if on:
		for y in range(13):
			for x in range(13):
				if inside[y * 13 + x] == 1:
					img.set_pixel(x, y, TecTheme.TEXT_ON_DARK)
		var steps := [[3, 6], [4, 7], [5, 8], [6, 9], [7, 8], [8, 7], [9, 6], [10, 5]]
		for s in steps:
			img.set_pixel(int(s[0]), int(s[1]), TecTheme.LINE)
			img.set_pixel(int(s[0]), int(s[1]) + 1, TecTheme.LINE)
	else:
		var neighbors := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		for y in range(13):
			for x in range(13):
				if inside[y * 13 + x] == 0:
					continue
				for d in neighbors:
					var nx: int = x + d.x
					var ny: int = y + d.y
					if nx < 0 or nx > 12 or ny < 0 or ny > 12 or inside[ny * 13 + nx] == 0:
						img.set_pixel(x, y, TecTheme.CARD)
						break
	return ImageTexture.create_from_image(img)


func _on_header_toggle(text: String, on: bool) -> void:
	match text:
		"合成消耗":
			if _cmds != null:
				_cmds.consume_tools = on
		"聚焦选中":
			_opt_focus = on
			_apply_focus()
		"新节点自动居中":
			_opt_reveal = on
			if on:
				_relayout(false, true)   # 开关本身要求「现在就居中」——签名没变也得跑


## 面包屑计数：与 Web `updateCrumbs()` 同口径（可见/总数 · 已探索场景 · 已试组合 · 线索 · 结局）
func _refresh_crumbs() -> void:
	if _crumb == null or graph == null:
		return
	var total := graph.nodes.size()
	var vis := 0
	for key in graph.nodes.keys():
		if graph.visible_node(graph.nodes[key]):
			vis += 1
	var scene_n := 0
	var ending_n := 0
	if case_def != null:
		scene_n = case_def.scenes.size()
		ending_n = case_def.endings.size()
	_crumb.text = "节点 %d/%d · 已探索场景 %d/%d · 已试组合 %d · 捕获线索 %d · 结局 %d/%d" % [
		vis, total, graph.explored.size(), scene_n, graph.tried.size(),
		graph.captured.size(), graph.endings.size(), ending_n]


## 「适应窗口」：按内容包围盒重新缩放居中。**不跑布局** —— 那会把玩家摆的位置全收回去。
func _fit_view() -> void:
	_fit_cards()


## 「检查可达性」：从当前切片场景出发沿连线走一遍，把走不到的画布节点报出来。
## Web 同名按钮是开发期自查；Godot 侧一样只提示、不改状态。
func _check_reachability() -> void:
	if graph == null:
		return
	var start := graph.scene_key(SLICE_SCENE)
	var seen := {start: true}
	var queue: Array = [start]
	while queue.size() > 0:
		var cur: String = queue.pop_front()
		for nb in graph.neighbors(cur):
			var nk := String(nb)
			if not seen.has(nk):
				seen[nk] = true
				queue.append(nk)
	var orphan: Array = []
	for key in graph.nodes.keys():
		if not seen.has(String(key)):
			orphan.append(String(key))
	if orphan.is_empty():
		_show_toast("可达性：全部 %d 个节点都能从当前场景走到" % graph.nodes.size())
	else:
		_show_toast("可达性：%d 个节点走不到 —— %s" % [orphan.size(), ", ".join(orphan.slice(0, 3))], true)


## 选中即聚焦：与选中卡既不相同、也没有连线的卡淡化（Web `applyFocus`）
func _apply_focus() -> void:
	if _cards == null:
		return
	var sel := _selected
	var live := _opt_focus and sel != "" and graph != null and graph.nodes.has(sel)
	var near := {}
	if live:
		near[sel] = true
		for nb in graph.neighbors(sel):
			near[String(nb)] = true
	for key in _cards.keys():
		var card: NodeCard = _cards[key]
		if card != null:
			card.set_dim(live and not near.has(String(key)))
			# 选中环独立于「聚焦淡化」：关掉聚焦时环照样在（Web 的 `.sel` 不依赖任何开关）
			card.set_selected(_selected != "" and _selected == String(key))
	_repaint_edges()


func _build_case_window() -> void:
	_case_win = SysWindow.new()
	_case_win.name = "case_win"
	## 主窗高度跟着设计基准走：桌面可用高 = DESIGN_H - HEADER_H，减去底部 2px 余量
	## 与窗框两侧 14px 的 PAD。宽度 1164 不变（86 图标列 + 1164 + 2×14 = 1278 ≤ 1280）。
	var case_h := DESIGN_H - HEADER_H - 2.0 - SysWindow.PAD * 2.0
	_case_win.setup(_case_window_title(), 1164, case_h)
	_case_win.position = Vector2(86, 0)
	_case_win.body.position = Vector2(SysWindow.PAD + 1, SysWindow.PAD + 1 + SysWindow.BAR_H)
	_case_win.body.size = Vector2(1162, case_h - 2 - SysWindow.BAR_H)
	_case_win.body.clip_contents = true
	_case_win.enable_case_controls()
	_case_win.closed.connect(func(): _park_case("icon"))
	_case_win.minimized.connect(func(): _park_case("dock"))
	_desk.add_child(_case_win)
	_place_z(_case_win, ZR_CASE)

	_stage = Control.new()
	_stage.name = "stage"
	_stage.size = _case_win.body.size
	_stage.clip_contents = true
	_stage.mouse_filter = Control.MOUSE_FILTER_PASS
	_stage.gui_input.connect(_on_stage_input)
	_case_win.body.add_child(_stage)

	## 桌布：**平涂中性灰**（Mac OS 8 式），不铺网点。
	## 25% 网点在 1x 屏上会被读成一层灰砂；五档密度试下来，拉大点距只是把「砂纸」
	## 换成「网点纸」，6px 那档更脏 —— 有效的是降对比或直接平涂，见 TecTheme.DESK_GRAY。
	## `mono_pattern.gdshader` 保留，改挂到标题栏横纹 / 进度条这类窄条上（那里才该有纹理）。
	## `stage_paper.png` 保留作视觉基准，不再挂载。
	var stage_bg := ColorRect.new()
	stage_bg.name = "stage_bg"
	stage_bg.color = TecTheme.DESK_GRAY
	stage_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(stage_bg)

	_card_layer = Control.new()
	_card_layer.name = "cards"
	_card_layer.size = Vector2(WORLD_W, WORLD_H)
	_card_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	_stage.add_child(_card_layer)

	# 连线层排在卡片之前（同一坐标系，跟着一起平移 / 缩放）
	_edge_layer = EdgeLayer.new()
	_edge_layer.name = "edges"
	_card_layer.add_child(_edge_layer)


## 桌面图标栏（对齐 Web `ICON_LAYOUT`）：8 个常驻，左侧竖排、**可自由拖动**。
## 站位：left 18 / top 16 / 步距 85；图标变多时按 Web `resetIconPositions()` 压缩步距
## （下限 70），避免最后一个被 `#desktop{overflow:hidden}` 裁掉。
## 拖动只改位置，**不进撤销栈、重置不回位**（与 Web 一致）。
const ICON_LEFT := 18.0
const ICON_TOP := 16.0
## P2：常驻图标按「64px 槽 + 12px 间距」等距（48px 线稿必须保持 1:1，不能缩到 44 重采样）。
## 960×560 放不下时切紧凑槽 52px，间距按剩余高度压到 8~12px。
const ICON_PITCH := 76.0
const ICON_MIN_PITCH := 68.0
const ICON_COMPACT_PITCH := 64.0
## 常驻 8 项：顺序即 Web `ICON_LAYOUT` 的顺序（人物排在线索册之后、日志排在 TEC 之后）
const ICON_DEFS := [
	["推演器", "infer", "star"],
	["档案", "goto", "archive"],
	["线索册", "clue", "notebook"],
	["人物", "people", "users"],
	["证物袋", "bag", "briefcase"],
	["TEC", "tec", "tec"],
	["日志", "log", "clipboard-list"],
	["案件地图", "map", "map"],
]

# ── z 序（Web 静态 z-index 表，05-apps.css / 06-shell.css / 03-desktop.css 抄录）──
# Web 没有点击置顶：层序只由「每类窗口的固定 z 值 + 同级打开顺序（后来者在上）」决定。
# 同 rank 依旧按打开顺序，高一档的窗永远盖低一档的 —— 日志(21)、详情(22) 开得再晚也压不过 TEC(28)。
const ZR_CASE := 1        # #case-win：永远在最底
const ZR_PW := 15         # .pw-pop：压过卡片、被诗行/叙事卡和其它窗口压住
const ZR_NARR := 16       # .narr-card / .bubble：回放叙事小卡
const ZR_LOG := 21        # .log-win
const ZR_DETAIL := 22     # .detail-win
const ZR_DOCK := 23       # #music-dock / #case-dock / #tec-chip
const ZR_ICONS := 24      # #icons：窗开着会被任何系统窗盖住（11-dialog.js:501 注释）
const ZR_WIN := 25        # .bag/.clue/.cert/.map/.music/.goto/.infer/.garden/.people-win
const ZR_CHAT := 26       # .chat-win / .avatar-win
const ZR_TEC := 28        # .tec-win / .dlg-win
const ZR_TOAST := 30      # #toast / #verdict
const ZR_MIRROR := 40     # #drag-layer：桌面最高层（批 3 的拖动镜像也用这档）


## 把一个桌面直系子控件排到 Web 同款的层序位置：插到**第一个更高 rank 的孩子**之前，
## 同 rank 的相对顺序保持不变（等价于后来者在上）。`ctrl` 本来就在名单里，若它排在
## 插入点之前，`move_child` 的目标下标要扣掉它自己占的 1 位。
func _place_z(ctrl: Control, rank: int) -> void:
	ctrl.set_meta("zrank", rank)
	# SysWindow/MemCard 的「点击提层」也走这套 rank 表（回调在控件里，这里只负责接线），
	# 别让标题栏一按 `move_to_front()` 就把窗顶到 icons / toast 之上，破坏批 4 的层序
	if not bool(ctrl.get_meta("raise_hooked", false)) and ctrl.has_method("set_raise_call"):
		ctrl.set_raise_call(Callable(self, "_on_window_raise"))
		ctrl.set_meta("raise_hooked", true)
	if ctrl is SysWindow and not bool(ctrl.get_meta("active_hooked", false)):
		ctrl.visibility_changed.connect(_refresh_window_activation)
		ctrl.tree_exited.connect(_refresh_window_activation)
		ctrl.set_meta("active_hooked", true)
	var kids := _desk.get_children()
	var at := kids.size() - 1
	var self_idx := kids.find(ctrl)
	for i in kids.size():
		if i == self_idx:
			continue
		var c := kids[i] as Control
		if int(c.get_meta("zrank", ZR_CASE)) > rank:
			at = i - 1 if i > self_idx else i
			break
	_desk.move_child(ctrl, at)
	_refresh_window_activation()


## 窗口标题栏 / 历史卡按下的提层请求：用**自己的 rank** 重新插队（同 rank 仍按顺序，
## 重按 = 挪到同 rank 组尾部，即 Web 里后来者在上）
func _on_window_raise(w: Control) -> void:
	_place_z(w, int(w.get_meta("zrank", ZR_WIN)))


## A2：激活态只看**实际层序**，不看谁最后被点击 —— 低 rank 的窗口即使后开 / 重按，
## 也不会在视觉上压过高 rank 的窗，不能让它抢走「激活」标题栏。
## 从 `_desk` 子序末尾往前找第一扇可见系统窗；隐藏、最小化、关窗后自动把
## 激活态交还给仍露在最上面的那扇。
func _refresh_window_activation() -> void:
	if _desk == null or not is_instance_valid(_desk):
		return
	var top: SysWindow = null
	for i in range(_desk.get_child_count() - 1, -1, -1):
		var c := _desk.get_child(i) as SysWindow
		if c != null and is_instance_valid(c) and c.visible and c.participates_in_activation():
			top = c
			break
	# 逐窗落态：新建窗默认是激活态，只在 top 未变时提前 return 会把它漏成「双激活」。
	# 叙事卡 / 记忆卡不参与，保持它们自己的默认外观，不在这里被改成灰标题。
	for i in _desk.get_child_count():
		var w := _desk.get_child(i) as SysWindow
		if w != null and is_instance_valid(w) and w.participates_in_activation():
			w.set_active(w == top)
	_active_win = top


func _build_icons() -> void:
	# 容器只做「分组 + 树路径」用（`desk/icons/icon_bag` 是测试与落点表的公共锚点），
	# 不再承担排版：图标改成绝对定位，才能自由拖动。
	var col := Control.new()
	col.name = "icons"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.position = Vector2.ZERO
	col.size = _desk.size
	_desk.add_child(col)
	_place_z(col, ZR_ICONS)
	for d in ICON_DEFS:
		var app := String(d[1])
		var b := DeskIcon.new()
		b.name = "icon_" + app
		b.setup(String(d[0]), "res://assets/icons/%s.svg" % String(d[2]))
		b.set_bounds(Rect2(Vector2.ZERO, _desk.size))
		if app == "tec":
			_tec_btn = b
		elif app == "map":
			_map_btn = b
		elif app == "goto":
			_archive_btn = b
		elif app == "infer":
			_infer_btn = b
		elif app == "bag":
			_bag_btn = b
		elif app == "clue":
			_clue_btn = b
		elif app == "people":
			_people_btn = b
		elif app == "log":
			_log_btn = b
		# 桌面图标：单击只选中，双击才打开（全桌一致，除播放器外 —— 见 Web attachIcon(onQuick)）
		b.clicked.connect(func(): _on_icon_pressed(app, b))
		col.add_child(b)

	_music_btn = DeskIcon.new()
	_music_btn.name = "icon_music"
	_music_btn.setup("播放器", "res://assets/icons/music.svg")
	_music_btn.set_bounds(Rect2(Vector2.ZERO, _desk.size))
	_music_btn.tooltip_text = "打开音乐播放器（唱针已装上唱机）"
	_music_btn.visible = false
	# 播放器是唯一「单击即开」的图标（Web 里 onQuick），用户明确要求过
	_music_btn.clicked.connect(func(): _on_icon_pressed("music", _music_btn))
	col.add_child(_music_btn)

	_garden_btn = DeskIcon.new()
	_garden_btn.name = "icon_garden"
	_garden_btn.setup("花园", "res://assets/icons/leaf.svg")
	_garden_btn.set_bounds(Rect2(Vector2.ZERO, _desk.size))
	_garden_btn.tooltip_text = "去花园看看真名留下的种子"
	_garden_btn.visible = false
	_garden_btn.clicked.connect(func(): _on_icon_pressed("garden", _garden_btn))
	col.add_child(_garden_btn)

	_build_map_badge()
	_build_archive_badge()
	# 批 1 新增：推演器 / 证物袋 / 线索册的条数角标 + 日志未读角标
	_infer_badge = _make_badge(_infer_btn, "infer_badge")
	_bag_badge = _make_badge(_bag_btn, "bag_badge")
	_clue_badge = _make_badge(_clue_btn, "clue_badge")
	_log_badge = _make_badge(_log_btn, "log_badge")
	_garden_badge = _make_badge(_garden_btn, "garden_badge")
	_reset_icon_positions()


## 角标基件（Web `.desk-icon .badge`：右上角、深底浅字、999px 药丸）
func _make_badge(parent: Control, badge_name: String, text: String = "") -> PanelContainer:
	if parent == null:
		return null
	var badge := PanelContainer.new()
	badge.name = badge_name
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := TecTheme.flat(TecTheme.LINE, TecTheme.R_PILL, TecTheme.LINE)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	badge.add_theme_stylebox_override("panel", sb)
	var l := TecTheme.label(text, TecTheme.FS_BODY, TecTheme.CARD)
	l.name = "Label"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(l)
	badge.visible = false
	parent.add_child(badge)
	if parent is DeskIcon:
		(parent as DeskIcon).place_badges()
	return badge


## text == "" = 收起角标
func _set_badge(badge: PanelContainer, text: String) -> void:
	if badge == null or not is_instance_valid(badge):
		return
	if text == "":
		badge.visible = false
		return
	badge.visible = true
	var lab: Label = badge.get_node_or_null("Label")
	if lab != null:
		lab.text = text
	if badge.get_parent() is DeskIcon:
		(badge.get_parent() as DeskIcon).place_badges()


## 按当前可见图标数重排（Web `resetIconPositions()`）—— 图标增减时才调，
## 平时不碰，免得把玩家拖过的位置收走。
func _reset_icon_positions() -> void:
	var layer := _icon_layer()
	var list: Array = []
	for c in layer.get_children():
		if c is DeskIcon and (c as DeskIcon).visible:
			list.append(c)
	if list.is_empty():
		return
	var desk_h := _desk.size.y
	var n := list.size()
	# 先按可用高度压到 ≥68px；压到 68 以下才切紧凑（图标本体仍是 48px，只藏标签）。
	# 这样第 9 个图标出现时只收间距，不会让整栏标签一起消失。
	var fit_pitch := minf(ICON_PITCH, floorf((desk_h - ICON_TOP - 12.0) / float(n)))
	var compact := fit_pitch < ICON_MIN_PITCH
	for b in list:
		(b as DeskIcon).set_compact(compact)
	var pitch := fit_pitch
	if compact:
		pitch = minf(ICON_COMPACT_PITCH,
			floorf((desk_h - ICON_TOP - 12.0) / float(n)))
	# 顺序：常驻 8 项按 ICON_DEFS，动态的（播放器 / 花园）排在后面
	var order: Array = []
	for d in ICON_DEFS:
		var b := _icon_by_app(String(d[1]))
		if b != null and b.visible:
			order.append(b)
	for b in list:
		if not order.has(b):
			order.append(b)
	for i in order.size():
		var ic := order[i] as DeskIcon
		ic.position = Vector2(ICON_LEFT, ICON_TOP + float(i) * pitch)
		ic.place_badges()


## 图标层（`desk/icons`）：只做分组，不排版。
func _icon_layer() -> Control:
	var n := _desk.get_node_or_null("icons") as Control
	return n if n != null else _desk


func _icon_by_app(app: String) -> Button:
	match app:
		"infer": return _infer_btn
		"goto": return _archive_btn
		"clue": return _clue_btn
		"people": return _people_btn
		"bag": return _bag_btn
		"tec": return _tec_btn
		"log": return _log_btn
		"map": return _map_btn
		"music": return _music_btn
		"garden": return _garden_btn
	return null


## 桌面图标：单击 = 选中（`.desk-icon.sel`），双击 = 打开（对齐 Web `attachIcon`）。
## 播放器是唯一例外（Web 里传了 onQuick，单击即开）。
func _on_icon_pressed(app: String, icon: DeskIcon) -> void:
	if app == "music":
		_toggle_music_win()
		_clear_icon_selection()
		return
	var now := Time.get_ticks_msec()
	if _icon_last_app == app and now - _icon_last_ms <= 300:
		_icon_last_app = ""
		_icon_last_ms = -100000
		_open_icon_app(app)
		return
	_icon_last_app = app
	_icon_last_ms = now
	_select_icon(icon)


func _select_icon(icon: DeskIcon) -> void:
	if _icon_sel != null and is_instance_valid(_icon_sel) and _icon_sel != icon:
		_icon_sel.set_selected(false)
	_icon_sel = icon
	if icon != null and is_instance_valid(icon):
		icon.set_selected(true)


func _clear_icon_selection() -> void:
	if _icon_sel != null and is_instance_valid(_icon_sel):
		_icon_sel.set_selected(false)
	_icon_sel = null


func _open_icon_app(app: String) -> void:
	match app:
		"infer":
			_toggle_matrix()
		"goto":
			_toggle_archive()
		"clue":
			_toggle_storage(GraphState.LEDGER)
		"people":
			_toggle_people()
		"bag":
			_toggle_storage(GraphState.BAG)
		"tec":
			_toggle_tec()
		"log":
			_toggle_log()
		"map":
			_toggle_case_map()
		"garden":
			_open_garden()
	_clear_icon_selection()


func _build_map_badge() -> void:
	_map_badge = _make_badge(_map_btn, "map_badge", "已关闭")


func _build_archive_badge() -> void:
	_archive_badge = _make_badge(_archive_btn, "archive_badge", "新")


# ── 音乐播放器 / 花园彩蛋（P2.5）────────────────────────────────────────

func _music_unlocked() -> bool:
	if graph == null:
		return false
	for n in graph.nodes.values():
		var ins = n.get("installed", {})
		if ins is Dictionary and bool(ins.get("ITEMS_cz", false)):
			return true
	return false


func _refresh_app_icons() -> void:
	if graph == null:
		return
	var music := _music_unlocked()
	var had_music := _music_btn != null and _music_btn.visible
	if _music_btn != null:
		_music_btn.visible = music
	if not music:
		if _music_win != null and is_instance_valid(_music_win):
			_music_win.queue_free()
		_music_win = null
		if _music_dock != null and is_instance_valid(_music_dock):
			_music_dock.queue_free()
		_music_dock = null

	var garden := GardenSystem.has_garden(graph)
	var had_garden := _garden_btn != null and _garden_btn.visible
	if _garden_btn != null:
		_garden_btn.visible = garden
	if not garden:
		if _garden_win != null and is_instance_valid(_garden_win):
			_garden_win.queue_free()
		_garden_win = null
		_set_badge(_garden_badge, "")
	else:
		GardenSystem.normalize(graph, case_def)
		var plots: Array = graph.garden.get("plots", [])
		var has_seed := bool(graph.garden.get("seed", false))
		if not plots.is_empty():
			_set_badge(_garden_badge, "%d 株" % plots.size())
		elif has_seed:
			_set_badge(_garden_badge, "种子")
		else:
			_set_badge(_garden_badge, "")

	_refresh_count_badges()
	# 图标增减会改步距（Web `resetIconPositions()`）。只在可见性真变时重排 ——
	# 每次提交都重排会把玩家拖过的位置收走。
	if music != had_music or garden != had_garden:
		_reset_icon_positions()


## 计数角标（Web `updateInferBadge` / `updateBagBadge` / `updateLedgerBadge` / `updateLogBadge`）：
## 推演器 = 桌布上已归位的线索条数、证物袋 = N 件、线索册 = N 条、日志 = 未读条数。
func _refresh_count_badges() -> void:
	if graph == null:
		return
	var infer := 0
	for sense in graph.matrix.keys():
		infer += (graph.matrix[sense] as Array).size()
	_set_badge(_infer_badge, ("%d 条" % infer) if infer > 0 else "")
	var bag := 0
	var ledger := 0
	for key in graph.stored.keys():
		var where := String(graph.stored[key])
		if where == GraphState.BAG:
			bag += 1
		elif where == GraphState.LEDGER:
			ledger += 1
	_set_badge(_bag_badge, ("%d 件" % bag) if bag > 0 else "")
	_set_badge(_clue_badge, ("%d 条" % ledger) if ledger > 0 else "")
	_set_badge(_log_badge, str(_log_unread) if _log_unread > 0 else "")


func _toggle_music_win() -> void:
	if _music_win == null or not is_instance_valid(_music_win):
		_open_music()
		return
	if _music_win.visible:
		_on_music_closed()
		return
	if _music_dock != null and is_instance_valid(_music_dock) and _music_dock.visible:
		_restore_music()
		return
	_open_music()


func _open_music() -> void:
	if not _music_unlocked():
		return
	if _music_win == null or not is_instance_valid(_music_win):
		_music_win = MusicWin.new()
		_music_win.name = "music_win"
		_music_win.setup_music()
		_music_win.closed.connect(_on_music_closed)
		_music_win.minimized.connect(_minimize_music)
		_music_win.progress_changed.connect(_on_music_progress)
		_desk.add_child(_music_win)
		_place_music_windows()
	_place_z(_music_win, ZR_WIN)
	_music_win.visible = true
	if _music_dock != null:
		_music_dock.visible = false


func _ensure_music_dock() -> MusicDock:
	if _music_dock != null and is_instance_valid(_music_dock):
		return _music_dock
	_music_dock = MusicDock.new()
	_music_dock.name = "music_dock"
	_music_dock.setup_dock()
	_music_dock.restore_requested.connect(_restore_music)
	_music_dock.toggle_requested.connect(_toggle_music)
	_music_dock.stop_requested.connect(_stop_music)
	_desk.add_child(_music_dock)
	_music_dock.visible = false
	_place_music_windows()
	return _music_dock


## 播放器与 dock 的默认落点按 1280×720 量的 906/414、1026/532；
## 缩到 960×560 时只把越界的那一轴拉回右下安全区，不改变 1280 的既有构图。
func _place_music_windows() -> void:
	var desk_h := _desk.size.y if _desk != null and is_instance_valid(_desk) else _vh() - HEADER_H
	if _music_win != null and is_instance_valid(_music_win):
		_music_win.position = Vector2(
			minf(906.0, _vw() - 14.0 - _music_win.size.x),
			minf(414.0, desk_h - 12.0 - _music_win.size.y))
	if _music_dock != null and is_instance_valid(_music_dock):
		_music_dock.position = Vector2(
			minf(1026.0, _vw() - 16.0 - _music_dock.size.x),
			minf(532.0, desk_h - 16.0 - _music_dock.size.y))


## 1280 下的浮窗坐标是量出来的；小窗口只收越界的那一轴，避免 TEC / 对话窗
## 在 960×560 里整扇跑到屏幕外。夹取基于 `size`，窗口长高后同样成立。
func _place_floating_windows() -> void:
	var desk_h := _desk.size.y if _desk != null and is_instance_valid(_desk) else _vh() - HEADER_H
	var vw := _vw()
	if _tec != null and is_instance_valid(_tec):
		if _tutorial_active:
			_tec.position = Vector2(
				maxf(14.0, (vw - _tec.size.x) * 0.5),
				maxf(14.0, (desk_h - _tec.size.y) * 0.5 - 24.0))
		else:
			_tec.position = Vector2(minf(906.0, vw - 14.0 - _tec.size.x),
				minf(264.0, desk_h - 14.0 - _tec.size.y))
	if _tec_chip != null and is_instance_valid(_tec_chip):
		_tec_chip.position = Vector2(minf(1068.0, vw - 16.0 - _tec_chip.size.x),
			minf(608.0, desk_h - 4.0 - _tec_chip.size.y))
	if _archive_win != null and is_instance_valid(_archive_win):
		_archive_win.position = Vector2(minf(458.0, vw - 14.0 - _archive_win.size.x),
			minf(84.0, desk_h - 14.0 - _archive_win.size.y))
	if _chat_win != null and is_instance_valid(_chat_win):
		## 对话窗在 1280 本来就是贴右 4px 的 858，别拿 14px 去夹它。
		_chat_win.position = Vector2(minf(858.0, vw - 4.0 - _chat_win.size.x),
			minf(58.0, desk_h - 14.0 - _chat_win.size.y))
	## G3：结局种子在桌布上。桌布与花园同时开时，能并排就并排（1280 及以上），
	## 让种子与花圃同屏；小窗口仍按原位置，玩家按 toast 指引把种子拖到花园图标。
	var matrix_ok := _matrix_win != null and is_instance_valid(_matrix_win) and _matrix_win.visible
	var garden_ok := _garden_win != null and is_instance_valid(_garden_win) and _garden_win.visible
	var paired := false
	if matrix_ok and garden_ok:
		var gap := 12.0
		var total_w := _matrix_win.size.x + _garden_win.size.x + gap
		var need_h := maxf(_matrix_win.size.y, _garden_win.size.y)
		if total_w <= vw - 28.0 and need_h <= desk_h - 54.0:
			var left := maxf(14.0, (vw - total_w) * 0.5)
			_matrix_win.position = Vector2(left,
				maxf(14.0, minf(40.0, desk_h - 14.0 - _matrix_win.size.y)))
			_garden_win.position = Vector2(left + _matrix_win.size.x + gap,
				maxf(14.0, minf(58.0, desk_h - 14.0 - _garden_win.size.y)))
			paired = true
	if matrix_ok and not paired and _matrix_pair_layout:
		_matrix_win.position = Vector2(
			maxf(14.0, minf(336.0, vw - 14.0 - _matrix_win.size.x)),
			maxf(14.0, minf(40.0, desk_h - 14.0 - _matrix_win.size.y)))
	_matrix_pair_layout = paired
	if garden_ok and not paired:
		_garden_win.position = Vector2(
			maxf(14.0, minf(380.0, vw - 14.0 - _garden_win.size.x)),
			maxf(14.0, minf(58.0, desk_h - 14.0 - _garden_win.size.y)))


func _minimize_music() -> void:
	if _music_win == null:
		return
	_music_win.visible = false
	var dock := _ensure_music_dock()
	dock.update_state(_music_win.state())
	dock.visible = true
	_place_z(dock, ZR_DOCK)


func _restore_music() -> void:
	if _music_win == null or not is_instance_valid(_music_win):
		_open_music()
		if _music_dock != null:
			_music_dock.visible = false
		return
	_music_win.visible = true
	_place_z(_music_win, ZR_WIN)
	if _music_dock != null:
		_music_dock.visible = false


func _on_music_closed() -> void:
	if _music_win != null:
		_music_win.visible = false
	if _music_dock != null:
		_music_dock.visible = false
	if _music_win != null and _music_win.is_playing():
		_show_toast("播放器已收起，音乐继续")


func _on_music_progress(_cur: float, _dur: float) -> void:
	if _music_dock != null and _music_dock.visible and _music_win != null:
		_music_dock.update_state(_music_win.state())


func _toggle_music() -> void:
	if _music_win == null:
		return
	_music_win.toggle_current()
	if _music_dock != null and _music_dock.visible:
		_music_dock.update_state(_music_win.state())


func _stop_music() -> void:
	if _music_win == null:
		return
	_music_win.stop()
	if _music_dock != null:
		_music_dock.visible = false


func _open_garden() -> void:
	if not GardenSystem.has_garden(graph):
		return
	if _garden_win != null and is_instance_valid(_garden_win):
		_garden_win.queue_free()
		_garden_win = null
		return
	GardenSystem.normalize(graph, case_def)
	_garden_win = GardenWin.new()
	_garden_win.name = "garden_win"
	_garden_win.setup_garden(graph, case_def)
	_garden_win.closed.connect(func(): _garden_win = null)
	_garden_win.plant_moved.connect(func(_idx): _autosave())
	_garden_win.garden_changed.connect(_on_garden_changed)
	_garden_win.plot_bloomed.connect(_on_garden_bloomed)
	_desk.add_child(_garden_win)
	_place_z(_garden_win, ZR_WIN)
	_place_floating_windows()


func _on_garden_changed() -> void:
	_autosave()
	_refresh_app_icons()


func _on_garden_bloomed(_idx: int, fresh: bool) -> void:
	if fresh:
		_show_toast("花园里的种子开花了")


## 种子从桌布拖到花园窗 / 花园图标；成功返回 true，MatrixWin 据此决定是否弹回。
func _drop_seed(at_global: Vector2) -> bool:
	if graph == null or not GardenSystem.has_garden(graph):
		return false
	if not bool(graph.garden.get("seed", false)):
		return false
	var spot := {}
	var over_win := _garden_win != null and is_instance_valid(_garden_win) \
		and _garden_win.get_global_rect().has_point(at_global)
	var over_icon := _garden_btn != null and _garden_btn.visible \
		and _garden_btn.get_global_rect().has_point(at_global)
	if over_win:
		spot = _garden_win.spot_of_global(at_global)
	elif over_icon:
		spot = GardenSystem.spot_of(GardenSystem.DEFAULT_X, GardenSystem.DEFAULT_Y)
	else:
		return false
	var before := _save.snapshot() if _save != null else {}
	if not GardenSystem.plant(graph, float(spot["x"]), float(spot["y"])):
		return false
	GardenSystem.normalize(graph, case_def)
	_commit(before)
	if _matrix_win != null and is_instance_valid(_matrix_win):
		_matrix_win.refresh_seed()
	if _garden_win != null and is_instance_valid(_garden_win):
		_garden_win.refresh()
		if over_icon:
			_place_z(_garden_win, ZR_WIN)
	else:
		_open_garden()
	_refresh_app_icons()
	_show_toast("种下了「真名」")
	return true


func _on_seed_dropped(at_global: Vector2) -> void:
	_drop_seed(at_global)


func _on_ending_finished() -> void:
	if _last_ending_id == "":
		return
	var e := case_def.ending_by_id(_last_ending_id)
	if e == null or not e.is_true_capture:
		return
	GardenSystem.normalize(graph, case_def)
	if not GardenSystem.grant_seed(graph, e.message, case_def):
		return
	_autosave()
	if _matrix_win != null and is_instance_valid(_matrix_win):
		_matrix_win.refresh_seed()
	_refresh_app_icons()
	_show_toast("结局留下了一枚种子。把桌布上的种子拖到左侧「花园」图标。")


func _build_case_park() -> void:
	_dock_card = Button.new()
	_dock_card.name = "case_dock"
	_dock_card.size = Vector2(170, 56)
	_dock_card.position = Vector2(1094, 678)
	_dock_card.focus_mode = Control.FOCUS_NONE
	var normal := TecTheme.flat(TecTheme.CARD, TecTheme.R_WIN, TecTheme.INK, 1)
	_dock_card.add_theme_stylebox_override("normal", normal)
	## 悬停 = 键线 1px → 2px（与全站按钮同一套语法）。原来是 `CARD → BG`，
	## 两个常量在单色版里都是纯白，等于没有反馈。
	_dock_card.add_theme_stylebox_override("hover", TecTheme.flat(TecTheme.CARD, TecTheme.R_WIN, TecTheme.INK, 2))
	_dock_card.add_theme_stylebox_override("pressed", TecTheme.flat(TecTheme.CARD, TecTheme.R_WIN, TecTheme.INK, 2))
	_dock_card.pressed.connect(_reopen_case)
	_dock_card.visible = false
	_desk.add_child(_dock_card)
	_place_z(_dock_card, ZR_DOCK)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_top = 8
	row.offset_right = -9
	row.offset_bottom = -8
	row.add_theme_constant_override("separation", 9)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock_card.add_child(row)

	var glyph_box := PanelContainer.new()
	glyph_box.custom_minimum_size = Vector2(32, 32)
	glyph_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph_box.add_theme_stylebox_override("panel",
		TecTheme.flat(TecTheme.CARD, TecTheme.R_BTN, TecTheme.INK, 1))
	row.add_child(glyph_box)
	var glyph := TecTheme.label("▣", TecTheme.FS_TITLE, TecTheme.MUTED)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph_box.add_child(glyph)

	var meta := VBoxContainer.new()
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.alignment = BoxContainer.ALIGNMENT_CENTER
	meta.add_theme_constant_override("separation", 1)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(meta)

	_dock_code = TecTheme.label("", TecTheme.FS_BODY, TecTheme.MUTED)
	_dock_code.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(_dock_code)
	_dock_title = TecTheme.label("", TecTheme.FS_BODY, TecTheme.TEXT)
	_dock_title.clip_text = true
	_dock_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_dock_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(_dock_title)
	_dock_sub = TecTheme.label("进度已保存 · 点此展开", TecTheme.FS_BODY, TecTheme.MUTED)
	_dock_sub.clip_text = true
	_dock_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_dock_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(_dock_sub)


func _build_tec_chip() -> void:
	_tec_chip = TecChip.new()
	_tec_chip.setup_chip()
	_tec_chip.position = Vector2(1068, 608)
	_tec_chip.visible = false
	_tec_chip.pressed.connect(_open_tec)
	_desk.add_child(_tec_chip)
	_place_z(_tec_chip, ZR_DOCK)


func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.name = "toast"
	var sb := StyleBoxFlat.new()
	sb.bg_color = TecTheme.LINE
	sb.set_corner_radius_all(TecTheme.R_PILL)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	_toast.add_theme_stylebox_override("panel", sb)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_toast_label = TecTheme.label("", TecTheme.FS_TITLE, TecTheme.CARD)
	_toast.add_child(_toast_label)
	_desk.add_child(_toast)
	_place_z(_toast, ZR_TOAST)


# ── 切片 ────────────────────────────────────────────────────────────────

func _case_id() -> String:
	return case_def.case_def.id if case_def != null and case_def.case_def != null else ""


func _case_label() -> String:
	return "案件 " + CaseCatalog.code_of(_active_case).trim_prefix("CASE ")


func _case_title() -> String:
	if case_def != null and case_def.case_def != null and case_def.case_def.title != "":
		return case_def.case_def.title
	return CaseCatalog.title_of(_active_case)


func _case_window_title() -> String:
	return "案件 " + CaseCatalog.code_of(_active_case).trim_prefix("CASE ") + " · " + _case_title()


func _update_case_chrome() -> void:
	if _case_win != null:
		_case_win.set_title(_case_window_title())
	_refresh_crumbs()


func _require_case() -> bool:
	if _case_open:
		return true
	_show_toast("当前不在案件中，请先展开案件地图图标或右下角案件卡片", true)
	return false


func _toggle_case_map() -> void:
	if _map_win != null and is_instance_valid(_map_win):
		_map_win.queue_free()
		_map_win = null
		return
	var w := CaseMapWin.new()
	w.name = "case_map"
	w.setup_map(_catalog, _active_case, _case_open)
	w.position = Vector2(420, 72)
	w.enter_requested.connect(_on_case_map_enter)
	w.closed.connect(func(): _map_win = null)
	_desk.add_child(w)
	_place_z(w, ZR_WIN)
	_map_win = w


func _on_case_map_enter(id: String) -> void:
	if _map_win != null and is_instance_valid(_map_win):
		_map_win.queue_free()
		_map_win = null
	_enter_case(id)


func _enter_case(id: String) -> bool:
	if not CaseCatalog.exists(id):
		_show_toast("没有这个案件地址", true)
		return false
	if not _catalog.is_unlocked(id):
		_show_toast("该案件地址尚未解密", true)
		return false
	if id == _active_case:
		if not _case_open:
			_reopen_case()
		return true
	if not CaseCatalog.data_ready(id):
		_show_toast("案件 " + CaseCatalog.code_of(id) + " 的数据尚未装载", true)
		return false
	_autosave()
	var loader := CaseLoader.new(CaseCatalog.path_of(id))
	if not loader.load_case():
		_show_toast("案件装载失败：" + loader.load_error, true)
		return false
	_active_case = id
	case_def = loader
	_catalog.last = id
	if not _progress_read_only:
		_catalog.save_progress()
	_case_open = true
	_case_held = false
	_case_docked = false
	_case_win.visible = true
	if _resume_allowed() and _resume_from_save():
		_show_toast("已加载上次进度")
	else:
		_start_slice()
	_update_case_chrome()
	_update_case_park_ui()
	_log("已进入案件 %s // %s" % [CaseCatalog.code_of(id), CaseCatalog.title_of(id)], "sys")
	return true


## 解锁提示里要写的「下一案编号」（A001 → CASE A-002）
func _next_case_code(from_id: String) -> String:
	var list: Array = CaseCatalog.all()
	for i in list.size():
		if String((list[i] as Dictionary)["id"]) != from_id:
			continue
		if i + 1 < list.size():
			return String((list[i + 1] as Dictionary).get("code", ""))
		break
	return ""


func _park_case(where: String) -> bool:
	if not _case_open:
		return false
	_autosave()
	_close_case_transients()
	_case_open = false
	_case_win.visible = false
	_case_held = where != "dock"
	_case_docked = where == "dock"
	_update_case_park_ui()
	return true


func _reopen_case() -> void:
	if _case_win == null:
		return
	_case_open = true
	_case_held = false
	_case_docked = false
	_case_win.visible = true
	_place_z(_case_win, ZR_CASE)
	if _tec != null and _tec.visible:
		_place_z(_tec, ZR_TEC)
	_update_case_park_ui()


func _close_case_transients() -> void:
	if _pw_pop != null and is_instance_valid(_pw_pop):
		_pw_pop.queue_free()
	_pw_pop = null
	_pw_ctx = {}
	if _narr != null and is_instance_valid(_narr):
		_narr.queue_free()
	_narr = null
	_close_mem_card()
	_close_chat()
	if _archive_win != null and is_instance_valid(_archive_win):
		_archive_win.queue_free()
	_archive_win = null
	_hide_tec()
	_selected = ""
	if graph != null:
		graph.selected = ""


func _update_case_park_ui() -> void:
	if _dock_card != null:
		_dock_code.text = CaseCatalog.code_of(_active_case)
		_dock_title.text = _case_title()
		_dock_sub.text = "进度已保存 · 点此展开"
		_dock_card.visible = _case_docked
		if _case_docked:
			_place_z(_dock_card, ZR_DOCK)
	if _map_badge != null:
		_map_badge.visible = _case_held
	if _map_win != null and is_instance_valid(_map_win):
		_map_win.set_case_state(_active_case, _case_open)


func _resume_allowed() -> bool:
	if not _save_enabled or _has_arg("--fresh"):
		return false
	return DisplayServer.get_name() != "headless"


## 重建一套运行时对象（图 / 命令系统 / 存档），并清掉旧卡片与会话窗
func _new_runtime() -> void:
	for c in _card_layer.get_children():
		if c is NodeCard:
			_card_layer.remove_child(c)
			c.queue_free()
	_cards.clear()
	_layout_sig = ""            # 换案子 / 重开一局：卡片表清空，下次 `_relayout()` 必须真跑一次
	graph = GraphState.new(case_def)
	combos = ComboSystem.new(case_def, graph)
	_cmds = CommandSystem.new(case_def, graph)
	_save = SaveSystem.new(graph, _case_id())
	dialogues = DialogueSystem.new(case_def, graph)
	_selected = ""
	graph.selected = ""
	_last_ending_id = ""
	_storage_before = {}
	if _ending != null:
		_ending.visible = false
	_hide_tec(true)
	if _pw_pop != null and is_instance_valid(_pw_pop):
		_pw_pop.queue_free()
	_pw_pop = null
	_pw_ctx = {}
	if _narr != null and is_instance_valid(_narr):
		_narr.queue_free()
	_narr = null
	_close_mem_card()
	_close_chat()
	if _archive_win != null and is_instance_valid(_archive_win):
		_archive_win.queue_free()
	_archive_win = null
	_clear_archive_new()
	if _matrix_win != null and is_instance_valid(_matrix_win):
		_restore_matrix_occlusion()
		_matrix_win.queue_free()
	_matrix_win = null
	if _bag_win != null and is_instance_valid(_bag_win):
		_bag_win.queue_free()
	_bag_win = null
	if _ledger_win != null and is_instance_valid(_ledger_win):
		_ledger_win.queue_free()
	_ledger_win = null
	if _map_win != null and is_instance_valid(_map_win):
		_map_win.queue_free()
	_map_win = null
	if _music_win != null and is_instance_valid(_music_win):
		_music_win.queue_free()
	_music_win = null
	if _music_dock != null and is_instance_valid(_music_dock):
		_music_dock.queue_free()
	_music_dock = null
	if _garden_win != null and is_instance_valid(_garden_win):
		_garden_win.queue_free()
	_garden_win = null
	if _people_win != null and is_instance_valid(_people_win):
		_people_win.queue_free()
	_people_win = null
	if _log_win != null and is_instance_valid(_log_win):
		_log_win.queue_free()
	_log_win = null
	# 日志是「本次调查的案卷」：重来 / 换案才清（Web 17-boot.js:20），撤销不回滚
	_log_unread = 0
	_set_badge(_log_badge, "")
	_refresh_app_icons()


func _reset_case() -> void:
	if not _require_case():
		return
	if _save != null:
		_save.clear_save()
	_start_slice()
	_log("已重置为初始状态", "sys")
	_show_toast("已重置为初始状态")


func _resume_from_save() -> bool:
	_new_runtime()
	if not _save.load_from_disk():
		_save.clear_history()
		return false
	_rebuild_from_graph()
	_sync_case_progress_from_graph()
	return true


func _sync_case_progress_from_graph() -> void:
	if graph == null or case_def == null or _progress_read_only:
		return
	for e in case_def.endings:
		if e == null or not e.is_true_capture or not graph.endings.has(e.id):
			continue
		_catalog.mark_completed(_active_case)
		var newly := _catalog.unlock_next(_active_case)
		_update_case_park_ui()
		if newly:
			_log("新案件地址已解锁：%s" % _next_case_code(_active_case), "cap")
		return


func _start_slice() -> void:
	_new_runtime()

	# 开局状态**照 Web `17-boot.js:42` 一模一样的口径**：画布上只放一张「未探索」的起始场景节点，
	# 位置也用 Web 的 (1000, 620)。手电筒不在这里给 —— 它在「花园 → 书桌 → 抽屉 → 左侧抽屉」
	# 这条真实链路的末端（旧版图省事直接摆一把在桌上，等于跳掉了整个开场探索）。
	var sid := SLICE_SCENE
	var loc := graph.add_node("loc", sid)
	loc["x"] = 1000.0
	loc["y"] = 620.0
	graph.mark_fresh(String(loc["key"]))
	_spawn_card(loc["key"])

	_set_crumb(_case_label() + " // " + case_def.scene_title(sid))
	_log("已载入%s：双击「场景节点」展开里面的东西，把节点拖到另一个节点上组合使用。" % _case_label())
	_log("提示：先双击「%s」展开场景，再双击「书桌」等继续展开，拖动手电筒到黑影上试试。"
		% case_def.scene_title(sid))
	_relayout()


## 面包屑不再显示「案件 + 场景名」——那是**案件窗标题栏**的职责（Web 也是这样分工）。
## 仍保留这个函数名，是因为各处收尾（展开 / 换时刻 / 重置）都调它；现在统一刷计数。
func _set_crumb(_text: String) -> void:
	_refresh_crumbs()


# ── 调查员 / 开场适性测试 ───────────────────────────────────────────────

func _intro_allowed() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return not _shot_mode() and not _has_arg("--no-intro")


## 第 0 幕：正常启动（非无头 / 非截图 / 未显式 --no-start）先停在开始界面。
func _start_screen_allowed() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return not _shot_mode() and not _has_arg("--no-start")


func _open_start_screen() -> void:
	if _start_screen != null and is_instance_valid(_start_screen):
		return
	var has_save := _save_enabled and _catalog != null and _catalog.has_save(_active_case)
	_start_screen = StartScreenScript.new()
	_start_screen.name = "start_screen"
	_start_screen.z_index = 100
	_start_screen.setup(has_save)
	_start_screen.start_requested.connect(_on_start_new)
	_start_screen.continue_requested.connect(_on_start_continue)
	_start_screen.quit_requested.connect(func(): get_tree().quit())
	add_child(_start_screen)


func _close_start_screen() -> void:
	if _start_screen != null and is_instance_valid(_start_screen):
		_start_screen.queue_free()
	_start_screen = null


func _boot_session() -> void:
	if _resume_allowed() and _resume_from_save():
		_show_toast("已继续上次进度")
	else:
		_start_slice()
	if _intro_allowed() and _investigator.is_empty():
		_open_intro()


func _on_start_new(overwrite: bool) -> void:
	_close_start_screen()
	if overwrite:
		_clear_case_save()
	_begin_tutorial()


## 第 1–2 幕：空白桌面 + 常驻 TEC + 三步登记教学。
## 不启动正式案件、不出图标栏、不放诊断入口；教学用自己的迷你案件数据。
func _begin_tutorial() -> void:
	_tutorial_active = true
	_tutorial_step = TutorialStep.DRAG_ACTOR
	var tutorial := CaseLoader.new(TUTORIAL_CASE_PATH)
	if tutorial.load_case():
		case_def = tutorial
	else:
		push_error("教学案件装载失败：" + tutorial.load_error)
	## 教学期不写盘：第 5 幕完成领证后才写第一份档。
	_save_enabled = false
	_new_runtime()
	_case_open = true
	_case_win.visible = true
	_place_z(_case_win, ZR_CASE)
	_case_win.set_title("T.E.C-OS // 调查员登记")
	_hide_tutorial_chrome()

	_tec.visible = true
	_place_z(_tec, ZR_TEC)
	_tec.set_drag_enabled(false)
	var close := _tec.get_node_or_null("bar/close") as Control
	var mini := _tec.get_node_or_null("bar/min") as Control
	if close != null:
		close.visible = false
	if mini != null:
		mini.visible = false
	_tec.reset_tec()
	_tec.append_line("欢迎来到 TEC，你将开始领取你的调查员证，以便展开工作。\n"
		+ "桌面上是你的档案——把「调查员」拖到我身上。")
	_tutorial_set_hint()

	_view_k = 1.0
	_view_pos = Vector2.ZERO
	_view_user = true
	_apply_view()
	_place_floating_windows()
	_spawn_tutorial_actor()
	## TEC 的内容高度会在一帧后落定；再等一帧重新居中，避免它缩高后偏下。
	await get_tree().process_frame
	await get_tree().process_frame
	if _tutorial_active:
		_place_floating_windows()


func _hide_tutorial_chrome() -> void:
	var icons := _icon_layer()
	if icons != null:
		icons.visible = false
	for n in ["btn_撤销", "btn_调试"]:
		var b := _head.get_node_or_null(n) as Control
		if b != null:
			b.visible = false
	if _brand_sub != null:
		_brand_sub.visible = false
	if _crumb != null:
		_crumb.visible = false
	if _inv_chip != null:
		_inv_chip.visible = false
	for n in ["bar/close", "bar/min"]:
		var c := _case_win.get_node_or_null(n) as Control
		if c != null:
			c.visible = false


func _spawn_tutorial_actor() -> void:
	var n := graph.add_node("char", TUT_ACTOR_ID)
	n["label"] = "调查员"
	var pos := _tutorial_card_pos(0)
	n["x"] = pos.x
	n["y"] = pos.y
	_tutorial_actor_key = String(n["key"])
	var card := _spawn_card(_tutorial_actor_key)
	if card != null:
		card.visible = true
		card.position = pos
		_sync_card_shell(card)


## 教学卡片沿左下角向上斜排：调查员 → 线索 → 证件 → 证件线索。
func _tutorial_card_pos(layer: int) -> Vector2:
	var y0 := maxf(40.0, _stage.size.y - 144.0)
	## 阶梯在宽屏上向右展开；窄窗里 TEC 会占掉中间，必须把横向步长收窄到
	## 卡片仍落在 TEC 左缘之外，否则最后一张线索会钻到 TEC 窗体底下。
	var step_x := TUT_CARD_STEP_X
	if _tec != null and _card_layer != null and _tec.visible:
		var inv := _card_layer.get_global_transform().affine_inverse()
		var tec_left := (inv * _tec.global_position).x
		var max_x := tec_left - (GraphState.ENT_W + CARD_PAD * 2.0) - 12.0
		step_x = minf(step_x, maxf(0.0, (max_x - TUT_CARD_X) / 3.0))
	var x := TUT_CARD_X + step_x * float(layer)
	var y := y0 - TUT_CARD_STEP_Y * float(layer)
	x = minf(x, maxf(20.0, _stage.size.x - 160.0))
	y = maxf(20.0, y)
	return Vector2(x, y)


func _tutorial_spawn_node(kind: String, id: String, layer: int) -> String:
	var n := graph.add_node(kind, id)
	var pos := _tutorial_card_pos(layer)
	n["x"] = pos.x
	n["y"] = pos.y
	var key := String(n["key"])
	graph.mark_fresh(key)
	_refresh_or_spawn_card(key)
	_relayout()
	return key


func _tutorial_spawn_clue(id: String, from_key: String, layer: int) -> String:
	var key := graph.capture_clue(id, from_key)
	var n := graph.node(key)
	var pos := _tutorial_card_pos(layer)
	n["x"] = pos.x
	n["y"] = pos.y
	graph.mark_fresh(key)
	_refresh_or_spawn_card(key)
	_relayout()
	return key


func _tutorial_say(text: String) -> void:
	if _tec == null or not is_instance_valid(_tec):
		return
	_tec.append_line(text)
	_recenter_tutorial_tec()


## 教学 TEC 固定在画布中央：内容变高变矮都要重新居中，否则会向下长出画面中心。
func _recenter_tutorial_tec() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _tutorial_active and _tec != null and _tec.visible:
		_place_floating_windows()


func _tutorial_set_hint() -> void:
	if _tec == null:
		return
	match _tutorial_step:
		TutorialStep.DRAG_ACTOR:
			_tec.set_guidance("待命 · 等你的档案", "把「调查员」拖到我身上")
		TutorialStep.DOUBLE_CLICK_CLUE:
			_tec.set_guidance("待命 · 等你双击线索", "双击「调查员」线索")
		TutorialStep.DRAG_CERT:
			_tec.set_guidance("待命 · 等你交证件", "把「调查员证」拖到我身上")
		_:
			_tec.set_guidance("待命 · 登记完成", "证件信息已核对")


## 拖到 TEC 前的教学门：只放行当前步骤该交的节点；其余由 TEC 亲口纠正。
func _tutorial_talk_line() -> String:
	match _tutorial_step:
		TutorialStep.DRAG_ACTOR:
			return "把你的档案拖到我身上，我给你看看。"
		TutorialStep.DOUBLE_CLICK_CLUE:
			return "双击「调查员」线索，看看里面有什么。"
		TutorialStep.DRAG_CERT:
			return "把「调查员证」拖给我，我核对一下。"
		_:
			return "登记已经完成了。证件信息都齐了。"


func _tutorial_tec_guard(key: String) -> bool:
	match _tutorial_step:
		TutorialStep.DRAG_ACTOR:
			if key == TUT_ACTOR_KEY:
				return true
			_tutorial_say("先把「调查员」拖给我。")
		TutorialStep.DOUBLE_CLICK_CLUE:
			_tutorial_say("先双击「调查员」线索，看看里面有什么。")
		TutorialStep.DRAG_CERT:
			if key == TUT_CERT_ITEM_KEY:
				return true
			_tutorial_say("把「调查员证」拖给我。")
		_:
			_tutorial_say("证件已经核对完了。")
	return false


## 双击的教学分支：只有「调查员」线索会调出证件，其余给一句口头提示。
func _tutorial_on_activate(key: String) -> bool:
	if _tutorial_step == TutorialStep.DOUBLE_CLICK_CLUE:
		if key == TUT_CLUE_KEY:
			var cert_key := _tutorial_spawn_node("item", TUT_CERT_ITEM_ID, 2)
			graph.link(TUT_CLUE_KEY, cert_key, "entity")
			_tutorial_step = TutorialStep.DRAG_CERT
			_tutorial_set_hint()
			_tutorial_say("这是你的调查员证。把它拖给我，我核对一下。")
			return true
		if key == TUT_ACTOR_KEY:
			_tutorial_say("双击不会把它交给我——把它拖过来。")
			return true
	elif _tutorial_step == TutorialStep.DRAG_CERT and key == TUT_CLUE_KEY:
		_tutorial_say("证件已经调出来了。把「调查员证」拖给我。")
		return true
	elif _tutorial_step == TutorialStep.DRAG_ACTOR and key == TUT_ACTOR_KEY:
		_tutorial_say("把它拖到我身上，不是双击。")
		return true
	return false


## TEC 分析完成：按步骤发线索，不走进正式案件的反应表。
func _tutorial_on_tec_done(key: String) -> bool:
	if _tutorial_step == TutorialStep.DRAG_ACTOR and key == TUT_ACTOR_KEY:
		_tutorial_spawn_clue(TUT_CLUE_ID, key, 1)
		_tutorial_step = TutorialStep.DOUBLE_CLICK_CLUE
		_tutorial_set_hint()
		_tutorial_say("分析完成。这是「调查员」线索——双击它，看看能调出什么。")
		return true
	if _tutorial_step == TutorialStep.DRAG_CERT and key == TUT_CERT_ITEM_KEY:
		_tutorial_spawn_clue(TUT_CERT_CLUE_ID, key, 3)
		_tutorial_step = TutorialStep.DONE
		_tutorial_set_hint()
		_tutorial_say("核对完成。证件信息已经齐了。")
		return true
	return false


func _on_start_continue() -> void:
	_close_start_screen()
	if _resume_allowed() and _resume_from_save():
		_show_toast("已继续上次进度")
		return
	## 存档损坏 / 被外部删掉：退回新调查，不把玩家卡在空桌面。
	_start_slice()
	if _intro_allowed() and _investigator.is_empty():
		_open_intro()
	_show_toast("存档不可用，已开始新调查", true)

func _clear_case_save() -> void:
	if _save != null:
		_save.clear_save()
	var path := SaveSystem.save_path_for(_case_id())
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _refresh_chip() -> void:
	if _inv_chip == null:
		return
	if _investigator.is_empty():
		_inv_chip.visible = false
		_inv_chip.text = ""
		_inv_chip.tooltip_text = ""
		return
	_inv_chip.text = "▣ %s · %s" % [String(_investigator.get("name", "")), String(_investigator.get("id", ""))]
	_inv_chip.tooltip_text = _inv_chip.text
	_inv_chip.visible = true


func _avatar_pool() -> Array:
	var out: Array = Investigator.AVATAR_INITIAL.duplicate()
	for key in graph.nodes.keys():
		if not String(key).begins_with("char:"):
			continue
		var id := String(key).substr(5)
		if id != "CHARS_TEC" and not out.has(id):
			out.append(id)
	return out


func _avatar_names() -> Dictionary:
	var out := {"CHARS_EXEC": "执行者", "CHARS_TEC": "TEC"}
	if case_def == null:
		return out
	for id in _avatar_pool():
		var ch := case_def.char_of(String(id))
		if ch != null and ch.name != "":
			out[String(id)] = ch.name
	return out


func _locked_avatar_count() -> int:
	if case_def == null:
		return 0
	var pool := _avatar_pool()
	var n := 0
	for id in case_def.chars.keys():
		if not pool.has(String(id)):
			n += 1
	return n


func _open_intro() -> IntroWin:
	if _intro != null and is_instance_valid(_intro):
		return _intro
	var w := IntroWin.new()
	w.name = "intro"
	w.store_path = _inv_path
	w.setup(_avatar_pool(), _avatar_names(), _locked_avatar_count())
	w.finished.connect(_on_intro_finished)
	w.tree_exited.connect(_on_intro_closed)
	add_child(w)
	_intro = w
	return w


func _on_intro_closed() -> void:
	_intro = null


func _on_intro_finished(card: Dictionary) -> void:
	_investigator = card.duplicate(true)
	_refresh_chip()
	_show_toast("调查员 %s 已接入 T.E.C-OS" % String(_investigator.get("name", "")))
	_log("调查员 %s（%s）已接入 T.E.C-OS" % [String(_investigator.get("name", "")),
		String(_investigator.get("id", ""))], "sys")


func _open_cert_review() -> void:
	if _investigator.is_empty():
		return
	if _cert_win != null and is_instance_valid(_cert_win):
		_cert_win.queue_free()
		_cert_win = null
	var w := SysWindow.new()
	w.name = "cert_win"
	w.setup("调查员证", 340, 540)
	w.position = Vector2(470, 40)
	_desk.add_child(w)
	_place_z(w, ZR_WIN)
	w.content.add_child(IntroWin.build_cert(_investigator))
	w.tree_exited.connect(func(): _cert_win = null)
	_cert_win = w


func _show_toast(text: String, warn: bool = false) -> void:
	## 首条立即显示（测试与即时反馈都依赖这一点）；正在显示 / 淡出时的后续消息排队，
	## 不再用新消息粗暴顶掉旧消息——玩家往往会连点两下，前一句没读完就换字更易漏信息。
	if _toast_active:
		_toast_queue.append({"text": text, "warn": warn})
		return
	_show_toast_now(text, warn)


func _show_toast_now(text: String, warn: bool) -> void:
	_toast_active = true
	_toast_label.text = text
	_toast.add_theme_stylebox_override("panel", _toast_style(warn))
	_toast.modulate.a = 1.0
	_toast.visible = true
	_toast.reset_size()
	_place_toast_anchor()
	_stop_toast_timer()
	_toast_timer = get_tree().create_timer(2.4)
	_toast_timer.timeout.connect(_fade_toast)


func _fade_toast() -> void:
	if not _toast_active:
		return
	_stop_toast_timer()
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.set_trans(Tween.TRANS_LINEAR)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.18)
	_toast_tween.finished.connect(_after_toast_fade)


func _after_toast_fade() -> void:
	_toast.visible = false
	_toast.modulate.a = 1.0
	_toast_active = false
	if _toast_queue.is_empty():
		return
	var next: Dictionary = _toast_queue.pop_front()
	_show_toast_now(String(next.get("text", "")), bool(next.get("warn", false)))


func _stop_toast_timer() -> void:
	if _toast_timer == null:
		return
	if _toast_timer.timeout.is_connected(_fade_toast):
		_toast_timer.timeout.disconnect(_fade_toast)
	_toast_timer = null


## toast 停**右下角**，不压底部正中：底部正中是叙事卡 / 详情卡的下沉落点
## （`_anchor_card_to` 上→下→右→左都会用到），停在那儿十有八九正好盖住卡上的字。
## 右下角与 TEC 收起胶囊同一列（右边距 16）；胶囊 / 播放器坞在场时往上让。
## 独立成函数是因为窗口 resize 之后要按新视口重新对边。
func _place_toast_anchor() -> void:
	if _toast == null or not is_instance_valid(_toast) or not _toast.visible:
		return
	## E4：底部居中，距底 16px。不再贴右下角，也不做 dock 避让 —— 居中后与
	## 右下角的 TEC 胶囊 / 音乐卡片天然分开。
	var bottom := _vh() - HEADER_H - 16.0
	_toast.position = Vector2((_vw() - _toast.size.x) * 0.5, bottom - _toast.size.y)


func _toast_style(warn: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = TecTheme.LINE
	sb.set_corner_radius_all(TecTheme.R_PILL)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	if warn:
		sb.border_width_left = 4
		sb.border_color = TecTheme.LINE2
	return sb


func _hide_toast() -> void:
	_stop_toast_timer()
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = null
	_toast_queue.clear()
	_toast_active = false
	_toast.modulate.a = 1.0
	_toast.visible = false


# ── 撤销 / 存档 ─────────────────────────────────────────────────────────

func _autosave() -> void:
	_autosave_pending = false
	if _save == null or not _save_enabled:
		return
	if not _save.save_to_disk():
		push_warning("自动存档失败：" + _save.last_error)


func _queue_autosave() -> void:
	if _save == null or not _save_enabled:
		return
	_autosave_pending = true
	_autosave_due_msec = Time.get_ticks_msec() + AUTOSAVE_DELAY_MSEC


## 动作开始前拍一张；动作结束后状态真的变了才入撤销栈并写盘
func _commit(before: Dictionary) -> void:
	if before.is_empty() or _save == null:
		return
	if JSON.stringify(before) == JSON.stringify(_save.snapshot()):
		return
	_save.push_history_snapshot(before)
	_queue_autosave()
	_refresh_app_icons()
	_refresh_detail()
	_refresh_people_win()
	_refresh_log_win()


func dbg_undo() -> bool:
	return _undo()


func dbg_history_size() -> int:
	return _save.history.size() if _save != null else 0


func dbg_save() -> bool:
	return _save.save_to_disk() if _save != null else false


func dbg_load() -> bool:
	if _save == null or not _save.load_from_disk():
		return false
	_rebuild_from_graph()
	return true


func dbg_clear_save() -> void:
	if _save != null:
		_save.clear_save()


func dbg_save_path() -> String:
	return _save.path if _save != null else ""


func dbg_use_temp_save(p_path: String) -> void:
	_save = SaveSystem.new(graph, _case_id(), p_path)
	_save.clear_save()
	_save.clear_history()


func _undo() -> bool:
	if not _require_case():
		return false
	if _save == null or not _save.can_undo():
		_log("没有可撤销的操作", "warn")
		_show_toast("没有可撤销的操作", true)
		return false
	if not _save.undo():
		_show_toast("撤销失败：" + _save.last_error, true)
		return false
	_rebuild_from_graph()
	_autosave()
	_show_toast("已撤销上一步")
	return true


## 按当前图状态重建所有卡片（撤销 / 续档共用）
func _rebuild_from_graph() -> void:
	for c in _card_layer.get_children():
		if c is NodeCard:
			_card_layer.remove_child(c)
			c.queue_free()
	_cards.clear()
	_selected = ""
	graph.selected = ""
	_storage_before = {}
	if _edge_layer != null:
		_edge_layer.clear_ghost()
	GardenSystem.normalize(graph, case_def)
	_refresh_people_win()
	_refresh_log_win()
	if _music_win != null and is_instance_valid(_music_win):
		_music_win.queue_free()
	_music_win = null
	if _music_dock != null and is_instance_valid(_music_dock):
		_music_dock.queue_free()
	_music_dock = null
	if _garden_win != null and is_instance_valid(_garden_win):
		_garden_win.queue_free()
	_garden_win = null
	if _pw_pop != null and is_instance_valid(_pw_pop):
		_pw_pop.queue_free()
	_pw_pop = null
	_pw_ctx = {}
	if _narr != null and is_instance_valid(_narr):
		_narr.queue_free()
	_narr = null
	_close_mem_card()
	_close_chat()
	if _archive_win != null and is_instance_valid(_archive_win):
		_archive_win.queue_free()
	_archive_win = null
	_clear_archive_new()
	_ending.visible = false
	if _tec != null:
		_tec.cancel_analysis()
		_sync_tec_chip()
	_suppress_archive_new = true
	for key in graph.nodes.keys():
		_spawn_card(String(key))
	_suppress_archive_new = false
	_apply_hidden()
	# 读档 / 撤销后摆位是存档里那一份，不能被下一次互动的重排顺手推走 —— 签名就地认下来。
	_layout_sig = _layout_signature()
	_refresh_matrix_views()
	_last_ending_id = String(graph.endings.keys()[0]) if not graph.endings.is_empty() else ""
	var sid := graph.last_scene
	_set_crumb(_case_label() + " // " + case_def.scene_title(sid) if sid != "" else _case_label())
	_update_case_chrome()
	_refresh_app_icons()


# ── 画布手势（Web `15-desktop.js`）────────────────────────────────────────
# 点空白 = 清选中；拖空白 = 平移；滚轮 = 以光标为锚连续缩放（0.45~2.0，×1.12）。
# 卡片自己 `MOUSE_FILTER_STOP` + `accept_event()`，所以拖节点不会漏成平移。

func _on_stage_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if not mb.pressed:
				return
			var mp := mb.position
			var step := ZOOM_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP
			var k2 := clampf(_view_k * step, ZOOM_MIN, ZOOM_MAX)
			## 近 100% 吸附：1.0 是点阵字唯一落在原生格上的倍率，别让玩家「差一点点」
			if absf(k2 - 1.0) < ZOOM_SNAP:
				k2 = 1.0
			if absf(k2 - _view_k) > 0.0001:
				_view_pos = mp - (mp - _view_pos) * (k2 / _view_k)
				_view_k = k2
				_view_user = true
				_apply_view()
			accept_event()
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			# 上一轮拖动如果没收到松手（切窗 / 失焦 / 事件丢失），这里先收尾。
			# 否则画布会带着一张「悬空的卡」继续平移，看着就是「桌布在动、节点不动」。
			if _drag_key != "":
				_abort_card_drag()
				return
			_panning = true
			_pan_from = mb.position
			_pan_origin = _view_pos
			_clear_selection()
		else:
			_panning = false
		return
	if event is InputEventMouseMotion and _panning:
		_view_pos = _pan_origin + ((event as InputEventMouseMotion).position - _pan_from)
		_view_user = true
		_apply_view()


## 拖动会话没收尾就遇到新的按下：把卡按当前坐标落地并清掉镜像。
## （正常路径由 NodeCard 的松手处理；这里只兜「松手事件丢了」的那条）
func _abort_card_drag() -> void:
	var key := _drag_key
	var card: NodeCard = _cards.get(key, null)
	_drag_key = ""
	_panning = false
	if card != null and is_instance_valid(card):
		card.cancel_drag()
	else:
		_drop_card_mirror(null)
		_clear_drop_over()
		if _edge_layer != null:
			_edge_layer.clear_ghost()


func _apply_view() -> void:
	if _card_layer == null:
		return
	_card_layer.position = _view_pos
	_card_layer.scale = Vector2(_view_k, _view_k)
	## 低倍率下连线按 1/k 反向加粗：不补偿的话 1.3px 的实体线到 0.62x 只剩 0.8px，
	## 会被纸纹底吃成「虚线」。补偿后屏幕上仍是 1.3px（见 EdgeLayer.set_zoom）。
	if _edge_layer != null and is_instance_valid(_edge_layer):
		_edge_layer.set_zoom(_view_k)
	_apply_lod()
	_reanchor_mem_card()


## 把当前倍率分发给每张卡（NodeCard.set_lod 自己判档并早退，重复调用不吃性能）
func _apply_lod() -> void:
	if _cards.is_empty():
		return
	for key in _cards.keys():
		var c: NodeCard = _cards.get(key, null)
		if c != null and is_instance_valid(c):
			c.set_lod(_view_k)


## 缩放 / 平移 / 重排都会让锚点节点在屏幕上换位置，而放映卡是**屏幕坐标**摆的 ——
## 不重锚它就会留在原地，看起来像压在节点上（实测 448×328 的卡盖住花园卡）。
func _reanchor_mem_card() -> void:
	if _mem_card != null and is_instance_valid(_mem_card) and _mem_anchor_key != "":
		_anchor_card_to(_mem_card, _mem_anchor_key)


func _clear_selection() -> void:
	_clear_icon_selection()
	if _selected == "":
		return
	_selected = ""
	if graph != null:
		graph.selected = ""
	_apply_focus()
	_refresh_detail()


# ── 卡片 ────────────────────────────────────────────────────────────────

func _spawn_card(key: String) -> NodeCard:
	if _cards.has(key):
		return _cards[key]
	var n := graph.node(key)
	if n.is_empty():
		return null
	if String(n["kind"]) == "time":
		if not _suppress_archive_new and graph.has_unread(key):
			_mark_archive_new()
		return null                       # 时间节点不上画布（入口在档案窗）
	var w := GraphState.SCENE_W if GraphState.is_scene_kind(String(n["kind"])) else GraphState.ENT_W
	var h := GraphState.SCENE_H if GraphState.is_scene_kind(String(n["kind"])) else GraphState.ENT_H
	var card := NodeCard.new()
	card.name = "card_" + key.replace(":", "_")
	card.setup(key, String(n["kind"]), n, w, h)
	_sync_card_shell(card)
	_seed_one(key)
	card.position = Vector2(float(n.get("x", 0.0)), float(n.get("y", 0.0)))
	card.drop_sink = Callable(self, "_handle_card_drop")
	card.world_rect = Rect2(Vector2.ZERO, Vector2(WORLD_W, WORLD_H))
	card.selected.connect(_on_card_selected)
	card.pressed.connect(_on_card_pressed)
	card.activated.connect(_on_card_activated)
	card.dragged.connect(_on_card_dragged)
	card.drag_moved.connect(_on_card_drag_moved)
	card.drag_finished.connect(_on_card_drag_finished)
	card.combo_requested.connect(_on_card_combo)
	card.pin_toggled.connect(_on_card_pin_toggled)
	_card_layer.add_child(card)
	_cards[key] = card
	## 新卡上画布时立刻对齐当前倍率，否则缩小状态下新出现的卡会带着「完整两行」出现
	card.set_lod(_view_k)
	# Web 的入场 pop：fresh 的节点初次上画布闪一下（`n.fresh` 渲染一次即被摘掉；
	# `unread`「新」角标继续保留，直到玩家点过卡片）。截图模式里不弹（像素对拍要稳），
	# 但 fresh 照样消费掉（两次截图的 fresh 状态必须收敛）。
	if bool(n.get("fresh", false)):
		graph.consume_fresh(key)
		if not _shot_mode():
			card.pivot_offset = card.size * 0.5
			card.play_pop()
	return card


## 播种：**只给还没落过位的节点**（x/y < 0）一个初始坐标，已落位的原样保留。
## 容器（场景 / 书桌）按 5 列网格，实体围在画布中央 —— 与 Web `layout()` 的 seed 同口径。
func _seed_one(key: String) -> void:
	var n := graph.node(key)
	if n.is_empty() or (float(n.get("x", -1.0)) >= 0.0 and float(n.get("y", -1.0)) >= 0.0):
		return
	var cidx := 0
	for k in graph.nodes.keys():
		var kk := String(k)
		if not graph.is_container_node(kk):
			continue
		var m := graph.node(kk)
		if kk == key or float(m.get("x", -1.0)) < 0.0:
			cidx += 1
	if graph.is_container_node(key):
		var i := maxi(cidx - 1, 0)
		n["x"] = 200.0 + float(i % 5) * 380.0
		n["y"] = 160.0 + float(i / 5) * 300.0
	else:
		# 实体：按 key 哈希撒在中央（确定性 —— 同一份存档每次开都落在同一处）
		var h := float(abs(key.hash()) % 1000) / 1000.0
		var h2 := float(abs(key.hash() * 31) % 1000) / 1000.0
		n["x"] = 700.0 + (h - 0.5) * 420.0
		n["y"] = 560.0 + (h2 - 0.5) * 420.0


func _on_card_selected(key: String) -> void:
	_selected = key
	graph.selected = key
	if graph.has_unread(key):
		graph.clear_fresh(key)
		_sync_card_shell(_cards.get(key, null))
	_apply_focus()
	_refresh_detail()


## 卡片按下（未拖未点都算）：把它的重排落位补间杀掉——卡冻结在指针下面，
## 双击不会因为卡「飞走了」而落空，拖动起手也不会跟 0.34s 过渡打架
func _on_card_pressed(key: String) -> void:
	_kill_move(key)


func _on_card_dragged(key: String) -> void:
	_kill_move(key)
	# Web 的拖动不改选中；但这里选中一下能让「聚焦选中」不把正在拖的卡淡化掉，
	# 属于报告 §3.1 ② 里点名的有意偏离。
	_selected = key
	graph.selected = key
	_apply_focus()
	# Web 拖起即把整卡搬进 #drag-layer（浮在所有窗子之上）+ 原件 `visibility:hidden`。
	# Godot 里用镜像卡承载「浮层」那份视觉，原件隐藏（连线仍然用它的 world 坐标）。
	_drag_key = key
	var card: NodeCard = _cards.get(key, null)
	if card != null:
		_mount_card_mirror(card)


## 拖动中：落点悬停高亮（Web 的 `.over`）+ 幽灵线，每帧按指针重算一次。
## 幽灵线画在连线层（world 空间），所以要把指针的屏幕坐标换算回 world。
func _on_card_drag_moved(key: String, at_global: Vector2) -> void:
	var card: NodeCard = _cards.get(key, null)
	if card != null and _edge_layer != null and _card_layer != null:
		var world_at: Vector2 = _card_layer.get_global_transform().affine_inverse() * at_global
		_edge_layer.set_ghost(card.visual_center(), world_at)
	_sync_card_mirror(card)
	_update_drop_over(at_global)
	_edges_dirty = true


## ── 拖动镜像（Web #drag-layer）──────────────────────────────────────────
## 镜像 = 卡片的「假身」：挂到桌布根（在所有窗子之上）、吃不到输入、
## 每帧跟着原卡的位置。原卡被隐藏，但仍是连线端点与数据写回的坐标来源。


func _mount_card_mirror(card: NodeCard) -> void:
	if card == null or _desk == null:
		return
	if _card_mirror != null and is_instance_valid(_card_mirror):
		_card_mirror.queue_free()
	# ⚠ 原件不能让 `visible = false`。Godot 的 GUI 命中判定会跳过「树里不可见」的控件：
	# 拖动第一帧把原件隐藏之后，鼠标移动就不再投递给它（mouse_focus 失效），
	# motion 断流 ⇒ 卡片停在原地、镜像不跟手、松手也没人处理（`_drag_key` 一直挂着）。
	# 之后任何一次按下都落到画布手势层 ⇒ 整块画布跟着鼠标平移 ——「桌布在动，节点不动」。
	# 改成全透明但仍在树里（NodeCard.set_ghost）：事件照收，画面交给镜像。
	card.set_ghost(true)
	var mirror := card.build_mirror()
	if mirror == null:
		return
	_desk.add_child(mirror)
	_place_z(mirror, ZR_MIRROR)
	mirror.scale = card.get_global_transform().get_scale()
	mirror.global_position = card.get_global_position()
	_card_mirror = mirror


func _sync_card_mirror(card: NodeCard) -> void:
	if _card_mirror == null or not is_instance_valid(_card_mirror) or card == null:
		return
	_card_mirror.global_position = card.get_global_position()


## 松手换身回来：镜像销毁、原卡按数据可见性复位（后续的弹回 / 收纳 / 消费各走各路）
func _drop_card_mirror(card: NodeCard) -> void:
	if _card_mirror != null and is_instance_valid(_card_mirror):
		_card_mirror.queue_free()
	_card_mirror = null
	if card != null and is_instance_valid(card):
		card.set_ghost(false)
		card.visible = graph.visible_node(graph.node(card.card_key))


## 松手：落点由 `_handle_card_drop` 分派；没命中就停在松手处并把坐标写回数据
func _on_card_drag_finished(key: String, pos: Vector2, handled: bool) -> void:
	var finished_card: NodeCard = _cards.get(key, null)
	_drop_card_mirror(finished_card)
	_drag_key = ""
	_clear_drop_over()
	if _edge_layer != null:
		_edge_layer.clear_ghost()
	_repaint_edges()
	var n := graph.node(key)
	if n.is_empty():
		return
	if handled:
		return
	var before := _save.snapshot()
	n["x"] = pos.x
	n["y"] = pos.y
	_refresh_crumbs()
	_commit(before)


## 重画连线（Web `paintEdges()`）：端点取 `visual_center()`，四种边各自配色 / 线宽 / 虚线。
## 聚焦选中开着时，与选中节点无关的边降到 12% 不透明（Web 的 `opacity .12`）。
func _repaint_edges() -> void:
	_edges_dirty = false
	if _edge_layer == null or graph == null:
		return
	var focus_sel := _selected if (_opt_focus and _selected != "" and graph.nodes.has(_selected)) else ""
	var segs: Array = []
	for e in graph.edges:
		var a := String(e.get("a", ""))
		var b := String(e.get("b", ""))
		var ca: NodeCard = _cards.get(a, null)
		var cb: NodeCard = _cards.get(b, null)
		if ca == null or cb == null:
			continue
		# 拖动中本卡被镜像隐藏（Web 也 `visibility:hidden` 原件）—— 边照常画
		if not (ca.visible or String(a) == _drag_key) or \
				not (cb.visible or String(b) == _drag_key):
			continue
		segs.append({
			"a": ca.visual_center(), "b": cb.visual_center(),
			"kind": String(e.get("rel", "entity")),
			"dim": focus_sel != "" and a != focus_sel and b != focus_sel,
		})
	# 「试过但没成」的边：Web 把它们当 kind=tried 的边画（`graph.tried` 里是 a>b 的字符串键）
	for raw in graph.tried.keys():
		var pair := String(raw).split(">", false, 1)
		if pair.size() != 2:
			continue
		var ca: NodeCard = _cards.get(pair[0], null)
		var cb: NodeCard = _cards.get(pair[1], null)
		if ca == null or cb == null:
			continue
		if not (ca.visible or String(pair[0]) == _drag_key) or \
				not (cb.visible or String(pair[1]) == _drag_key):
			continue
		segs.append({
			"a": ca.visual_center(), "b": cb.visual_center(), "kind": "tried",
			"dim": focus_sel != "" and pair[0] != focus_sel and pair[1] != focus_sel,
		})
	_edge_layer.set_segments(segs)


## 兼容旧入口（无头测试与 dbg 钩子还在调）：等价于「卡片松手落在 at_global」的完整分派。
## 真实交互走 NodeCard → drop_sink → `_handle_card_drop`，这里只是给测试用的一次性封装。
func _on_card_drag_released(key: String, at_global: Vector2) -> void:
	if _handle_card_drop(key, at_global):
		if _cards.has(key):
			(_cards[key] as NodeCard).spring_back()
		return
	var target := _card_key_at(at_global)
	if target != "" and target != key:
		if _cards.has(key):
			(_cards[key] as NodeCard).spring_back()
		_on_card_combo(key, target)


## 右键 = 钉住 / 取消钉住（Web 里这是唯一入口，拖动不再顺手钉住）
func _on_card_pin_toggled(key: String) -> void:
	var n := graph.node(key)
	if n.is_empty():
		return
	var before := _save.snapshot()
	n["pinned"] = not bool(n.get("pinned", false))
	_sync_card_shell(_cards.get(key, null))
	_commit(before)


# ── 落点（对齐 Web `nodeDropTargets()`，顺序即优先级）──────────────────────

## 单一的落点表。**禁止**在别处再堆 `if 命中某某图标` —— 加落点只改这里。
## 顺序：对话窗 → 两扇收纳窗 → 五个桌面图标 → TEC 头像 / 收起卡 → 推演桌布。
## 窗口排在图标之前：窗开着时通常盖在图标列上，此时归属窗口。
func _drop_targets() -> Array:
	var out: Array = []
	if _chat_win != null and is_instance_valid(_chat_win) and _chat_win.is_visible_in_tree():
		out.append({"id": "chat-win", "rect": _chat_win.get_global_rect()})
	if _bag_win != null and is_instance_valid(_bag_win) and _bag_win.is_visible_in_tree():
		out.append({"id": "bag-win", "rect": _bag_win.get_global_rect()})
	if _ledger_win != null and is_instance_valid(_ledger_win) and _ledger_win.is_visible_in_tree():
		out.append({"id": "clue-win", "rect": _ledger_win.get_global_rect()})
	for pair in [["bag-dock", "icon_bag"], ["clue-icon", "icon_clue"], ["tec-dock", "icon_tec"],
			["infer-icon", "icon_infer"], ["goto-icon", "icon_goto"]]:
		var ic: Control = _desk.get_node_or_null("icons/" + String(pair[1])) as Control
		if ic != null and ic.is_visible_in_tree():
			out.append({"id": String(pair[0]), "rect": ic.get_global_rect()})
	if _tec != null and is_instance_valid(_tec) and _tec.visible:
		## 教学期 TEC 就是「角色」：整个窗体都接拖拽，玩家不必精准命中头像。
		## 正式案件仍只认头像，避免挡住 TEC 窗后面的画布操作。
		out.append({"id": "tec-dock" if _tutorial_active else "tec-avatar",
			"rect": _tec.get_global_rect() if _tutorial_active else _tec.avatar_global_rect()})
	if _tec_chip != null and is_instance_valid(_tec_chip) and _tec_chip.visible:
		out.append({"id": "tec-chip", "rect": _tec_chip.get_global_rect()})
	if _matrix_win != null and is_instance_valid(_matrix_win):
		out.append({"id": "mx-board", "rect": _matrix_win.board_global_rect()})
	return out


## 节点详情窗（Web `#detail-win`）：选中即显示，点空白即收起
func _ensure_detail() -> DetailWin:
	if _detail_win != null and is_instance_valid(_detail_win):
		return _detail_win
	_detail_win = DetailWin.new()
	_detail_win.name = "detail_win"
	_detail_win.setup_detail(graph, case_def)
	_detail_win.renarr_scene.connect(func(id: String): _show_narr(id))
	_detail_win.renarr_talk.connect(_replay_talk)
	_detail_win.play_monologue.connect(func(id: String): _open_monologue(id))
	_detail_win.play_music.connect(_open_music)
	_desk.add_child(_detail_win)
	_detail_win.place_right(_vw())
	_place_z(_detail_win, ZR_DETAIL)
	return _detail_win


func _refresh_detail() -> void:
	if _detail_win == null or not is_instance_valid(_detail_win):
		if _selected == "" or graph == null or not graph.nodes.has(_selected):
			return
		_ensure_detail()
	if _selected == "" or graph == null or not graph.nodes.has(_selected):
		_detail_win.hide()
		return
	_detail_win.show_node(_selected)


## 「重看对话」：把这个人已经说过的台词整段重放进对话窗（Web `renarrTalk`）
func _replay_talk(key: String) -> bool:
	var n := graph.node(key)
	if n.is_empty() or _chat_win != null and is_instance_valid(_chat_win):
		return false
	if String(n["kind"]) != "char":
		return false
	var ch := case_def.char_of(String(n["id"]))
	if ch == null:
		return false
	var prog := mini(int(graph.talk_prog.get(key, 0)), ch.talk_queue.size())
	if prog <= 0:
		return false
	var d := DialogueDef.new()
	d.id = "replay_" + String(ch.id)
	var parts: Array[CharDef] = [ch]
	d.participants = parts
	for i in prog:
		var line := DialogueLineDef.new()
		line.kind = "say"
		line.who = ch
		line.text = ch.talk_queue[i]
		d.script_lines.append(line)
	return _open_chat(d, [String(ch.id)])


## 拖动中用：命中的落点加 `.over`（图标反白 / 窗与桌布虚线框 / 目标节点反白）
func _update_drop_over(at_global: Vector2) -> void:
	var hit_id := ""
	for t in _drop_targets():
		if (t["rect"] as Rect2).has_point(at_global):
			hit_id = String(t["id"])
			break
	if hit_id != _drop_over_id:
		_clear_drop_over()
		_drop_over_id = hit_id
		if hit_id != "":
			_drop_over_node = _node_of_drop(hit_id)
			_set_over(_drop_over_node, true)
	# 目标节点（组合）：只在没有图标 / 窗口命中时高亮
	var under := ""
	if hit_id == "":
		under = _card_key_at(at_global)
	if under != _drag_over_card:
		if _drag_over_card != "" and _cards.has(_drag_over_card):
			(_cards[_drag_over_card] as NodeCard).set_over(false)
		_drag_over_card = under
		if under != "":
			(_cards[under] as NodeCard).set_over(true)


func _clear_drop_over() -> void:
	_set_over(_drop_over_node, false)
	_drop_over_node = null
	_drop_over_id = ""
	if _drag_over_card != "" and _cards.has(_drag_over_card):
		(_cards[_drag_over_card] as NodeCard).set_over(false)
	_drag_over_card = ""


## 落点悬停高亮的统一入口（TecChip 之类没实现 set_over 的控件自动跳过）
func _set_over(node: Node, on: bool) -> void:
	if node != null and is_instance_valid(node) and node.has_method("set_over"):
		node.call("set_over", on)


## 落点 id → 可着色的控件（图标 / 窗口 / 桌布）
func _node_of_drop(id: String) -> Node:
	match id:
		"chat-win":
			return _chat_win
		"bag-win":
			return _bag_win
		"clue-win":
			return _ledger_win
		"bag-dock":
			return _desk.get_node_or_null("icons/icon_bag")
		"clue-icon":
			return _desk.get_node_or_null("icons/icon_clue")
		"tec-dock":
			return _tec_btn
		"infer-icon":
			return _desk.get_node_or_null("icons/icon_infer")
		"goto-icon":
			return _desk.get_node_or_null("icons/icon_goto")
		"tec-avatar":
			return _tec if _tec != null and _tec.visible else null
		"tec-chip":
			return _tec_chip
		"mx-board":
			return _matrix_win
	return null


## 松手分派：命中落点即消费（卡片回原位）。返回 true 表示已被落点接管。
func _handle_card_drop(key: String, at_global: Vector2) -> bool:
	for t in _drop_targets():
		if (t["rect"] as Rect2).has_point(at_global):
			_apply_drop(String(t["id"]), key)
			return true
	return false


func _apply_drop(id: String, key: String) -> void:
	var n := graph.node(key)
	if n.is_empty():
		return
	match id:
		"chat-win":
			_chat_drop(key)
		"bag-win", "bag-dock":
			_store_into(GraphState.BAG, key)
		"clue-win", "clue-icon":
			_store_into(GraphState.LEDGER, key)
		"tec-dock", "tec-avatar", "tec-chip":
			_start_tec_analysis(key)
		"infer-icon", "mx-board":
			if String(n["kind"]) == "clue":
				_assign_to_matrix(key)
			else:
				_show_toast("只有线索能进推演器" if id == "infer-icon" else "只有线索能上桌布", true)
		"goto-icon":
			if GraphState.is_scene_kind(String(n["kind"])):
				_goto_scene(String(n["id"]))
			else:
				_show_toast("只有场景能进档案", true)


## 收进证物袋 / 线索册（拒收时给一句人话，别让玩家以为是坏了）
func _store_into(where: String, key: String) -> void:
	var n := graph.node(key)
	if n.is_empty():
		return
	if graph.stored.has(key):
		_show_toast("它已经在收纳里了", true)
		return
	if graph.is_container_node(key):
		_show_toast("场景与容器收不进收纳袋", true)
		return
	if where == GraphState.LEDGER and String(n["kind"]) != "clue":
		_show_toast("只有线索能进线索册", true)
		return
	var before := _save.snapshot()
	var ok := graph.bag_store(key) if where == GraphState.BAG else graph.ledger_store(key)
	if not ok:
		return
	_apply_hidden()
	_refresh_storage_wins()
	_show_toast("「%s」收进%s" % [String(n.get("label", "")),
		"证物袋" if where == GraphState.BAG else "线索册"])
	_commit(before)


func _refresh_storage_wins() -> void:
	if _bag_win != null and is_instance_valid(_bag_win):
		_bag_win.refresh_store()
	if _ledger_win != null and is_instance_valid(_ledger_win):
		_ledger_win.refresh_store()


## 「前往」（Web gotoScene）：确保场景卡在画布上，镜头平移居中并选中它
func _goto_scene(id: String) -> void:
	if case_def == null or case_def.scene_of(id) == null:
		return
	var key := graph.scene_key(id)
	var before := _save.snapshot()
	if not graph.nodes.has(key):
		graph.add_node("loc", id)
		_spawn_card(key)
		_apply_hidden()
		_relayout()
	var card: NodeCard = _cards.get(key, null)
	if card == null:
		return
	_selected = key
	graph.selected = key
	_center_on(card)
	_apply_focus()
	_refresh_crumbs()
	_log("前往「%s」" % case_def.scene_title(id), "act")
	_show_toast("前往「%s」" % case_def.scene_title(id))
	_commit(before)


## 把镜头平移到某张卡（只平移，不替玩家改缩放 —— 与 Web 的 focusOn 同口径）
func _center_on(card: NodeCard) -> void:
	if _stage == null or _card_layer == null:
		return
	var c := card.visual_center()
	_view_pos = _stage.size * 0.5 - c * _view_k
	_card_layer.position = _view_pos
	_view_user = true


## 指针下面是哪张卡（world 顺序里最上面那张：从后往前找）
func _card_key_at(at_global: Vector2) -> String:
	for i in range(_card_layer.get_child_count() - 1, -1, -1):
		var card := _card_layer.get_child(i) as NodeCard
		if card == null or not card.visible:
			continue
		# 正在拖的卡忽略自己：它现在跟着指针走，命中自己会被误判成「拖到别的节点上」
		if card.card_key == _drag_key:
			continue
		if card.get_global_rect().grow(-NodeCard.PAD * 0.5).has_point(at_global):
			return card.card_key
	return ""


func _on_card_activated(key: String) -> void:
	var n := graph.node(key)
	if n.is_empty():
		return
	if _tutorial_active and _tutorial_on_activate(key):
		return
	var id := String(n["id"])
	# 线索：双击 = 捕获（Web `runPrimary` 的第一支）。**不跑命令、不弹提示条**，
	# 结果只进案卷 —— 卡面自己会翻成深色反白（`.got`），画面已经说清楚了。
	if String(n["kind"]) == "clue":
		_capture_clue_node(key)
		return
	if n["kind"] == "loc":
		# Web dblclick：场景若带命令（SCENES[id].commands），双击先跑 commands[0]，
		# 不展开容器 —— 数据里 0/11 的场景用到这条，分支为未来案件铺路
		var sc := case_def.scene_of(id)
		if sc != null and sc.commands.size() > 0:
			var before_loc := _save.snapshot()
			var res := combos.activate(key)
			if res.is_empty():
				return
			_apply_outcome(res, key)
			_commit(before_loc)
			return
		_toggle_container("loc", id)
		return
	if graph.is_container("item", id):
		_toggle_container("item", id)
		return
	# 其余：跑第一条命令（text / password / choice / conditional / reveal 都从这儿进）
	var before := _save.snapshot()
	var res := combos.activate(key)
	if res.is_empty():
		if String(n["kind"]) == "char":
			if _say_next_line(id):
				return
			if _open_monologue(id):
				return
		return
	_apply_outcome(res, key)
	_commit(before)


## 双击线索 = 捕获（对齐 Web `08-interact.js:346`）。
## 捕获进 `graph.captured` + 卡面翻成 `.got` + 案卷一条 `cap`；重复双击只留一条 warn。
## **不进 toast** —— Web 这里刻意不弹，让画面自己说话。
func _capture_clue_node(key: String) -> void:
	var n := graph.node(key)
	if n.is_empty():
		return
	var id := String(n["id"])
	var lab := String(n.get("label", id))
	if graph.captured.has(id):
		_log("线索「%s」已经捕获过了" % lab, "warn")
		return
	var before := _save.snapshot()
	graph.capture_clue(id)          # 同时把节点字典的 captured 置位（卡片读的是同一份引用）
	_refresh_or_spawn_card(key)
	_log("已捕获线索「%s」" % lab, "cap")
	_on_card_selected(key)
	_commit(before)


## 容器双重身份：第一次双击展开，已展开再双击收起（对齐 Web 的展开 / 折叠）
func _toggle_container(kind: String, id: String) -> void:
	var before := _save.snapshot()
	if graph.explored.has(id) and not graph.is_collapsed(id):
		graph.collapse(id)
		_apply_hidden()
		var left := 0
		var self_key := graph.key_of(kind, id)
		for k in graph.nodes.keys():
			var kk := String(k)
			if kk == self_key:
				continue
			var nn := graph.node(kk)
			if String(nn.get("home_scene", "")) != id:
				continue
			if graph.visible_node(nn):
				left += 1
		if left > 0:
			_log("「%s」另有 %d 个节点留在画布上（已固定 / 与场外相连）"
				% [case_def.label_of(kind, id), left], "sys")
		_show_toast("收起了「%s」" % case_def.label_of(kind, id))
		_relayout(true)
		_commit(before)
		return
	var fresh := graph.reveal_container(kind, id)
	graph.uncollapse(id)
	_apply_hidden()
	for k in fresh:
		_spawn_card(String(k))
	if _cards.has(graph.key_of(kind, id)):
		_cards[graph.key_of(kind, id)].refresh()
		_sync_card_shell(_cards[graph.key_of(kind, id)])
	_relayout(true)
	if kind == "loc":
		_show_narr(id)
		_set_crumb(_case_label() + " // " + case_def.scene_title(id))
	else:
		_show_toast("展开了「%s」" % case_def.label_of(kind, id))
	_commit(before)


## 把图状态的隐藏结论落到卡片上（对齐 Web 的 recomputeHidden：钉住的、跟场外有连线的都不藏）
func _apply_hidden() -> void:
	graph.recompute_hidden()
	for key in _cards.keys():
		(_cards[key] as NodeCard).visible = graph.visible_node(graph.node(String(key)))
	_repaint_edges()
	_refresh_detail()


## 统一落地一次命令结果：提示 / 长卡片 / 刷新 / 重排
func _apply_outcome(res: Dictionary, node_key: String) -> void:
	if res.get("needs_password", false):
		_open_password(node_key)
		return
	var blocked := bool(res.get("blocked", false))
	var msg := String(res.get("message", ""))
	if msg != "":
		var nlab := String(graph.node(node_key).get("label", node_key))
		_log("「%s」：%s" % [nlab, msg], "warn" if blocked else "act")
		_show_toast(msg, blocked)
	for m in res.get("messages", []):
		if String(m) != "":
			_show_toast(String(m))
	for k in res.get("spawn", []):
		_spawn_card(String(k))
	for k in res.get("reveal", []):
		_spawn_card(String(k))
	for k in res.get("captured", []):
		_refresh_or_spawn_card(String(k))
	if bool(res.get("lit_changed", false)):
		if _cards.has(node_key):
			_cards[node_key].refresh()
			_sync_card_shell(_cards[node_key])
		var flavor := String(res.get("flavor", ""))
		if flavor != "":
			_show_toast(flavor)
	if res.has("next_scene") and String(res.get("next_scene", "")) != "":
		_set_crumb(_case_label() + " // " + case_def.scene_title(String(res["next_scene"])))
	_relayout()


# ── 收纳窗（证物袋 / 线索册）────────────────────────────────────────────

func _toggle_storage(kind: String) -> void:
	if not _require_case():
		return
	if kind == GraphState.BAG:
		if _bag_win != null and is_instance_valid(_bag_win):
			_bag_win.queue_free()
			_bag_win = null
			return
		_bag_win = StorageWin.new()
		_bag_win.name = "bag_win"
		_bag_win.setup_store("证物袋", GraphState.BAG, graph, case_def)
		_bag_win.position = Vector2(150, 300)
		_bag_win.will_take.connect(_on_storage_will_take)
		_bag_win.took.connect(_on_storage_took)
		_bag_win.row_pressed.connect(_on_row_pressed)
		_bag_win.closed.connect(func(): _bag_win = null)
		_desk.add_child(_bag_win)
		_place_z(_bag_win, ZR_WIN)
		return
	if _ledger_win != null and is_instance_valid(_ledger_win):
		_ledger_win.queue_free()
		_ledger_win = null
		return
	_ledger_win = StorageWin.new()
	_ledger_win.name = "clue_win"
	_ledger_win.setup_store("线索册", GraphState.LEDGER, graph, case_def)
	_ledger_win.position = Vector2(410, 300)
	_ledger_win.will_take.connect(_on_storage_will_take)
	_ledger_win.took.connect(_on_storage_took)
	_ledger_win.to_matrix.connect(_on_ledger_to_matrix)
	_ledger_win.row_pressed.connect(_on_row_pressed)
	_ledger_win.closed.connect(func(): _ledger_win = null)
	_desk.add_child(_ledger_win)
	_place_z(_ledger_win, ZR_WIN)


## 收纳窗取出前先拍快照（StorageWin 自己改图，Desktop 只能从信号里抢在它前面）
func _on_storage_will_take(_key: String) -> void:
	_storage_before = _save.snapshot()


## 从收纳窗取回：节点回到画布，并刷新两个清单窗
func _on_storage_took(key: String) -> void:
	if _cards.has(key):
		(_cards[key] as NodeCard).visible = graph.visible_node(graph.node(key))
	_relayout()
	if _bag_win != null and is_instance_valid(_bag_win):
		_bag_win.refresh_store()
	if _ledger_win != null and is_instance_valid(_ledger_win):
		_ledger_win.refresh_store()
	_commit(_storage_before)
	_storage_before = {}


# ── 人物名册 / 因果追踪（批 1：差距报告 I1 / I2）─────────────────────────

## 名册：Web `people-win`（right 328 / top 60 / 宽 324）—— 紧挨详情窗左侧，列表与详情成一对。
## 宽 324 = 300 + 头像加大的 24px：文本列净宽与 24×24 时代一致，描述不会被压窄。
func _toggle_people() -> void:
	if not _require_case():
		return
	if _people_win != null and is_instance_valid(_people_win):
		_people_win.queue_free()
		_people_win = null
		return
	_people_win = PeopleWin.new()
	_people_win.name = "people_win"
	_people_win.setup_people(graph, case_def)
	# 定位按 Web 的 right / top 算，并且跟着**实际尺寸**走（size 含 PAD 的投影余量）
	_people_win.position = Vector2(_vw() - 328.0 - _people_win.size.x + SysWindow.PAD, 60.0)
	_people_win.row_clicked.connect(_on_people_row)
	_people_win.closed.connect(func(): _people_win = null)
	_desk.add_child(_people_win)
	_place_z(_people_win, ZR_WIN)


func _refresh_people_win() -> void:
	if _people_win != null and is_instance_valid(_people_win):
		_people_win.refresh_people()


## 点行（Web `refreshPeopleWin` 的 click）：常驻成员 = 打开各自的窗；
## 遇到的人 = 叫到画布中央、选中，接着说下一句。
func _on_people_row(id: String) -> void:
	if not _require_case():
		return
	if id == "CHARS_TEC":
		_toggle_tec()
		return
	if id == "CHARS_EXEC":
		_toggle_matrix()
		return
	_goto_char(id)


## 把人物叫到画面中央（Web `gotoChar`）：没节点就补一个、在袋里就取回，然后居中 + 选中。
func _goto_char(id: String) -> bool:
	if case_def == null:
		return false
	var key := graph.key_of("char", id)
	var ch := case_def.char_of(id)
	var label := ch.name if ch != null and ch.name != "" else id
	var before := _save.snapshot() if _save != null else {}
	var spawn := false
	if not graph.nodes.has(key):
		var n := graph.add_node("char", id)
		if String(n.get("home_scene", "")) == "":
			n["home_scene"] = graph.last_scene
		spawn = true
	if graph.stored.has(key):
		graph.take_back(key)
		spawn = true
	if spawn or not _cards.has(key):
		_refresh_or_spawn_card(key)
		_relayout()
	else:
		var card0: NodeCard = _cards[key]
		card0.visible = graph.visible_node(graph.node(key))
	_repaint_edges()
	var card: NodeCard = _cards.get(key, null)
	if card != null:
		_center_on(card)
	_on_card_selected(key)
	if _say_next_line(id):
		return true
	_show_toast("「%s」\n（暂无对话文本）" % label, true)
	_commit(before)
	return true


## 说下一句（Web `showCharLine`）：推进 talkQueue、收下台词里提到的线索、开对话窗。
## 说完 / 没有台词时不推进 —— 点了也不再出新句。
func _say_next_line(id: String) -> bool:
	if case_def == null:
		return false
	var key := graph.key_of("char", id)
	var ch := case_def.char_of(id)
	if ch == null:
		return false
	var queue := graph.char_talk_queue(id)
	var prog := int(graph.talk_prog.get(key, 0))
	if queue.is_empty() or prog >= queue.size():
		return false
	if _chat_win != null and is_instance_valid(_chat_win):
		return false        # 对话窗开着：不叠第二扇（Web 的 dlg-win 独立，P2.4 侧待补）
	var before := _save.snapshot() if _save != null else {}
	graph.talk_prog[key] = prog + 1
	var line := String(queue[prog])
	var got := _capture_text_clues(line, key)
	_refresh_clue_keys(got)
	var d := DialogueDef.new()
	d.id = "talk_" + String(ch.id)
	var parts: Array[CharDef] = [ch]
	d.participants = parts
	var ld := DialogueLineDef.new()
	ld.kind = "say"
	ld.who = ch
	ld.text = line
	d.script_lines.append(ld)
	_open_chat(d, [String(ch.id)])
	if not got.is_empty():
		_log("「%s」的话里提到了线索：%s" % [ch.name, "、".join(_labels_of(got))], "cap")
	_commit(before)
	return true


func _labels_of(ids: Array) -> Array:
	var out: Array = []
	for cid in ids:
		out.append(case_def.label_of("clue", String(cid)))
	return out


## 日志窗：Web `#log-win`（right 14 / bottom 96 / 宽 320）
func _toggle_log() -> void:
	if not _require_case():
		return
	if _log_win != null and is_instance_valid(_log_win):
		_log_win.queue_free()
		_log_win = null
		return
	_log_win = LogWin.new()
	_log_win.name = "log_win"
	_log_win.setup_log(graph)
	_log_win.position = Vector2(_vw() - 14.0 - _log_win.size.x + SysWindow.PAD,
		_vh() - HEADER_H - 96.0 - _log_win.size.y + SysWindow.PAD)
	_log_win.closed.connect(func(): _log_win = null)
	_desk.add_child(_log_win)
	_place_z(_log_win, ZR_LOG)
	_log_unread = 0
	_set_badge(_log_badge, "")


func _refresh_log_win() -> void:
	if _log_win != null and is_instance_valid(_log_win):
		_log_win.refresh_log()


## 写一条案卷（口径见 GraphState.add_log 上方）。窗关着时累未读 —— Web `logUnread`。
## 带内部 key 的调试条目（`item:ITEMS_x` / `loc:SCENES_y`）不进玩家案卷，
## 只落 `user://tec-debug.log`，避免日志窗出现「组合 item:IT」这种破句。
func _log(text: String, kind: String = "") -> void:
	if graph == null or text == "":
		return
	if _has_internal_key(text):
		_append_debug_log(text, kind)
		return
	graph.add_log(text, kind)
	if _log_win != null and is_instance_valid(_log_win):
		_log_win.refresh_log()
		return
	_log_unread += 1
	_set_badge(_log_badge, str(_log_unread))


func _has_internal_key(text: String) -> bool:
	var re := RegEx.new()
	if re.compile("(?i)(?:^|[\\s（「『【\\[,，：])(?:item|clue|char|loc|scene|time|dlg|npcs?|scenes|chars|items|clues):[a-z0-9_]+") != OK:
		return false
	return re.search(text) != null


func _append_debug_log(text: String, kind: String) -> void:
	var path := "user://tec-debug.log"
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("[%s]%s %s" % [Time.get_datetime_string_from_system(false, true),
		(" " + kind) if kind != "" else "", text])


# ── 推演桌布（五感槽位 / 归位 / 长按推演）──────────────────────────────

func _toggle_matrix() -> void:
	if not _require_case():
		return
	if _matrix_win != null and is_instance_valid(_matrix_win):
		_restore_matrix_occlusion()
		_matrix_win.queue_free()
		_matrix_win = null
		_place_floating_windows()
		return
	_matrix_win = MatrixWin.new()
	_matrix_win.name = "matrix_win"
	_matrix_win.setup_matrix(graph, case_def)
	_matrix_win.position = Vector2(336, 40)
	_matrix_win.clue_taken.connect(_on_matrix_took)
	_matrix_win.clue_dropped.connect(_on_matrix_dropped)
	_matrix_win.inference_requested.connect(_run_inference)
	_matrix_win.seed_dropped.connect(_on_seed_dropped)
	## A7：用户点窗内 × 关闭时也要恢复被淡出的卡片；不能只覆盖图标开关那条路径。
	_matrix_win.closed.connect(_on_matrix_closed)
	# 线索卡拖动的镜像挂在桌面上（桌布自己 clip_contents，镜像挂里面拖到边缘会被裁掉）
	_matrix_win.drag_host = _desk
	_matrix_win.item_rect_changed.connect(_sync_matrix_occlusion)
	_desk.add_child(_matrix_win)
	_place_z(_matrix_win, ZR_WIN)
	_place_floating_windows()
	_sync_matrix_occlusion.call_deferred()


## A7：矩阵窗会把正下方的卡片遮得只剩一条白边，看起来像窗口漏了一块。
## 只对「大部分面积都被窗盖住」的卡片淡出；拖窗时实时重算，关窗恢复。
## 用 modulate 而非 visible：_layout_force 只排可见卡片，隐藏会让别的卡重排。
func _sync_matrix_occlusion() -> void:
	_restore_matrix_occlusion()
	if _matrix_win == null or not is_instance_valid(_matrix_win) or not _matrix_win.visible:
		return
	var win := Rect2(_matrix_win.global_position, _matrix_win.size)
	for key in _cards.keys():
		var c: NodeCard = _cards[key]
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
		_matrix_faded.append(key)


func _restore_matrix_occlusion() -> void:
	for key in _matrix_faded:
		var c: NodeCard = _cards.get(String(key), null)
		if c != null and is_instance_valid(c):
			c.modulate.a = 1.0
			c.process_mode = Node.PROCESS_MODE_INHERIT
	_matrix_faded.clear()


func _on_matrix_closed() -> void:
	_restore_matrix_occlusion()
	_matrix_win = null
	_place_floating_windows()


## 画布 / 册子 → 桌布。感官自动取线索自身的 sense（与 Web 的 assignClue 一致）。
func _assign_to_matrix(key: String) -> bool:
	var n := graph.node(key)
	if n.is_empty():
		return false
	if String(n["kind"]) != "clue":
		_show_toast("只有线索能归位到推演桌布", true)
		return false
	var cl := case_def.clue_of(String(n["id"]))
	if cl == null:
		return false
	var before := _save.snapshot()
	if not graph.matrix_assign(key):
		_show_toast("「%s」的感官类型是%s，归位失败" % [n.get("label", ""), GraphState.SENSE_NAMES.get(cl.sense, cl.sense)], true)
		return false
	_apply_hidden()
	_refresh_or_spawn_card(key)
	_refresh_matrix_views()
	_commit(before)
	return true


func _on_matrix_took(key: String, at_global: Vector2 = Vector2(-1.0, -1.0)) -> void:
	var before := _save.snapshot()
	# 带坐标取回（Web `boardTake(cid, sense, cx, cy)`）：落在松手那一点。换算与 `_finish_sdrag` 同一条公式。
	var world := Vector2(-1.0, -1.0)
	if at_global.x >= 0.0:
		world = (at_global - _stage.get_global_position() - _view_pos) / maxf(_view_k, 0.01)
	if not graph.matrix_take(key, world.x, world.y):
		return
	_apply_hidden()
	_refresh_or_spawn_card(key)
	if world.x >= 0.0:
		var card := _cards.get(key, null) as NodeCard
		if card != null:
			card.position = world
			card.set_home(world)
	_repaint_edges()
	_refresh_matrix_views()
	_commit(before)


## 桌布上的线索拖到线索册（窗**或册图标**，Web `overLedgerDrop` 的两条）= 改归册子；
## 拖出桌布落到别处 = **带坐标**取回画布（反向 8 条路径的最后一条）
func _on_matrix_dropped(key: String, at_global: Vector2) -> void:
	var ic := _desk.get_node_or_null("icons/icon_clue") as Control
	var on_ledger := _ledger_win != null and is_instance_valid(_ledger_win) \
		and _ledger_win.is_visible_in_tree() and _ledger_win.get_global_rect().has_point(at_global)
	if ic != null and ic.is_visible_in_tree() and ic.get_global_rect().has_point(at_global):
		on_ledger = true
	if on_ledger:
		var before := _save.snapshot()
		if graph.restash(key, GraphState.MATRIX, GraphState.LEDGER):
			_apply_hidden()
			_refresh_matrix_views()
			_commit(before)
		return
	_on_matrix_took(key, at_global)


func _on_ledger_to_matrix(key: String) -> void:
	var before := _save.snapshot()
	if graph.matrix_assign(key):
		_apply_hidden()
		_refresh_matrix_views()
		_commit(before)
	else:
		_show_toast("这条线索没有可用的感官槽位", true)


func _refresh_matrix_views() -> void:
	if _matrix_win != null and is_instance_valid(_matrix_win):
		_matrix_win.refresh_matrix()
		_matrix_win.refresh_seed()
	if _bag_win != null and is_instance_valid(_bag_win):
		_bag_win.refresh_store()
	if _ledger_win != null and is_instance_valid(_ledger_win):
		_ledger_win.refresh_store()


## 长按蓄力完成 → 配方判定（Web 的 executeInference）：恰好命中才算，多余线索也失败
func _run_inference() -> void:
	var hit := graph.match_ending()
	if hit == null:
		if _matrix_win != null and is_instance_valid(_matrix_win):
			_matrix_win.show_heartbroken()
		_log("推演失败：当前阵列不匹配任何结局配方", "warn")
		_show_toast("推演失败：当前阵列不匹配任何结局配方", true)
		return
	var before := _save.snapshot()
	graph.mark_ending(hit.id)
	_last_ending_id = hit.id
	if hit.is_true_capture and not _progress_read_only:
		_catalog.mark_completed(_active_case)
		if _catalog.unlock_next(_active_case):
			_log("新案件地址已解锁：%s" % _next_case_code(_active_case), "cap")
		_update_case_park_ui()
	if _matrix_win != null and is_instance_valid(_matrix_win):
		_matrix_win.play_shock()
	_log("结局达成：%s" % hit.name, "cap")
	_ending.play(hit)
	_commit(before)


func _refresh_or_spawn_card(key: String) -> void:
	var card: NodeCard = _cards.get(key, null)
	if card == null:
		card = _spawn_card(key)
	if card != null:
		card.visible = graph.visible_node(graph.node(key))
		card.refresh()
		_sync_card_shell(card)


func _sync_card_shell(card: NodeCard) -> void:
	if card == null or graph == null:
		return
	var n := graph.node(card.card_key)
	var id := String(n.get("id", ""))
	card.set_shell_state(graph.is_container_node(card.card_key),
		graph.explored.has(id), graph.is_collapsed(id), bool(n.get("unread", false)),
		graph.is_hub(String(n.get("kind", "")), id))
	card.set_warn(graph.is_no_entry(card.card_key))


## 供测试钩子 / 后续接线用：把当前选中的节点收进某个收纳处
## 无头钩子：模拟「把收纳窗里的一行拖到 at_global」（跳过 _process 的指针轮询）
func dbg_storage_drag(key: String, at_global: Vector2) -> void:
	if not graph.stored.has(key):
		return
	_on_row_pressed(key, String(graph.stored.get(key, "")), at_global)
	_sdrag_started = true
	_finish_sdrag(at_global)


## 探针：当前落点表的 id 列表（保持顺序）。
## 单一入口的意义就在这里 —— 以后加落点只改 `_drop_targets()` 与 `_apply_drop()`，
## 悬停高亮、松手分派共用同一份，不可能出现"高亮了但不生效"。
func dbg_drop_target_ids() -> Array:
	var out: Array = []
	for t in _drop_targets():
		out.append(String(t["id"]))
	return out


func dbg_store(kind: String) -> bool:
	if _selected == "":
		return false
	if kind == GraphState.MATRIX:
		return _assign_to_matrix(_selected)
	var before := _save.snapshot()
	var ok := false
	if kind == GraphState.BAG:
		ok = graph.bag_store(_selected)
	elif kind == GraphState.LEDGER:
		ok = graph.ledger_store(_selected)
	if not ok:
		return false
	_apply_hidden()
	_refresh_matrix_views()
	_commit(before)
	return true


# ── 密码弹窗 ────────────────────────────────────────────────────────────

func _open_password(node_key: String) -> void:
	var n := graph.node(node_key)
	var it := case_def.item_of(String(n.get("id", "")))
	if it == null:
		return
	var cmd: PasswordCommandDef = null
	for c in it.commands:
		if c is PasswordCommandDef:
			cmd = c
			break
	if cmd == null:
		return
	if _pw_pop != null and is_instance_valid(_pw_pop):
		if _pw_pop.get_parent() != null:
			_pw_pop.get_parent().remove_child(_pw_pop)
		_pw_pop.queue_free()
	var card: NodeCard = _cards.get(node_key, null)
	_pw_pop = PasswordPop.new()
	_pw_pop.name = "pw_pop"
	_pw_pop.setup_password(it.label, cmd.label)
	var base := Vector2(300, 300)
	if card != null:
		var r := card.get_global_rect()
		base = Vector2(r.position.x - _desk.get_global_rect().position.x,
			r.end.y - _desk.get_global_rect().position.y + 10.0)
	_pw_pop.position = base
	_pw_pop.submitted.connect(_submit_password)
	_desk.add_child(_pw_pop)
	_place_z(_pw_pop, ZR_PW)
	_pw_ctx = {"node_key": node_key, "cmd": cmd}


func _submit_password(text: String) -> void:
	if _pw_ctx.is_empty():
		return
	var before := _save.snapshot()
	var res := _cmds.submit_password(String(_pw_ctx["node_key"]), _pw_ctx["cmd"], text)
	if bool(res.get("wrong_password", false)):
		if _pw_pop != null and is_instance_valid(_pw_pop):
			_pw_pop.reject_wrong()
		var pw_key := String(_pw_ctx.get("node_key", ""))
		var pw_lab := String(graph.node(pw_key).get("label", pw_key))
		var pw_txt := String(text) if String(text) != "" else "(空)"
		_log("「%s」密码 %s 不正确" % [pw_lab, pw_txt], "warn")
		_show_toast(String(res.get("message", "")), true)
		return
	if _pw_pop != null and is_instance_valid(_pw_pop):
		_pw_pop.queue_free()
	_pw_pop = null
	_apply_outcome(res, String(_pw_ctx["node_key"]))
	_pw_ctx = {}
	_commit(before)


func _on_card_combo(tool_key: String, target_key: String) -> void:
	# 折叠的容器（场景 / 书桌 / 垃圾桶）既不收纳也不组合：里面的东西看不见，隔空命中的结果没有着力点
	var tn := graph.node(target_key)
	if not tn.is_empty() and graph.is_container_node(target_key) \
		and graph.collapsed.has(String(tn.get("id", ""))):
		_show_toast("「%s」已折叠：先双击展开，或把节点拖到证物袋" % String(tn.get("label", "")), true)
		return
	var before := _save.snapshot()
	# 标签要在 use_item 之前取：工具可能被消耗并从图中移除，事后再拿只剩内部 key。
	var tool_label := String(graph.node(tool_key).get("label", tool_key))
	var target_label := String(tn.get("label", target_key))
	if _try_memory_combo(tool_key, target_key, before):
		return
	if _try_dialogue_combo(tool_key, target_key):
		return
	var res := combos.use_item(tool_key, target_key)
	# 前往：容器正文里 `[loc:对方]` 列着它 ⇒ 展开目标场景（Web 的 revealScene）。
	# 案卷记一条 act；不弹提示条，也不写「组合」字样 —— 这是走动，不是合成。
	var travel := String(res.get("travel", ""))
	if travel != "":
		_log("前往场景「%s」" % case_def.scene_title(travel), "act")
		_expand_scene(travel, true)
		_commit(before)
		return
	if res.has("blocked") and res["blocked"]:
		# 发光门：不记 tried、不进撤销，但拦下的理由要进案卷（Web 09-commands.js:10）
		_log(String(res.get("message", "")), "warn")
		_show_toast(String(res.get("message", "")), true)
		return
	if res.get("ok", false):
		# 组合成功**不弹提示条**（Web 刻意）：结果靠画面自证，正文与「获得 / 消耗」只进案卷（C8）
		var bits := "组合 %s ⇒ %s：%s" % [tool_label, target_label, String(res.get("message", ""))]
		var gained: Array = []
		for k in res.get("reveal", []):
			gained.append(String(graph.node(String(k)).get("label", k)))
		for k in res.get("captured", []):
			gained.append(String(graph.node(String(k)).get("label", k)))
		if not gained.is_empty():
			bits += "　［获得 %s］" % "、".join(gained)
		var consumed: Array = []
		for k in res.get("consumed", []):
			var kk := String(k)
			var iid := kk.substr(kk.find(":") + 1)
			consumed.append(case_def.label_of("item", iid))
		if not consumed.is_empty():
			bits += "　［消耗 %s］" % "、".join(consumed)
		_log(bits, "act")
		var next_scene := String(res.get("next_scene", ""))
		if next_scene != "":
			_expand_scene(next_scene, true)
		for k in res.get("reveal", []):
			_spawn_card(String(k))
		for k in res.get("captured", []):
			_refresh_or_spawn_card(String(k))
		_relayout()
		_commit(before)
	else:
		var msg := String(res.get("message", ""))
		if msg != "":
			# 失败**不弹提示条**（Web `05-combine.js:168` 的 fail()：条件不足 = 什么也没发生，
			# 原因只留在案卷里）。原先这里还弹一张条，等于一边说「组合失败」一边打断画面。
			_log("组合失败：" + msg, "warn")
		# 失败只多一条「试过」虚线，**不动坐标**（以前这里跑 _relayout，等于每次失败都把全场归位）
		_repaint_edges()


func _expand_scene(sid: String, show_narr: bool) -> void:
	var was_explored := graph.explored.has(sid)
	var fresh := graph.reveal_scene(sid)
	var key := graph.scene_key(sid)
	var had := _cards.has(key)
	for k in fresh:
		_spawn_card(String(k))
	if not had:
		_spawn_card(key)
	if _cards.has(key):
		_cards[key].refresh()
		_sync_card_shell(_cards[key])
	_relayout()
	if show_narr:
		_show_narr(sid)
	_set_crumb(_case_label() + " // " + case_def.scene_title(sid))
	# 首次展开的两条提示（Web 04-graph.js:118/120）：回忆锚点 / TEC 档案，两条互不替代
	if not was_explored:
		var title := case_def.scene_title(sid)
		if case_def.is_time_id(sid):
			_log("「%s」可以当一段回忆的锚点（把它拖到一个地点上，再拖一个人物上去）" % title, "sys")
		var tec := case_def.char_of("CHARS_TEC")
		if tec != null:
			for st in tec.scene_talks:
				if st != null and st.scene != null and st.scene.id == sid:
					_log("「%s」似乎有可以解读的档案（把场景节点拖给 TEC 分析）" % title, "sys")
					break


func _show_narr(sid: String) -> void:
	var n := graph.node(graph.scene_key(sid))
	if n.is_empty():
		return
	var body := case_def.text_of(graph.normalize_kind("loc", sid), sid)
	if _narr != null and is_instance_valid(_narr):
		_narr.queue_free()
	_narr = NarrCard.new()
	_narr.name = "narr_card"
	_narr.setup_narr(case_def.scene_title(sid), body, 340, 300)
	_narr.position = Vector2(700, 290)
	_narr.closed.connect(_on_narr_closed)
	_desk.add_child(_narr)
	_place_z(_narr, ZR_NARR)


func _on_narr_closed() -> void:
	_narr = null


# ── 档案 / 时间图层 / 回忆放映 ─────────────────────────────────────────

func _toggle_archive() -> void:
	if not _require_case():
		return
	if _archive_win != null and is_instance_valid(_archive_win):
		_archive_win.queue_free()
		_archive_win = null
		return
	_archive_win = ArchiveWin.new()
	_archive_win.name = "archive_win"
	_archive_win.setup_archive(graph, case_def)
	_archive_win.time_selected.connect(_on_archive_time)
	_archive_win.closed.connect(func(): _archive_win = null)
	_desk.add_child(_archive_win)
	_place_z(_archive_win, ZR_WIN)
	_place_floating_windows()
	_clear_archive_new()
	for sid in graph.timeline_known():
		graph.clear_fresh(graph.scene_key(String(sid)))


func _on_archive_time(tid: String) -> void:
	_select_time(tid)


func _try_memory_combo(tool_key: String, target_key: String, before: Dictionary) -> bool:
	if graph == null or case_def == null or graph.time == GraphState.PRESENT_TIME:
		return false
	var tool := graph.node(tool_key)
	var target := graph.node(target_key)
	if tool.is_empty() or target.is_empty():
		return false
	var who: Dictionary = {}
	var where: Dictionary = {}
	var where_key := ""
	if String(tool["kind"]) == "char":
		who = tool
	elif String(target["kind"]) == "char":
		who = target
	if String(tool["kind"]) == "loc":
		where = tool
		where_key = tool_key
	elif String(target["kind"]) == "loc":
		where = target
		where_key = target_key
	if who.is_empty() or where.is_empty():
		return false
	var mem := case_def.memory_for(graph.time, String(who["id"]), String(where["id"]))
	graph.tried[tool_key + ">" + target_key] = true
	if mem != null:
		_open_memory_play(mem, where_key)
		var title := mem.title if mem.title != "" else mem.id
		_show_toast("想起了一段回忆：" + title)
	else:
		_show_toast("「%s」里没有「%s」的回忆" % [String(where["label"]), String(who["label"])], true)
	_commit(before)
	_relayout()
	return true


## 换档 = 改 graph.time → 收掉锚在画布上的浮层 → 带出那天的登场人物 → 重算可见性。
func _select_time(tid: String) -> bool:
	if graph == null or case_def == null:
		return false
	if tid != GraphState.PRESENT_TIME and not case_def.is_time_id(tid):
		return false
	if graph.time == tid:
		if tid != GraphState.PRESENT_TIME:
			_open_time_card(tid)
		return true
	_close_time_transients()
	graph.time = tid
	_selected = ""
	graph.selected = ""
	if tid != GraphState.PRESENT_TIME:
		graph.spawn_mem_cast(tid)
	_sync_cards_for_time()
	_apply_hidden()
	_sync_time_crumb()
	_open_time_card_once(tid)
	_autosave()
	return true


func _close_time_transients() -> void:
	if _pw_pop != null and is_instance_valid(_pw_pop):
		_pw_pop.queue_free()
	_pw_pop = null
	_pw_ctx = {}
	if _narr != null and is_instance_valid(_narr):
		_narr.queue_free()
	_narr = null
	_close_mem_card()
	_close_chat()


## 把图上已有、但还没上过画布的实体补成卡片；已存在的只刷新（时刻切换不重排）。
func _sync_cards_for_time() -> void:
	for key in graph.nodes.keys():
		var n := graph.node(String(key))
		if n.is_empty() or String(n["kind"]) == "time":
			continue
		if _cards.has(String(key)):
			(_cards[String(key)] as NodeCard).refresh()
			_sync_card_shell(_cards[String(key)])
		else:
			_spawn_card(String(key))


func _sync_time_crumb() -> void:
	if graph.time != GraphState.PRESENT_TIME:
		_set_crumb(_case_label() + " // " + graph.time_label_of())
		return
	var sid := graph.last_scene
	if sid != "":
		_set_crumb(_case_label() + " // " + case_def.scene_title(sid))
	else:
		_set_crumb(_case_label() + " // " + graph.time_label_of())


## 每档回忆的放映卡只自动放一遍；重放走档案里点当前档。
func _open_time_card_once(tid: String) -> void:
	if tid == GraphState.PRESENT_TIME or not case_def.is_time_id(tid):
		return
	if bool(graph.card_seen.get(tid, false)):
		return
	graph.card_seen[tid] = true
	_open_time_card(tid)
	_autosave()


func _open_time_card(tid: String) -> void:
	if tid == GraphState.PRESENT_TIME or not case_def.is_time_id(tid):
		return
	_close_mem_card()
	_mem_card = MemCard.new()
	_mem_card.name = "mem_card"
	_mem_card.setup_memory("记忆 · " + case_def.time_label_of(tid), _memory_lines(tid))
	_mem_card.closed.connect(_on_mem_closed)
	_desk.add_child(_mem_card)
	_anchor_memory_card(_mem_card, tid)
	_place_z(_mem_card, ZR_NARR)


## 放映卡正文 = 日期场景正文（按行拆）+ 该场景里各角色当天的 sceneTalks。
func _memory_lines(tid: String) -> Array:
	var out: Array = []
	var s := case_def.scene_of(tid)
	if s == null:
		return out
	var body := s.content if s.content.strip_edges() != "" else s.desc
	for raw in case_def.strip_tags(body).split("\n"):
		var line := String(raw).strip_edges()
		if line != "":
			out.append(line)
	for tag in case_def.nodes_of_scene(s):
		if String(tag["kind"]) != "char":
			continue
		var cid := String(tag["id"])
		var ch := case_def.char_of(cid)
		if ch == null:
			continue
		for st in ch.scene_talks:
			if st == null or st.scene == null or st.scene.id != tid:
				continue
			for raw in st.lines:
				var talk_line := case_def.strip_tags(String(raw)).strip_edges()
				if talk_line != "":
					out.append("——%s：%s" % [ch.name, talk_line])
	return out


func _memory_play_lines(mem: MemoryDef) -> Array:
	var out: Array = []
	for line in mem.script_lines:
		if line == null:
			continue
		var text := case_def.strip_tags(line.text).strip_edges()
		if text == "":
			continue
		var kind := "say" if line.kind == "say" else "narr"
		var who_id := line.who.id if line.who != null else ""
		var who_name := line.who.name if line.who != null else ""
		out.append({"t": kind, "text": text, "who": who_id, "name": who_name})
	return out


func _open_memory_play(mem: MemoryDef, where_key: String) -> void:
	if mem == null:
		return
	_close_mem_card()
	_mem_card = MemCard.new()
	_mem_card.name = "mem_card"
	var title := mem.title if mem.title != "" else mem.id
	_log("想起了一段回忆：%s" % title, "sys")
	_mem_card.setup_play("记忆 · " + title, _memory_play_lines(mem), 420, 300)
	_mem_card.closed.connect(_on_mem_closed)
	_desk.add_child(_mem_card)
	_anchor_card_to(_mem_card, where_key)
	_place_z(_mem_card, ZR_NARR)


## 锚在该时刻的发生地点上方；上方放不下就放下面，再整体钳进桌面。
func _anchor_memory_card(card: MemCard, tid: String) -> void:
	var place := case_def.mem_place_of(tid)
	_anchor_card_to(card, graph.scene_key(place.id) if place != null else "")


## 锚定时的「锚点节点」：节点还在重排补间里飞的时候锚出来的位置是**中途位置**，
## 补间一结束就对不上（实测 448×328 的放映卡压住花园节点）。补间收尾时按新位置重锚。
var _mem_anchor_key := ""


func _anchor_card_to(card: MemCard, node_key: String) -> void:
	if card == null:
		return
	_mem_anchor_key = node_key
	var area := Vector2(_vw(), _vh() - HEADER_H)
	var pos := Vector2(700.0, 290.0)
	var nc := _cards.get(node_key) as NodeCard
	if nc != null and is_instance_valid(nc) and nc.visible:
		var origin := _desk.get_global_rect().position
		var g := nc.get_global_rect()
		var t := Rect2(g.position - origin, g.size)
		var cs := card.size
		var cx := t.position.x + (t.size.x - cs.x) * 0.5
		var cy := t.position.y + (t.size.y - cs.y) * 0.5
		## 四方位按「上 → 下 → 右 → 左」试，取第一个既不越界、也不压住其它可见卡的位置。
		## 720 基准下桌面只剩 668 高：放映卡（448×328）与节点都居中时，
		## 单靠「上/下」二选一必然压住节点（上方局部 −9 越界、下方 742 越界，
		## 钳回 332 之后正好盖住地点卡）。Web 是流式布局，没这个死角。
		var cands: Array = [
			Vector2(cx, t.position.y - cs.y - 14.0),
			Vector2(cx, t.position.y + t.size.y + 14.0),
			Vector2(t.position.x + t.size.x + 14.0, cy),
			Vector2(t.position.x - cs.x - 14.0, cy),
		]
		var board := Rect2(Vector2(8, 8), area - Vector2(16, 16))
		var picked := Vector2.INF
		for c in cands:
			var r := Rect2(c, cs)
			if board.encloses(r) and not _mem_blocked(r, node_key):
				picked = c
				break
		if not picked.is_finite():
			## 四方位都塞不下：720 基准下桌面只有 668 高，448×328 的放映卡与居中节点
			## 垂直方向正好差几像素（上方 −9、下方 742）。这时把卡压到「上方可用高」以内
			## 再贴顶放下 —— 内容区本来就有滚动条，少 17px 视觉无感。
			var avail_h := maxf(180.0, t.position.y - 8.0 - 14.0)
			if avail_h < cs.y:
				card.set_inner_height(avail_h - SysWindow.PAD * 2.0)
				cs = card.size
			picked = Vector2(cx, t.position.y - cs.y - 14.0)
		pos = picked
	pos.x = clampf(pos.x, MEM_CARD_MIN_X, area.x - card.size.x - 8.0)
	pos.y = clampf(pos.y, 8.0, area.y - card.size.y - 8.0)
	card.position = pos


## 回忆卡候选位是否压住别的可见节点（浮窗不算 —— 那本就允许被压）。
func _mem_blocked(r: Rect2, skip_key: String) -> bool:
	var origin := _desk.get_global_rect().position
	for k in _cards.keys():
		if String(k) == skip_key:
			continue
		var c := _cards[k] as NodeCard
		if c == null or not is_instance_valid(c) or not c.visible:
			continue
		var g := c.get_global_rect()
		if r.intersects(Rect2(g.position - origin, g.size)):
			return true
	return false


func _close_mem_card() -> void:
	if _mem_card != null and is_instance_valid(_mem_card):
		_mem_card.queue_free()
	_mem_card = null


func _on_mem_closed() -> void:
	_mem_card = null


func _close_chat() -> void:
	if _chat_win != null and is_instance_valid(_chat_win):
		_chat_win.queue_free()
	_chat_win = null


func _on_chat_closed() -> void:
	_chat_win = null


## 对话窗固定贴右上（Web `.chat-win`：right 18 / top 72；desk 已让出 header，再减 PAD 14）。
func _open_chat(entry: DialogueDef, ids: Array) -> bool:
	if entry == null or case_def == null:
		return false
	_close_chat()
	_chat_win = ChatWindow.new()
	_chat_win.name = "chat_win"
	_chat_win.setup_chat(entry, ids, case_def)
	_chat_win.closed.connect(_on_chat_closed)
	_desk.add_child(_chat_win)
	_place_z(_chat_win, ZR_CHAT)
	_place_floating_windows()
	return true


func _open_monologue(char_id: String) -> bool:
	if dialogues == null:
		return false
	var entry := dialogues.monologue_of(char_id)
	if entry == null:
		return false
	return _open_chat(entry, [char_id])


func _try_dialogue_combo(tool_key: String, target_key: String) -> bool:
	if dialogues == null:
		return false
	var a := graph.node(tool_key)
	var b := graph.node(target_key)
	if a.is_empty() or b.is_empty():
		return false
	if String(a["kind"]) != "char" or String(b["kind"]) != "char":
		return false
	var ids := [String(a["id"]), String(b["id"])]
	var entry := dialogues.lookup(ids)
	if entry == null:
		entry = dialogues.fallback(ids)
	return _open_chat(entry, ids)


func _chat_drop_hit(at_global: Vector2) -> bool:
	var chat := dbg_chat()
	return chat != null and chat.get_global_rect().has_point(at_global)


func _chat_drop(key: String) -> bool:
	var chat := dbg_chat()
	if chat == null or graph == null:
		return false
	var n := graph.node(key)
	if n.is_empty():
		return false
	return chat.drop_node(String(n["kind"]), String(n["id"]))


func _mark_archive_new() -> void:
	_archive_new = true
	if _archive_badge != null:
		_archive_badge.visible = true


func _clear_archive_new() -> void:
	_archive_new = false
	if _archive_badge != null:
		_archive_badge.visible = false


## 当前「可见节点集合」的签名。力导向只认它：集合没变 = 结构没变 = 一个坐标都不该动。
## 对齐 Web `09-commands.js`：「开关灯只重绘（重排会让灯自己跳位置）」—— 那边只有真长出
## 新节点的分支才 `layout()`。
var _layout_sig := ""


func _layout_signature() -> String:
	var keys: Array = []
	for key in _cards.keys():
		if (_cards[key] as NodeCard).visible:
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
	if force or sig != _layout_sig:
		_layout_sig = sig
		if _tutorial_active:
			_layout_tutorial()
		else:
			_layout_force(animated)
		## 自动档才重框；玩家自己调过镜头（滚轮 / 拖空白 / 定位某张卡）就别动他的视野，
		## 否则每加一个节点、镜头就被拉开一次 —— 刚放大到某张卡细看时会像「被抢走」。
		if _opt_reveal and not _view_user:
			_fit_cards()
	_refresh_crumbs()
	_sync_header_sizes()
	_repaint_edges()
	_reanchor_mem_card()
	_sync_matrix_occlusion()


## 教学桌面不做力导向：三张卡是 TEC 亲手摆的教学道具，位置必须稳定可预期，
## 否则刚生成的线索会被弹簧/斥力推到画布边上，玩家根本找不到。
func _layout_tutorial() -> void:
	for key in _cards.keys():
		var card: NodeCard = _cards[key]
		if card == null or not card.visible:
			continue
		_kill_move(String(key))
		var n := graph.node(String(key))
		var p := Vector2(float(n.get("x", 0.0)), float(n.get("y", 0.0)))
		card.set_home_silent(p)
		card.position = p


## 力导向：斥力 30000/d²、最小间距 R_a+R_b+14、弹簧 rest 185/300/150、向心 0.0022，260 轮。
## 参数照抄 `src/js/07-render.js`；R 用视觉半径（半对角线），与 Web 的 80 / 68 同口径。
func _layout_force(animated: bool = false) -> void:
	var list: Array = []
	for key in _cards.keys():
		if (_cards[key] as NodeCard).visible:
			list.append(String(key))
	if list.is_empty():
		return
	# 1) 播种：容器（场景 / 书桌）按 5 列网格，实体围在画布中央撒开
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EED
	var ci := 0
	var first_place: Dictionary = {}
	for key in list:
		# 播种（可能写 n.x/n.y）之前先记录「这个节点还没落过位」—— x<0 = 新上画
		first_place[key] = float(graph.node(key).get("x", -1.0)) < 0.0
		var n := graph.node(key)
		if float(n.get("x", -1.0)) >= 0.0 and float(n.get("y", -1.0)) >= 0.0:
			ci += 1
			continue
		if graph.is_container_node(key):
			n["x"] = 200.0 + float(ci % 5) * 380.0
			n["y"] = 160.0 + float((ci / 5) as int) * 300.0
		else:
			n["x"] = 700.0 + (rng.randf() - 0.5) * 420.0
			n["y"] = 560.0 + (rng.randf() - 0.5) * 420.0
		ci += 1
	var pos := {}
	for key in list:
		var n := graph.node(key)
		pos[key] = Vector2(float(n.get("x", 0.0)), float(n.get("y", 0.0)))
	var free := {}
	for key in list:
		free[key] = not bool(graph.node(key).get("pinned", false))
	var radius := {}
	for key in list:
		var r := 68.0
		if graph.is_container_node(key):
			r = 80.0
		radius[key] = r

	for _it in 260:
		for i in list.size():
			var a: String = list[i]
			for j in range(i + 1, list.size()):
				var b: String = list[j]
				var pa: Vector2 = pos[a]
				var pb: Vector2 = pos[b]
				var delta: Vector2 = pb - pa
				var d2 := delta.length_squared()
				if d2 < 1.0:
					delta = Vector2(rng.randf() - 0.5, rng.randf() - 0.5)
					d2 = 1.0
				var d := sqrt(d2)
				var u := delta / d
				var rep := 30000.0 / d2
				if free[a]:
					pa -= u * rep
				if free[b]:
					pb += u * rep
				var min_d: float = float(radius[a]) + float(radius[b]) + 14.0
				if d < min_d:
					var push := (min_d - d) * 0.5
					if free[a]:
						pa -= u * push
					if free[b]:
						pb += u * push
				pos[a] = pa
				pos[b] = pb
		for e in graph.edges:
			var a := String(e.get("a", ""))
			var b := String(e.get("b", ""))
			if not pos.has(a) or not pos.has(b):
				continue
			var pa: Vector2 = pos[a]
			var pb: Vector2 = pos[b]
			var delta: Vector2 = pb - pa
			var d := delta.length()
			if d < 0.001:
				continue
			var u := delta / d
			var rest := 185.0
			if String(e.get("rel", "entity")) == "move":
				rest = 300.0
			elif String(e.get("rel", "entity")) == "cond":
				rest = 150.0
			var f := (d - rest) * 0.014
			if free[a]:
				pa += u * f
			if free[b]:
				pb -= u * f
			pos[a] = pa
			pos[b] = pb
		for key in list:
			if not free[key]:
				continue
			var p: Vector2 = pos[key]
			p += Vector2(WORLD_W * 0.5 - p.x, WORLD_H * 0.5 - p.y) * 0.0022
			pos[key] = p

	for key in list:
		var n := graph.node(key)
		var card: NodeCard = _cards[key]
		var p: Vector2 = pos[key]
		var fp: bool = bool(first_place.get(key, false))
		if not free[key]:
			n["x"] = p.x
			n["y"] = p.y
			continue
		## P2：自动摆卡落 8px 网格。边界也取 8 的倍数，保证靠边时仍对齐；
		## 手动拖动的落点由 `NodeCard._clamp_pos()` 同样吸到 8px 网格（C3）。
		p = Vector2(clampf(p.x, 64.0, WORLD_W - 224.0),
			clampf(p.y, 56.0, WORLD_H - 120.0))
		p = p.snapped(Vector2(8, 8))
		n["x"] = p.x
		n["y"] = p.y
		var before_pos: Vector2 = card.position   # 先记原位：set_home_silent 只改锚点不挪卡
		card.set_home_silent(p)
		# Web 的 .node 过渡 = `left/top 0.34s cubic-bezier(.4,0,.2,1)`：已有节点位置动了才播过渡；
		# 新上画的节点（Web 是 createElement 时直接定 left/top，初绘没有“从哪里来”）与
		# 截图流水线一律直接落位。动画期间连线逐帧跟画（Web paintEdgesFor(420) 同口径）；
		# 折叠 / 展开触发的那次重排才播动画（`_relayout(true)`），普通重排默认秒到——
		# 无头回归与坐标语义都建立在「重排=即刻就位」上，不能整体动。
		if fp or not animated or _shot_mode() or before_pos.distance_to(p) < 2.0:
			card.position = p
		else:
			_start_move_tween(key, card, p)


var _move_twens: Dictionary = {}      # key -> 卡片落位补间（下一次重排前先杀）
var _follow_frames := 0               # >0 时每帧重画连线（过渡期间连线跟着节点走）


func _start_move_tween(key: String, card: NodeCard, p: Vector2) -> void:
	_kill_move(key)
	var tw := card.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(card, "position", p, 0.34)
	tw.finished.connect(func() -> void:
		_move_twens.erase(key)
		card.position = p
		# 锚在它身上的浮层（回忆放映卡 / 叙事卡）跟着落地重锚，否则卡片停在节点半路的位置上
		if _mem_anchor_key == key and _mem_card != null and is_instance_valid(_mem_card):
			_anchor_card_to(_mem_card, key)
		_repaint_edges(), CONNECT_ONE_SHOT)
	_move_twens[key] = tw
	_follow_frames = maxi(_follow_frames, 21)   # ≈420ms @ 60fps（Web paintEdgesFor(420)）


func _kill_move(key: String) -> void:
	if _move_twens.has(key):
		(_move_twens[key] as Tween).kill()
		_move_twens.erase(key)


func _fit_cards() -> void:
	if _card_layer == null:
		return
	var bounds := Rect2()
	var has_card := false
	for c in _card_layer.get_children():
		var card := c as NodeCard
		if card == null or not card.visible:
			continue
		# 用数据里的最终位（过渡动画期间 card.position 还在路上，镜头该框的是终点）
		var n := graph.node(card.card_key)
		var at := Vector2(float(n.get("x", card.position.x)), float(n.get("y", card.position.y)))
		var r := Rect2(at + Vector2(NodeCard.PAD, NodeCard.PAD),
			card.size - Vector2(NodeCard.PAD * 2.0, NodeCard.PAD * 2.0))
		if has_card:
			bounds = bounds.merge(r)
		else:
			bounds = r
			has_card = true
	if not has_card or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		_view_k = 1.0
		_view_pos = Vector2.ZERO
		_card_layer.position = Vector2.ZERO
		_card_layer.scale = Vector2.ONE
		_view_user = false
		return
	## 按包围盒缩放（0.45~1.3）：节点多到一屏装不下时缩出去，才是「适应窗口」的本义。
	## 缩出来的非整数倍由 LOD 兜住 —— 读不清的倍率下副标与角标已经退场，不会留下糊字。
	var pad := 60.0
	var k := minf((_stage.size.x - pad * 2.0) / bounds.size.x,
		(_stage.size.y - pad * 2.0) / bounds.size.y)
	_view_k = clampf(k, ZOOM_MIN, FIT_MAX)
	var z := _zoom_override()
	if z > 0.0:
		_view_k = z
	_view_pos = (_stage.size - bounds.size * _view_k) * 0.5 - bounds.position * _view_k
	_view_user = false
	_apply_view()


# ── TEC ─────────────────────────────────────────────────────────────────

func _tec_key(target: String) -> String:
	if target.contains(":"):
		var parts := target.split(":", true, 1)
		if parts.size() == 2:
			return graph.key_of(parts[0], parts[1])
		return target
	return graph.scene_key(target)


func _open_tec() -> void:
	if not _require_case():
		return
	if _tec == null:
		return
	_tec.visible = true
	_place_z(_tec, ZR_TEC)
	_tec_min = false
	_tec_dot = false
	if _tec_chip != null:
		_tec_chip.visible = false


func _close_tec() -> void:
	if _tec == null:
		return
	_tec.visible = false
	_tec_min = false
	if _tec_chip != null:
		_tec_chip.visible = false


func _minimize_tec() -> void:
	if _tec == null or not _tec.visible:
		return
	_tec.visible = false
	_tec_min = true
	_sync_tec_chip()


func _hide_tec(reset: bool = false) -> void:
	if _tec == null:
		return
	_tec.cancel_analysis()
	_tec.visible = false
	if reset:
		_tec.reset_tec()
	_tec_min = false
	_tec_dot = false
	_tec_before = {}
	if _tec_chip != null:
		_tec_chip.visible = false


func _toggle_tec() -> void:
	if not _require_case():
		return
	if _tec.visible:
		_close_tec()
	else:
		_open_tec()


func _sync_tec_chip() -> void:
	if _tec_chip == null:
		return
	if not _tec_min:
		_tec_chip.visible = false
		return
	_tec_chip.visible = true
	_place_z(_tec_chip, ZR_DOCK)
	if _tec.is_analyzing():
		_tec_chip.set_analyzing(_tec.target_label(), _tec.progress())
	else:
		_tec_chip.set_idle(_tec_dot)


func _tec_drop_hit(at_global: Vector2) -> bool:
	if _tec_btn != null and _tec_btn.get_global_rect().has_point(at_global):
		return true
	if _tec.visible and _tec.avatar_global_rect().has_point(at_global):
		return true
	if _tec_chip != null and _tec_chip.visible and _tec_chip.get_global_rect().has_point(at_global):
		return true
	return false


func _start_tec_analysis(key: String) -> bool:
	if not _require_case() or _tec == null:
		return false
	key = _tec_key(key)
	var n := graph.node(key)
	if n.is_empty():
		return false
	if _tec.is_analyzing():
		if _tutorial_active:
			_tutorial_say("让我先看完这个。")
		else:
			_show_toast("TEC 正在分析中，请稍候…", true)
		return false
	if _tutorial_active and not _tutorial_tec_guard(key):
		return false
	if String(n["kind"]) == "clue":
		_show_toast("线索节点不需要再让 TEC 分析", true)
		return false
	if not _tec.visible and not _tec_min:
		_open_tec()
	return _tec.analyze(key, String(n.get("label", key)))


func _on_tec_analysis_started(_target: String, _label: String) -> void:
	_tec_before = _save.snapshot() if _save != null else {}
	_tec_dot = false
	if _tec_min:
		_sync_tec_chip()


func _on_tec_analysis_progress(ratio: float) -> void:
	if _tec_min and _tec_chip != null:
		_tec_chip.set_analyzing(_tec.target_label(), ratio)


func _capture_text_clues(text: String, from_key: String = "") -> Array:
	var got: Array = []
	for tag in case_def.tags_of(text):
		if tag["kind"] != "clue":
			continue
		var cid := String(tag["id"])
		if graph.captured.has(cid):
			continue
		got.append(graph.capture_clue(cid, from_key))
	return got


func _refresh_clue_keys(keys: Array) -> void:
	if keys.is_empty():
		return
	for key in keys:
		_refresh_or_spawn_card(String(key))
	_relayout()


func _hidden_clue_of(kind: String, id: String) -> HiddenClueDef:
	match kind:
		"loc", "time":
			var s := case_def.scene_of(id)
			return s.hidden_clue if s != null else null
		"item":
			var it := case_def.item_of(id)
			return it.hidden_clue if it != null else null
		"char":
			var ch := case_def.char_of(id)
			return ch.hidden_clue if ch != null else null
	return null


func _capture_node_hidden_clues(kind: String, id: String, host_key: String) -> Dictionary:
	var hc := _hidden_clue_of(kind, id)
	if hc == null:
		return {"keys": [], "names": [], "text": ""}
	var got: Array = []
	var names: Array = []
	var seen := {}
	for clue in hc.clues:
		if clue == null or graph.captured.has(clue.id) or seen.has(clue.id):
			continue
		seen[clue.id] = true
		got.append(graph.capture_clue(clue.id, host_key))
		names.append(clue.label)
	for tag in case_def.tags_of(hc.text):
		var cid := String(tag["id"])
		if tag["kind"] != "clue" or graph.captured.has(cid) or seen.has(cid):
			continue
		seen[cid] = true
		got.append(graph.capture_clue(cid, host_key))
		names.append(case_def.label_of("clue", cid))
	_refresh_clue_keys(got)
	return {"keys": got, "names": names, "text": case_def.strip_tags(hc.text)}


## TEC 解读完成后捕获 hiddenClue（场景 / 物品同一套字段；当前先接场景分析链路）
func _capture_hidden_clue(scene_id: String) -> void:
	var kind := graph.normalize_kind("loc", scene_id)
	var host := graph.key_of(kind, scene_id)
	var res := _capture_node_hidden_clues(kind, scene_id, host)
	if res["keys"].is_empty():
		return
	_show_toast("捕获线索：" + "、".join(res["names"]))


func _tec_talk_lines(sid: String) -> Array:
	var tec := case_def.char_of("CHARS_TEC")
	if tec == null:
		return []
	for st in tec.scene_talks:
		if st != null and st.scene != null and st.scene.id == sid:
			return st.lines
	return []


func _tec_reaction(key: String) -> bool:
	var n := graph.node(key)
	if n.is_empty() or _tec == null:
		return false
	var tec := case_def.char_of("CHARS_TEC")
	if tec == null:
		return false
	var id := String(n["id"])
	var raw := ""
	for r in tec.item_reactions:
		if r != null and ((r.item != null and r.item.id == id) or r.trigger_id == id):
			raw = r.text
			break
	if raw == "":
		for r in tec.clue_reactions:
			if r != null and ((r.clue != null and r.clue.id == id) or r.trigger_id == id):
				raw = r.text
				break
	if raw == "":
		_tec.append_line("关于「%s」，我暂时没有更多线索。试试把它和别的节点组合。" % String(n["label"]))
		_log("TEC 对「%s」没有特别的反应" % String(n["label"]), "warn")
		graph.tried[key + ">tec-dock"] = true
		return false
	_tec.append_line("（分析 %s）%s" % [String(n["label"]), case_def.strip_tags(raw)])
	var got := _capture_text_clues(raw)
	_refresh_clue_keys(got)
	return true


func _tec_talk() -> void:
	if not _require_case() or _tec == null:
		return
	if not _tec.visible:
		_open_tec()
	if _tutorial_active:
		_tutorial_say(_tutorial_talk_line())
		return
	var tec := case_def.char_of("CHARS_TEC")
	var queue: Array = tec.talk_queue if tec != null else []
	if queue.is_empty():
		_tec.append_line("（把节点拖到我身上，我来分析）", TecTheme.MUTED)
		return
	var idx := int(graph.tec_prog.get("_def", 0))
	if idx >= queue.size():
		return
	graph.tec_prog["_def"] = idx + 1
	_tec.append_line(case_def.strip_tags(String(queue[idx])))
	_autosave()


func _on_tec_analysis_done(target: String) -> void:
	var key := _tec_key(target)
	if _tutorial_active and _tutorial_on_tec_done(key):
		_tec_before = {}
		return
	var n := graph.node(key)
	if n.is_empty():
		_tec_before = {}
		return
	var kind := String(n["kind"])
	var id := String(n["id"])
	var label := String(n.get("label", id))
	if GraphState.is_scene_kind(kind):
		var talks := _tec_talk_lines(id)
		var prog := int(graph.tec_prog.get(id, 0))
		var unread := talks.size() - prog
		var hidden := _capture_node_hidden_clues(kind, id, key)
		if not (hidden["keys"] as Array).is_empty():
			_tec.append_line("分析完成：「%s」中提取到线索 —— %s。（已落到画布上，可自由拖动）"
				% [label, "、".join(hidden["names"])])
			if String(hidden["text"]) != "":
				_tec.append_line(String(hidden["text"]))
			_log("TEC 捕获「%s」的隐藏线索：%s" % [label, "、".join(hidden["names"])], "cap")
			_show_toast("捕获线索：" + "、".join(hidden["names"]))
		elif unread <= 0:
			_tec.append_line("分析完成：「%s」中没有可以捕获的线索。" % label)
			_log("TEC 分析「%s」：无可捕获线索" % label, "warn")
		if not talks.is_empty() and unread > 0:
			var line := String(talks[prog])
			graph.tec_prog[id] = prog + 1
			_tec.append_line(case_def.strip_tags(line))
			_refresh_clue_keys(_capture_text_clues(line))
			_log("TEC 解读了「%s」的档案（%d/%d）" % [label, prog + 1, talks.size()], "sys")
		elif not talks.is_empty():
			_tec.append_line("「%s」的档案已经全部解读完毕。" % label)
	else:
		_tec_reaction(key)
		var ent_hidden := _capture_node_hidden_clues(kind, id, key)
		if not (ent_hidden["keys"] as Array).is_empty():
			_tec.append_line("分析完成：「%s」中提取到线索 —— %s。（已落到画布上，可自由拖动）"
				% [label, "、".join(ent_hidden["names"])])
			if String(ent_hidden["text"]) != "":
				_tec.append_line(String(ent_hidden["text"]))
			_log("TEC 捕获「%s」的隐藏线索：%s" % [label, "、".join(ent_hidden["names"])], "cap")
			_show_toast("捕获线索：" + "、".join(ent_hidden["names"]))
	if _tec_min:
		_tec_dot = true
		_sync_tec_chip()
	_commit(_tec_before)
	_tec_before = {}


# ── 测试钩子（与 Web 版 window.__* 同名，便于把操作脚本逐行翻译）──────────

func dbg_state() -> Dictionary:
	return {
		"nodes": _cards.keys(),
		"explored": graph.explored.keys(),
		"captured": graph.captured.keys(),
		"tec_prog": graph.tec_prog.duplicate(),
		"lit": _lit_map(),
		"selected": _selected,
		"cards": _cards.size(),
		"collapsed": graph.collapsed.keys(),
		"stored": graph.stored.keys(),
		"hidden": graph.hidden.keys(),
		"installed": _installed_map(),
		"matrix": graph.matrix.duplicate(true),
		"matrix_ids": graph.matrix_ids(),
		"endings": graph.endings.keys(),
		"ending_visible": _ending.visible if _ending != null else false,
		"ending_id": _last_ending_id,
		"can_undo": _save.can_undo() if _save != null else false,
		"history": _save.history.size() if _save != null else 0,
	}


func _installed_map() -> Dictionary:
	var out := {}
	for k in graph.nodes.keys():
		var n: Dictionary = graph.nodes[k]
		if n["kind"] == "item" and not (n.get("installed", {}) as Dictionary).is_empty():
			out[k] = (n["installed"] as Dictionary).keys()
	return out


func _lit_map() -> Dictionary:
	var out := {}
	for k in graph.nodes.keys():
		var n: Dictionary = graph.nodes[k]
		if n["kind"] == "item":
			out[String(n["id"])] = bool(n.get("lit", false))
	return out


func dbg_expand(sid: String) -> void:
	_expand_scene(sid, false)


func dbg_combo(tool_id: String, target_id: String) -> Dictionary:
	var tkind := CaseLoader.kind_of_ref(tool_id)
	var okind := CaseLoader.kind_of_ref(target_id)
	return combos.use_item(graph.key_of(tkind, tool_id), graph.key_of(okind, target_id))


## 双击某张卡（跑第一条命令 / 展开容器，与真实双击同一条路）
func dbg_activate(key: String) -> void:
	_on_card_activated(key)


## 建节点并上卡片（等价 Web 的 __ensure）
func dbg_ensure(kind: String, id: String) -> String:
	var n := graph.add_node(kind, id)
	_spawn_card(String(n["key"]))
	_relayout()
	return String(n["key"])


func dbg_pw_open(node_key: String) -> void:
	_open_password(node_key)


func dbg_password(node_key: String, value: String) -> void:
	# 已经为这个节点开着窗就直接提交（模拟「在同一个弹窗里改输入再点确定」）
	if _pw_pop == null or not is_instance_valid(_pw_pop) or String(_pw_ctx.get("node_key", "")) != node_key:
		_open_password(node_key)
	_submit_password(value)


func dbg_toggle_light(id: String) -> Dictionary:
	return combos.toggle_light(graph.key_of("item", id))


## 选中某个节点（等价点一下卡）
func dbg_select(key: String) -> void:
	_selected = key
	graph.selected = key


## 打开某个收纳窗
func dbg_open_storage(kind: String) -> void:
	_toggle_storage(kind)


func dbg_tec_analyze(sid: String) -> void:
	_start_tec_analysis(_tec_key(sid))


func dbg_tec_finish() -> int:
	return _tec.done_count() if _tec != null else 0


func dbg_tec_complete() -> void:
	if _tec != null:
		_tec.finish_now()


func dbg_tec_open() -> void:
	_open_tec()


func dbg_tec_close() -> void:
	_close_tec()


func dbg_tec_minimize() -> void:
	_minimize_tec()


func dbg_tec_win() -> TecWindow:
	return _tec


func dbg_tec_chip() -> TecChip:
	return _tec_chip


func dbg_tec_talk() -> void:
	_tec_talk()


func dbg_tec_analyze_key(key: String) -> bool:
	return _start_tec_analysis(key)


func dbg_tec_drop_hit(at_global: Vector2) -> bool:
	return _tec_drop_hit(at_global)


func dbg_tec_drop(key: String, at_global: Vector2) -> void:
	_on_card_drag_released(key, at_global)


func dbg_tec_icon_rect() -> Rect2:
	return _tec_btn.get_global_rect() if _tec_btn != null else Rect2()


func dbg_tec_info() -> Dictionary:
	var win := {}
	if _tec != null:
		win = _tec.dbg_status()
	var chip := {}
	if _tec_chip != null:
		chip = _tec_chip.dbg_state()
	return {
		"visible": _tec.visible if _tec != null else false,
		"min": _tec_min,
		"dot": _tec_dot,
		"chip_visible": _tec_chip.visible if _tec_chip != null else false,
		"win": win,
		"chip": chip,
	}


# ── 档案 / 放映卡测试钩子（P2.3）──────────────────────────────────────

func dbg_open_archive() -> ArchiveWin:
	if _archive_win == null or not is_instance_valid(_archive_win):
		_toggle_archive()
	return _archive_win


func dbg_archive_press(tid: String) -> bool:
	if _archive_win == null or not is_instance_valid(_archive_win):
		return false
	return _archive_win.press_time(tid)


func dbg_archive_new() -> bool:
	return _archive_new


# ── 多人对话 / 独白测试钩子（P2.4）────────────────────────────────────

func dbg_chat() -> ChatWindow:
	if _chat_win != null and is_instance_valid(_chat_win):
		return _chat_win
	return null


func dbg_chat_state() -> Dictionary:
	var chat := dbg_chat()
	if chat == null:
		return {"open": false, "id": "", "participants": [], "joined": [], "idx": 0,
			"total": 0, "waitingFor": "", "typing": false, "done": false, "lines": 0}
	return chat.state()


func dbg_chat_advance() -> bool:
	var chat := dbg_chat()
	return chat.advance() if chat != null else false


func dbg_chat_finish() -> void:
	var chat := dbg_chat()
	if chat != null:
		chat.finish_line()


func dbg_chat_drop(kind: String, id: String) -> bool:
	var chat := dbg_chat()
	return chat.drop_node(kind, id) if chat != null else false


func dbg_chat_drop_key(key: String) -> bool:
	return _chat_drop(key)


func dbg_chat_hint() -> String:
	var chat := dbg_chat()
	return chat.hint_text() if chat != null else ""


func dbg_chat_title() -> String:
	var chat := dbg_chat()
	return chat.title if chat != null else ""


func dbg_chat_rect() -> Rect2:
	var chat := dbg_chat()
	return chat.get_global_rect() if chat != null else Rect2()


func dbg_chat_close() -> void:
	_close_chat()


func dbg_open_dialogue(id: String, ids: Array) -> bool:
	if dialogues == null:
		return false
	return _open_chat(dialogues.by_id(id), ids)


func dbg_open_monologue(char_id: String) -> bool:
	return _open_monologue(char_id)


func dbg_dialogues() -> DialogueSystem:
	return dialogues


func dbg_time() -> String:
	return graph.time if graph != null else ""


func dbg_time_label() -> String:
	return graph.time_label_of() if graph != null else ""


func dbg_time_known() -> Array:
	return graph.timeline_known() if graph != null else []


func dbg_set_time(tid: String) -> bool:
	return _select_time(tid)


func dbg_mem_card() -> MemCard:
	return _mem_card


func dbg_mem_advance() -> bool:
	return _mem_card.advance() if _mem_card != null and is_instance_valid(_mem_card) else false


func dbg_close_mem() -> void:
	_close_mem_card()


func dbg_card_visible(key: String) -> bool:
	var card: NodeCard = _cards.get(key, null)
	return card != null and card.visible


func dbg_card_pos(key: String) -> Vector2:
	var card: NodeCard = _cards.get(key, null)
	return card.position if card != null else Vector2.ZERO


func dbg_mem_pos() -> Vector2:
	return _mem_card.position if _mem_card != null and is_instance_valid(_mem_card) else Vector2.ZERO


## 屏幕坐标里的视觉矩形 —— 画布有缩放 / 平移之后，「谁压住谁」只能在同一个空间里比，
## 拿 world 坐标去和桌面坐标比必然误判（2026-10-21 世界层上线的副产物）。
func dbg_card_global(key: String) -> Rect2:
	var card: NodeCard = _cards.get(key, null)
	if card == null or not is_instance_valid(card) or not card.visible:
		return Rect2()
	return card.get_global_rect()


func dbg_mem_global() -> Rect2:
	if _mem_card == null or not is_instance_valid(_mem_card):
		return Rect2()
	return _mem_card.get_global_rect()


func dbg_combo_ui(tool_id: String, target_id: String) -> void:
	if graph == null:
		return
	_on_card_combo(_dbg_node_key(tool_id), _dbg_node_key(target_id))


func _dbg_node_key(id: String) -> String:
	for key in graph.nodes.keys():
		var n := graph.node(String(key))
		if String(n.get("id", "")) == id and String(n.get("kind", "")) != "time":
			return String(key)
	return graph.key_of(CaseLoader.kind_of_ref(id), id)


func dbg_toast_text() -> String:
	return _toast_label.text if _toast_label != null else ""


# ── 人物名册 / 因果追踪 / 图标栏测试钩子（批 1）────────────────────────────

func dbg_open_people() -> PeopleWin:
	if _people_win == null or not is_instance_valid(_people_win):
		_toggle_people()
	return _people_win


func dbg_people_win() -> PeopleWin:
	return _people_win if _people_win != null and is_instance_valid(_people_win) else null


func dbg_close_people() -> void:
	if _people_win != null and is_instance_valid(_people_win):
		_people_win.queue_free()
	_people_win = null


func dbg_people_row(id: String) -> void:
	_on_people_row(id)


func dbg_open_log() -> LogWin:
	if _log_win == null or not is_instance_valid(_log_win):
		_toggle_log()
	return _log_win


func dbg_log_win() -> LogWin:
	return _log_win if _log_win != null and is_instance_valid(_log_win) else null


func dbg_close_log() -> void:
	if _log_win != null and is_instance_valid(_log_win):
		_log_win.queue_free()
	_log_win = null


func dbg_log_kinds() -> Array:
	return graph.logs.map(func(e): return String((e as Dictionary).get("kind", "")))


func dbg_log_texts() -> Array:
	return graph.logs.map(func(e): return String((e as Dictionary).get("text", "")))


func dbg_add_log(text: String, kind: String = "") -> void:
	_log(text, kind)


## 图标栏：位置 / 顺序 / 角标文字（都是玩家可见的状态，不碰内部缓存）
func dbg_icon_pos(app: String) -> Vector2:
	var b := _icon_by_app(app)
	return b.position if b != null else Vector2(-1, -1)


func dbg_icon_visible(app: String) -> bool:
	var b := _icon_by_app(app)
	return b != null and b.visible


## 图标栏（只列当前可见的 —— 播放器 / 花园解锁前不算占位）
func dbg_icon_apps() -> Array:
	var out: Array = []
	for c in _icon_layer().get_children():
		if c is DeskIcon and (c as DeskIcon).visible:
			out.append(String(c.name).trim_prefix("icon_"))
	return out


## 模拟一次图标拖动（不吃输入事件，直接走同一段位移逻辑）
func dbg_drag_icon(app: String, at: Vector2) -> void:
	var b := _icon_by_app(app)
	if b != null:
		b.position = Vector2(clampf(at.x, 0.0, _desk.size.x - b.size.x),
			clampf(at.y, 0.0, _desk.size.y - b.size.y))


func dbg_badge_text(app: String) -> String:
	var pair := {"infer": _infer_badge, "bag": _bag_badge, "clue": _clue_badge,
		"log": _log_badge, "garden": _garden_badge}
	var badge: PanelContainer = pair.get(app, null)
	if badge == null or not is_instance_valid(badge) or not badge.visible:
		return ""
	var lab: Label = badge.get_node_or_null("Label")
	return lab.text if lab != null else ""


func dbg_log_unread() -> int:
	return _log_unread


## 模拟双击图标（两次点击必须落在 300ms 判决窗内，见 _on_icon_pressed）
func dbg_double_click_icon(app: String) -> void:
	var b := _icon_by_app(app)
	if b == null:
		return
	_on_icon_pressed(app, b)
	_on_icon_pressed(app, b)


# ── 推演桌布测试钩子（P1.4）────────────────────────────────────────────

func dbg_open_matrix() -> MatrixWin:
	if _matrix_win == null or not is_instance_valid(_matrix_win):
		_toggle_matrix()
	return _matrix_win


func dbg_matrix_assign(key: String) -> bool:
	return _assign_to_matrix(key)


func dbg_matrix_win() -> MatrixWin:
	return _matrix_win if _matrix_win != null and is_instance_valid(_matrix_win) else null


func dbg_matrix_charge() -> void:
	if _matrix_win != null and is_instance_valid(_matrix_win):
		_matrix_win.finish_charge()


func dbg_matrix_take(key: String) -> void:
	_on_matrix_took(key)


func dbg_ending() -> EndingOverlay:
	return _ending


func dbg_ending_id() -> String:
	return _last_ending_id


func dbg_ending_finish() -> void:
	if _ending != null:
		_ending.finish_now()


func dbg_confirm_ending() -> void:
	if _ending == null or not _ending.visible:
		return
	_ending.visible = false
	_ending.finished.emit()


# ── 音乐播放器 / 花园测试钩子（P2.5）──────────────────────────────────

func dbg_music_icon_visible() -> bool:
	return _music_btn != null and _music_btn.visible


func dbg_garden_icon_visible() -> bool:
	return _garden_btn != null and _garden_btn.visible


func dbg_garden_badge_text() -> String:
	if _garden_badge == null or not _garden_badge.visible:
		return ""
	var l: Label = _garden_badge.get_node_or_null("Label")
	return l.text if l != null else ""


func dbg_music_win() -> MusicWin:
	return _music_win if _music_win != null and is_instance_valid(_music_win) else null


func dbg_music_dock() -> MusicDock:
	return _music_dock if _music_dock != null and is_instance_valid(_music_dock) else null


func dbg_click_music_icon() -> void:
	_toggle_music_win()


func dbg_open_music() -> MusicWin:
	_open_music()
	return dbg_music_win()


func dbg_minimize_music() -> void:
	_minimize_music()


func dbg_restore_music() -> void:
	_restore_music()


func dbg_close_music() -> void:
	_on_music_closed()


func dbg_music_play(id: String) -> bool:
	var w := dbg_music_win()
	if w == null:
		w = dbg_open_music()
	return w.play_track(id) if w != null else false


func dbg_music_toggle() -> bool:
	return _music_win.toggle_current() if dbg_music_win() != null else false


func dbg_music_stop() -> void:
	_stop_music()


func dbg_music_state() -> Dictionary:
	var w := dbg_music_win()
	if w == null:
		return {}
	var s := w.state()
	s["win_visible"] = w.visible
	s["dock_visible"] = _music_dock != null and is_instance_valid(_music_dock) and _music_dock.visible
	return s


func dbg_garden_win() -> GardenWin:
	return _garden_win if _garden_win != null and is_instance_valid(_garden_win) else null


func dbg_open_garden() -> GardenWin:
	if _garden_win == null or not is_instance_valid(_garden_win):
		_open_garden()
	return dbg_garden_win()


func dbg_close_garden() -> void:
	if _garden_win != null and is_instance_valid(_garden_win):
		_garden_win.queue_free()
	_garden_win = null


func dbg_garden_state() -> Dictionary:
	var w := dbg_garden_win()
	if w != null:
		return w.dbg_state()
	return {}


func dbg_garden_icon_rect() -> Rect2:
	return _garden_btn.get_global_rect() if _garden_btn != null else Rect2()


func dbg_drop_seed(at_global: Vector2) -> bool:
	return _drop_seed(at_global)


func dbg_play_true_ending() -> void:
	if _ending == null:
		return
	_last_ending_id = "TRUE_E"
	_ending.play(case_def.ending_by_id("TRUE_E"))


func dbg_touch_garden_plot(idx: int, at_ms: int) -> bool:
	if graph == null or not (graph.garden is Dictionary):
		return false
	var plots: Array = graph.garden.get("plots", [])
	if idx < 0 or idx >= plots.size():
		return false
	plots[idx]["at"] = at_ms
	plots[idx]["hit"] = false
	if _garden_win != null and is_instance_valid(_garden_win):
		_garden_win.refresh()
	return true


# ── 案件系统测试钩子（P2.1）────────────────────────────────────────────

func dbg_use_temp_progress(path: String) -> void:
	_progress_path = path
	_progress_read_only = false
	_catalog.clear_progress(path)
	_catalog = CaseCatalog.new(path)
	_update_case_park_ui()


func dbg_case_info() -> Dictionary:
	return {
		"id": _active_case,
		"open": _case_open,
		"held": _case_held,
		"dock": _case_docked,
		"dock_visible": _dock_card != null and _dock_card.visible,
		"badge_visible": _map_badge != null and _map_badge.visible,
		"map_open": _map_win != null and is_instance_valid(_map_win),
		"title": _case_win.title if _case_win != null else "",
		"unlocked": _catalog.unlocked.duplicate(),
		"completed": _catalog.completed.duplicate(),
		"last": _catalog.last,
		"progress_path": _progress_path,
	}


func dbg_park_case(where: String) -> bool:
	return _park_case(where)


func dbg_reopen_case() -> void:
	_reopen_case()


func dbg_open_case_map() -> CaseMapWin:
	if _map_win == null or not is_instance_valid(_map_win):
		_toggle_case_map()
	return _map_win


func dbg_case_map_win() -> CaseMapWin:
	return _map_win if _map_win != null and is_instance_valid(_map_win) else null


func dbg_case_map_click(id: String) -> bool:
	var w := dbg_case_map_win()
	return w.dbg_click(id) if w != null else false


func dbg_case_map_state(id: String) -> String:
	var w := dbg_case_map_win()
	return w.dbg_row_state(id) if w != null else ""


func dbg_enter_case(id: String) -> bool:
	return _enter_case(id)


func dbg_catalog_unlock(id: String) -> bool:
	var ok := _catalog.unlock(id)
	_update_case_park_ui()
	return ok


func dbg_catalog() -> CaseCatalog:
	return _catalog


func dbg_catalog_unlock_next(id: String) -> bool:
	var ok := _catalog.unlock_next(id)
	_update_case_park_ui()
	return ok


# ── 调查员测试钩子（P1.6）──────────────────────────────────────────────

func dbg_use_temp_investigator(path: String) -> void:
	_inv_path = path
	_investigator = Investigator.load_from(path)
	_refresh_chip()


func dbg_clear_investigator() -> void:
	Investigator.clear(_inv_path)
	_investigator = {}
	_refresh_chip()


func dbg_investigator() -> Dictionary:
	return _investigator.duplicate(true)


func dbg_open_intro() -> IntroWin:
	return _open_intro()


func dbg_intro_open() -> bool:
	return _intro != null and is_instance_valid(_intro)


func dbg_open_cert() -> void:
	_open_cert_review()


func dbg_cert_open() -> bool:
	return _cert_win != null and is_instance_valid(_cert_win)


# ── 截图采样（P0 视觉自查：跑一遍切片，按阶段存 PNG 到 docs/）──────────

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[shot] ", path, " ", img.get_width(), "x", img.get_height())


func _shot_flow() -> void:
	await _wait(0.6)
	await _shot("res://docs/p0_1_desktop.png")

	_expand_scene("SCENES_garden", true)
	await _wait(0.5)
	await _shot("res://docs/p0_2_garden.png")

	# 开局不再直接给手电筒（对齐 Web）：截图流程走真实链路 书桌 → 抽屉 → 左侧抽屉
	_on_card_activated("item:ITEM_shuzhuo")
	await _wait(0.25)
	_on_card_activated("item:ITEM_chouti")
	await _wait(0.25)
	_on_card_activated("loc:SCENES_choutiyi")
	await _wait(0.25)

	combos.toggle_light("item:ITEM_shoudiantong")
	if _cards.has("item:ITEM_shoudiantong"):
		_cards["item:ITEM_shoudiantong"].refresh()
		_sync_card_shell(_cards["item:ITEM_shoudiantong"])
	_on_card_combo("item:ITEM_shoudiantong", "item:ITEM_something")
	await _wait(0.5)
	await _shot("res://docs/p0_3_body.png")

	_toggle_tec()
	_start_tec_analysis("loc:SCENES_body")
	await _wait(1.1)                      # 分析进行中（真实 5–8 秒，这里取中段）
	await _shot("res://docs/p0_4_tec.png")
	_tec.finish_now()
	await _wait(0.25)
	# P1.4 起 TEC 分析不再直接触发结局：这里仍按 P0 基线直接放 TRUE_E，只为保留对拍图
	_ending.play(case_def.ending_by_id("TRUE_E"))
	await _wait(0.25)
	await _shot("res://docs/p0_5_ending.png")
	_ending.finish_now()
	await _wait(0.25)
	await _shot("res://docs/p0_6_ending_full.png")

	# ── P1 新特性：容器展开 / 选项节点 / 密码弹窗 / 折叠 ──
	_ending.visible = false
	_start_slice()
	await _wait(0.3)
	_expand_scene("SCENES_garden", false)
	await _wait(0.2)
	_ensure_card("item", "ITEM_shuzhuo")
	_toggle_container("item", "ITEM_shuzhuo")
	await _wait(0.35)
	await _shot("res://docs/p1_1_container.png")

	_toggle_container("item", "ITEM_chouti")    # choice：两个抽屉一起上画布
	await _wait(0.35)
	await _shot("res://docs/p1_2_choice.png")

	_ensure_card("item", "ITEMS_jzmh")
	_open_password(graph.key_of("item", "ITEMS_jzmh"))
	await _wait(0.35)
	await _shot("res://docs/p1_3_password.png")
	_submit_password("0321")
	await _wait(0.35)
	await _shot("res://docs/p1_4_unlocked.png")

	_toggle_container("item", "ITEM_shuzhuo")   # 再双击 = 收起
	await _wait(0.35)
	await _shot("res://docs/p1_5_collapsed.png")

	# ── 收纳三态（P1.2）：证物袋 / 线索册两扇窗 ──
	_start_slice()
	await _wait(0.3)
	_expand_scene("SCENES_garden", false)
	await _wait(0.2)
	_ensure_card("item", "ITEM_taideng")
	dbg_select("item:ITEM_taideng")
	dbg_store("BAG")
	_ensure_card("clue", "CLUES_nm")
	dbg_select("clue:CLUES_nm")
	dbg_store("LEDGER")
	_toggle_storage(GraphState.BAG)
	await _wait(0.35)
	await _shot("res://docs/p1_6_bag.png")

	_toggle_storage(GraphState.LEDGER)
	await _wait(0.35)
	await _shot("res://docs/p1_7_ledger.png")

	# ── 推演桌布（P1.4）：五感归位 → 长按 → 真名遮罩 ──
	var true_e := case_def.ending_by_id("TRUE_E")
	for clue in true_e.recipe:
		_ensure_card("clue", clue.id)
		_assign_to_matrix(graph.key_of("clue", clue.id))
	dbg_open_matrix()
	await _wait(0.4)
	await _shot("res://docs/p1_8_matrix.png")

	dbg_matrix_charge()
	await _wait(0.3)
	dbg_ending_finish()
	await _wait(0.3)
	await _shot("res://docs/p1_9_truename.png")
	quit_app()


func _shot_intro_flow() -> void:
	await _wait(0.4)
	_inv_path = "user://shot_investigator.json"
	Investigator.clear(_inv_path)
	_investigator = {}
	_refresh_chip()
	var w := _open_intro()
	await _wait(0.4)
	await _shot("res://docs/p1_10_intro_name.png")
	w.dbg_set_name("林雾")
	w.dbg_begin()
	await _wait(0.3)
	await _shot("res://docs/p1_11_intro_quiz.png")
	w.dbg_answer(0)
	w.dbg_answer(0)
	w.dbg_answer(2)
	await _wait(0.3)
	await _shot("res://docs/p1_12_intro_avatar.png")
	w.dbg_confirm_pick()
	await _wait(0.3)
	await _shot("res://docs/p1_13_intro_card.png")
	w.dbg_confirm()
	await _wait(0.5)
	await _shot("res://docs/p1_14_investigator.png")
	_open_cert_review()
	await _wait(0.3)
	await _shot("res://docs/p1_15_cert.png")
	Investigator.clear(_inv_path)
	quit_app()


func _shot_p2_flow() -> void:
	await _wait(0.5)
	_catalog.clear_progress(_progress_path)
	_catalog = CaseCatalog.new(_progress_path)
	_update_case_park_ui()

	# ── P4.2：桌面图标的按下态（只反白标签条，图标本体不垫底板）──
	# 必须**在流程开头**拍：跑到结尾时图标栏已经切紧凑模式、标签被收掉了。
	var pressed_icon := _icon_by_app("bag")
	if pressed_icon != null:
		pressed_icon.set_selected(true)
		_hide_toast()
		await _wait(0.3)
		await _shot("res://docs/p2_23_icon_press.png")
		pressed_icon.set_selected(false)

	dbg_open_case_map()
	await _wait(0.35)
	await _shot("res://docs/p2_1_case_map.png")
	if _map_win != null and is_instance_valid(_map_win):
		_map_win.queue_free()
	_map_win = null

	dbg_park_case("dock")
	await _wait(0.35)
	await _shot("res://docs/p2_2_case_dock.png")

	dbg_reopen_case()
	await _wait(0.25)
	dbg_park_case("icon")
	await _wait(0.35)
	await _shot("res://docs/p2_3_case_closed.png")

	dbg_catalog_unlock("A002")
	dbg_open_case_map()
	await _wait(0.35)
	await _shot("res://docs/p2_4_case_unlocked.png")
	if _map_win != null and is_instance_valid(_map_win):
		_map_win.queue_free()
	_map_win = null

	_reopen_case()
	_start_slice()
	await _wait(0.3)
	_expand_scene("SCENES_body", false)
	_open_tec()
	_tec_talk()
	_tec_talk()
	_tec.finish_typing()
	_hide_toast()
	await _wait(0.35)
	await _shot("res://docs/p2_5_tec_chat.png")

	_start_tec_analysis("loc:SCENES_body")
	await _wait(2.5)
	await _shot("res://docs/p2_6_tec_analysis.png")

	_minimize_tec()
	await _wait(0.35)
	await _shot("res://docs/p2_7_tec_chip.png")

	_tec.finish_now()
	await _wait(0.3)
	_hide_toast()
	await _wait(0.2)
	await _shot("res://docs/p2_8_tec_chip_done.png")

	_open_tec()
	await _wait(0.35)
	await _shot("res://docs/p2_9_tec_archive.png")

	_hide_tec()
	_expand_scene("SCENES_fkjl", false)
	await _wait(0.35)
	_toggle_archive()
	await _wait(0.35)
	await _shot("res://docs/p2_10_archive.png")
	_toggle_archive()
	await _wait(0.15)

	_expand_scene("SCENES_lhsdst", false)
	await _wait(0.2)
	_select_time("SCENES_0602")
	await _wait(0.5)
	_show_mem_lines(3)
	await _wait(0.3)
	await _shot("res://docs/p2_11_memory_card.png")

	_close_mem_card()
	_on_card_combo("char:NPC_FB", "loc:SCENES_garden")
	await _wait(0.3)
	_show_mem_lines(4)
	await _wait(0.35)
	await _shot("res://docs/p2_12_memory_play.png")

	_close_mem_card()
	_select_time("SCENES_0704")
	await _wait(0.5)
	_close_mem_card()
	_hide_toast()
	_on_card_combo("char:CHARS_zs", "char:CHARS_luhengs")
	await _wait(0.35)
	_show_chat_lines(5)
	_hide_toast()
	await _wait(0.35)
	await _shot("res://docs/p2_13_dialogue.png")
	_close_chat()

	var garden := dialogues.by_id("DLG_garden_review") if dialogues != null else null
	_open_chat(garden, ["CHARS_zs", "NPC_FB"])
	await _wait(0.3)
	_chat_win.finish_line()
	_chat_win.advance()
	_chat_win.finish_line()
	_chat_win.advance()
	_hide_toast()
	await _wait(0.35)
	await _shot("res://docs/p2_14_dialogue_join.png")
	_close_chat()

	_open_monologue("CHARS_luhengs")
	await _wait(0.3)
	_show_chat_lines(4)
	_hide_toast()
	await _wait(0.35)
	await _shot("res://docs/p2_15_monologue.png")
	_close_chat()

	# ── P2.5 音乐播放器 / 花园彩蛋 ──
	_ensure_card("item", "ITEMS_changji")
	_ensure_card("item", "ITEMS_cz")
	dbg_combo_ui("ITEMS_cz", "ITEMS_changji")
	_hide_toast()
	var music := dbg_open_music()
	if music != null:
		music.play_track("Air_Bach")
		await _wait(0.2)
		music.seek_ratio(0.25)
	await _wait(0.8)
	await _shot("res://docs/p2_16_music.png")
	_minimize_music()
	await _wait(0.45)
	await _shot("res://docs/p2_17_music_dock.png")
	_restore_music()
	_stop_music()
	_on_music_closed()

	dbg_play_true_ending()
	dbg_confirm_ending()
	await _wait(0.25)
	dbg_open_matrix()
	_hide_toast()
	await _wait(0.4)
	await _shot("res://docs/p2_18_matrix_seed.png")
	if _matrix_win != null and is_instance_valid(_matrix_win):
		_matrix_win.queue_free()
	_matrix_win = null
	var gwin := dbg_open_garden()
	_hide_toast()
	await _wait(0.45)
	await _shot("res://docs/p2_19_garden_seed.png")
	if gwin != null:
		_drop_seed(gwin.field_global_rect().get_center())
		dbg_touch_garden_plot(0, GardenSystem.now_ms_now() - 181000)
		gwin._process(1.1)
		await _wait(0.2)
		gwin.dbg_open_narr(0)
		gwin.dbg_advance_narr()
		_hide_toast()
		await _wait(0.45)
		await _shot("res://docs/p2_20_garden_narr.png")

	# ── 批 1：人物名册 / 因果追踪 ──
	dbg_close_garden()
	await _wait(0.3)
	var people := dbg_open_people()
	_hide_toast()
	await _wait(0.45)
	await _shot("res://docs/p2_21_people.png")
	dbg_close_people()
	await _wait(0.25)
	dbg_open_log()
	_hide_toast()
	await _wait(0.45)
	await _shot("res://docs/p2_22_log.png")
	dbg_close_log()
	quit_app()


func _shot_p3_flow() -> void:
	await _wait(0.5)
	_new_runtime()
	## 与 Web 侧对拍脚本对齐：那边走完开场适性测试（姓名「陈调整」），页眉才有证章。
	## 证号写死成 TEC-GD-2160，两边的证章文字才逐字相同。
	_investigator = {"name": "陈调整", "id": "TEC-GD-2160", "sense": ["vision"], "avatarId": "CHARS_EXEC"}
	_refresh_chip()
	var loc := graph.add_node("loc", SLICE_SCENE)
	loc["x"] = 40.0
	loc["y"] = 30.0
	graph.mark_fresh(String(loc["key"]))
	_spawn_card(loc["key"])
	_relayout()
	_hide_toast()
	await _wait(0.5)
	await _shot("res://docs/p3/godot/start.png")
	quit_app()


func _show_chat_lines(n: int) -> void:
	if _chat_win == null or not is_instance_valid(_chat_win):
		return
	_chat_win.finish_line()
	for i in maxi(0, n - 1):
		if not _chat_win.advance():
			break
		_chat_win.finish_line()


func _show_mem_lines(n: int) -> void:
	if _mem_card == null or not is_instance_valid(_mem_card):
		return
	_mem_card.finish_line()
	for i in maxi(0, n - 1):
		if not _mem_card.advance():
			break
		_mem_card.finish_line()


func _ensure_card(kind: String, id: String) -> void:
	var n := graph.add_node(kind, id)
	_spawn_card(String(n["key"]))
	_relayout()


func quit_app() -> void:
	_autosave()
	if _shot_mode() and FileAccess.file_exists(_progress_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_progress_path))
	get_tree().quit()
