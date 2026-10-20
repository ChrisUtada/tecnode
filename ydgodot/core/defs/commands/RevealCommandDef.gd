class_name RevealCommandDef
extends CommandDef
## 翻看命令：把文字物里提到的东西一起摊出来（可要求先有光）。

@export_multiline var value: String = ""
@export var items: Array[ItemDef] = []
