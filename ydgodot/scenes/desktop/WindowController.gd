class_name WindowController
extends Node
## 由 Desktop 挂载的子系统控制器。
## 过渡期直接通过注入的 `desk` 访问宿主成员；搬出的函数名保持不变。

var desk: Desktop


## 主窗铺满「桌面 − 左侧图标列」。宽度/高度都用实际视口算，1280×720 下正好落在
## 原来的 1164(内宽) × 638(内高)、画布 1162 × 608，与 Web 版 P3 对拍口径一致
## （`test_ui` 有断言钉住这两个数）。
func _resize_case_window(vw: float, vh: float) -> void:
	if desk._case_win == null or not is_instance_valid(desk._case_win):
		return
	var inner_w := maxf(vw - 86.0 - SysWindow.PAD * 2.0 - 2.0, 640.0)
	var inner_h := maxf(vh - Desktop.HEADER_H - 2.0 - SysWindow.PAD * 2.0, 360.0)
	desk._case_win.position = Vector2(86, 0)
	desk._case_win.resize_to(inner_w, inner_h)
	desk._case_win.body.position = Vector2(SysWindow.PAD + 1, SysWindow.PAD + 1 + SysWindow.BAR_H)
	desk._case_win.body.size = Vector2(inner_w - 2, inner_h - 2 - SysWindow.BAR_H)
	if desk._stage == null or not is_instance_valid(desk._stage):
		return
	var old := desk._stage.size
	if old == desk._case_win.body.size:
		return
	desk._stage.size = desk._case_win.body.size
	if desk._card_layer == null or not is_instance_valid(desk._card_layer):
		return
	if desk._view_user:
		## 玩家自己调过镜头：只补偿尺寸差的一半，保持画面中心不跑，缩放比不动。
		desk._view_pos += (desk._stage.size - old) * 0.5
		desk.canvas._apply_view()
	else:
		## 还在「适应窗口」自动档上：窗口变大就重新铺满，否则卡片会缩在中间一小块。
		desk.canvas._fit_cards()


## 贴右边的常驻浮窗（人物名册 / 日志）：只在它们开着的时候重算，关着的等下次打开。
## 日志窗是**右下角**（x、y 都贴边），名册只有 x 贴边、y 固定 60。
func _relayout_edge_windows(vw: float) -> void:
	if desk._people_win != null and is_instance_valid(desk._people_win):
		desk._people_win.position.x = vw - 328.0 - desk._people_win.size.x + SysWindow.PAD
	if desk._log_win != null and is_instance_valid(desk._log_win):
		desk._log_win.position = Vector2(vw - 14.0 - desk._log_win.size.x + SysWindow.PAD,
			desk._desk.size.y - 96.0 - desk._log_win.size.y + SysWindow.PAD)


func _build_case_window() -> void:
	desk._case_win = SysWindow.new()
	desk._case_win.name = "case_win"
	## 主窗高度跟着设计基准走：桌面可用高 = DESIGN_H - HEADER_H，减去底部 2px 余量
	## 与窗框两侧 14px 的 PAD。宽度 1164 不变（86 图标列 + 1164 + 2×14 = 1278 ≤ 1280）。
	var case_h := Desktop.DESIGN_H - Desktop.HEADER_H - 2.0 - SysWindow.PAD * 2.0
	desk._case_win.setup(desk.session._case_window_title(), 1164, case_h)
	desk._case_win.position = Vector2(86, 0)
	desk._case_win.body.position = Vector2(SysWindow.PAD + 1, SysWindow.PAD + 1 + SysWindow.BAR_H)
	desk._case_win.body.size = Vector2(1162, case_h - 2 - SysWindow.BAR_H)
	desk._case_win.body.clip_contents = true
	desk._case_win.enable_case_controls()
	desk._case_win.closed.connect(func(): desk.session._park_case("icon"))
	desk._case_win.minimized.connect(func(): desk.session._park_case("dock"))
	desk._desk.add_child(desk._case_win)
	_place_z(desk._case_win, Desktop.ZR_CASE)

	desk._stage = Control.new()
	desk._stage.name = "stage"
	desk._stage.size = desk._case_win.body.size
	desk._stage.clip_contents = true
	desk._stage.mouse_filter = Control.MOUSE_FILTER_PASS
	desk._stage.gui_input.connect(desk.canvas._on_stage_input)
	desk._case_win.body.add_child(desk._stage)

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
	desk._stage.add_child(stage_bg)

	desk._card_layer = Control.new()
	desk._card_layer.name = "cards"
	desk._card_layer.size = Vector2(Desktop.WORLD_W, Desktop.WORLD_H)
	desk._card_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	desk._stage.add_child(desk._card_layer)

	# 连线层排在卡片之前（同一坐标系，跟着一起平移 / 缩放）
	desk._edge_layer = EdgeLayer.new()
	desk._edge_layer.name = "edges"
	desk._card_layer.add_child(desk._edge_layer)
	desk._drag_line = EdgeLayer.new()
	desk._drag_line.name = "drag_edges"
	desk._desk.add_child(desk._drag_line)
	_place_z(desk._drag_line, Desktop.ZR_MIRROR - 1)

# ── z 序基准（Web 静态 z-index 表，05-apps.css / 06-shell.css / 03-desktop.css 抄录）──
# 这些 rank 决定初始/打开时的层序；系统窗打开或被点击后会提到浮动窗栈顶，
# 因此「日志(21)、详情(22) 开得再晚也压不过 TEC(28)」不再是硬规则。
# toast / 拖拽描边 / 拖拽镜像 / 领证窗在浮动窗之上，点击提层不会越过它们。


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
	var kids := desk._desk.get_children()
	var at := kids.size() - 1
	var self_idx := kids.find(ctrl)
	for i in kids.size():
		if i == self_idx:
			continue
		var c := kids[i] as Control
		if int(c.get_meta("zrank", Desktop.ZR_CASE)) > rank:
			at = i - 1 if i > self_idx else i
			break
	desk._desk.move_child(ctrl, at)
	if ctrl is SysWindow and ctrl != desk._case_win and ctrl.visible:
		(ctrl as SysWindow).clamp_into_parent()
	## 新打开的系统窗就是当前窗：放到浮动窗栈顶，但仍压在 toast / 拖拽描边 / 拖拽镜像之下。
	if ctrl is SysWindow and ctrl != desk._case_win and rank < Desktop.ZR_DROP \
		and (ctrl as SysWindow).participates_in_activation() and ctrl.visible:
		_raise_to_front(ctrl, false)
	_refresh_window_activation()


## 把一扇已经打开的窗口提到浮动窗栈顶（不改变它的默认 zrank）。
## 这样点任何窗口都能成为当前窗，但 toast、拖拽虚线框、拖拽镜像和领证窗仍在最上层。
func _raise_to_front(w: Control, refresh := true) -> void:
	if w == null or not is_instance_valid(w) or w.get_parent() != desk._desk:
		return
	if not (w is SysWindow) or w == desk._case_win or not w.visible:
		return
	if int(w.get_meta("zrank", Desktop.ZR_WIN)) >= Desktop.ZR_DROP:
		return
	var target := desk._desk.get_child_count()
	var self_idx := w.get_index()
	for i in range(desk._desk.get_child_count()):
		if i == self_idx:
			continue
		var c := desk._desk.get_child(i) as Control
		if c == null:
			continue
		if int(c.get_meta("zrank", Desktop.ZR_CASE)) >= Desktop.ZR_DROP:
			target = i - 1 if i > self_idx else i
			break
	desk._desk.move_child(w, target)
	if refresh:
		_refresh_window_activation()


## 指针按下：把指针下最上层的可见系统窗提为当前窗；点空白 / 卡片 / 图标不改层级。
func _raise_window_at(at_global: Vector2) -> bool:
	if desk._desk == null or not is_instance_valid(desk._desk):
		return false
	for i in range(desk._desk.get_child_count() - 1, -1, -1):
		var c := desk._desk.get_child(i) as Control
		if c == null or not is_instance_valid(c) or not c.visible:
			continue
		if not c.get_global_rect().has_point(at_global):
			continue
		if not (c is SysWindow):
			if c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				return false
			continue
		var w := c as SysWindow
		if w == desk._case_win:
			return false
		if int(w.get_meta("zrank", Desktop.ZR_WIN)) >= Desktop.ZR_DROP:
			return false
		_raise_to_front(w)
		return true
	return false


## 关掉层序最上面的可见系统窗。案件主窗排最后：有浮窗时先收浮窗，只剩案件时才收起。
func _close_top_window() -> bool:
	if desk._desk == null or not is_instance_valid(desk._desk):
		return false
	for i in range(desk._desk.get_child_count() - 1, -1, -1):
		var w := desk._desk.get_child(i) as SysWindow
		if w == null or not is_instance_valid(w) or not w.visible or w == desk._case_win:
			continue
		if w is CertWin and (desk._tutorial_cert_win == w or desk._cert_win == w):
			continue
		w._on_close_pressed()
		return true
	if desk._case_win != null and is_instance_valid(desk._case_win) and desk._case_win.visible and desk._case_open:
		return desk.session._park_case("icon")
	return false


## 窗口标题栏 / 历史卡按下的提层请求：提到浮动窗栈顶，并成为当前激活窗。
func _on_window_raise(w: Control) -> void:
	_raise_to_front(w)


## A2：激活态只看**实际层序**。系统窗打开或被点击后会提到栈顶，因此当前窗就是
## `_desk` 子序里最靠后的可见系统窗；隐藏、最小化、关窗后自动让位。
## 从 `_desk` 子序末尾往前找第一扇可见系统窗。
func _refresh_window_activation() -> void:
	if desk._desk == null or not is_instance_valid(desk._desk):
		return
	var top: SysWindow = null
	for i in range(desk._desk.get_child_count() - 1, -1, -1):
		var c := desk._desk.get_child(i) as SysWindow
		if c != null and is_instance_valid(c) and c.visible and c.participates_in_activation():
			top = c
			break
	# 逐窗落态：新建窗默认是激活态，只在 top 未变时提前 return 会把它漏成「双激活」。
	# 叙事卡 / 记忆卡不参与，保持它们自己的默认外观，不在这里被改成灰标题。
	for i in desk._desk.get_child_count():
		var w := desk._desk.get_child(i) as SysWindow
		if w != null and is_instance_valid(w) and w.participates_in_activation():
			w.set_active(w == top)
	desk._active_win = top


## 播放器与 dock 的默认落点按 1280×720 量的 906/414、1026/532；
## 缩到 960×560 时只把越界的那一轴拉回右下安全区，不改变 1280 的既有构图。
## 案件收进右下角时的卡片：跟随桌面现算，别再用 1280×720 下的固定 678。
func _clamp_windows_to_desk() -> void:
	if desk._desk == null or not is_instance_valid(desk._desk):
		return
	for c in desk._desk.get_children():
		var w := c as SysWindow
		if w != null and is_instance_valid(w) and w.visible:
			w.clamp_into_parent()


## 1280 下的浮窗坐标是量出来的；小窗口只收越界的那一轴，避免 TEC / 对话窗
## 在 960×560 里整扇跑到屏幕外。夹取基于 `size`，窗口长高后同样成立。
func _place_floating_windows() -> void:
	var desk_h := desk._desk.size.y if desk._desk != null and is_instance_valid(desk._desk) else desk._vh() - Desktop.HEADER_H
	var vw := desk._vw()
	if desk._tec != null and is_instance_valid(desk._tec):
		if desk._tutorial_active:
			## 只在第一次摆位时居中；之后 TEC 是普通窗口，玩家拖到哪就留在哪。
			if not desk._tutorial_tec_placed:
				desk._tec.position = Vector2(
					maxf(14.0, (vw - desk._tec.size.x) * 0.5),
					maxf(14.0, (desk_h - desk._tec.size.y) * 0.5 - 24.0))
				desk._tutorial_tec_placed = true
		else:
			desk._tec.position = Vector2(minf(906.0, vw - 14.0 - desk._tec.size.x),
				minf(264.0, desk_h - 14.0 - desk._tec.size.y))
	if desk._tec_chip != null and is_instance_valid(desk._tec_chip):
		if desk._tec_chip.user_placed():
			desk._tec_chip.clamp_into_parent()
		else:
			desk._tec_chip.position = Vector2(minf(1068.0, vw - 16.0 - desk._tec_chip.size.x),
				minf(608.0, desk_h - 4.0 - desk._tec_chip.size.y))
	if desk._archive_win != null and is_instance_valid(desk._archive_win):
		desk._archive_win.position = Vector2(minf(458.0, vw - 14.0 - desk._archive_win.size.x),
			minf(84.0, desk_h - 14.0 - desk._archive_win.size.y))
	if desk._chat_win != null and is_instance_valid(desk._chat_win):
		## 对话窗在 1280 本来就是贴右 4px 的 858，别拿 14px 去夹它。
		desk._chat_win.position = Vector2(minf(858.0, vw - 4.0 - desk._chat_win.size.x),
			minf(58.0, desk_h - 14.0 - desk._chat_win.size.y))
	## G3：结局种子在桌布上。桌布与花园同时开时，能并排就并排（1280 及以上），
	## 让种子与花圃同屏；小窗口仍按原位置，玩家按 toast 指引把种子拖到花园图标。
	var matrix_ok := desk._matrix_win != null and is_instance_valid(desk._matrix_win) and desk._matrix_win.visible
	var garden_ok := desk._garden_win != null and is_instance_valid(desk._garden_win) and desk._garden_win.visible
	var paired := false
	if matrix_ok and garden_ok:
		var gap := 12.0
		var total_w := desk._matrix_win.size.x + desk._garden_win.size.x + gap
		var need_h := maxf(desk._matrix_win.size.y, desk._garden_win.size.y)
		if total_w <= vw - 28.0 and need_h <= desk_h - 54.0:
			var left := maxf(14.0, (vw - total_w) * 0.5)
			desk._matrix_win.position = Vector2(left,
				maxf(14.0, minf(40.0, desk_h - 14.0 - desk._matrix_win.size.y)))
			desk._garden_win.position = Vector2(left + desk._matrix_win.size.x + gap,
				maxf(14.0, minf(58.0, desk_h - 14.0 - desk._garden_win.size.y)))
			paired = true
	if matrix_ok and not paired and desk._matrix_pair_layout:
		desk._matrix_win.position = Vector2(
			maxf(14.0, minf(336.0, vw - 14.0 - desk._matrix_win.size.x)),
			maxf(14.0, minf(40.0, desk_h - 14.0 - desk._matrix_win.size.y)))
	desk._matrix_pair_layout = paired
	if garden_ok and not paired:
		desk._garden_win.position = Vector2(
			maxf(14.0, minf(380.0, vw - 14.0 - desk._garden_win.size.x)),
			maxf(14.0, minf(58.0, desk_h - 14.0 - desk._garden_win.size.y)))
