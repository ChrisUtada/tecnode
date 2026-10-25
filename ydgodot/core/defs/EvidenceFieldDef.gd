class_name EvidenceFieldDef
extends Resource
## 人物档案卡的关键字段：玩家从词库选一个值，再附上一张「证」级证据，交给 TEC 核对。
## `support` 是可由玩家拿到的证据集合（任意一张即可支撑）；`drop_clue` 在全部关键字段核准后掉落。

@export var id: String = ""
@export var label: String = ""
@export_multiline var prompt: String = ""
@export var options: PackedStringArray = PackedStringArray()
@export var correct: String = ""
@export var support: Array[EvidenceDef] = []
## 字段全部核准后掉落的人物证据（origin=deduce，落地即已捕获）。
@export var drop_clue: EvidenceDef = null
