class_name MemoryDef
extends Resource
## 一段回忆：when（哪一天）× where（在哪）× who（谁的视角）+ 剧本。

@export var id: String = ""
@export var when: SceneDef = null
@export var where: SceneDef = null
@export var who: CharDef = null
@export var title: String = ""
@export var script_lines: Array[DialogueLineDef] = []   # 不能叫 script：Resource 自己有个 script
