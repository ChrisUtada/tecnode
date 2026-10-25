class_name PayloadDef
extends Resource
## 命令成功后要做的事（applyPayload 的等价物）：给文本 + 长出物品 + 揭示场景。

@export_multiline var message: String = ""
@export var scene: SceneDef = null
@export var items: Array[ItemDef] = []
## §7-2：命令成功直接产出的线索。正文不再用 `[clue:X]` 表达逻辑。
@export var clues: Array[ClueDef] = []
