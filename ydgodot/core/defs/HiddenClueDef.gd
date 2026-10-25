class_name HiddenClueDef
extends Resource
## 「隐藏线索」：读一段文字就顺手拿到的东西（场景 / 物品 / 人物都可能挂）。

@export_multiline var text: String = ""
## 字段名保留 `clues` 只为旧资源兼容；内容一律是 EvidenceDef（证）。
@export var clues: Array[EvidenceDef] = []
