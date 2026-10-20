class_name ClueDef
extends Resource
## 线索（五感槽位的载体）。`sense` 用下拉枚举，杜绝打错字。

@export var id: String = ""
@export var label: String = ""
@export_enum("vision", "hearing", "touch", "taste", "smell") var sense: String = "vision"
@export_multiline var desc: String = ""
