class_name DialogueLineDef
extends Resource
## 剧本的一行：旁白或某人的台词（记忆小剧场与多人对话共用）。

@export_enum("narr", "say") var kind: String = "narr"
@export var who: CharDef = null
@export_multiline var text: String = ""
