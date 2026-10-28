class_name NodeState
extends RefCounted
## 节点运行时态的强类型实体。
##
## `GraphState.nodes` 的值就是 NodeState；磁盘存档仍由 `to_dict()` 输出
## Dictionary（`format: 1` 不变）。NodeState 是**字段名 / 类型 / 默认值**的唯一来源：
##   · `GraphState.add_node()` 直接建实体，读写都走属性；
##   · `SaveSystem.restore()` 用 `from_dict()` 归一化旧档（缺字段补默认、类型纠偏）；
##   · 旧调用若仍把 Dictionary 塞进 `nodes`，`GraphState.node()` 会在首次读取时就地升级。
##
## 未识别的字段收进 `_extra`，`to_dict()` 原样带回 —— 旧档 / 前瞻字段都不会丢。

const F_KEY := "key"
const F_KIND := "kind"
const F_ID := "id"
const F_LABEL := "label"
const F_X := "x"
const F_Y := "y"
const F_LIT := "lit"
const F_HOME := "home_scene"
const F_PINNED := "pinned"
const F_BAG_FROM := "bag_from"
const F_INSTALLED := "installed"
const F_CAPTURED := "captured"
const F_FRESH := "fresh"
const F_UNREAD := "unread"
const F_TIER := "tier"
const F_SENSE := "sense"
const F_ORIGIN := "origin"
const F_ALWAYS := "always_visible"
const F_STORED := "stored"
const F_STORED_IN := "storedIn"

const KNOWN := [
	F_KEY, F_KIND, F_ID, F_LABEL, F_X, F_Y, F_LIT, F_HOME, F_PINNED,
	F_BAG_FROM, F_INSTALLED, F_CAPTURED, F_FRESH, F_UNREAD,
	F_TIER, F_SENSE, F_ORIGIN, F_ALWAYS, F_STORED, F_STORED_IN,
]

var key: String = ""
var kind: String = ""
var id: String = ""
var label: String = ""
var x: float = 0.0
var y: float = 0.0
var lit: bool = false
var home_scene: String = ""
var pinned: bool = false
var bag_from: String = ""
var installed: Dictionary = {}
var captured: bool = false
var fresh: bool = false
var unread: bool = false
## 证据专属字段；只在源数据确实有这一项时才写回，避免给旧档凭空加键。
var tier: String = ""
var sense: String = ""
var origin: String = ""
var always_visible: bool = false
## 读档时从节点上拆出来的收纳去向（运行时由 GraphState.stored 持有）。
var stored_in: String = ""

var _present: Dictionary = {}
var _extra: Dictionary = {}


## 新建节点：坐标 -1 = 还没落位（与 `add_node` 的语义一致）。
static func make_new(p_kind: String, p_id: String, p_key: String, p_label: String) -> NodeState:
	var s := NodeState.new()
	s.kind = p_kind
	s.id = p_id
	s.key = p_key
	s.label = p_label
	s.x = -1.0
	s.y = -1.0
	return s


## 空节点判定（替代旧 Dictionary.is_empty()）。
func is_empty() -> bool:
	return key == "" and kind == "" and id == ""


## 任意来源 → NodeState（Dictionary / NodeState / 其他 → 空节点）。
static func from_value(value) -> NodeState:
	if value is NodeState:
		return from_dict((value as NodeState).to_dict())
	if value is Dictionary:
		return from_dict(value)
	return NodeState.new()


## 读档归一化：缺字段补默认，类型纠偏，未知字段留底。
## 坐标默认 0（旧档没有 x/y 时按原点摆），与 add_node 的 -1「未落位」区分开。
static func from_dict(data) -> NodeState:
	var s := NodeState.new()
	if not (data is Dictionary):
		return s
	var d: Dictionary = data
	s.key = String(d.get(F_KEY, ""))
	s.kind = String(d.get(F_KIND, ""))
	s.id = String(d.get(F_ID, ""))
	s.label = String(d.get(F_LABEL, s.id))
	s.x = float(d.get(F_X, 0.0))
	s.y = float(d.get(F_Y, 0.0))
	s.lit = bool(d.get(F_LIT, false))
	s.home_scene = String(d.get(F_HOME, ""))
	s.pinned = bool(d.get(F_PINNED, false))
	s.bag_from = String(d.get(F_BAG_FROM, ""))
	var ins = d.get(F_INSTALLED, {})
	s.installed = (ins as Dictionary).duplicate(true) if ins is Dictionary else {}
	s.captured = bool(d.get(F_CAPTURED, false))
	s.fresh = bool(d.get(F_FRESH, false))
	s.unread = bool(d.get(F_UNREAD, false))
	for f in [F_TIER, F_SENSE, F_ORIGIN, F_ALWAYS]:
		if d.has(f):
			s._present[f] = true
	s.tier = String(d.get(F_TIER, ""))
	s.sense = String(d.get(F_SENSE, ""))
	s.origin = String(d.get(F_ORIGIN, ""))
	s.always_visible = bool(d.get(F_ALWAYS, false))
	s.stored_in = String(d.get(F_STORED_IN, ""))
	for k in d.keys():
		if not KNOWN.has(String(k)):
			s._extra[String(k)] = d[k]
	return s


## 证据节点的专属字段（tier / sense / origin / always_visible）。
func apply_evidence(ev: EvidenceDef, already_captured: bool) -> void:
	tier = ev.tier if ev != null else "zheng"
	sense = ev.sense if ev != null else "vision"
	origin = ev.origin if ev != null else "tec"
	always_visible = true
	captured = tier == "zheng" and already_captured
	for f in [F_TIER, F_SENSE, F_ORIGIN, F_ALWAYS]:
		_present[f] = true


## 运行时节点字典（写回 `GraphState.nodes` / 存档用）。
func to_dict() -> Dictionary:
	var d := _extra.duplicate(true)
	d[F_KEY] = key
	d[F_KIND] = kind
	d[F_ID] = id
	d[F_LABEL] = label
	d[F_X] = x
	d[F_Y] = y
	d[F_LIT] = lit
	d[F_HOME] = home_scene
	d[F_PINNED] = pinned
	d[F_BAG_FROM] = bag_from
	d[F_INSTALLED] = installed.duplicate(true)
	d[F_CAPTURED] = captured
	d[F_FRESH] = fresh
	d[F_UNREAD] = unread
	if _present.has(F_TIER):
		d[F_TIER] = tier
	if _present.has(F_SENSE):
		d[F_SENSE] = sense
	if _present.has(F_ORIGIN):
		d[F_ORIGIN] = origin
	if _present.has(F_ALWAYS):
		d[F_ALWAYS] = always_visible
	return d
