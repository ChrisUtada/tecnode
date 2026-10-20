class_name SceneDef
extends Resource
## 场景 / 时刻（时刻是「带日期的场景」，由 CaseDef.memories 反查 who/where 决定）。

@export var id: String = ""
@export var title: String = ""
@export_multiline var content: String = ""
@export_multiline var desc: String = ""
@export var image: String = ""
@export var can_be_picked: bool = false
@export var hidden_clue: HiddenClueDef = null
