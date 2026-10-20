class_name ItemDef
extends Resource
## 物品（含「容器物品」：书桌 / 抽屉这类 content 里带标签的）。

@export var id: String = ""
@export var label: String = ""
@export_multiline var desc: String = ""
@export_multiline var content: String = ""
@export var can_be_picked: bool = false

# ── 光照 ──
@export var toggle_light: bool = false
@export var needs_lit_to_use: bool = false
@export_multiline var lit_on_message: String = ""
@export_multiline var lit_off_message: String = ""
@export_multiline var lit_fail_message: String = ""

@export var commands: Array[CommandDef] = []
@export var excerpts: Array[ExcerptDef] = []
@export var hidden_clue: HiddenClueDef = null
