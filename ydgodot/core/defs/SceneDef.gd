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
## 双击可先跑的命令（Web `SCENES[id].commands`，a001 里 0/11 用到；为未来案件铺路）。
## 空数组 = 回到容器展开 / 折叠的默认行为。
@export var commands: Array[CommandDef] = []
