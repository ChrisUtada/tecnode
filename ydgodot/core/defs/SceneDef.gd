@tool
class_name SceneDef
extends Resource
## 场景 / 时刻（时刻是「带日期的场景」，由 CaseDef.memories 反查 who/where 决定）。
##
## ⚠ `@tool` 与下面四个默认值**都不能删**（2026-10-21 实测踩过）：
## 非 tool 脚本在编辑器里用的是 `PlaceholderScriptInstance`，它的 `set()` 要求写入值的
## 类型与「脚本里的默认值类型」完全一致；默认值写 `[]` 会变成无类型 Array（typeof 28），
## 于是 `.tres` 里存的 `PackedStringArray(...)`（typeof 34）被**整条丢弃** —— 检查器四栏
## 全空、但游戏里一切正常（运行时用真脚本实例，没有这层校验）。
## 所以：`@tool` + `= PackedStringArray()` 两个都要。

@export var id: String = ""
@export var title: String = ""
@export_multiline var content: String = ""
@export_multiline var desc: String = ""
@export var image: String = ""
@export var can_be_picked: bool = false
@export var hidden_clue: HiddenClueDef = null
## TEC 分析该场景时一并掉落的「物」级证据。
@export var hidden_evidence: Array[EvidenceDef] = []
## 双击可先跑的命令（Web `SCENES[id].commands`，a001 里 0/11 用到；为未来案件铺路）。
## 空数组 = 回到容器展开 / 折叠的默认行为。
@export var commands: Array[CommandDef] = []

## ── 画布节点 ─────────────────────────────────────────────────────────────
## 这个场景展开时摆上桌面的东西。**只认这四栏**：正文写什么、提到谁，都不再决定
## 画布上出现什么（正文只负责文字，`[item:X]` 标签只用于把名字显示成物品名）。
##
## 存 id（PackedStringArray）而不是资源引用，是 `.tres` 的硬性限制：地点之间本来就
## 互通（花园 ↔ 尸体 ↔ 书桌 …），`node_locs` 必然双向；实测 `.tres` 与 `.res` 冷启动
## 都不支持环（"referenced non-existent resource"），一存环整包案件就打不开。
## 但**不需要手打 id**：`addons/case_nodes/` 把四栏渲染成资源选择列表，点「＋」从
## 案件目录里挑资源，id 由插件写入。资源改名 / 挪目录不影响 id（id 是资源内的字段）。
@export_group("画布节点")
@export var node_items: PackedStringArray = PackedStringArray()   # 物品 id，如 ITEMS_zhiwu
@export var node_chars: PackedStringArray = PackedStringArray()   # 人物 id，如 CHARS_zs / NPC_FB
@export var node_locs: PackedStringArray = PackedStringArray()    # 地点 id，如 SCENES_body
@export var node_clues: PackedStringArray = PackedStringArray()   # 线索 id，如 CLUES_fb
