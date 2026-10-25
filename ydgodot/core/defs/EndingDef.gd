class_name EndingDef
extends Resource
## 结局：五感配方 + 是否真名捕获 + 分幕 + 说明。

@export var id: String = ""
@export var name: String = ""
@export var truename: String = ""
@export var recipe: Array[EvidenceDef] = []
@export var is_true_capture: bool = false
@export var lines: Array[EndingLineDef] = []
@export_multiline var message: String = ""
