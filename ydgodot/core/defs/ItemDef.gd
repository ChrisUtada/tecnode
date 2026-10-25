@tool
class_name ItemDef
extends Resource
## 物品（含「容器物品」：书桌 / 抽屉这类 content 里带标签的）。
## ⚠ `@tool` 与四栏 `PackedStringArray` 的默认值都不能删 —— 原因见 `SceneDef.gd` 顶部注释。

@export var id: String = ""
@export var label: String = ""
@export_multiline var desc: String = ""
@export_multiline var content: String = ""
@export var can_be_picked: bool = false
## 是否可以放进证物袋。与「能否从现场拾起」解耦：有些东西能捡但不能收纳，
## 容器则应显式关掉（默认开，普通物品不用逐条勾）。
@export var baggable: bool = true

# ── 光照 ──
@export var toggle_light: bool = false
@export var needs_lit_to_use: bool = false
@export_multiline var lit_on_message: String = ""
@export_multiline var lit_off_message: String = ""
@export_multiline var lit_fail_message: String = ""

@export var commands: Array[CommandDef] = []
@export var excerpts: Array[ExcerptDef] = []
## TEC 分析该物品时产出的证（字段名保留 hidden_clue，内容已收敛为证）。
@export var hidden_clue: HiddenClueDef = null

## ── 画布节点 ─────────────────────────────────────────────────────────────
## 容器物品（书桌 / 抽屉 / 垃圾桶）展开时倒出来的东西。与场景同一套语义：
## **只认这四栏**，正文里写了什么标签都不再决定展开出什么。四栏全空 = 不是容器。
## 与场景同一套语义与同一套 id 存储理由（见 SceneDef 的注释）。
## 检查器里由 `addons/case_nodes/` 提供资源选择列表，不用手打 id。
@export_group("画布节点")
@export var node_items: PackedStringArray = PackedStringArray()
@export var node_chars: PackedStringArray = PackedStringArray()
@export var node_locs: PackedStringArray = PackedStringArray()
@export var node_clues: PackedStringArray = PackedStringArray()
