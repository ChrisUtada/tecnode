class_name EdgeLayer
extends Control
## 画布连线（Web `paintEdges()` 的 Godot 版）。
##
## C2 图例（一处实现，四种状态）：
##   已连通/已探索：1px 实线（INK）—— entity / move
##   可连未试：    1px 灰线（EDGE_UNTRIED = edge(0.3)）—— cond
##   试过未成：    1px 虚线（EDGE_TRIED）—— tried
##   拖动中：      2px 实线 + 末端箭头（ghost）
##
## 形状：二次贝塞尔，中点抬升 `min(70, |dx| × 0.16)`（Web 的 `Q` 控制点）。
## Godot 没有 SVG path，用 24 段采样；虚线按弧长手工切段。
##
## 坐标：**world 空间**（与卡片同一坐标系）。本层挂在 `_card_layer` 里、排在卡片之前，
## 于是平移 / 缩放自动跟随，不需要每帧换算屏幕坐标。

const SEGMENTS := 24
const GHOST_WIDTH := 2.0
const GHOST_ARROW := 7.0

## 1-bit：强度只由「线宽 + 线型」表达。cond 是唯一允许的灰线，语义是「可连但未试」。
const STYLE := {
	"entity": {"color": TecTheme.INK, "width": 1.0, "dash": 0.0, "gap": 0.0, "alpha": 1.0},
	"move": {"color": TecTheme.INK, "width": 1.0, "dash": 0.0, "gap": 0.0, "alpha": 1.0},
	"cond": {"color": TecTheme.EDGE_UNTRIED, "width": 1.0, "dash": 0.0, "gap": 0.0, "alpha": 1.0},
	"tried": {"color": TecTheme.EDGE_TRIED, "width": 1.0, "dash": 4.0, "gap": 4.0, "alpha": 1.0},
}

## [{a: Vector2, b: Vector2, kind: String, dim: bool, id: String}]
var _segments: Array = []
## F2：按「边身份」缓存贝塞尔采样点。拖动时只有和被拖卡相连的几条边端点会变，
## 其余静态边直接复用上一帧的 24 点折线，不再每帧全量重采样。
## `_items` 是带 `pts` 的绘制项；`_segments` 保留原始输入供 segment_count / 调试。
var _items: Array = []
var _curve_cache: Dictionary = {}     # id -> {a, b, pts}
var _curve_cache_on := true
var _curve_builds := 0
## 拖动幽灵线（Web `08-interact.js:63`）：`{a, b}` 或空。从被拖节点的中心直连指针，
## C2 改为 2px 实线 + 末端箭头 —— 直线（不走贝塞尔）。
var _ghost := {}
## 相机倍率：线宽与虚线节奏都按 1/k 反向补偿，屏幕上恒为 1.0~1.6px。
## 不补偿的话，1.3px 的实体线在 0.62x 下只剩 0.8px（被纸纹底吃成虚影），
## 5-4 的虚线周期也被压成 3-2、糊成实线。
var _zoom := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 尺寸必须跟着父层（世界层 2000×1300）。只写 anchors 会留下 0×0 的矩形，
	# 而零尺寸的 Control 在渲染时会被整块剔除 —— 线画了但一个像素都不出。
	if get_parent() is Control:
		size = (get_parent() as Control).size


func set_segments(segs: Array) -> void:
	_segments = segs
	var alive := {}
	var next_items: Array = []
	for raw in segs:
		var s: Dictionary = raw
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		var sid := String(s.get("id", ""))
		if sid == "":
			sid = _fallback_id(a, b, String(s.get("kind", "entity")))
		alive[sid] = true
		var pts: PackedVector2Array
		var cached: Dictionary = _curve_cache.get(sid, {})
		if _curve_cache_on and not cached.is_empty() \
				and (cached["a"] as Vector2).is_equal_approx(a) \
				and (cached["b"] as Vector2).is_equal_approx(b):
			pts = cached["pts"]
		else:
			pts = _curve(a, b)
			_curve_builds += 1
			_curve_cache[sid] = {"a": a, "b": b, "pts": pts}
		## 直接写回本次新建的 segment 字典，避免每帧再 duplicate 一份。
		s["pts"] = pts
		next_items.append(s)
	# 结构收缩时把旧边从缓存里清掉（60 条边规模，线性扫描足够便宜）。
	for sid in _curve_cache.keys():
		if not alive.has(sid):
			_curve_cache.erase(sid)
	_items = next_items
	queue_redraw()


func _fallback_id(a: Vector2, b: Vector2, kind: String) -> String:
	return "%s|%s|%s" % [str(a), str(b), kind]


## 基准 / 回归：临时关掉缓存等于回到 F2 之前的「每帧全量采样」。
func dbg_set_curve_cache(on: bool) -> void:
	_curve_cache_on = on
	if not on:
		_curve_cache.clear()
	queue_redraw()


func dbg_curve_builds() -> int:
	return _curve_builds


func dbg_reset_curve_builds() -> void:
	_curve_builds = 0


func dbg_curve_cache_size() -> int:
	return _curve_cache.size()


## 相机倍率回灌（Desktop `_apply_view`）。只影响下一次重绘，不动几何。
func set_zoom(k: float) -> void:
	var k2 := clampf(k, 0.1, 4.0)
	if absf(k2 - _zoom) < 0.0005:
		return
	_zoom = k2
	queue_redraw()


## world 尺寸 → 屏幕恒定的视觉尺寸
func _w(v: float) -> float:
	return v / _zoom


func segment_count() -> int:
	return _segments.size()


## 拖动中每帧调一次（world 坐标）。传同一个点或空调用 `clear_ghost()` 收起。
func set_ghost(a: Vector2, b: Vector2) -> void:
	_ghost = {"a": a, "b": b}
	queue_redraw()


func clear_ghost() -> void:
	if _ghost.is_empty():
		return
	_ghost = {}
	queue_redraw()


func has_ghost() -> bool:
	return not _ghost.is_empty()


func ghost_points() -> Dictionary:
	return _ghost.duplicate()


func _draw() -> void:
	for raw in _items:
		var s: Dictionary = raw
		var kind := String(s.get("kind", "entity"))
		if not STYLE.has(kind):
			kind = "entity"
		var st: Dictionary = STYLE[kind]
		var pts: PackedVector2Array = s["pts"]
		var col: Color = st["color"]
		var alpha: float = float(st["alpha"]) * (0.12 if bool(s.get("dim", false)) else 1.0)
		col.a = alpha
		if float(st["dash"]) > 0.0:
			_draw_dashed(pts, col, _w(float(st["width"])), _w(float(st["dash"])), _w(float(st["gap"])))
		else:
			draw_polyline(pts, col, _w(float(st["width"])), true)
	# 幽灵线最后画，压在既有连线上面（Web 是 appendChild 到同一个 svg，天然在最上层）
	if not _ghost.is_empty():
		_draw_ghost(_ghost["a"], _ghost["b"])


## C2 拖动线：2px 实线，末端画两笔箭头；都按相机倍率反补，屏幕上尺寸恒定。
func _draw_ghost(a: Vector2, b: Vector2) -> void:
	var col := TecTheme.INK
	var width := _w(GHOST_WIDTH)
	draw_line(a, b, col, width, true)
	var delta := b - a
	if delta.length() < 0.5:
		return
	var dir := delta.normalized()
	var side := Vector2(-dir.y, dir.x)
	var wing := _w(GHOST_ARROW)
	var tip := b
	draw_line(tip, tip - dir * wing + side * wing * 0.55, col, width, true)
	draw_line(tip, tip - dir * wing - side * wing * 0.55, col, width, true)


## 二次贝塞尔：控制点抬升 = min(70, |dx| × 0.16)
func _curve(a: Vector2, b: Vector2) -> PackedVector2Array:
	var ctrl := Vector2((a.x + b.x) * 0.5, (a.y + b.y) * 0.5 - minf(70.0, absf(b.x - a.x) * 0.16))
	var out := PackedVector2Array()
	for i in SEGMENTS + 1:
		var t := float(i) / float(SEGMENTS)
		var u := 1.0 - t
		out.append(a * (u * u) + ctrl * (2.0 * u * t) + b * (t * t))
	return out


## 沿折线按弧长切虚线（Godot 的 draw_dashed_line 只吃直线段）
##
## ⚠ 两个坑（2026-10-22 实测踩到，缩放后整帧卡死）：
## 1. `traveled` 必须随时取模。它是沿整条折线累加的，一条长曲线上千像素、period 只有
##    几像素，浮点尾数一丢，`fposmod` 就会返回 `period` 本身而不是 `[0,period)` ——
##    此时「跳过空白」那一步算出 0，`while t < seg_len` 永远前进不了。
## 2. 因此推进量要兜一个 ε 下限，任何情况下都必须严格前进。
func _draw_dashed(pts: PackedVector2Array, col: Color, width: float, dash: float, gap: float) -> void:
	var period := dash + gap
	if period <= 0.0:
		return
	var traveled := 0.0
	for i in range(1, pts.size()):
		var p0 := pts[i - 1]
		var p1 := pts[i]
		var seg_len := p0.distance_to(p1)
		if seg_len <= 0.0001:
			continue
		var t := 0.0
		while t < seg_len:
			var phase := fposmod(traveled + t, period)
			if not is_finite(phase) or phase >= period:
				phase = 0.0
			if phase < dash:
				var run := minf(dash - phase, seg_len - t)
				if run > 0.0:
					var a := p0.lerp(p1, t / seg_len)
					var b := p0.lerp(p1, (t + run) / seg_len)
					draw_line(a, b, col, width, true)
				t += maxf(run, 0.0001)
			else:
				t += maxf(minf(period - phase, seg_len - t), 0.0001)
		traveled = fposmod(traveled + seg_len, period)
