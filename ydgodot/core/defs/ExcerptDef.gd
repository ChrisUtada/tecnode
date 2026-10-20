class_name ExcerptDef
extends Resource
## 文本物上的「摘录」：读到某个词，就长出指向某个实体的边（二选一，另一路为空）。

@export var text: String = ""
@export var target_scene: SceneDef = null
@export var target_char: CharDef = null
