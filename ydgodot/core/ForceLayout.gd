class_name ForceLayout
extends RefCounted
## F1：与 Desktop._layout_force 同口径的力导向求解器，但把 260 轮拆成可调用的 step()。
## 纯数据，不碰 Control；调用方决定每帧跑几轮、什么时候写回卡片。
##
## 参数照抄 `src/js/07-render.js`：斥力 30000/d²、最小间距 R_a+R_b+14、
## 弹簧 rest 185/300/150、向心 0.0022。R 用视觉半径（半对角线），与 Web 80/68 同口径。

const TOTAL_ROUNDS := 260

var keys: Array = []
var pos: Dictionary = {}
var free: Dictionary = {}
var radius: Dictionary = {}
var first_place: Dictionary = {}
var rounds_done := 0

var _rng := RandomNumberGenerator.new()


## 播种并建立本轮求解的只读参数。坐标仍写回 graph（与旧版一致）：
## x/y < 0 的节点按 5 列网格 / 中央随机撒开，已有坐标不动。
func prepare(graph: GraphState, key_list: Array) -> void:
	keys = key_list.duplicate()
	pos.clear()
	free.clear()
	radius.clear()
	first_place.clear()
	rounds_done = 0
	_rng.seed = 0x5EED
	var ci := 0
	for key in keys:
		var n := graph.node(String(key))
		first_place[key] = float(n.get("x", -1.0)) < 0.0
		if float(n.get("x", -1.0)) >= 0.0 and float(n.get("y", -1.0)) >= 0.0:
			ci += 1
			continue
		if graph.is_container_node(String(key)):
			n["x"] = 200.0 + float(ci % 5) * 380.0
			n["y"] = 160.0 + float((ci / 5) as int) * 300.0
		else:
			n["x"] = 700.0 + (_rng.randf() - 0.5) * 420.0
			n["y"] = 560.0 + (_rng.randf() - 0.5) * 420.0
		ci += 1
	for key in keys:
		var n := graph.node(String(key))
		pos[key] = Vector2(float(n.get("x", 0.0)), float(n.get("y", 0.0)))
		free[key] = not bool(n.get("pinned", false))
		radius[key] = 80.0 if graph.is_container_node(String(key)) else 68.0
	_edges = graph.edges


func done() -> bool:
	return rounds_done >= TOTAL_ROUNDS


## 跑 `count` 轮。多次调用与一次性跑完的数值结果一致（rng 状态连续）。
func step(count: int) -> void:
	var left := mini(count, TOTAL_ROUNDS - rounds_done)
	for _i in maxi(left, 0):
		_round()
		rounds_done += 1


func _round() -> void:
	for i in keys.size():
		var a: String = keys[i]
		for j in range(i + 1, keys.size()):
			var b: String = keys[j]
			var pa: Vector2 = pos[a]
			var pb: Vector2 = pos[b]
			var delta: Vector2 = pb - pa
			var d2 := delta.length_squared()
			if d2 < 1.0:
				delta = Vector2(_rng.randf() - 0.5, _rng.randf() - 0.5)
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
	for e in _edges:
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
	for key in keys:
		if not free[key]:
			continue
		var p: Vector2 = pos[key]
		p += Vector2(2000.0 * 0.5 - p.x, 1300.0 * 0.5 - p.y) * 0.0022
		pos[key] = p


## 边表由调用方在 prepare 后注入（避免求解器持有 GraphState 引用）。
var _edges: Array = []


func set_edges(edges: Array) -> void:
	_edges = edges
