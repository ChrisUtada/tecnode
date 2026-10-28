class_name Desktop
extends Control
## 桌面外壳 + 画布 + P0 垂直切片链路
##
## 切片（计划 §三 P0）：花园展开 → 手电筒拖到黑影 → 尸体场景 → TEC 分析计时 → 结局演出。
## 数据直读 `data/case-a001.json`（P0 允许），逻辑全在 core/ 里，本文件只管「搭界面 + 接线」。

const HEADER_H := 52.0

## 窗口 / 浮层层级（与 Web z-index 对齐）。
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
## 常驻 8 项：顺序固定；证据在人物之前、日志在 TEC 之后。
const ICON_DEFS := [
	["推演", "infer", "star"],
	["档案", "goto", "archive"],
	["证据", "clue", "notebook"],
	["人物", "people", "users"],
	["物品", "bag", "briefcase"],
	["TEC", "tec", "tec"],
	["日志", "log", "clipboard-list"],
	["案件", "map", "map"],
]

const ZR_CASE := 1        # #case-win：永远在最底
const ZR_PW := 15         # .pw-pop：压过卡片、被诗行/叙事卡和其它窗口压住
const ZR_NARR := 16       # .narr-card / .bubble：回放叙事小卡
const ZR_LOG := 21        # .log-win
const ZR_DETAIL := 22     # .detail-win
const ZR_DOCK := 23       # #music-dock / #case-dock / #tec-chip
const ZR_PERSON := 27     # 人物档案卡：高于普通系统窗，低于 TEC / toast
const ZR_ICONS := 24      # #icons：窗开着会被任何系统窗盖住（11-dialog.js:501 注释）
const ZR_WIN := 25        # .bag/.clue/.cert/.map/.music/.goto/.infer/.garden/.people-win
const ZR_CHAT := 26       # .chat-win / .avatar-win
const ZR_TEC := 28        # .tec-win / .dlg-win
const ZR_DROP := 29       # 拖拽落点虚线框：压住 TEC / 窗口 / 图标
const ZR_TOAST := 30      # #toast / #verdict
const ZR_CERT := 32       # 教学期领证窗体：压住 TEC / 地图，必须填完
const ZR_MIRROR := 40     # #drag-layer：桌面最高层（批 3 的拖动镜像也用这档）
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
const LAYOUT_QUICK_ROUNDS := 8
const LAYOUT_FRAME_ROUNDS := 5
const StartScreenScript := preload("res://ui/StartScreen.gd")

## ── 开场教学（第 1–6 幕）───────────────────────────────────────────────────
## 第 2 幕只在教学迷你案件里跑，不碰 A-001 的存档与节点。数据在
## `cases/tutorial/case.tres`；正式案件在第 6 幕选择后再装载。
const TUTORIAL_CASE_PATH := "res://cases/tutorial/case.tres"
const TUT_OFFICE_ID := "SCENES_TEC_OFFICE"
const TUT_CERT_ITEM_ID := "ITEMS_investigator_cert"
const TUT_CERT_CLUE_ID := "CLUES_INVESTIGATOR_CERT"
const TUT_ENDING_ID := "TUT_CERT"
const CertWinScript := preload("res://scenes/windows/CertWin.gd")
const PhotoWinScript := preload("res://scenes/windows/PhotoWin.gd")
const ConfirmWinScript := preload("res://ui/ConfirmWin.gd")
const DropOutlineScript := preload("res://ui/DropOutline.gd")
const PersonCardScript := preload("res://scenes/windows/PersonCard.gd")
const TUT_OFFICE_KEY := "loc:" + TUT_OFFICE_ID
const TUT_CERT_ITEM_KEY := "item:" + TUT_CERT_ITEM_ID
const TUT_CERT_CLUE_KEY := "evidence:" + TUT_CERT_CLUE_ID
const TUT_CARD_X := 40.0
const TUT_CARD_STEP_X := 60.0
const TUT_CARD_STEP_Y := 80.0

enum TutorialStep {
	DOUBLE_CLICK_OFFICE, # ① 双击「TEC办公室」调出调查员证
	DRAG_CERT,         # ② 把「调查员证」拖给 TEC
	STORE_SUPPLIES,    # ③ 收纳可选提醒
	INFER,             # ④ 单线索「调查员证」+ 长按执行者
	CERT_FORM,         # ⑤ 填写调查员证
	CHOOSE_CASE,       # ⑥ 在案件里选 A-001
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
## G6：目标 / 计数两行共用这一块，实际宽度在 `_layout_header_left()` 里按右组左沿现算。
const HDR_GOAL_W := 610.0
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
## 测试 / 截图 API。仅在调试构建或 --shot 下存在；产品代码不得引用。
var debug = null
## 子系统控制器（批次 3 起逐步搬出）。只持宿主引用，不复制状态。
var garden_music = null
var people = null
var tec = null
var matrix = null
var tutorial = null
var session = null
var canvas = null
var drag = null
var launcher = null
var narrative = null
var card_ui = null
var windows = null
var chrome = null

var _desk: Control
var _head: Panel
var _ui_built := false
var _stage: Control
var _card_layer: Control
var _edge_layer: EdgeLayer
## 拖动时的幽灵连线提升层：画在桌布根、所有系统窗之上（画布内的边仍留在 stage）。
var _drag_line: EdgeLayer
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
## U1/W10：自动「适应窗口」只缩小不放大。1x 是点阵字唯一原生格倍率，
## 单卡开局顶到 1.3 会让玩家第一眼看到糊字。
const FIT_MAX := 1.0
## 自动 fit 的文字底线：0.95 = LOD_TITLE。自动构图只缩到这里，先保证卡片有完整标题；
## 想看全局总览时玩家仍可滚轮手动缩小，或点调试面板的「适应窗口」。
const FIT_TEXT_MIN := 0.95
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
var _goal: Label
var _brand_sub: Label
var _debug_btn: Button
var _undo_btn: Button
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
## 拖动中指针下的目标卡（卡片叠卡片时作为组合目标）
var _drag_over_card := ""
## 拖动镜像（Web #drag-layer）：拖起时在桌布根上占一份"假身"，松手销毁。
var _card_mirror: NodeCard = null
## 正在拖的节点 key（原卡被隐藏期间，连线照常以它为端点）
var _drag_key := ""
var _edges_dirty := false
## 收纳行拖拽会话（见 _process）
var _sdrag_key := ""
## 事件流鼠标状态（见 `_input`）：拖拽会话的可信坐标/按键来源
var _mouse_pos := Vector2.ZERO
var _mouse_left_down := false
var _sdrag_from := ""
var _sdrag_origin := Vector2.ZERO
var _sdrag_started := false
var _sdrag_ghost: PanelContainer = null
## 行拖拽小标签放在 CanvasLayer 上：直接用视口坐标跟随光标，不经过 desk / card_layer 变换。
var _sdrag_layer: CanvasLayer = null
var _sdrag_label := ""
## 桌面图标的单击/双击（双击才开窗）
var _icon_sel: DeskIcon = null
var _icon_last_app := ""
var _icon_last_ms := -100000
var _icon_layout_h := -1.0
var _cmds: CommandSystem
var _pw_pop: PasswordPop = null
var _pw_ctx: Dictionary = {}
## G11：按节点记连续错误次数；关掉弹窗重开不清零，输对才清。
var _pw_wrong: Dictionary = {}
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
## U2：叙事卡存在期间挂起的详情；关闭叙事或明确点节点切换后才显示。
var _pending_detail := false
var _detail_full_once := false
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
var _tutorial_step := TutorialStep.DOUBLE_CLICK_OFFICE
var _tutorial_office_key := ""
var _tutorial_apps_unlocked := false
var _tutorial_map_unlocked := false
var _tutorial_cert_win: SysWindow = null
var _tutorial_tec_placed := false
var _tutorial_tec_icon_visible := false
var _tutorial_map_arranged := false
var _photo_win: SysWindow = null
var _confirm_win: Control = null
var _drop_outline: DropOutline = null
## K11：节点右键上下文菜单。
var _card_ctx: PanelContainer = null
var _card_ctx_key := ""
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
var _dock_card: PanelContainer = null
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
## U7：案件卡片拖动状态 / 玩家是否亲手摆过（resize 不再吸回右下角）。
var _dock_down := false
var _dock_dragged := false
var _dock_press_global := Vector2.ZERO
var _dock_grab := Vector2.ZERO
var _dock_user_placed := false
var _normal_style: StyleBoxFlat = null
var _hover_style: StyleBoxFlat = null
## 批 1（差距报告 I1 / I2 / I3）：日志窗 + 人物名册 + 四个计数角标
var _people_win: PeopleWin = null
var _people_card = null
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
	chrome._layout_debug_panel()
	if _desk != null and is_instance_valid(_desk):
		_desk.position = Vector2(0, HEADER_H)
		_desk.size = Vector2(vw, vh - HEADER_H)
	if _drag_line != null and is_instance_valid(_drag_line):
		_drag_line.size = _desk.size
	windows._resize_case_window(vw, vh)
	if _detail_win != null and is_instance_valid(_detail_win):
		_detail_win.place_right(vw)
	if _desk.size.y != _icon_layout_h:
		_icon_layout_h = _desk.size.y
		## W7：窗口拉高只更新拖动边界并夹回图标，不能把玩家亲手摆的位置全部归位。
		launcher._sync_icon_bounds()
	_place_toast_anchor()
	garden_music._place_music_windows()
	session._place_case_dock()
	windows._place_floating_windows()
	people._place_person_card()
	windows._relayout_edge_windows(vw)
	windows._clamp_windows_to_desk()

## 窄窗口先收左半边：按右侧「撤销 / 调试」的真实左沿反推目标条可用宽度，
## 太窄时隐藏目标条与副题，并把证章挪到品牌后。
func _layout_header_left(vw: float) -> void:
	if _brand_sub == null or _inv_chip == null or _crumb == null:
		return
	if not is_instance_valid(_brand_sub) or not is_instance_valid(_inv_chip) \
			or not is_instance_valid(_crumb):
		return
	## A1 之后右侧只剩「撤销 / 调试」122px；按它们的真实左沿算，
	## 960 宽也能留下 290px 给目标条，不必再拿旧工具组的 670 做保守值。
	var right_left := vw - (DESIGN_W - HDR_X_UNDO)
	var strip_w := right_left - HDR_X_CRUMB - 12.0
	var show_strip := strip_w >= 180.0 and not _tutorial_active
	var show_sub := right_left >= HDR_X_CHIP + HDR_W_CHIP + 12.0 and not _tutorial_active
	_goal.visible = show_strip
	_crumb.visible = show_strip
	_goal.size.x = maxf(120.0, strip_w)
	_crumb.size.x = maxf(120.0, strip_w)
	_brand_sub.visible = show_sub
	_inv_chip.position.x = HDR_X_CHIP if show_sub else HDR_X_SUB

## 页眉工具组是 flex 的 `margin-left:auto`：贴右，不贴左。坐标表按 1280 量出来的，
## 存的是「距右边多少」，所以窗口变宽时整体右移即可。
func _layout_header_right(vw: float) -> void:
	for pair in _hdr_right:
		var c: Control = pair[0]
		if is_instance_valid(c):
			c.position.x = vw - float(pair[1])

func _ready() -> void:
	_setup_window_scale()
	theme = TecTheme.build()
	_progress_path = "user://shot_progress.json" if _shot_mode() else CaseCatalog.PROGRESS_PATH
	_progress_read_only = DisplayServer.get_name() == "headless" and not _shot_mode()
	_catalog = CaseCatalog.new(_progress_path)
	## C2/S14：继续 = 上次游玩的案件；last 不可用（老档 / 数据未接入）时回 A-001。
	_active_case = _catalog.resume_case_id()
	case_def = CaseLoader.new(CaseCatalog.path_of(_active_case))
	if not case_def.load_case():
		push_error("案件数据装载失败：" + case_def.load_error)
		return
	_save_enabled = not _shot_mode() and DisplayServer.get_name() != "headless"
	_investigator = Investigator.load_from(_inv_path)
	graph = GraphState.new(case_def)
	combos = ComboSystem.new(case_def, graph)
	_cmds = CommandSystem.new(case_def, graph)
	_mount_parts()
	_build_ui()
	if OS.is_debug_build() or _shot_mode():
		debug = load("res://scenes/debug/DesktopDebug.gd").new()
		debug.name = "debug"
		debug.desk = self
		add_child(debug)
	session._update_case_chrome()
	session._update_case_park_ui()
	session._refresh_chip()
	if session._start_screen_allowed():
		session._open_start_screen()
	else:
		session._boot_session()
	if debug == null:
		return
	if _has_arg("--shot-p2"):
		debug._shot_p2_flow.call_deferred()
	elif _has_arg("--shot-p3"):
		debug._shot_p3_flow.call_deferred()
	elif _has_arg("--shot"):
		if _has_arg("--shot-intro"):
			debug._shot_intro_flow.call_deferred()
		else:
			debug._shot_flow.call_deferred()

## 挂载子系统控制器：必须在 `_build_ui()` 之前，后者会调用它们建 UI。
func _mount_parts() -> void:
	garden_music = load("res://scenes/desktop/GardenMusicController.gd").new()
	garden_music.name = "garden_music"
	garden_music.desk = self
	add_child(garden_music)
	people = load("res://scenes/desktop/PeopleController.gd").new()
	people.name = "people"
	people.desk = self
	add_child(people)
	tec = load("res://scenes/desktop/TecController.gd").new()
	tec.name = "tec"
	tec.desk = self
	add_child(tec)
	matrix = load("res://scenes/desktop/MatrixController.gd").new()
	matrix.name = "matrix"
	matrix.desk = self
	add_child(matrix)
	tutorial = load("res://scenes/desktop/TutorialFlow.gd").new()
	tutorial.name = "tutorial"
	tutorial.desk = self
	add_child(tutorial)
	session = load("res://scenes/desktop/CaseSession.gd").new()
	session.name = "session"
	session.desk = self
	add_child(session)

	canvas = load("res://scenes/desktop/CanvasController.gd").new()
	canvas.name = "canvas"
	canvas.desk = self
	add_child(canvas)

	drag = load("res://scenes/desktop/DragDropController.gd").new()
	drag.name = "drag"
	drag.desk = self
	add_child(drag)

	launcher = load("res://scenes/desktop/LauncherController.gd").new()
	launcher.name = "launcher"
	launcher.desk = self
	add_child(launcher)

	narrative = load("res://scenes/desktop/NarrativeController.gd").new()
	narrative.name = "narrative"
	narrative.desk = self
	add_child(narrative)

	card_ui = load("res://scenes/desktop/CardUiController.gd").new()
	card_ui.name = "card_ui"
	card_ui.desk = self
	add_child(card_ui)

	windows = load("res://scenes/desktop/WindowController.gd").new()
	windows.name = "windows"
	windows.desk = self
	add_child(windows)

	chrome = load("res://scenes/desktop/ChromeController.gd").new()
	chrome.name = "chrome"
	chrome.desk = self
	add_child(chrome)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		session._autosave()
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
	## 空闲关流：没有分帧任务 / 拖拽会话 / 待写盘时不再每帧进函数。
	## 任何重新产生工作的入口都要 `_wake_process()`。
	if not _has_process_work():
		set_process(false)
		return
	if _panning and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_panning = false
		if _stage != null:
			_stage.mouse_default_cursor_shape = Control.CURSOR_ARROW
	if _autosave_pending and Time.get_ticks_msec() >= _autosave_due_msec:
		session._autosave()
	## F1：分帧力导向。每帧只推进 8 轮，卡片随收敛缓慢落位，主线程不再整帧卡死。
	if canvas._layout_job != null:
		canvas._layout_job.step(LAYOUT_FRAME_ROUNDS)
		canvas._apply_layout_job(false, true)
		_edges_dirty = true
		if canvas._layout_job.done():
			canvas._layout_job = null
			if _opt_reveal and not _view_user:
				canvas._fit_cards()
	var edges_due := _edges_dirty
	if canvas._follow_frames > 0:
		canvas._follow_frames -= 1
		edges_due = true
	if edges_due:
		canvas._repaint_edges()
	# 锚点节点还在重排补间里飞：浮层每帧重锚，跟着它一起走（Web 是每次 render 重算锚点）。
	# 只在补间期间做 —— 落地后重锚交给 `_start_move_tween` 的 finished，免得跟玩家拖窗口打架。
	if _mem_card != null and is_instance_valid(_mem_card) and narrative._mem_anchor_key != "" \
		and canvas._move_twens.has(narrative._mem_anchor_key):
		narrative._anchor_card_to(_mem_card, narrative._mem_anchor_key)
	if _sdrag_key == "":
		set_process(_has_process_work())
		return
	if _card_mirror != null and is_instance_valid(_card_mirror):
		drag._drop_card_mirror(null)
	## 光标用事件流坐标（`_input` 里持续更新），不用轮询——见 `_input` 注释。
	var at := _mouse_pos
	if not _sdrag_started:
		if at.distance_to(_sdrag_origin) < 5.0:
			if not _mouse_left_down:
				var clicked := _sdrag_key
				drag._sdrag_cancel()
				# 没移动就松手 = 单击这一行 = 取回（Web 的行单击口径）
				drag._take_from_store(clicked, "")
			return
		_sdrag_started = true
		_sdrag_ghost = drag._make_drag_ghost(_sdrag_label)
		if _sdrag_ghost != null:
			_sdrag_ghost.position = drag._sdrag_ghost_position(at)
	else:
		if _sdrag_ghost != null and is_instance_valid(_sdrag_ghost):
			_sdrag_ghost.position = drag._sdrag_ghost_position(at)
	drag._update_drop_over(at)
	if not _mouse_left_down:
		drag._finish_sdrag(at)
	set_process(_has_process_work())


## 还有没有需要逐帧推进的工作：分帧力导向、连线重画、拖拽会话、待写盘、浮层跟锚。
func _has_process_work() -> bool:
	if _panning or _autosave_pending or _edges_dirty or _sdrag_key != "":
		return true
	if canvas != null and (canvas._layout_job != null or canvas._follow_frames > 0):
		return true
	if narrative != null and _mem_card != null and is_instance_valid(_mem_card) \
			and narrative._mem_anchor_key != "" and canvas._move_twens.has(narrative._mem_anchor_key):
		return true
	return false


## 把 `_process` 重新拉起来；空闲帧由 `_process` 自己关流。
func _wake_process() -> void:
	if not is_processing():
		set_process(true)


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

	chrome._build_header()

	_desk = Control.new()
	_desk.name = "desk"
	_desk.position = Vector2(0, HEADER_H)
	_desk.size = Vector2(DESIGN_W, DESIGN_H - HEADER_H)
	_desk.mouse_filter = Control.MOUSE_FILTER_PASS
	## 对齐 Web `#desktop{overflow:hidden}`：窗框的九切片会往外撑 32px 画投影，
	## 桌面必须裁掉溢到页眉上的那一段，否则页眉底下会多一圈影。
	_desk.clip_contents = true
	add_child(_desk)

	windows._build_case_window()
	launcher._build_icons()
	session._build_case_park()
	tec._build_tec_chip()

	_tec = TecWindow.new()
	_tec.name = "tec_win"
	_tec.setup_tec()
	_tec.position = Vector2(906, 264)
	_tec.visible = false
	_tec.closed.connect(tec._close_tec)
	_tec.minimized.connect(tec._minimize_tec)
	_tec.analysis_started.connect(tec._on_tec_analysis_started)
	_tec.analysis_progress.connect(tec._on_tec_analysis_progress)
	_tec.analysis_done.connect(tec._on_tec_analysis_done)
	_tec.talk_requested.connect(tec._tec_talk)
	_desk.add_child(_tec)
	windows._place_z(_tec, ZR_TEC)

	_narr = NarrCard.new()
	_narr.name = "narr_card"
	_narr.visible = false
	_desk.add_child(_narr)
	windows._place_z(_narr, ZR_NARR)

	_ending = EndingOverlay.new()
	_ending.name = "ending"
	garden_music.setup_ending()

	_build_toast()
	chrome._build_debug_panel()

	_drop_outline = DropOutlineScript.new()
	_drop_outline.name = "drop_outline"
	_drop_outline.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drop_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desk.add_child(_drop_outline)
	windows._place_z(_drop_outline, ZR_DROP)

	## 界面建完才开自适应：_build_ui 期间主窗/浮层还没影，重排会空转。
	_ui_built = true
	_layout_root()

## 「适应窗口」：按内容包围盒重新缩放居中。**不跑布局** —— 那会把玩家摆的位置全收回去。
func _fit_view() -> void:
	canvas._fit_cards(false)

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

func _input(event: InputEvent) -> void:
	## 事件流是唯一可信的鼠标来源：轮询（get_mouse_position）在嵌入运行/非常规窗口下
	## 可能拿到带窗口偏移的绝对坐标（实测偏出正好一个窗口位置），而事件坐标与点击命中同流。
	if event is InputEventMouseMotion:
		_mouse_pos = (event as InputEventMouseMotion).global_position
	elif event is InputEventMouseButton:
		var b := event as InputEventMouseButton
		if b.button_index == MOUSE_BUTTON_LEFT:
			_mouse_left_down = b.pressed
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if _start_screen != null and is_instance_valid(_start_screen):
		return
	if _drag_key != "" or _sdrag_key != "" or _panning:
		return
	if _card_ctx != null and is_instance_valid(_card_ctx) \
			and not _card_ctx.get_global_rect().has_point(mb.global_position):
		card_ui._close_card_context()
	windows._raise_window_at(mb.global_position)

## W11：最小键盘层。Esc = 关最上层窗（先收密码浮层 / 人物卡），Ctrl+Z = 撤销。
## 不做全局快捷键表，避免和输入框、浏览器/系统快捷键打架。
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.ctrl_pressed and key.keycode == KEY_Z:
		session._undo()
		get_viewport().set_input_as_handled()
		return
	if key.keycode != KEY_ESCAPE:
		return
	if _start_screen != null and is_instance_valid(_start_screen):
		return
	if _intro != null and is_instance_valid(_intro) and _intro.visible:
		return
	if _ending != null and _ending.visible:
		return
	if _card_ctx != null and is_instance_valid(_card_ctx):
		card_ui._close_card_context()
		get_viewport().set_input_as_handled()
		return
	if _pw_pop != null and is_instance_valid(_pw_pop):
		_pw_pop.queue_free()
		_pw_pop = null
		_pw_ctx = {}
		get_viewport().set_input_as_handled()
		return
	if _people_card != null and is_instance_valid(_people_card) and _people_card.visible:
		people._close_person_card()
		get_viewport().set_input_as_handled()
		return
	if windows._close_top_window():
		get_viewport().set_input_as_handled()

# ── K3：打开入口统一为幂等「open」；原地关闭只由窗口自己承担 ──────────────

# ── 音乐播放器 / 花园彩蛋（P2.5）────────────────────────────────────────

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
	windows._place_z(_toast, ZR_TOAST)

# ── 切片 ────────────────────────────────────────────────────────────────

# ── 调查员 / 开场适性测试 ───────────────────────────────────────────────

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

# ── 画布手势（Web `15-desktop.js`）────────────────────────────────────────
# 点空白 = 清选中；拖空白 = 平移；滚轮 = 以光标为锚连续缩放（0.45~2.0，×1.12）。
# 卡片自己 `MOUSE_FILTER_STOP` + `accept_event()`，所以拖节点不会漏成平移。

# ── 卡片 ────────────────────────────────────────────────────────────────

## ── 拖动镜像（Web #drag-layer）──────────────────────────────────────────
## 镜像 = 卡片的「假身」：挂到桌布根（在所有窗子之上）、吃不到输入、
## 每帧跟着原卡的位置。原卡被隐藏，但仍是连线端点与数据写回的坐标来源。

# ── 落点（对齐 Web `nodeDropTargets()`，顺序即优先级）──────────────────────

# ── 收纳窗（物品 / 证据）────────────────────────────────────────────

# ── 人物名册 / 因果追踪（批 1：差距报告 I1 / I2）─────────────────────────

# ── 人物档案卡（PEOPLE_CARD_PLAN）────────────────────────────────────────

## 日志窗：Web `#log-win`（right 14 / bottom 96 / 宽 320）
func _toggle_log() -> void:
	if not session._require_case():
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
	windows._place_z(_log_win, ZR_LOG)
	_log_unread = 0
	launcher._set_badge(_log_badge, "")

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
	launcher._set_badge(_log_badge, str(_log_unread))

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

# ── 密码弹窗 ────────────────────────────────────────────────────────────

# ── 档案 / 时间图层 / 回忆放映 ─────────────────────────────────────────

# ── 证据：落地 / 同源去重 / 首次教学 ─────────────────────────────────────

# ── TEC ─────────────────────────────────────────────────────────────────

## G14：这组线索里有没有「真名结局」配方需要的条目。
## 只用于 TEC 输出行的提醒样式，不向玩家指名具体是哪一条。
func _has_true_name_clue(keys: Array) -> bool:
	if case_def == null or keys.is_empty():
		return false
	var ending := case_def.ending_by_id("TRUE_E")
	if ending == null or ending.recipe.is_empty():
		return false
	var recipe := {}
	for clue in ending.recipe:
		if clue != null:
			recipe[String(clue.id)] = true
	for key in keys:
		var n := graph.node(String(key))
		if recipe.has(n.id):
			return true
	return false

# ── 测试钩子（与 Web 版 window.__* 同名，便于把操作脚本逐行翻译）──────────

# ── 档案 / 放映卡测试钩子（P2.3）──────────────────────────────────────

# ── 多人对话 / 独白测试钩子（P2.4）────────────────────────────────────

# ── 人物名册 / 因果追踪 / 图标栏测试钩子（批 1）────────────────────────────

# ── 推演桌布测试钩子（P1.4）────────────────────────────────────────────

# ── 音乐播放器 / 花园测试钩子（P2.5）──────────────────────────────────

# ── 案件系统测试钩子（P2.1）────────────────────────────────────────────

# ── 调查员测试钩子（P1.6）──────────────────────────────────────────────

# ── 截图采样（P0 视觉自查：跑一遍切片，按阶段存 PNG 到 docs/）──────────

func quit_app() -> void:
	session._autosave()
	if _shot_mode() and FileAccess.file_exists(_progress_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_progress_path))
	get_tree().quit()
