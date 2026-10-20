class_name HiddenClueDef
extends Resource
## 「隐藏线索」：读一段文字就顺手拿到的东西（场景 / 物品 / 人物都可能挂）。

@export_multiline var text: String = ""
@export var clues: Array[ClueDef] = []
