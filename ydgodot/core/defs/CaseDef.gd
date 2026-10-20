class_name CaseDef
extends Resource
## 一个案件的索引：实体全在这里，字符串 id 引用已换成类型化引用。

@export var id: String = ""
@export var title: String = ""
@export var now_label: String = ""
@export var start_scene: SceneDef = null
@export var memory_scenes: Array[SceneDef] = []
@export var reusable_tools: Array[ItemDef] = []
@export var scenes: Array[SceneDef] = []
@export var items: Array[ItemDef] = []
@export var chars: Array[CharDef] = []
@export var clues: Array[ClueDef] = []
@export var memories: Array[MemoryDef] = []
@export var dialogues: Array[DialogueDef] = []
@export var endings: Array[EndingDef] = []
