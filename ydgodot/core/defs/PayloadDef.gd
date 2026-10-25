class_name PayloadDef
extends Resource
## 命令成功后要做的事（applyPayload 的等价物）：给文本 + 长出物品 + 揭示场景。

@export_multiline var message: String = ""
@export var scene: SceneDef = null
@export var items: Array[ItemDef] = []
## 命令成功直接产出的证（类型已收敛为 EvidenceDef）。
@export var clues: Array[EvidenceDef] = []
