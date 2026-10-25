class_name GardenSystem
extends RefCounted
## 花园彩蛋（对齐 Web 版 16-cases.js 的花园模块）
##
## 真名结局「确认捕获」后发一枚种子；种子拖进花园即落土，按真实时间
## 45s 嫩芽 → 90s 展叶 → 135s 舒叶 → 180s 开花。株只记 at（下种 Unix 毫秒），
## 关游戏再回来不会倒退；位置是花圃百分比（8..92 / 30..85）。
## 开花后点花逐段显示结局 message（narr）。

const STAGE_MS := [0, 45000, 90000, 135000, 180000]
const STAGE_NAMES := ["种子", "嫩芽", "展叶", "舒叶", "开花"]
const STAGE_IMAGES := [
	"res://assets/raw/flower/plant_seed.png",
	"res://assets/raw/flower/plant_sprout.png",
	"res://assets/raw/flower/plant_leaf_stage_1.png",
	"res://assets/raw/flower/plant_leaf_stage_2.png",
	"res://assets/raw/flower/plant_flower.png",
]
const X_MIN := 8
const X_MAX := 92
const Y_MIN := 30
const Y_MAX := 85
const DEFAULT_X := 50
const DEFAULT_Y := 58
const BLOOM_FRESH_MS := 10000


static func blank() -> Dictionary:
	return {"seed": false, "plots": []}


## 老档归一化：过滤 null、补坐标 / at / hit；已有株但缺 narr 时回填真名说明。
static func normalize(graph: GraphState, case_def: CaseLoader = null) -> Dictionary:
	if graph == null:
		return blank()
	var missing := not (graph.garden is Dictionary)
	var g = graph.garden
	if missing:
		g = blank()
		graph.garden = g
	if not (g.get("plots", []) is Array):
		g["plots"] = []
	g["seed"] = bool(g.get("seed", false))
	## S5：真名结局一旦入账，种子就属于进度，不该等收幕按钮才发。
	## 旧档（有结尾、garden 里 seed=false 且没有已种下的株）也在这里补发；
	## 已种下的株（plots 非空）说明种子已经被消费，不再重复补。
	var true_done := false
	if case_def != null:
		for e in case_def.endings:
			if e != null and e.is_true_capture and graph.endings.has(e.id):
				true_done = true
				break
	else:
		true_done = graph.endings.has("TRUE_E")
	if true_done and not bool(g["seed"]) and (g["plots"] as Array).is_empty():
		g["seed"] = true
		if String(g.get("narr", "")).strip_edges() == "" and case_def != null:
			g["narr"] = true_ending_message(case_def)
	var kept: Array = []
	for raw in (g["plots"] as Array):
		if not (raw is Dictionary):
			continue
		var p: Dictionary = raw
		p["at"] = int(p.get("at", 0))
		p["hit"] = bool(p.get("hit", false))
		if not p.has("x"):
			p["x"] = 24 + (kept.size() % 4) * 18
		if not p.has("y"):
			p["y"] = DEFAULT_Y
		p["x"] = int(clampf(float(p.get("x", DEFAULT_X)), X_MIN, X_MAX))
		p["y"] = int(clampf(float(p.get("y", DEFAULT_Y)), Y_MIN, Y_MAX))
		kept.append(p)
	g["plots"] = kept
	if not kept.is_empty() and String(g.get("narr", "")).strip_edges() == "" and case_def != null:
		g["narr"] = true_ending_message(case_def)
	return g


static func has_garden(graph: GraphState) -> bool:
	if graph == null or not (graph.garden is Dictionary):
		return false
	var g: Dictionary = graph.garden
	return bool(g.get("seed", false)) or not (g.get("plots", []) as Array).is_empty()


static func true_ending_message(case_def: CaseLoader) -> String:
	if case_def == null:
		return ""
	for e in case_def.endings:
		if e != null and e.is_true_capture:
			return e.message
	return ""


## 「确认捕获」时发种子：只发一枚；种下 / 已有株后不再发，也不改已有旁白。
static func grant_seed(graph: GraphState, msg: String, case_def: CaseLoader = null) -> bool:
	var g := normalize(graph, case_def)
	if bool(g.get("seed", false)) or not (g["plots"] as Array).is_empty():
		return false
	if String(msg) != "":
		g["narr"] = String(msg)
	g["seed"] = true
	return true


## 下种：x/y 是花圃百分比；落点越界夹回。now_ms <= 0 时取真实时间。
static func plant(graph: GraphState, x: float, y: float, now_ms: int = 0) -> bool:
	var g := normalize(graph)
	if not bool(g.get("seed", false)):
		return false
	var spot := spot_of(x, y)
	var at := now_ms if now_ms > 0 else now_ms_now()
	g["seed"] = false
	(g["plots"] as Array).append({"at": at, "hit": false, "x": spot["x"], "y": spot["y"]})
	return true


static func spot_of(x: float, y: float) -> Dictionary:
	return {
		"x": int(round(clampf(x, X_MIN, X_MAX))),
		"y": int(round(clampf(y, Y_MIN, Y_MAX))),
	}


static func now_ms_now() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


static func stage_of(plot: Dictionary, now_ms: int = 0) -> int:
	var now := now_ms if now_ms > 0 else now_ms_now()
	var at := int(plot.get("at", now))
	var elapsed := maxi(0, now - at)
	elapsed = int(elapsed / 1000) * 1000
	var st := 0
	for i in range(1, STAGE_MS.size()):
		if elapsed >= int(STAGE_MS[i]):
			st = i
	return st


static func progress_of(plot: Dictionary, now_ms: int = 0) -> float:
	var now := now_ms if now_ms > 0 else now_ms_now()
	var at := int(plot.get("at", now))
	return clampf(float(maxi(0, now - at)) / float(STAGE_MS[4]), 0.0, 1.0)


static func is_bloomed(plot: Dictionary, now_ms: int = 0) -> bool:
	return stage_of(plot, now_ms) >= 4


## 真名说明分段（Web narrSegments 同口径）：
## 先按句末标点断句；>140 字的长句在逗号 / 顿号 / 分号处对半切；
## 再贪心并句到约 150 字一段，读起来是几段话而不是一堵字墙。
static func narr_segments(text: String) -> Array:
	var t := String(text).strip_edges()
	if t == "":
		return []
	var re := RegEx.new()
	re.compile("[^。！？…]+[。！？…]*")
	var sents: Array = []
	for m in re.search_all(t):
		sents.append(m.get_string())
	if sents.is_empty():
		sents.append(t)
	var clauses: Array = []
	for s in sents:
		_split_long_clause(String(s).strip_edges(), clauses)
	var segs: Array = []
	var cur := ""
	for c in clauses:
		var clause := String(c)
		if clause == "":
			continue
		if cur != "" and (cur + clause).length() > 150:
			segs.append(cur)
			cur = ""
		cur += clause
	if cur != "":
		segs.append(cur)
	return segs


static func _split_long_clause(s: String, out: Array) -> void:
	if s.length() <= 140:
		out.append(s)
		return
	var re := RegEx.new()
	re.compile("[^，、；]+[，、；]?")
	var parts: Array = []
	for m in re.search_all(s):
		parts.append(m.get_string())
	if parts.size() <= 1:
		var mid := int(s.length() / 2)
		_split_long_clause(s.substr(0, mid), out)
		_split_long_clause(s.substr(mid), out)
		return
	var acc := 0
	var cut := 0
	var best := 1.0e20
	for i in parts.size():
		acc += String(parts[i]).length()
		var d := absf(float(acc) - float(s.length()) * 0.5)
		if i < parts.size() - 1 and d < best:
			best = d
			cut = i
	var left := ""
	var right := ""
	for i in parts.size():
		if i <= cut:
			left += String(parts[i])
		else:
			right += String(parts[i])
	_split_long_clause(left, out)
	_split_long_clause(right, out)
